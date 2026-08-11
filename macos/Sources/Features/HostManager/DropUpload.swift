import AppKit
import Foundation

/// Handles files dragged onto an SSH terminal pane.
///
/// Routing:
/// - Plain SSH tab → upload via SFTP straight into the remote current directory
///   (tracked by OSC 7 shell integration; falls back to the login `pwd`).
/// - Docker-attached SSH tab → upload via SFTP into a temp dir on the host,
///   then `docker cp` into the container's current directory, then clean up.
///
/// Non-SSH surfaces keep Ghostty's original behavior (insert the paths as text).
enum DropUpload {

    /// A docker attach target: the container name plus whether the attach uses
    /// `sudo` (so the `docker cp`/`docker exec` probes can too).
    struct Container {
        let name: String
        let needsSudo: Bool
    }

    /// Try to handle a file drop on `surface`. Returns true when the drop was
    /// consumed as an upload (the caller must NOT also insert text). Only
    /// handles surfaces owned by an SSH terminal tab; everything else returns
    /// false so the caller keeps its default behavior.
    @MainActor
    static func handle(urls: [URL], surface: Ghostty.SurfaceView) -> Bool {
        let tabs = VaultsTabsModel.shared
        let tab = tabs.tab(containing: surface)
        // The host for a live SSH pane lives in the per-surface connection
        // registry (`connectSavedHostInPane` — restore/split/copy-session —
        // never sets `tab.connectHost`); `connectHost` covers the staged
        // `startSSHConnection` path. Check both, like applyFontWeight does.
        let host = tabs.connections[surface.id]?.model.host ?? tab?.connectHost
        NSLog("%@", "[DropUpload] handle: urls=\(urls.count) tab=\(tab == nil ? "nil" : "found") host=\(host?.displayLabel ?? "nil") surfaceID=\(surface.id)")
        guard let host else { return false }
        // Capture main-thread state up front; the upload runs off-main.
        let pwd = surface.pwd
        // A "run in current tab" docker attach is typed into the terminal, so
        // the tab's host carries no startup command — check the per-surface
        // registry the attach flow records, then fall back to parsing the
        // host's startup command (new tab / split attach).
        let container = tabs.containerAttaches[surface.id] ?? containerInfo(from: host)

        // Immediate feedback: a progress card floats over this pane.
        let files = urls.map { ($0.lastPathComponent, Self.fileSize(of: $0)) }
        DropUploadFeedback.shared.begin(surfaceID: surface.id, hostLabel: host.displayLabel, files: files)
        Task {
            let (dir, results) = await perform(urls: urls, host: host, surfacePwd: pwd, container: container, surfaceID: surface.id)
            await MainActor.run {
                let dest = container.map { "\($0.name):\(dir)" } ?? dir
                DropUploadFeedback.shared.setDest(surfaceID: surface.id, dest)
                DropUploadFeedback.shared.finish(surfaceID: surface.id,
                                                 ok: results.allSatisfy(\.ok))
                for (name, ok, reason) in results {
                    SarvNotifications.shared.notify(ok
                        ? .dropUploadFinished(file: name, host: host.displayLabel, dest: dest)
                        : .dropUploadFailed(file: name, host: host.displayLabel, dest: dest, reason: reason))
                }
            }
        }
        return true
    }

    private static func fileSize(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The docker container this SSH tab is attached to, parsed from the
    /// attach startup command (`[sudo] docker exec -it [-e PROMPT_COMMAND=…]`
    /// `<name> bash`). nil when the tab isn't a docker attach.
    static func containerInfo(from host: SavedHost) -> Container? {
        containerInfo(fromCommand: host.initialCommand)
    }

    /// Parse `[sudo] docker exec … <name> …` out of a command line — shared by
    /// the host-startup-command path and the "run in current tab" registry.
    static func containerInfo(fromCommand command: String) -> Container? {
        let tokens = command.split(whereSeparator: \.isWhitespace)
        // `1..<0` traps at runtime ("Range requires lowerBound <= upperBound")
        // — an empty startup command must not reach the range.
        guard tokens.count > 1 else { return nil }
        for i in 1..<tokens.count where tokens[i] == "exec" && tokens[i - 1] == "docker" {
            var j = i + 1
            while j < tokens.count {
                let t = tokens[j]
                // Skip docker options (`-it`, `-e`) and env assignments
                // (`PROMPT_COMMAND='…'`) — the container name is the first
                // positional argument. Container names can't contain `=`.
                if t.hasPrefix("-") || t.contains("=") {
                    j += 1
                    continue
                }
                return Container(name: String(t), needsSudo: tokens[0] == "sudo")
            }
        }
        return nil
    }

    // MARK: - Upload

    private static func perform(
        urls: [URL], host: SavedHost, surfacePwd: String?, container: Container?, surfaceID: UUID
    ) async -> (dir: String, results: [(name: String, ok: Bool, reason: String)]) {
        let dir = await resolveDir(host: host, surfacePwd: surfacePwd, container: container)
        if let container {
            let results = await uploadIntoContainer(urls: urls, host: host, container: container, dir: dir, surfaceID: surfaceID)
            return (dir, results)
        }
        let results = await uploadDirect(urls: urls, host: host, dir: dir, surfaceID: surfaceID)
        return (dir, results)
    }

    /// Accept only output that is actually a POSIX directory path. The remote
    /// shell can leak the sudo "enter password" prompt or mangled command text
    /// into stdout — a bogus "dir" would make `docker cp` fail with
    /// "no such directory", so garbage is rejected and the caller falls back.
    private static func cleanDir(_ raw: String) -> String? {
        let d = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard d.hasPrefix("/"),
              !d.contains(" "),
              !d.contains("\t"),
              !d.contains("\n"),
              !d.contains("\r") else { return nil }
        return d
    }

    /// The remote directory to upload into.
    ///
    /// Plain SSH: `surfacePwd` (OSC 7 live shell cwd) wins, else the login dir.
    ///
    /// Container: `surfacePwd` is NOT trustworthy here — it can hold the HOST's
    /// cwd (the login shell's OSC 7), which is the wrong place inside the
    /// container. Instead we ask the container directly: the attached shell's
    /// PROMPT_COMMAND writes its live `$PWD` to `/tmp/.sarv-cwd` on every
    /// prompt, so `docker exec … cat` returns the directory the user is
    /// actually cd'd into. Fall back to surfacePwd (it might be the container's
    /// own OSC 7) and then the container WORKDIR.
    private static func resolveDir(host: SavedHost, surfacePwd: String?, container: Container?) async -> String {
        if let container {
            let docker = container.needsSudo ? "sudo -S docker" : "docker"
            let stdin = container.needsSudo ? host.password + "\n" : nil
            let marker = await RemoteCommand.run(
                host: host,
                command: "\(docker) exec \(shellQuote(container.name)) sh -c 'cat /tmp/.sarv-cwd 2>/dev/null'",
                stdin: stdin)
            if marker.status == 0, let d = cleanDir(marker.stdout) { return d }
            if let surfacePwd, let d = cleanDir(surfacePwd) { return d }
            let wd = await RemoteCommand.run(
                host: host,
                command: "\(docker) exec \(shellQuote(container.name)) sh -c 'pwd'",
                stdin: stdin)
            if wd.status == 0, let d = cleanDir(wd.stdout) { return d }
            return "/"
        }
        if let surfacePwd, let d = cleanDir(surfacePwd) { return d }
        let r = await RemoteCommand.run(host: host, command: "pwd", stdin: nil)
        if r.status == 0, let d = cleanDir(r.stdout) { return d }
        return "/"
    }

    /// Plain SSH: one SFTP upload per file straight into `dir`.
    private static func uploadDirect(
        urls: [URL], host: SavedHost, dir: String, surfaceID: UUID
    ) async -> [(name: String, ok: Bool, reason: String)] {
        let remote = RemoteFileBackend(host: host)
        let local = LocalFileBackend()
        var out: [(String, Bool, String)] = []
        for url in urls {
            let item = makeItem(url)
            await MainActor.run { DropUploadFeedback.shared.setUploading(surfaceID: surfaceID, file: item.name) }
            let destPath = remote.join(dir, item.name)
            let poller = TransferProgressPoller.start(destBackend: remote, destPath: destPath) { size, _ in
                if let size {
                    DropUploadFeedback.shared.updateProgress(surfaceID: surfaceID, file: item.name, transferred: size)
                }
                return true
            }
            do {
                try await FileTransfer.copy(item: item, from: local, to: remote,
                                            destDir: dir, resolution: .replace)
                await MainActor.run { DropUploadFeedback.shared.markDone(surfaceID: surfaceID, file: item.name) }
                out.append((item.name, true, ""))
            } catch {
                let msg = errorMessage(error)
                await MainActor.run { DropUploadFeedback.shared.markFailed(surfaceID: surfaceID, file: item.name, reason: msg) }
                out.append((item.name, false, msg))
            }
            poller.cancel()
        }
        return out
    }

    /// Docker attach: SFTP into a host temp dir, `docker cp` into the
    /// container's current directory, then remove the temp dir.
    private static func uploadIntoContainer(
        urls: [URL], host: SavedHost, container: Container, dir: String, surfaceID: UUID
    ) async -> [(name: String, ok: Bool, reason: String)] {
        let docker = container.needsSudo ? "sudo -S docker" : "docker"
        let stdin = container.needsSudo ? host.password + "\n" : nil
        let tmpDir = "/tmp/sarv-drop-\(UUID().uuidString.prefix(8))"

        let mk = await RemoteCommand.run(host: host, command: "mkdir -p \(shellQuote(tmpDir))", stdin: stdin)
        guard mk.status == 0 else {
            return urls.map { ($0.lastPathComponent, false,
                              mk.stderr.isEmpty ? "Couldn't create the host temp directory." : mk.stderr) }
        }
        defer {
            Task { _ = await RemoteCommand.run(host: host, command: "rm -rf \(shellQuote(tmpDir))", stdin: stdin) }
        }

        let remote = RemoteFileBackend(host: host)
        let local = LocalFileBackend()
        var out: [(String, Bool, String)] = []
        for url in urls {
            let item = makeItem(url)
            await MainActor.run { DropUploadFeedback.shared.setUploading(surfaceID: surfaceID, file: item.name) }
            let hostTmpPath = tmpDir + "/" + item.name
            // The poller watches the host temp file, which grows during the
            // SFTP leg; it stays at full size while `docker cp` runs.
            let poller = TransferProgressPoller.start(destBackend: remote, destPath: hostTmpPath) { size, _ in
                if let size {
                    DropUploadFeedback.shared.updateProgress(surfaceID: surfaceID, file: item.name, transferred: size)
                }
                return true
            }
            do {
                try await FileTransfer.copy(item: item, from: local, to: remote,
                                            destDir: tmpDir, resolution: .replace)
            } catch {
                poller.cancel()
                let msg = errorMessage(error)
                await MainActor.run { DropUploadFeedback.shared.markFailed(surfaceID: surfaceID, file: item.name, reason: msg) }
                out.append((item.name, false, msg))
                continue
            }
            // `docker cp SRC CONTAINER:DIR/` — the trailing slash makes the
            // destination a directory. `container:` needs the `:`, and the path
            // may contain spaces, so quote the whole dest as one argument.
            let containerDest = "\(container.name):\(dir == "/" ? "/" : dir + "/")"
            let copy = await RemoteCommand.run(
                host: host,
                command: "\(docker) cp \(shellQuote(tmpDir + "/" + item.name)) \(shellQuote(containerDest))",
                stdin: stdin)
            poller.cancel()
            if copy.status == 0 {
                await MainActor.run { DropUploadFeedback.shared.markDone(surfaceID: surfaceID, file: item.name) }
                out.append((item.name, true, ""))
            } else {
                await MainActor.run { DropUploadFeedback.shared.markFailed(surfaceID: surfaceID, file: item.name, reason: copy.stderr) }
                out.append((item.name, false, copy.stderr.isEmpty ? "docker cp failed." : copy.stderr))
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func makeItem(_ url: URL) -> FileItem {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return FileItem(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: (attrs?[.type] as? FileAttributeType) == .typeDirectory,
            isSymlink: false,
            size: (attrs?[.size] as? NSNumber)?.int64Value ?? 0,
            modified: nil,
            permissions: nil
        )
    }

    private static func errorMessage(_ error: Error) -> String {
        (error as? FileOpError)?.message ?? error.localizedDescription
    }

    /// POSIX single-quote for a remote shell command argument.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
