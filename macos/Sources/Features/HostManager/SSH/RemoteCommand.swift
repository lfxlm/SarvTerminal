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

    /// Common ssh options derived from the host (mirrors RemoteFileBackend),
    /// plus connection multiplexing so repeated queries share one ssh link.
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
        args += controlOptions(for: host)
        return args
    }

    /// OpenSSH connection multiplexing: the first call to a host becomes the
    /// master connection; later calls to the same host (docker list + pods,
    /// the sudo fallback, monitor auto-refresh every few seconds) reuse it via
    /// a control socket — no per-call TCP + ssh handshake. `ControlMaster=auto`
    /// reuses when available, else starts a fresh master and OpenSSH auto-removes
    /// a stale socket from a killed master. `ControlPersist=60` keeps the master
    /// alive 60s after the last use so a 3s refresh loop never reconnects.
    ///
    /// The socket lives in a SHORT path (`/tmp`): OpenSSH appends a random
    /// suffix to the ControlPath, and a socket path can be at most 104 bytes —
    /// macOS's `NSTemporaryDirectory()` (`/var/folders/…/T/`) is too long and
    /// fails with "too long for Unix domain socket".
    private static func controlOptions(for host: SavedHost) -> [String] {
        let dir = "/tmp/sarv-ssh-ctrl"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let key = "\(host.username)@\(host.hostname):\(host.port)"
        var hash = UInt64(1469598103934665603)   // FNV-1a
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let socket = "\(dir)/sarv-\(String(format: "%08x", hash & 0xFFFFFFFF)).sock"
        return ["-o", "ControlMaster=auto",
                "-o", "ControlPath=\(socket)",
                "-o", "ControlPersist=60"]
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
