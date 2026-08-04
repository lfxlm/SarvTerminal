import SwiftUI

/// SFTP side panel that slides in from the right edge of the Vaults window.
/// Shows a single-pane remote file browser for the connected SSH host, with
/// an upload button to transfer local files to the server.
struct SftpSidePanelView: View {
    let host: SavedHost
    let onClose: () -> Void

    @StateObject private var remote = SFTPBrowserModel()

    @ObservedObject private var lang = AppLanguageSettings.shared

    // ── Upload progress ───────────────────────────────────────────
    struct UploadProgress: Identifiable {
        let id = UUID()
        let fileName: String
        let fileSize: Int64     // 0 = indeterminate (dir)
        let direction: Direction
        var transferred: Int64
        var bytesPerSecond: Double
        var startTime: Date
        var status: Status
        enum Status { case uploading, completed, failed(String), cancelled }
        enum Direction { case upload, download }
    }
    @State private var uploads: [UploadProgress] = []
    @State private var activePollers: [Task<Void, Never>] = []
    /// In-flight upload/download Tasks keyed by record id — lets the per-row
    /// cancel button actually stop the transfer (not just hide the row).
    @State private var activeTransfers: [UUID: Task<Void, Never>] = [:]

    // ── Dialog state ──────────────────────────────────────────────
    @State private var showNewFolder = false
    @State private var renameTarget: FileItem?
    @State private var renameText = ""
    @State private var permTarget: FileItem?
    @State private var pendingDeletion: [FileItem]?
    @State private var imagePreview: ImagePreviewData?
    /// Queue of URLs whose remote name already exists; shown one-at-a-time via ConflictDialog.
    @State private var uploadConflictQueue: [URL] = []
    /// URLs that had no conflict and can be uploaded immediately once the queue is resolved.
    @State private var uploadNoConflict: [URL] = []
    /// Queue of FileItems whose local destination name already exists; shown
    /// one-at-a-time via ConflictDialog (downloads).
    @State private var downloadConflictQueue: [FileItem] = []
    /// Items with no conflict, pending once the download conflict queue resolves.
    @State private var downloadNoConflict: [FileItem] = []
    /// The chosen download directory while a download conflict queue is active.
    @State private var downloadDestDir: String?
    /// Debounced remote reload so batch uploads refresh the listing once, not N times.
    @State private var reloadTask: Task<Void, Never>?

    struct ImagePreviewData: Identifiable {
        let id = UUID()
        let url: URL
        let fileName: String
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(host.displayLabel)
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer()
            Button(action: uploadFiles) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text(loc(.upload)).font(.system(size: 11))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(loc(.upload_files))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc(.sftp_panel_close))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Body

    var body: some View {
        VaultsEditorSidebar(onClose: onClose, initialWidth: 420, minWidth: 340) {
            VStack(spacing: 0) {
                header
                Divider()
                FilePaneView(
                    model: remote,
                    onAction: { action in handle(action) },
                    showHostPicker: false,
                    compact: true,
                    copyActionLabel: loc(.download)
                )
                uploadProgressList
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers); return true
            }
            .overlay {
                if isDropTargeted {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 36))
                        Text("Drop files to upload")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear { remote.connect(to: .host(host)) }
        // ── Dialogs ───────────────────────────────────────────────
        .onChange(of: showNewFolder) { visible in
            guard visible else { return }
            SarvAlert.present(
                title: loc(.new_folder_title),
                buttons: [.init(loc(.create), isDefault: true), .init(loc(.cancel), isCancel: true)],
                inputInitial: ""
            ) { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await remote.newFolder(named: result.inputText) }
                }
            }
            showNewFolder = false
        }
        .onChange(of: renameTarget?.name) { _ in
            guard let target = renameTarget else { return }
            SarvAlert.present(
                title: loc(.rename_title),
                buttons: [.init(loc(.rename), isDefault: true), .init(loc(.cancel), isCancel: true)],
                inputInitial: renameText
            ) { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await remote.rename(target, to: result.inputText) }
                }
            }
            renameTarget = nil
        }
        .sheet(isPresented: Binding(
            get: { permTarget != nil },
            set: { if !$0 { permTarget = nil } }
        )) {
            if let t = permTarget {
                PermissionsSheet(
                    fileName: t.name, isDirectory: t.isDirectory, octal: octalGuess(t),
                    onApply: { octal in
                        Task { await remote.setPermissions(t, octal: octal) }
                        permTarget = nil
                    },
                    onCancel: { permTarget = nil }
                )
            }
        }
        .onChange(of: pendingDeletion?.count) { _ in
            guard let items = pendingDeletion else { return }
            let names = items.map(\.name)
            if names.count == 1 {
                DeleteConfirmation.confirm(names[0], detail: loc(.delete_confirm_detail)) { confirmed in
                    if confirmed { Task { await performDelete(items) } }
                }
            } else {
                SarvAlert.present(
                    title: loc(.delete_multi_title, names.count),
                    message: loc(.delete_multi_message, names.count),
                    buttons: [.init(loc(.delete), isDefault: true, isDestructive: true), .init(loc(.cancel), isCancel: true)]
                ) { result in
                    if result.buttonIndex == 0 { Task { await performDelete(items) } }
                }
            }
            pendingDeletion = nil
        }
        .overlay {
            if let p = imagePreview {
                ImagePreviewView(url: p.url, fileName: p.fileName) { imagePreview = nil }
            }
        }
        .overlay {
            if let url = uploadConflictQueue.first {
                ConflictDialog(name: url.lastPathComponent, showApplyToAll: true) { resolution, all in
                    resolveUploadConflict(resolution, applyToAll: all)
                }
            }
        }
        .overlay {
            if let item = downloadConflictQueue.first {
                ConflictDialog(name: item.name, showApplyToAll: true) { resolution, all in
                    resolveDownloadConflict(item, resolution, applyToAll: all)
                }
            }
        }
        .onDisappear {
            // Clean up all active transfers AND pollers when the panel disappears
            // — a cancelled Task terminates the underlying ssh/scp process, so
            // uploads don't keep running invisibly after the panel closes.
            activeTransfers.values.forEach { $0.cancel() }
            activeTransfers.removeAll()
            activePollers.forEach { $0.cancel() }
            activePollers.removeAll()
            reloadTask?.cancel()
            uploads.removeAll()
        }
    }

    // -- Drag-and-drop state --
    @State private var isDropTargeted = false

    /// Load file URLs from dropped providers and upload them.
    private func handleDrop(_ providers: [NSItemProvider]) {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !collected.isEmpty { uploadURLs(collected) }
        }
    }

    // MARK: - Upload progress list (bottom)

    @ViewBuilder
    private var uploadProgressList: some View {
        if !uploads.isEmpty {
            Divider()
            VStack(spacing: 0) {
                // Header with clear button
                if uploads.contains(where: { if case .completed = $0.status { return true }
                    if case .failed = $0.status { return true }; return false }) {
                    HStack {
                        Spacer()
                        Button(loc(.clear_completed)) {
                            // Only drop finished records — never the in-flight ones.
                            uploads.removeAll { if case .uploading = $0.status { return false }; return true }
                        }
                            .controlSize(.small).buttonStyle(.plain)
                            .foregroundStyle(.secondaryText)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    Divider()
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(uploads) { u in uploadRow(u) }
                    }
                }
                .frame(maxHeight: 120)
            }
            .background(Color.secondary.opacity(0.04))
        }
    }

    private func uploadRow(_ u: UploadProgress) -> some View {
        return HStack(spacing: 10) {
            // Source → Destination
            if u.direction == .upload {
                HStack(spacing: 3) {
                    Image(systemName: "desktopcomputer").font(.system(size: 9))
                    Text(loc(.local)).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 70, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiaryText).frame(width: 10)
                HStack(spacing: 3) {
                    Image(systemName: "server.rack").font(.system(size: 9))
                    Text(host.displayLabel).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 70, alignment: .leading)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "server.rack").font(.system(size: 9))
                    Text(host.displayLabel).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 70, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiaryText).frame(width: 10)
                HStack(spacing: 3) {
                    Image(systemName: "desktopcomputer").font(.system(size: 9))
                    Text(loc(.local)).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 70, alignment: .leading)
            }

            // File name
            Text(u.fileName).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(u.fileSize > 0 ? byteString(u.fileSize) : "—")
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 60, alignment: .trailing)

            // Progress / status
            HStack(spacing: 4) {
                switch u.status {
                case .uploading:
                    if u.fileSize > 0 {
                        let f = min(1, Double(max(0, u.transferred)) / Double(u.fileSize))
                        ProgressView(value: f)
                            .progressViewStyle(.linear)
                            .frame(width: 50)
                            .hoverTip {
                                String(format: "%.1f%%", f * 100) + " · " + formatElapsed(Date().timeIntervalSince(u.startTime))
                            }
                    } else {
                        ProgressView()
                            .scaleEffect(x: 0.7, y: 0.4, anchor: .leading)
                            .frame(width: 40)
                            .hoverTip {
                                formatElapsed(Date().timeIntervalSince(u.startTime))
                            }
                    }
                case .completed:
                    Text(loc(.done)).foregroundStyle(.green)
                        .hoverTip {
                            formatElapsed(Date().timeIntervalSince(u.startTime))
                        }
                case .failed(let msg):
                    Text(msg).foregroundStyle(.red).lineLimit(1)
                        .hoverTip {
                            formatElapsed(Date().timeIntervalSince(u.startTime))
                        }
                case .cancelled:
                    Text(loc(.cancelled)).foregroundStyle(.secondaryText)
                }
                if case .uploading = u.status, u.bytesPerSecond > 0 {
                    Text("\(byteString(Int64(u.bytesPerSecond)))/s")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiaryText)
                }
            }
            .frame(width: 90, alignment: .leading)

            // Cancel / Dismiss
            switch u.status {
            case .uploading:
                Button { cancelTransfer(u.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondaryText)
                .hoverTipText(loc(.cancel_transfer_tip))
            case .completed, .failed, .cancelled:
                Button { uploads.removeAll(where: { $0.id == u.id }) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondaryText)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).padding(.vertical, 3)
        .frame(minHeight: 22)
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return String(format: "%dm%02ds", m, s)
        } else {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            return String(format: "%dh%02dm", h, m)
        }
    }

    // MARK: - File actions

    private func handle(_ action: FilePaneAction) {
        switch action {
        case .chooseHost: break
        case .open(let item):
            if item.isDirectory { remote.open(item) }
            else if isImageFile(item.name) { openImagePreview(item) }
            else {
                FileEditorWindowController.shared.open(
                    model: FileViewerModel(item: item, backend: remote.backend), onDismiss: {})
            }
        case .goUp: remote.goUp()
        case .navigate(let p): Task { await remote.load(p) }
        case .refresh: Task { await remote.reload() }
        case .newFolder: showNewFolder = true
        case .rename(let item): renameText = item.name; renameTarget = item
        case .delete(let items): pendingDeletion = items
        case .editPermissions(let item): permTarget = item
        case .copyToTarget(let items): downloadItems(items)
        }
    }

    // MARK: - Download

    private func downloadItems(_ items: [FileItem]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = loc(.choose_download_folder)
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            let local = LocalFileBackend()
            Task {
                // Never silently overwrite a local file with the same name.
                var conflicts: [FileItem] = []
                var safe: [FileItem] = []
                for item in items {
                    if (try? await local.exists(local.join(destURL.path, item.name))) ?? false {
                        conflicts.append(item)
                    } else {
                        safe.append(item)
                    }
                }
                if conflicts.isEmpty {
                    performDownload(safe, destDir: destURL.path, resolution: .replace)
                } else {
                    downloadNoConflict = safe
                    downloadDestDir = destURL.path
                    downloadConflictQueue = conflicts
                }
            }
        }
    }

    /// Actually execute downloads (after any conflict confirmation).
    private func performDownload(_ items: [FileItem], destDir: String, resolution: ConflictResolution) {
        let local = LocalFileBackend()
        for item in items {
            let destPath = local.join(destDir, item.name)
            let size = item.isDirectory ? 0 : item.size
            let prog = UploadProgress(
                fileName: item.name, fileSize: size,
                direction: .download, transferred: 0, bytesPerSecond: 0,
                startTime: Date(), status: .uploading
            )
            uploads.append(prog)
            let pid = prog.id
            let poller = startPoller(for: pid, destBackend: local, destPath: destPath, totalSize: size)
            activeTransfers[pid] = Task {
                defer {
                    poller.cancel()
                    activeTransfers.removeValue(forKey: pid)
                }
                do {
                    try await FileTransfer.copy(
                        item: item, from: remote.backend, to: local,
                        destDir: destDir, resolution: resolution
                    )
                    snapToFullSize(pid)
                    setStatus(pid, .completed)
                } catch {
                    if Task.isCancelled { setStatus(pid, .cancelled) }
                    else { setStatus(pid, .failed(error.localizedDescription)) }
                }
            }
        }
    }

    /// Handle a user choice from a download ConflictDialog.
    /// `applyToAll` resolves the whole remaining queue with one choice.
    private func resolveDownloadConflict(_ item: FileItem, _ resolution: ConflictResolution, applyToAll: Bool) {
        guard let destDir = downloadDestDir, !downloadConflictQueue.isEmpty else { return }

        if applyToAll {
            let remaining = downloadConflictQueue
            let safe = downloadNoConflict
            downloadConflictQueue.removeAll()
            downloadNoConflict.removeAll()
            switch resolution {
            case .stop, .skip:
                break
            case .replace, .duplicate, .merge:
                performDownload(remaining, destDir: destDir, resolution: resolution)
                if !safe.isEmpty { performDownload(safe, destDir: destDir, resolution: .replace) }
            }
            return
        }

        downloadConflictQueue.removeFirst()
        switch resolution {
        case .stop:
            downloadConflictQueue.removeAll()
            downloadNoConflict.removeAll()
            return
        case .skip:
            break
        case .replace, .duplicate, .merge:
            performDownload([item], destDir: destDir, resolution: resolution)
        }
        if downloadConflictQueue.isEmpty && !downloadNoConflict.isEmpty {
            performDownload(downloadNoConflict, destDir: destDir, resolution: .replace)
            downloadNoConflict.removeAll()
        }
    }

    // MARK: - Upload

    private func uploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            uploadURLs(panel.urls)
        }
    }

    /// Core upload logic shared by the file-picker button and drag-and-drop.
    /// Checks for name conflicts first, shows ConflictDialog one-at-a-time.
    private func uploadURLs(_ urls: [URL]) {
        Task {
            var conflicts: [URL] = []
            var safe: [URL] = []
            for url in urls {
                if await remote.exists(name: url.lastPathComponent) {
                    conflicts.append(url)
                } else {
                    safe.append(url)
                }
            }
            if conflicts.isEmpty {
                performUpload(urls, resolution: .replace)
            } else {
                uploadNoConflict = safe
                uploadConflictQueue = conflicts
            }
        }
    }

    /// Handle a user choice from the per-file ConflictDialog.
    /// `applyToAll` resolves the whole remaining queue with one choice.
    private func resolveUploadConflict(_ resolution: ConflictResolution, applyToAll: Bool) {
        guard !uploadConflictQueue.isEmpty else { return }

        // "Apply to all remaining" — resolve the whole queue at once.
        if applyToAll {
            let remaining = uploadConflictQueue
            let safe = uploadNoConflict
            uploadConflictQueue.removeAll()
            uploadNoConflict.removeAll()
            switch resolution {
            case .stop:
                markCancelled(remaining + safe)
            case .skip:
                if !safe.isEmpty { performUpload(safe, resolution: .replace) }
            case .replace, .duplicate, .merge:
                performUpload(remaining, resolution: resolution)
                if !safe.isEmpty { performUpload(safe, resolution: .replace) }
            }
            return
        }

        let url = uploadConflictQueue.removeFirst()
        switch resolution {
        case .stop:
            // Abort everything remaining — surface the aborted uploads in the list.
            markCancelled(uploadConflictQueue + uploadNoConflict)
            uploadConflictQueue.removeAll()
            uploadNoConflict.removeAll()
            return
        case .skip:
            break // just skip this file
        case .replace, .duplicate, .merge:
            performUpload([url], resolution: resolution)
        }
        // If queue is empty, also upload all non-conflicting files.
        if uploadConflictQueue.isEmpty && !uploadNoConflict.isEmpty {
            performUpload(uploadNoConflict, resolution: .replace)
            uploadNoConflict.removeAll()
        }
    }

    /// Record aborted uploads in the transfer list so the user sees what was cancelled.
    private func markCancelled(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            uploads.append(UploadProgress(
                fileName: url.lastPathComponent,
                fileSize: size?.int64Value ?? 0,
                direction: .upload,
                transferred: 0,
                bytesPerSecond: 0,
                startTime: Date(),
                status: .cancelled))
        }
    }

    /// Debounced reload: one refresh after the burst of upload completions settles.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await remote.reload()
        }
    }

    /// Actually execute the upload (after any conflict confirmation).
    private func performUpload(_ urls: [URL], resolution: ConflictResolution) {
        let fm = FileManager.default
        let local = LocalFileBackend()
        let destDir = remote.path

        for url in urls {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
            let item = FileItem(
                name: url.lastPathComponent, path: url.path,
                isDirectory: isDir, isSymlink: false,
                size: fileSize, modified: nil, permissions: nil
            )
            let destPath = remote.backend.join(destDir, item.name)
            let progress = UploadProgress(
                fileName: url.lastPathComponent, fileSize: fileSize,
                direction: .upload, transferred: 0, bytesPerSecond: 0,
                startTime: Date(), status: .uploading
            )
            uploads.append(progress)
            let pid = progress.id
            let poller = startPoller(for: pid, destBackend: remote.backend, destPath: destPath, totalSize: fileSize)
            activePollers.append(poller)

            activeTransfers[pid] = Task {
                defer {
                    poller.cancel()
                    activePollers.removeAll { $0 == poller }
                    activeTransfers.removeValue(forKey: pid)
                }
                do {
                    try await FileTransfer.copy(
                        item: item, from: local, to: remote.backend,
                        destDir: destDir, resolution: resolution
                    )
                    snapToFullSize(pid)
                    setStatus(pid, .completed)
                    scheduleReload()
                } catch {
                    if Task.isCancelled { setStatus(pid, .cancelled) }
                    else { setStatus(pid, .failed(error.localizedDescription)) }
                }
            }
        }
    }

    /// Cancel a transfer that's still in flight — terminates the underlying
    /// ssh/scp process via Task cancellation (see `runProcess`), so the upload
    /// really stops instead of finishing silently in the background.
    private func cancelTransfer(_ id: UUID) {
        activeTransfers[id]?.cancel()
        activeTransfers[id] = nil
        setStatus(id, .cancelled)
    }

    private func startPoller(for pid: UUID, destBackend: FileBackend, destPath: String, totalSize: Int64) -> Task<Void, Never> {
        TransferProgressPoller.start(destBackend: destBackend, destPath: destPath) { size, elapsed in
            guard let idx = uploads.firstIndex(where: { $0.id == pid }),
                  case .uploading = uploads[idx].status else { return false }
            uploads[idx].transferred = size ?? uploads[idx].transferred
            uploads[idx].bytesPerSecond = Double(uploads[idx].transferred) / elapsed
            return true
        }
    }

    private func snapToFullSize(_ pid: UUID) {
        guard let idx = uploads.firstIndex(where: { $0.id == pid }) else { return }
        let total = uploads[idx].fileSize
        if total > 0 { uploads[idx].transferred = total }
    }

    private func setStatus(_ id: UUID, _ status: UploadProgress.Status) {
        if let idx = uploads.firstIndex(where: { $0.id == id }) {
            uploads[idx].status = status
        }
    }

    // MARK: - Delete

    @MainActor
    private func performDelete(_ items: [FileItem]) async {
        var failures: [(name: String, message: String)] = []
        for item in items {
            do {
                try await remote.backend.delete(item)
            } catch {
                let msg = (error as? FileOpError)?.message ?? error.localizedDescription
                failures.append((item.name, msg))
            }
        }
        await remote.reload()
        if !failures.isEmpty { presentDeleteFailures(failures, total: items.count) }
    }

    /// Surface delete failures instead of swallowing them — a permission error
    /// or a busy file must not look like a successful deletion.
    private func presentDeleteFailures(_ failures: [(name: String, message: String)], total: Int) {
        let message = loc(.delete_failed_message, failures.count, total)
            + "\n\n"
            + failures.map { "\($0.name) — \($0.message)" }.joined(separator: "\n")
        SarvAlert.present(
            title: loc(.delete_failed_title),
            message: message,
            buttons: [.init(loc(.ok), isDefault: true)]
        )
    }

    // MARK: - Image preview

    private func isImageFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg","jpeg","png","gif","bmp","tiff","tif","heic","heif","webp","ico","icns"].contains(ext)
    }

    private func openImagePreview(_ item: FileItem) {
        Task {
            do {
                let url = try await remote.backend.localCopy(of: item)
                imagePreview = ImagePreviewData(url: url, fileName: item.name)
            } catch {
                FileEditorWindowController.shared.open(
                    model: FileViewerModel(item: item, backend: remote.backend), onDismiss: {})
            }
        }
    }

    private func octalGuess(_ item: FileItem) -> String {
        guard let p = item.permissions, p.count == 9 else { return item.isDirectory ? "755" : "644" }
        let chars = Array(p)
        var digits = ""
        for chunk in stride(from: 0, to: 9, by: 3) {
            var v = 0
            if chars[chunk] == "r" { v += 4 }
            if chars[chunk + 1] == "w" { v += 2 }
            if chars[chunk + 2] == "x" { v += 1 }
            digits += "\(v)"
        }
        return digits
    }
}
