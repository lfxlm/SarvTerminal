import Foundation

/// Runs a command on a remote host over `ssh`, using a saved host's connection
/// options and — for password hosts — the askpass helper. Backs the Docker
/// Attach panel and the server-monitor view so they can query the SERVER without
/// opening a terminal. One round-trip per call; the askpass temp file is
/// cleaned up when the process exits.
enum RemoteCommand {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Common ssh options derived from the host (mirrors RemoteFileBackend).
    static func sshOptions(for host: SavedHost) -> [String] {
        var args: [String] = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=\(host.connectTimeoutSeconds > 0 ? host.connectTimeoutSeconds : 10)",
        ]
        if host.port != 22 { args += ["-p", "\(host.port)"] }
        if !host.identityFile.isEmpty {
            args += ["-i", (host.identityFile as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
        }
        if !host.proxyJump.isEmpty { args += ["-J", host.proxyJump] }
        if host.forwardAgent { args.append("-A") }
        return args
    }

    static func target(_ host: SavedHost) -> String {
        host.username.isEmpty ? host.hostname : "\(host.username)@\(host.hostname)"
    }

    /// Run `command` on the remote host. Best-effort — failures come back as a
    /// non-zero status with stderr, never thrown. `stdin` (e.g. a sudo password
    /// for `sudo -S`) is piped to the remote command through ssh's stdin.
    static func run(host: SavedHost, command: String, stdin: String? = nil) async -> Result {
        let askpassEnv = SSHAskpass.env(forPassword: host.password)
        let args = sshOptions(for: host) + [target(host), command]
        let res = (try? await RemoteFileBackend.runProcess("/usr/bin/ssh", args, env: askpassEnv, stdin: stdin))
        if let file = askpassEnv["SARV_ASKPASS_FILE"] {
            try? FileManager.default.removeItem(atPath: file)
        }
        guard let res else {
            return Result(status: -1, stdout: "", stderr: "Couldn't launch ssh.")
        }
        return Result(status: res.status, stdout: res.stdout, stderr: res.stderr)
    }

    /// The `docker`/`kubectl` "no permission" marker (daemon socket denied, or
    /// sudo refusing) — lets callers fall back to `sudo -n` or show the fix.
    static func isPermissionDenied(_ stderr: String) -> Bool {
        let l = stderr.lowercased()
        return l.contains("permission denied")
            || l.contains("cannot connect to the docker daemon")
            || l.contains("a password is required")
            || l.contains("not in the sudoers file")
            || l.contains("is not in the sudoers")
    }
}
