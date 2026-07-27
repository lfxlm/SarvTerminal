import Foundation

/// Feeds SSH passwords to `ssh` out-of-band via an `SSH_ASKPASS` helper, so ssh
/// never prompts for the password on the terminal (no "password:" line, no echo).
///
/// The helper is a tiny one-shot script: it prints a per-connection password
/// file's contents to stdout, then deletes the file. We set `SSH_ASKPASS` +
/// `SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+, which macOS ships) on the ssh
/// surface's environment so ssh calls the helper instead of the TTY.
enum SSHAskpass {
    /// Path to the helper script, (re)created on first access.
    private static let helperPath: String? = {
        guard let dir = supportDirectory() else { return nil }
        let url = dir.appendingPathComponent("sarv-askpass.sh")
        // Print the correct password based on the SSH prompt:
        //   - If the prompt mentions the jump host ($SARV_JUMP_HOST_ID),
        //     return the jump host's password from $SARV_JUMP_ASKPASS_FILE.
        //   - Otherwise return the target host's password.
        // ssh may call askpass more than once (e.g. auth method fallback),
        // so we do NOT delete the files here — the app removes them on
        // connect / close / relaunch.
        let script = """
        #!/bin/sh
        if [ -n "$SARV_JUMP_ASKPASS_FILE" ] && [ -n "$SARV_JUMP_HOST_ID" ] && echo "$*" | grep -qiF "$SARV_JUMP_HOST_ID"; then
          cat "$SARV_JUMP_ASKPASS_FILE"
        else
          cat "$SARV_ASKPASS_FILE"
        fi
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
    ///   - jumpPassword: The jump host's password (if it uses password auth).
    static func env(forPassword password: String,
                    jumpHostID: String? = nil,
                    jumpPassword: String? = nil) -> [String: String] {
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

        // Jump host password file (best-effort — skip on failure).
        if let jumpHostID, let jumpPassword, !jumpPassword.isEmpty {
            let jumpFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sarv-jump-\(UUID().uuidString)")
            if (try? (jumpPassword + "\n").write(to: jumpFileURL, atomically: true, encoding: .utf8)) != nil,
               (try? FileManager.default.setAttributes(
                   [.posixPermissions: 0o600], ofItemAtPath: jumpFileURL.path)) != nil {
                env["SARV_JUMP_ASKPASS_FILE"] = jumpFileURL.path
                env["SARV_JUMP_HOST_ID"] = jumpHostID
            }
        }

        return env
    }
}
