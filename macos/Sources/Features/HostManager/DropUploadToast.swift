import SwiftUI

/// Live, per-pane feedback for drag-and-drop uploads into terminal panes.
///
/// The moment a drop lands, a small progress card floats over the pane it was
/// dropped on — per-file progress bars (like the SFTP panel's transfer list)
/// plus the resolved destination. It disappears a few seconds after ALL files
/// finish. macOS notifications are unreliable (authorization can be denied) and
/// only appear after the fact, so this is the primary feedback channel.
@MainActor
final class DropUploadFeedback: ObservableObject {
    static let shared = DropUploadFeedback()
    private init() {}

    enum State: Equatable {
        case uploading
        case success
        case failed
    }

    struct FileProgress: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let total: Int64
        var transferred: Int64 = 0
        var state: FileState = .pending

        enum FileState: Equatable {
            case pending
            case uploading
            case done
            case failed(String)
        }

        var fraction: Double {
            total > 0 ? Double(min(transferred, total)) / Double(total) : 0
        }
    }

    struct Item: Equatable {
        let surfaceID: UUID
        let hostLabel: String
        var dest: String?
        var files: [FileProgress]
        var state: State = .uploading
    }

    @Published private(set) var items: [UUID: Item] = [:]
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    /// Start tracking an upload batch dropped on `surfaceID`.
    func begin(surfaceID: UUID, hostLabel: String, files: [(name: String, size: Int64)]) {
        dismissTasks[surfaceID]?.cancel()
        items[surfaceID] = Item(
            surfaceID: surfaceID,
            hostLabel: hostLabel,
            files: files.map { FileProgress(name: $0.name, total: $0.size) }
        )
    }

    func setDest(surfaceID: UUID, _ dest: String) {
        items[surfaceID]?.dest = dest
    }

    func setUploading(surfaceID: UUID, file: String) {
        mutate(surfaceID: surfaceID) { item in
            if let i = item.files.firstIndex(where: { $0.name == file }) {
                item.files[i].state = .uploading
            }
        }
    }

    func updateProgress(surfaceID: UUID, file: String, transferred: Int64) {
        mutate(surfaceID: surfaceID) { item in
            if let i = item.files.firstIndex(where: { $0.name == file }) {
                item.files[i].transferred = transferred
            }
        }
    }

    func markDone(surfaceID: UUID, file: String) {
        mutate(surfaceID: surfaceID) { item in
            if let i = item.files.firstIndex(where: { $0.name == file }) {
                item.files[i].state = .done
                item.files[i].transferred = item.files[i].total
            }
        }
    }

    func markFailed(surfaceID: UUID, file: String, reason: String) {
        mutate(surfaceID: surfaceID) { item in
            if let i = item.files.firstIndex(where: { $0.name == file }) {
                item.files[i].state = .failed(reason)
                item.files[i].transferred = item.files[i].total
            }
        }
    }

    /// All files are done — flip the card to success/failure and schedule the
    /// auto-dismiss a few seconds later.
    func finish(surfaceID: UUID, ok: Bool) {
        guard items[surfaceID] != nil else { return }
        items[surfaceID]?.state = ok ? .success : .failed
        dismissTasks[surfaceID]?.cancel()
        dismissTasks[surfaceID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.items[surfaceID] = nil
        }
    }

    /// Dismiss immediately (pane closed, etc.).
    func dismiss(surfaceID: UUID) {
        dismissTasks[surfaceID]?.cancel()
        items[surfaceID] = nil
    }

    private func mutate(surfaceID: UUID, _ body: (inout Item) -> Void) {
        guard var item = items[surfaceID] else { return }
        body(&item)
        items[surfaceID] = item
    }
}

/// The progress card floated over the pane a file was dropped on.
struct PaneTransferProgressView: View {
    let item: DropUploadFeedback.Item
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            ForEach(item.files) { f in
                fileRow(f)
            }
            if let reason = failureReason {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(9)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 1)
        .padding(12)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.15)) { appeared = true } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            switch item.state {
            case .uploading:
                ProgressView().controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red).font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(headerText)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("→ \(destText)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func fileRow(_ f: DropUploadFeedback.FileProgress) -> some View {
        HStack(spacing: 6) {
            Text(f.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .frame(maxWidth: 118, alignment: .leading)
            ProgressView(value: f.fraction)
                .progressViewStyle(.linear)
                .controlSize(.mini)
                .frame(maxWidth: .infinity)
            Text("\(Self.byteString(f.transferred))/\(Self.byteString(f.total))")
                .font(.system(size: 8).monospacedDigit())
                .foregroundStyle(.secondaryText)
                .frame(width: 74, alignment: .trailing)
        }
    }

    private var headerText: String {
        switch item.state {
        case .uploading:
            if item.files.count > 1 {
                let done = item.files.filter { $0.state == .done }.count
                return "Uploading \(done + 1)/\(item.files.count)"
            }
            return "Uploading"
        case .success: return "Upload complete"
        case .failed: return "Upload failed"
        }
    }

    private var destText: String {
        item.dest.map { "\(item.hostLabel):\($0)" } ?? item.hostLabel
    }

    private var failureReason: String? {
        for f in item.files {
            if case .failed(let reason) = f.state { return reason }
        }
        return nil
    }

    private static func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
