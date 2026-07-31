import Foundation

/// Percent-encode a username/password segment for the `mount_smbfs` URL.
/// `//[domain;][user[:password]@]server/share` — the userinfo is parsed as a
/// URL, so reserved characters (`/ : @ ; %` …) must be encoded.
private extension String {
    func smbURLEncoded() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// A `FileBackend` backed by an SMB share mounted with the system
/// `/sbin/mount_smbfs`. The share is mounted lazily (on first `homeDirectory`)
/// into a private temp directory; afterwards every operation is a plain local
/// file-system call forwarded to `LocalFileBackend`.
@MainActor
final class SMBFileBackend: FileBackend {
    let connection: SMBConnection
    let location: FileLocation

    /// Cached mount point once the share is mounted.
    private var mountPoint: String?
    private let local = LocalFileBackend()

    init(connection: SMBConnection) {
        self.connection = connection
        self.location = .smb(connection)
    }

    var supportsPermissions: Bool { false }

    // MARK: - FileBackend

    func homeDirectory() async throws -> String {
        if let mp = mountPoint { return mp }
        let mp = try await Self.mount(connection)
        mountPoint = mp
        return mp
    }

    func list(_ path: String) async throws -> [FileItem] {
        try await local.list(path)
    }

    func makeDirectory(_ path: String) async throws {
        try await local.makeDirectory(path)
    }

    func rename(_ path: String, to newPath: String) async throws {
        try await local.rename(path, to: newPath)
    }

    func delete(_ item: FileItem) async throws {
        try await local.delete(item)
    }

    func setPermissions(_ path: String, octal: String) async throws {
        throw FileOpError(message: loc(.smb_no_permissions))
    }

    func exists(_ path: String) async throws -> Bool {
        try await local.exists(path)
    }

    func localCopy(of item: FileItem) async throws -> URL {
        try await local.localCopy(of: item)
    }

    func save(_ text: String, to item: FileItem) async throws {
        try await local.save(text, to: item)
    }

    func fileSize(_ path: String) async -> Int64? {
        await local.fileSize(path)
    }

    /// Unmount the share (best effort) and drop the cached mount point. Never
    /// throws to the caller — disconnect is a cleanup path.
    func disconnect() {
        guard let mp = mountPoint else { return }
        mountPoint = nil
        Task.detached(priority: .utility) {
            try? Self.umount(mp)
        }
    }

    // MARK: - Mounting

    /// Mount `connection` and return the mount point path. Runs the blocking
    /// `mount_smbfs` process off the main actor.
    private static func mount(_ connection: SMBConnection) async throws -> String {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("sarv-smb-\(connection.id.uuidString)", isDirectory: true)
            .path
        try await Task.detached(priority: .userInitiated) {
            try mountSync(connection: connection, mountPoint: mountPoint)
        }.value
        register(mountPoint: mountPoint)
        return mountPoint
    }

    /// Blocking mount. Called from a detached task.
    nonisolated private static func mountSync(connection: SMBConnection, mountPoint: String) throws {
        try FileManager.default.createDirectory(
            atPath: mountPoint,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var url = "//"
        if !connection.domain.isEmpty {
            url += connection.domain.smbURLEncoded() + ";"
        }
        if !connection.username.isEmpty {
            url += connection.username.smbURLEncoded()
            if !connection.password.isEmpty {
                url += ":" + connection.password.smbURLEncoded()
            }
            url += "@"
        }
        url += connection.server.smbURLEncoded() + "/" + connection.share.smbURLEncoded()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/mount_smbfs")
        proc.arguments = ["-N", url, mountPoint]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            try? FileManager.default.removeItem(atPath: mountPoint)
            throw FileOpError(message: loc(.smb_mount_failed, "\(error.localizedDescription)"))
        }
        // Best-effort hang guard: mount_smbfs can block for a long time on an
        // unreachable server. SIGTERM it after 45s and report a timeout.
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
            if proc.isRunning { proc.terminate() }
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            try? FileManager.default.removeItem(atPath: mountPoint)
            let stderr = (proc.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
            let detail = stderr.flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? "exit \(proc.terminationStatus)"
            throw FileOpError(message: loc(.smb_mount_failed, detail))
        }
    }

    /// Blocking unmount: `umount`, falling back to `diskutil unmount force`.
    nonisolated private static func umount(_ mountPoint: String) throws {
        unregister(mountPoint: mountPoint)
        var status: Int32 = -1
        let um = Process()
        um.executableURL = URL(fileURLWithPath: "/sbin/umount")
        um.arguments = [mountPoint]
        um.standardOutput = Pipe()
        um.standardError = Pipe()
        if (try? um.run()) != nil { um.waitUntilExit(); status = um.terminationStatus }
        if status == 0 {
            try? FileManager.default.removeItem(atPath: mountPoint)
            return
        }
        let d = Process()
        d.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        d.arguments = ["unmount", "force", mountPoint]
        d.standardOutput = Pipe()
        d.standardError = Pipe()
        if (try? d.run()) != nil { d.waitUntilExit(); status = d.terminationStatus }
        if status == 0 {
            try? FileManager.default.removeItem(atPath: mountPoint)
            return
        }
        throw FileOpError(message: "umount \(mountPoint) failed (\(status))")
    }

    // MARK: - Mount registry (app-quit cleanup)

    nonisolated private static func register(mountPoint: String) {
        smbMountRegistryLock.lock()
        defer { smbMountRegistryLock.unlock() }
        smbMountRegistry.append(mountPoint)
    }

    nonisolated private static func unregister(mountPoint: String) {
        smbMountRegistryLock.lock()
        defer { smbMountRegistryLock.unlock() }
        smbMountRegistry.removeAll { $0 == mountPoint }
    }

    /// Unmount every share still mounted (application terminate). Best effort;
    /// safe to call multiple times.
    static func cleanupAllMounts() {
        let points: [String] = {
            smbMountRegistryLock.lock()
            defer { smbMountRegistryLock.unlock() }
            let p = smbMountRegistry
            smbMountRegistry = []
            return p
        }()
        for p in points {
            try? umount(p)
        }
    }
}

/// Mount points registered by live `SMBFileBackend` instances, guarded by
/// `smbMountRegistryLock`. Fileprivate globals (not class statics) so both the
/// MainActor-isolated backend and its nonisolated helpers can touch them.
private let smbMountRegistryLock = NSLock()
private var smbMountRegistry: [String] = []
