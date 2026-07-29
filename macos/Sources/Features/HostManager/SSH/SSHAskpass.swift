import Foundation

/// Feeds SSH passwords to `ssh` out-of-band via an `SSH_ASKPASS` helper, so ssh
/// never prompts for the password on the terminal (no "password:" line, no echo).
///
/// The helper is a tiny one-shot script: it prints a per-connection password
/// file's contents to stdout, then deletes the file. We set `SSH_ASKPASS` +
/// `SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+, which macOS ships) on the ssh
/// surface's environment so ssh calls the helper instead of the TTY.
///
/// Multi-hop jump chains: ssh prompts for each jump host's password in order.
/// The helper receives each prompt text (e.g. `user@host's password:`) and
/// matches it against the ordered list of jump host IDs to pick the right file.
enum SSHAskpass {
    /// Path to the helper script, (re)created on first access.
    private static let helperPath: String? = {
        guard let dir = supportDirectory() else { return nil }
        let url = dir.appendingPathComponent("sarv-askpass.sh")
        // Print the correct password based on the SSH prompt:
        //   - If the prompt mentions one of the jump host IDs (checked in
        //     order, so a multi-hop chain matches the right host), return
        //     that jump host's password from its askpass file.
        //   - Otherwise return the target host's password.
        // ssh may call askpass more than once (e.g. auth method fallback),
        // so we do NOT delete the files here — the app removes them on
        // connect / close / relaunch.
        let script = """
        #!/bin/sh
        # Multi-hop jump password matching.
        # SARV_JUMP_IDS / SARV_JUMP_FILES are newline-separated, parallel lists.
        if [ -n "$SARV_JUMP_IDS" ] && [ -n "$SARV_JUMP_FILES" ]; then
          i=0
          printf '%s\\n' "$SARV_JUMP_IDS" | while IFS= read -r jid; do
            if [ -n "$jid" ] && echo "$*" | grep -qiF "$jid"; then
              # Print the i-th file. Use a second pipe to pick the file by index.
              break
            fi
            i=$((i + 1))
          done
          # Re-scan to actually emit the matching file (the while subshell
          # can't export `i` back, so we do a second pass).
          i=0
          printf '%s\\n' "$SARV_JUMP_IDS" | while IFS= read -r jid; do
            if [ -n "$jid" ] && echo "$*" | grep -qiF "$jid"; then
              printf '%s\\n' "$SARV_JUMP_FILES" | sed -n "$((i + 1))p" | xargs -I{} cat {}
              exit 0
            fi
            i=$((i + 1))
          done
        fi
        # No jump host matched — target host password.
        cat "$SARV_ASKPASS_FILE"
        """
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }()

    private static func supportDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(AppIdentity.bundleID, isDirectory: true)
    }

    /// Environment variables to set on an ssh surface so it reads `password`
    /// from the askpass helper. Returns an empty dict for an empty password (key
    /// / agent auth — ssh should not be forced through askpass then).
    ///
    /// - Parameters:
    ///   - password: The target host's password (non-empty to enable askpass).
    ///   - jumpHostID: The `user@host` (or `user@host:port`) of the jump host.
    ///     Kept for backward compatibility — when `jumpHosts` is empty this is
    ///     used as a single-hop jump.
    ///   - jumpPassword: The jump host's password (if it uses password auth).
    ///     Kept for backward compatibility.
    ///   - jumpHosts: Ordered list of `(id, password)` for a multi-hop jump
    ///     chain. Each `id` is the `user@host` string ssh will prompt with;
    ///     each `password` is that jump host's password (empty = skip).
    static func env(forPassword password: String,
                    jumpHostID: String? = nil,
                    jumpPassword: String? = nil,
                    jumpHosts: [(id: String, password: String)] = []) -> [String: String] {
        guard !password.isEmpty, let helper = helperPath else { return [:] }

        // Target password file (always written when password is non-empty).
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sarv-ssh-\(UUID().uuidString)")
        do {
            // Newline-terminated; ssh strips the trailing newline.
            try (password + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            return [:]
        }

        var env: [String: String] = [
            "SSH_ASKPASS": helper,
            "SSH_ASKPASS_REQUIRE": "force",
            "SARV_ASKPASS_FILE": fileURL.path,
        ]

        // Build the ordered jump-host list. Prefer the multi-hop `jumpHosts`
        // list; fall back to the single-hop legacy pair.
        var hops: [(id: String, password: String)] = jumpHosts
        if hops.isEmpty, let jumpHostID, let jumpPassword, !jumpPassword.isEmpty {
            hops = [(id: jumpHostID, password: jumpPassword)]
        }

        // Jump host password files (best-effort — skip on failure).
        var jumpIDs: [String] = []
        var jumpFiles: [String] = []
        for hop in hops where !hop.password.isEmpty {
            let jumpFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sarv-jump-\(UUID().uuidString)")
            if (try? (hop.password + "\n").write(to: jumpFileURL, atomically: true, encoding: .utf8)) != nil,
               (try? FileManager.default.setAttributes(
                   [.posixPermissions: 0o600], ofItemAtPath: jumpFileURL.path)) != nil {
                jumpIDs.append(hop.id)
                jumpFiles.append(jumpFileURL.path)
            }
        }

        if !jumpIDs.isEmpty {
            env["SARV_JUMP_IDS"] = jumpIDs.joined(separator: "\n")
            env["SARV_JUMP_FILES"] = jumpFiles.joined(separator: "\n")
            // Legacy single-hop vars (kept so an old helper script still works).
            env["SARV_JUMP_ASKPASS_FILE"] = jumpFiles[0]
            env["SARV_JUMP_HOST_ID"] = jumpIDs[0]
        }

        return env
    }
}