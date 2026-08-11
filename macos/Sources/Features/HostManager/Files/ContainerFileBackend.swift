import Foundation

/// A file-browser backend rooted INSIDE a docker container on a remote host.
///
/// Directory operations run through `docker exec <name> …`; transfers use a
/// host temp dir as a relay: upload = SFTP local→host temp, then
/// `docker cp temp/file container:dir/`; download is the reverse. `sudo` is
/// prepended (with the saved password piped to `sudo -S`) when the container
/// requires it.
final class ContainerFileBackend: FileBackend, SFTPTransferSource {
    let location: FileLocation
    private let host: SavedHost
    let containerName: String
    let needsSudo: Bool
    /// askpass env so the ssh/sftp legs can authenticate non-interactively.
    private let askpassEnv: [String: String]

    init(host: SavedHost, container: String, needsSudo: Bool) {
        self.host = host
        self.containerName = container
        self.needsSudo = needsSudo
        self.location = .container(host: host, name: container, needsSudo: needsSudo)
        self.askpassEnv = host.password.isEmpty
            ? [:]
            : SSHAskpass.env(forPassword: host.password)
    }

    /// `sudo -S docker` / `docker` — the prefix for container commands.
    var dockerCommand: String { needsSudo ? "sudo -S docker" : "docker" }

    private var target: String {
        host.username.isEmpty ? host.hostname : "\(host.username)@\(host.hostname)"
    }

    /// Common ssh options derived from the host (mirrors RemoteFileBackend).
    private func sshOptions() -> [String] {
        var args: [String] = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=no",
            "-o", "NumberOfPasswordPrompts=1",
        ]
        if host.connectTimeoutSeconds > 0 { args += ["-o", "ConnectTimeout=\(host.connectTimeoutSeconds)"] }
        if !host.identityFile.isEmpty {
            args += ["-i", (host.identityFile as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
        }
        if !host.proxyJump.isEmpty { args += ["-J", host.proxyJump] }
        if host.forwardAgent { args.append("-A") }
        return args
    }

    // MARK: ssh runners

    private func runHost(_ remoteArgs: [String]) async throws -> RemoteFileBackend.ProcessResult {
        var args = sshOptions()
        if host.port != 22 { args += ["-p", "\(host.port)"] }
        args.append(target)
        args.append(remoteArgs.joined(separator: " "))
        // `sudo -S docker …` reads the password from the remote command's
        // stdin, which ssh forwards from our own stdin — so feed it here
        // (same as the docker-list probes / attach flow).
        return try await RemoteFileBackend.runProcess("/usr/bin/ssh", args, env: askpassEnv,
                                                      stdin: needsSudo ? host.password + "\n" : nil)
    }

    @discardableResult
    private func runHostChecked(_ remoteArgs: [String]) async throws -> RemoteFileBackend.ProcessResult {
        let r = try await runHost(remoteArgs)
        guard r.status == 0 else { throw FileOpError(message: r.stderr.isEmpty ? "Operation failed." : r.stderr) }
        return r
    }

    /// Run `command` inside the container via `docker exec`.
    private func exec(_ command: String) async throws -> RemoteFileBackend.ProcessResult {
        try await runHost(["\(dockerCommand) exec", Self.q(containerName), command])
    }

    @discardableResult
    private func execChecked(_ command: String) async throws -> RemoteFileBackend.ProcessResult {
        let r = try await exec(command)
        guard r.status == 0 else { throw FileOpError(message: r.stderr.isEmpty ? "Operation failed." : r.stderr) }
        return r
    }

    /// SFTP transfer plumbing (the host-temp leg). Mirrors RemoteFileBackend's
    /// transfer surface so `FileTransfer.sftp` can reuse it.
    var remoteTarget: String { target }
    var transferOptions: [String] { sshOptions() }
    var transferEnv: [String: String] { askpassEnv }
    var transferPort: Int { host.port }

    // MARK: FileBackend

    func homeDirectory() async throws -> String {
        // The container's WORKDIR (docker exec pwd) — a sensible initial browse
        // spot; the user can navigate anywhere from there.
        let r = try await exec("sh -c 'pwd'")
        let home = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return home.isEmpty ? "/" : home
    }

    func list(_ path: String) async throws -> [FileItem] {
        let res = try await exec("ls -la \(Self.q(path))")
        guard res.status == 0 else { throw FileOpError(message: res.stderr.isEmpty ? "Failed to list directory." : res.stderr) }
        return RemoteFileBackend.parseLS(res.stdout, dir: path).sorted(by: LocalFileBackend.sort)
    }

    func makeDirectory(_ path: String) async throws { try await execChecked("mkdir \(Self.q(path))") }

    func rename(_ path: String, to newPath: String) async throws {
        try await execChecked("mv \(Self.q(path)) \(Self.q(newPath))")
    }

    func delete(_ item: FileItem) async throws {
        let cmd = item.isDirectory ? "rm -rf" : "rm -f"
        try await execChecked("\(cmd) \(Self.q(item.path))")
    }

    func setPermissions(_ path: String, octal: String) async throws {
        try await execChecked("chmod \(octal) \(Self.q(path))")
    }

    func exists(_ path: String) async throws -> Bool {
        let res = try await exec("test -e \(Self.q(path)) && echo Y || echo N")
        return res.stdout.contains("Y")
    }

    func localCopy(of item: FileItem) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sarv-view-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(item.name)
        try await transferOut(itemPath: item.path, toLocal: dest.path)
        return dest
    }

    func save(_ text: String, to item: FileItem) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sarv-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent(item.name)
        try text.write(to: local, atomically: true, encoding: .utf8)
        try await transferIn(fromLocal: local.path, destDir: (item.path as NSString).deletingLastPathComponent)
    }

    func fileSize(_ path: String) async -> Int64? {
        guard let r = try? await exec("wc -c < \(Self.q(path))"), r.status == 0 else { return nil }
        let digits = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(digits)
    }

    // MARK: Transfers (host-temp relay)

    /// Upload `fromLocal` into the container at `destDir/` via host temp + docker cp.
    func transferIn(fromLocal: String, destDir: String) async throws {
        let tmpDir = "/tmp/sarv-upload-\(UUID().uuidString.prefix(8))"
        try await runHostChecked(["mkdir", "-p", tmpDir])
        defer { Task { _ = try? await runHost(["rm", "-rf", tmpDir]) } }
        try await FileTransfer.sftpUp(localPath: fromLocal, isDir: false,
                                      backend: self, remotePath: tmpDir, upload: true)
        let name = (fromLocal as NSString).lastPathComponent
        let containerDest = "\(containerName):\(destDir == "/" ? "/" : destDir + "/")"
        try await runHostChecked(["\(dockerCommand) cp", Self.q(tmpDir + "/" + name), Self.q(containerDest)])
    }

    /// Download the container file `itemPath` to `toLocal` via docker cp + host temp.
    func transferOut(itemPath: String, toLocal: String) async throws {
        let tmpDir = "/tmp/sarv-download-\(UUID().uuidString.prefix(8))"
        try await runHostChecked(["mkdir", "-p", tmpDir])
        defer { Task { _ = try? await runHost(["rm", "-rf", tmpDir]) } }
        try await runHostChecked(["\(dockerCommand) cp", Self.q("\(containerName):\(itemPath)"), Self.q(tmpDir)])
        let name = (itemPath as NSString).lastPathComponent
        try await FileTransfer.sftpUp(localPath: toLocal, isDir: false,
                                      backend: self, remotePath: tmpDir + "/" + name,
                                      upload: false)
    }

    /// POSIX single-quote for a remote shell command argument.
    static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
