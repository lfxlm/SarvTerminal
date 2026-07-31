import SwiftUI

/// Dual-pane file manager (SFTP + local, server↔server). Each pane points at
/// Local or a saved host; "Copy to target directory" transfers the selection
/// into the OTHER pane's current folder. Replaces the old SFTP and SCP tabs.
/// Holds the two SFTP panes so their state (current folder, connected host,
/// listing) survives the dashboard being torn down when a terminal tab shows.
/// `SFTPView`'s own `@StateObject` panes used to reset on every re-mount.
/// Live progress for an in-flight transfer.
struct TransferState: Equatable {
    enum Status: Equatable {
        case inProgress
        case completed
        case failed(String)
        case cancelled
    }

    var fileName: String
    var total: Int64          // 0 = indeterminate (e.g. a directory)
    var transferred: Int64
    var bytesPerSecond: Double
    var direct: Bool          // true = server→server direct; false = via this Mac
    var status: Status = .inProgress
    var startTime: Date
}

@MainActor
final class SFTPSession: ObservableObject {
    static let shared = SFTPSession()
    let left = SFTPBrowserModel()
    let right = SFTPBrowserModel()

    /// Current transfers (typically 0–1 items). Lives here so the table
    /// survives the dashboard being torn down for a terminal tab.
    @Published var transfers: [TransferState] = []
    /// The in-flight transfer task, so it can be cancelled from the table.
    var transferTask: Task<Void, Never>?

    func cancelTransfer() { transferTask?.cancel() }

    private var started = false
    private init() {}

    /// Connect both panes to Local — once, ever. No-op after the first call so
    /// returning to SFTP keeps wherever the user navigated.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        left.connect(to: .local)
        right.connect(to: .local)
    }
}

struct SFTPView: View {
    @ObservedObject private var left = SFTPSession.shared.left
    @ObservedObject private var right = SFTPSession.shared.right
    @ObservedObject private var session = SFTPSession.shared

    enum Side: String, Identifiable { case left, right; var id: String { rawValue } }

    // Dialog state (centralized so both panes share identical behavior).
    @State private var hostPickerSide: Side?
    @State private var newFolderSide: Side?
    @State private var newFolderName = ""
    @State private var renameTarget: (side: Side, item: FileItem)?
    @State private var renameText = ""
    @State private var permTarget: (side: Side, item: FileItem)?
    @State private var conflict: ConflictRequest?
    @State private var pendingDelete: (side: Side, item: FileItem)?

    struct ConflictRequest: Identifiable {
        let id = UUID()
        let item: FileItem
        let fromSide: Side
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FilePaneView(model: left) { handle($0, on: .left) }
                Divider()
                FilePaneView(model: right) { handle($0, on: .right) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !session.transfers.isEmpty {
                Divider()
                transfersTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { SFTPSession.shared.startIfNeeded() }
        .sheet(item: $hostPickerSide) { side in
            FileHostChooser { location in
                model(side).connect(to: location)
                hostPickerSide = nil
            } onCancel: { hostPickerSide = nil }
        }
        // Dialogs go through SarvAlert (centered-logo card) — same semantics as
        // every other popup in the app.
        .onChange(of: newFolderSide) { side in
            guard let side else { return }
            SarvAlert.present(
                title: "New Folder",
                buttons: [
                    .init("Create", isDefault: true),
                    .init("Cancel", isCancel: true),
                ],
                inputInitial: "") { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await model(side).newFolder(named: result.inputText) }
                }
            }
            newFolderSide = nil
        }
        .onChange(of: renameTarget?.item.name) { _ in
            guard let target = renameTarget else { return }
            SarvAlert.present(
                title: "Rename",
                buttons: [
                    .init("Rename", isDefault: true),
                    .init("Cancel", isCancel: true),
                ],
                inputInitial: renameText) { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await model(target.side).rename(target.item, to: result.inputText) }
                }
            }
            renameTarget = nil
        }
        .sheet(isPresented: Binding(get: { permTarget != nil }, set: { if !$0 { permTarget = nil } })) {
            if let t = permTarget {
                PermissionsSheet(
                    fileName: t.item.name,
                    isDirectory: t.item.isDirectory,
                    octal: octalGuess(t.item),
                    onApply: { octal in
                        Task { await model(t.side).setPermissions(t.item, octal: octal) }
                        permTarget = nil
                    },
                    onCancel: { permTarget = nil })
            }
        }
        // Shared centered-logo confirm — one delete semantic everywhere.
        .onChange(of: pendingDelete?.item.name) { _ in
            guard let d = pendingDelete else { return }
            DeleteConfirmation.confirm(d.item.name, detail: "This can't be undone.") { confirmed in
                if confirmed { Task { await model(d.side).delete(d.item) } }
            }
            pendingDelete = nil
        }
        .overlay {
            if let c = conflict { ConflictDialog(name: c.item.name) { r, _ in resolve(c, r) } }
        }
    }

    // MARK: - Transfer table

    /// Minimal transfer list at the bottom of the view.
    private var transfersTable: some View {
        VStack(spacing: 0) {
            ForEach(session.transfers.indices, id: \.self) { idx in
                let t = session.transfers[idx]
                TransferRow(state: t, byteString: byteString,
                            onCancel: { session.cancelTransfer() },
                            onDelete: { session.transfers.remove(at: idx) })
            }
            HStack {
                if session.transfers.allSatisfy({ $0.status != .inProgress }) {
                    Spacer()
                    Button("Clear completed") { session.transfers.removeAll() }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    // MARK: - Coordination

    private func model(_ side: Side) -> SFTPBrowserModel { side == .left ? left : right }
    private func otherSide(_ side: Side) -> Side { side == .left ? .right : .left }

    private func handle(_ action: FilePaneAction, on side: Side) {
        let m = model(side)
        switch action {
        case .chooseHost: hostPickerSide = side
        case .open(let item):
            if item.isDirectory { m.open(item) }
            else { FileEditorWindowController.shared.open(model: FileViewerModel(item: item, backend: m.backend), onDismiss: { SFTPWindowManager.shared.show() }) }
        case .goUp: m.goUp()
        case .navigate(let p): Task { await m.load(p) }
        case .refresh: Task { await m.reload() }
        case .newFolder: newFolderName = ""; newFolderSide = side
        case .rename(let item): renameText = item.name; renameTarget = (side, item)
        case .delete(let items):
            if SFTPSettings.shared.confirmDelete { pendingDelete = (side, items.first!) }
            else { Task { for item in items { try? await m.delete(item) } } }
        case .editPermissions(let item): permTarget = (side, item)
        case .copyToTarget(let items): startCopy(items.first!, from: side)
        }
    }

    private func startCopy(_ item: FileItem, from side: Side) {
        let dest = model(otherSide(side))
        Task {
            if await dest.exists(name: item.name) {
                conflict = ConflictRequest(item: item, fromSide: side)
            } else {
                beginTransfer(item, from: side, resolution: .replace) // no conflict → straight copy
            }
        }
    }

    private func resolve(_ request: ConflictRequest, _ resolution: ConflictResolution) {
        conflict = nil
        guard resolution != .stop, resolution != .skip else { return }
        beginTransfer(request.item, from: request.fromSide, resolution: resolution)
    }

    /// Start a transfer as a cancellable task tracked by the session.
    private func beginTransfer(_ item: FileItem, from side: Side, resolution: ConflictResolution) {
        let task = Task { await performCopy(item, from: side, resolution: resolution) }
        session.transferTask = task
        Task { await task.value; session.transferTask = nil }
    }

    private func performCopy(_ item: FileItem, from side: Side, resolution: ConflictResolution) async {
        let source = model(side), dest = model(otherSide(side))
        let started = Date()
        // Server → server. We have both hosts' details, so never ask — try the
        // direct path when the destination is key-based, and otherwise (or if the
        // servers can't reach each other) relay through this Mac automatically.
        if source.backend is RemoteFileBackend, dest.backend is RemoteFileBackend {
            // Always try a direct A→B transfer first (key → agent forwarding,
            // password → saved password via one-shot askpass on A). Only relay
            // through this Mac if the servers can't reach each other.
            var ok = await runRemoteTransfer(item, from: side, resolution: resolution, direct: true)
            if !ok, !Task.isCancelled {
                ok = await runRemoteTransfer(item, from: side, resolution: resolution, direct: false)
            }
            notifyTransferOutcome(item: item, succeeded: ok, reason: dest.error, started: started)
            return
        }
        // Local ⇄ remote (or local ⇄ local): the existing path, with progress.
        var failure: String?
        await withProgress(item: item, destBackend: dest.backend, destDir: dest.path,
                           resolution: resolution, direct: false) {
            try await FileTransfer.copy(item: item, from: source.backend, to: dest.backend,
                                        destDir: dest.path, resolution: resolution)
        } onFinish: { await dest.reload() } onError: { dest.error = $0; failure = $0 }
        notifyTransferOutcome(item: item, succeeded: failure == nil, reason: failure, started: started)
    }

    /// Post a finished/failed notification for one completed transfer. Quick
    /// transfers (< 3s) only notify on failure, to avoid noise; a user-cancelled
    /// transfer doesn't notify at all.
    private func notifyTransferOutcome(item: FileItem, succeeded: Bool, reason: String?, started: Date) {
        if Task.isCancelled { return }
        let elapsed = Date().timeIntervalSince(started)
        Task { @MainActor in
            if succeeded {
                if elapsed >= 3 {
                    SarvNotifications.shared.notify(.sftpFinished(file: item.name, host: nil))
                }
            } else {
                SarvNotifications.shared.notify(
                    .sftpFailed(file: item.name, host: nil, reason: reason ?? "Transfer failed"))
            }
        }
    }

    /// Run a server→server transfer. Returns false on failure (so the caller can
    /// fall back from direct → relay). A relay failure is surfaced to the pane;
    /// a direct failure is silent (we just relay instead).
    @discardableResult
    private func runRemoteTransfer(_ item: FileItem, from side: Side, resolution: ConflictResolution, direct: Bool) async -> Bool {
        guard let src = model(side).backend as? RemoteFileBackend,
              let dst = model(otherSide(side)).backend as? RemoteFileBackend else { return false }
        let dest = model(otherSide(side))
        var ok = true
        await withProgress(item: item, destBackend: dst, destDir: dest.path, resolution: resolution, direct: direct) {
            _ = try await FileTransfer.serverToServer(item: item, from: src, to: dst,
                                                      destDir: dest.path, resolution: resolution, direct: direct)
        } onFinish: { await dest.reload() } onError: { msg in
            ok = false
            if !direct { dest.error = msg }   // relay is the final attempt → surface it
        }
        return ok
    }

    /// Wrap a transfer with the progress overlay + a poller that watches the
    /// destination file's size against the known source size.
    private func withProgress(item: FileItem, destBackend: FileBackend, destDir: String,
                              resolution: ConflictResolution, direct: Bool,
                              _ op: @escaping () async throws -> Void,
                              onFinish: @escaping () async -> Void,
                              onError: @escaping (String) -> Void) async {
        let destPath = destBackend.join(destDir, FileTransfer.finalName(for: item, resolution: resolution))
        let total = item.isDirectory ? 0 : item.size
        let state = TransferState(fileName: item.name, total: total, transferred: 0,
                                  bytesPerSecond: 0, direct: direct, startTime: Date())
        session.transfers.append(state)
        let poller = TransferProgressPoller.start(destBackend: destBackend, destPath: destPath) { size, elapsed in
            guard let idx = session.transfers.lastIndex(where: { $0.status == .inProgress }) else { return false }
            session.transfers[idx].transferred = size ?? session.transfers[idx].transferred
            session.transfers[idx].bytesPerSecond = Double(session.transfers[idx].transferred) / elapsed
            return true
        }
        do {
            try await op()
            await onFinish()
            // Mark as completed (fill transferred if known).
            if let idx = session.transfers.lastIndex(where: { $0.status == .inProgress }) {
                if session.transfers[idx].total > 0 {
                    session.transfers[idx].transferred = session.transfers[idx].total
                }
                session.transfers[idx].status = .completed
            }
        } catch {
            if Task.isCancelled {
                if let idx = session.transfers.lastIndex(where: { $0.status == .inProgress }) {
                    session.transfers[idx].status = .cancelled
                }
            } else {
                let msg = (error as? FileOpError)?.message ?? error.localizedDescription
                onError(msg)
                if let idx = session.transfers.lastIndex(where: { $0.status == .inProgress }) {
                    session.transfers[idx].status = .failed(msg)
                }
            }
        }
        poller.cancel()
    }

    /// Best-effort octal default for the permissions dialog from "rwxr-xr-x".
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

// MARK: - Transfer row

/// A single row in the transfer-progress list at the bottom of SFTPView.
private struct TransferRow: View {
    let state: TransferState
    let byteString: (Int64) -> String
    let onCancel: () -> Void
    let onDelete: () -> Void

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

    var body: some View {
        let fraction = state.total > 0
            ? min(1, Double(state.transferred) / Double(state.total))
            : 0
        HStack(spacing: 6) {
            // File name
            Text(state.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)

            Spacer(minLength: 4)

            // Status + progress
            switch state.status {
            case .inProgress:
                if state.total > 0 {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .hoverTip {
                            String(format: "%.1f%%", fraction * 100) + " · " + formatElapsed(Date().timeIntervalSince(state.startTime))
                        }
                } else {
                    ProgressView()
                        .scaleEffect(x: 0.8, y: 0.5, anchor: .leading)
                        .frame(width: 60)
                        .hoverTip {
                            formatElapsed(Date().timeIntervalSince(state.startTime))
                        }
                }
            case .completed:
                Text("Done").font(.caption2).foregroundStyle(.green)
            case .failed:
                Text("Failed").font(.caption2).foregroundStyle(.red)
            case .cancelled:
                Text("Cancelled").font(.caption2).foregroundStyle(.secondaryText)
            }

            // Size / speed
            if state.total > 0 || state.status == .inProgress {
                Text(state.status == .inProgress
                     ? byteString(state.transferred)
                     : "\(byteString(state.transferred)) / \(byteString(state.total))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondaryText)
                    .frame(minWidth: 60, alignment: .trailing)
            }

            // Speed (only in-progress)
            if state.status == .inProgress, state.bytesPerSecond > 0 {
                Text("\(byteString(Int64(state.bytesPerSecond)))/s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiaryText)
                    .frame(width: 64, alignment: .trailing)
            }

            // Action
            switch state.status {
            case .inProgress:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            case .completed, .failed, .cancelled:
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.secondaryText)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(state.status == .inProgress ? Color.blue.opacity(0.03) : Color.clear)
    }
}

/// Actions a pane reports up to the coordinator.
enum FilePaneAction {
    case chooseHost
    case open(FileItem)
    case goUp
    case navigate(String)
    case refresh
    case newFolder
    case rename(FileItem)
    case delete([FileItem])
    case editPermissions(FileItem)
    case copyToTarget([FileItem])
}
