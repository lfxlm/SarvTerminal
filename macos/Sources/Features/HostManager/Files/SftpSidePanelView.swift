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
        var status: Status
        enum Status { case uploading, completed, failed(String) }
        enum Direction { case upload, download }
    }
    @State private var uploads: [UploadProgress] = []

    // ── Dialog state ──────────────────────────────────────────────
    @State private var showNewFolder = false
    @State private var renameTarget: FileItem?
    @State private var renameText = ""
    @State private var permTarget: FileItem?
    @State private var pendingDeletion: [FileItem]?
    @State private var imagePreview: ImagePreviewData?

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
                        Button(loc(.clear_completed)) { uploads.removeAll() }
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
                        ProgressView(value: f).progressViewStyle(.linear).frame(width: 50)
                    } else {
                        ProgressView().scaleEffect(x: 0.7, y: 0.4, anchor: .leading).frame(width: 40)
                    }
                case .completed:
                    Text(loc(.done)).foregroundStyle(.green)
                case .failed(let msg):
                    Text(msg).foregroundStyle(.red).lineLimit(1)
                }
                if case .uploading = u.status, u.bytesPerSecond > 0 {
                    Text("\(byteString(Int64(u.bytesPerSecond)))/s")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiaryText)
                }
            }
            .frame(width: 90, alignment: .leading)

            // Dismiss
            switch u.status {
            case .uploading: EmptyView()
            case .completed, .failed:
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
            for item in items {
                let destPath = local.join(destURL.path, item.name)
                let size = item.isDirectory ? 0 : item.size
                let prog = UploadProgress(
                    fileName: item.name, fileSize: size,
                    direction: .download, transferred: 0, bytesPerSecond: 0,
                    status: .uploading
                )
                uploads.append(prog)
                let pid = prog.id
                let poller = startPoller(for: pid, destBackend: local, destPath: destPath, totalSize: size)

                Task {
                    defer { poller.cancel() }
                    do {
                        try await FileTransfer.copy(
                            item: item, from: remote.backend, to: local,
                            destDir: destURL.path, resolution: .replace
                        )
                        snapToFullSize(pid)
                        setStatus(pid, .completed)
                    } catch {
                        setStatus(pid, .failed(error.localizedDescription))
                    }
                }
            }
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
            let fm = FileManager.default
            let local = LocalFileBackend()
            let destDir = remote.path

            for url in panel.urls {
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let item = FileItem(
                    name: url.lastPathComponent, path: url.path,
                    isDirectory: false, isSymlink: false,
                    size: fileSize, modified: nil, permissions: nil
                )
                let destPath = remote.backend.join(destDir, item.name)
                let progress = UploadProgress(
                    fileName: url.lastPathComponent, fileSize: fileSize,
                    direction: .upload, transferred: 0, bytesPerSecond: 0,
                    status: .uploading
                )
                uploads.append(progress)
                let pid = progress.id
                let poller = startPoller(for: pid, destBackend: remote.backend, destPath: destPath, totalSize: fileSize)

                Task {
                    defer { poller.cancel() }
                    do {
                        try await FileTransfer.copy(
                            item: item, from: local, to: remote.backend,
                            destDir: destDir, resolution: .replace
                        )
                        snapToFullSize(pid)
                        setStatus(pid, .completed)
                        await remote.reload()
                    } catch {
                        setStatus(pid, .failed(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func startPoller(for pid: UUID, destBackend: FileBackend, destPath: String, totalSize: Int64) -> Task<Void, Never> {
        let start = Date()
        return Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { break }
                guard let idx = uploads.firstIndex(where: { $0.id == pid }),
                      case .uploading = uploads[idx].status else { break }
                let size = await destBackend.fileSize(destPath) ?? uploads[idx].transferred
                let elapsed = max(0.001, Date().timeIntervalSince(start))
                uploads[idx].transferred = size
                uploads[idx].bytesPerSecond = Double(size) / elapsed
            }
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
        for item in items { try? await remote.delete(item) }
        await remote.reload()
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
