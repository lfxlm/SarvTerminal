import SwiftUI

/// Unified transport table showing all active and completed transfers across
/// every tab. Displays source server, dest server, file name, size, progress,
/// speed, and cancel/delete actions. Styled to match FilePaneView's layout.
///
/// When collapsed the entire section (including the title bar) disappears from
/// the layout.  It auto‑expands when a new transfer starts.
struct UnifiedTransferTable: View {
    @ObservedObject private var manager = SFTPTransferManager.shared
    @State private var expanded = true
    @ObservedObject private var lang = AppLanguageSettings.shared

    /// Fixed height for the entire expanded area (title bar + rows).
    private let tableHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Header row — matches FilePaneView.columnHeader style.
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                }
                .buttonStyle(.plain)
                .help(expanded ? loc(.collapsed) : loc(.expanded))

                Text(loc(.transfers)).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondaryText)
                    .frame(width: 68, alignment: .leading)

                HStack(spacing: 10) {
                    Text(loc(.source_column)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                        .frame(width: 95, alignment: .leading)
                    Color.clear.frame(width: 10)
                    Text(loc(.destination_column)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                        .frame(width: 95, alignment: .leading)
                    Text(loc(.file_column)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(loc(.size_column_small)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                        .frame(width: 70, alignment: .trailing)
                    Text(loc(.progress_column)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondaryText)
                        .frame(width: 110, alignment: .leading)
                }

                Spacer(minLength: 0)

                if !manager.transfers.isEmpty {
                    Button(loc(.clear_completed)) {
                        manager.transfers.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondaryText)
                    .disabled(manager.transfers.contains(where: { $0.status == .inProgress }))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 16)
            .background(Color.secondary.opacity(0.06))

            if expanded {
                Divider()

                // Rows — fills remaining space and scrolls when overflow.
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(manager.transfers.enumerated().reversed()),
                                id: \.element.id) { idx, record in
                            TransferRecordRow(
                                record: record,
                                byteString: byteString,
                                onCancel: { manager.cancelTransfer() },
                                onDelete: { manager.transfers.remove(at: idx) }
                            )
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: expanded ? tableHeight : 0, alignment: .top)
        .clipped()
        .animation(.easeInOut(duration: 0.15), value: expanded)
        .onReceive(manager.$transfers) { newValue in
            if !newValue.isEmpty, !expanded { expanded = true }
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

// MARK: - Transfer Record Row

private struct TransferRecordRow: View {
    let record: TransferRecord
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
        let fraction = record.totalSize > 0
            ? min(1, Double(record.transferred) / Double(record.totalSize))
            : 0
        HStack(spacing: 10) {
            // Source
            HStack(spacing: 3) {
                Image(systemName: record.sourceLabel == "Local"
                      ? "desktopcomputer" : "server.rack")
                    .font(.system(size: 9))
                Text(record.sourceLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 95, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiaryText)
                .frame(width: 10)

            // Destination
            HStack(spacing: 3) {
                Image(systemName: record.destLabel == "Local"
                      ? "desktopcomputer" : "server.rack")
                    .font(.system(size: 9))
                Text(record.destLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 95, alignment: .leading)

            // File name
            Text(record.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(record.totalSize > 0
                 ? byteString(record.totalSize)
                 : record.status == .inProgress ? "\u{2014}" : byteString(record.transferred))
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 70, alignment: .trailing)

            // Progress
            HStack(spacing: 4) {
                switch record.status {
                case .inProgress:
                    if record.totalSize > 0 {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                            .hoverTip {
                                String(format: "%.1f%%", fraction * 100) + " · " + formatElapsed(Date().timeIntervalSince(record.startedAt))
                            }
                    } else {
                        ProgressView()
                            .scaleEffect(x: 0.7, y: 0.4, anchor: .leading)
                            .frame(width: 50)
                            .hoverTip {
                                formatElapsed(Date().timeIntervalSince(record.startedAt))
                            }
                    }
                case .completed:
                    Text(loc(.done)).foregroundStyle(.green)
                case .failed:
                    Text(loc(.failed)).foregroundStyle(.red)
                case .cancelled:
                    Text(loc(.cancelled)).foregroundStyle(.secondaryText)
                }

                if record.status == .inProgress, record.bytesPerSecond > 0 {
                    Text("\(byteString(Int64(record.bytesPerSecond)))/s")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiaryText)
                }
            }
            .frame(width: 110, alignment: .leading)

            Spacer(minLength: 0)

            // Action
            switch record.status {
            case .inProgress:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            case .completed, .failed, .cancelled:
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondaryText)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).padding(.vertical, 3)
        .frame(minHeight: 22)
        .background(record.status == .inProgress
                    ? Color.blue.opacity(0.03)
                    : Color.clear)
    }
}
