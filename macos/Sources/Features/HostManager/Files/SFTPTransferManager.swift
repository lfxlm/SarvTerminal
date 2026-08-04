import Foundation
import SwiftUI

/// A single transfer record displayed in the unified transport table.
struct TransferRecord: Identifiable, Equatable {
    enum Status: Equatable {
        case inProgress
        case completed
        case failed(String)
        case cancelled
    }

    let id: UUID
    let fileName: String
    let sourceLabel: String          // "Local" or host display name
    let destLabel: String            // "Local" or host display name
    let totalSize: Int64
    var transferred: Int64
    var bytesPerSecond: Double
    var direct: Bool                 // server→server direct transfer
    var status: Status = .inProgress
    let startedAt: Date

    init(id: UUID = UUID(), fileName: String, sourceLabel: String,
         destLabel: String, totalSize: Int64, transferred: Int64,
         bytesPerSecond: Double, direct: Bool, status: Status = .inProgress,
         startedAt: Date) {
        self.id = id
        self.fileName = fileName
        self.sourceLabel = sourceLabel
        self.destLabel = destLabel
        self.totalSize = totalSize
        self.transferred = transferred
        self.bytesPerSecond = bytesPerSecond
        self.direct = direct
        self.status = status
        self.startedAt = startedAt
    }

    static func == (lhs: TransferRecord, rhs: TransferRecord) -> Bool {
        lhs.id == rhs.id
    }
}

/// Shared queue for all SFTP transfers across every tab. Tracks each record
/// by a stable ID so progress polling always finds the right entry,
/// regardless of how many records have been added or completed.
@MainActor
final class SFTPTransferManager: ObservableObject {
    static let shared = SFTPTransferManager()
    private init() {}

    @Published var transfers: [TransferRecord] = []

    /// All in-flight transfer tasks, keyed by record ID, for cancellation.
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    /// Retry closures keyed by record ID — re-runs the same source/dest/item
    /// after a failure, keeping the record row in place.
    private var retryHandlers: [UUID: () -> Void] = [:]

    /// Maximum number of completed/failed/cancelled records to keep in memory.
    private let maxCompletedRecords = 50

    /// Re-run a failed transfer with the SAME record (keeps its row in the
    /// table and its history position). No-op for a finished or in-flight one.
    func retry(id: UUID) {
        retryHandlers[id]?()
    }

    /// Cancel one transfer, or all of them when `id` is nil. A single-row
    /// cancel must never kill the other in-flight transfers, so the UI passes
    /// the specific record id.
    func cancelTransfer(id: UUID? = nil) {
        if let id {
            activeTasks[id]?.cancel()
            activeTasks[id] = nil
        } else {
            for (_, task) in activeTasks { task.cancel() }
            activeTasks.removeAll()
        }
    }

    /// Clean up completed records when they exceed the limit. Always keeps the
    /// in-flight ones and the MOST RECENT finished ones (suffix, since the
    /// array is in start order).
    func cleanupCompletedRecords() {
        let nonActive = transfers.filter { $0.status != .inProgress }
        if nonActive.count > maxCompletedRecords {
            let active = transfers.filter { $0.status == .inProgress }
            let recentCompleted = nonActive.suffix(maxCompletedRecords)
            let recentIds = Set(recentCompleted.map(\.id))
            transfers = transfers.filter { $0.status == .inProgress || recentIds.contains($0.id) }
        }
    }

    /// Start a transfer from the active source tab to the active dest tab.
    func startTransfer(
        from sourceTab: SFTPTab,
        to destTab: SFTPTab,
        item: FileItem,
        resolution: ConflictResolution
    ) {
        let id = UUID()
        let record = TransferRecord(
            id: id,
            fileName: item.name,
            sourceLabel: sourceTab.title,
            destLabel: destTab.title,
            totalSize: item.isDirectory ? 0 : item.size,
            transferred: 0,
            bytesPerSecond: 0,
            direct: sourceTab.browser.backend is RemoteFileBackend
                && destTab.browser.backend is RemoteFileBackend,
            status: .inProgress,
            startedAt: Date()
        )
        transfers.append(record)

        // Capture everything the retry button needs, keyed by this record's id.
        let sourceTabRef = sourceTab
        let destTabRef = destTab
        retryHandlers[id] = { [weak self] in
            self?.retryTransfer(id: id, sourceTab: sourceTabRef, destTab: destTabRef,
                                item: item, resolution: resolution)
        }

        activeTasks[id] = Task { @MainActor [weak self] in
            defer { self?.activeTasks[id] = nil }
            await self?.performTransfer(
                sourceTab: sourceTab, destTab: destTab,
                item: item, resolution: resolution,
                id: id
            )
        }
    }

    // MARK: - Internal

    /// Re-run a failed transfer keeping the same record (row + id). The record
    /// flips back to `.inProgress` and a fresh task drives it.
    private func retryTransfer(id: UUID, sourceTab: SFTPTab, destTab: SFTPTab,
                               item: FileItem, resolution: ConflictResolution) {
        guard activeTasks[id] == nil,
              let idx = transfers.firstIndex(where: { $0.id == id }),
              case .failed = transfers[idx].status else { return }
        transfers[idx].status = .inProgress
        transfers[idx].transferred = 0
        transfers[idx].bytesPerSecond = 0
        activeTasks[id] = Task { @MainActor [weak self] in
            defer { self?.activeTasks[id] = nil }
            await self?.performTransfer(
                sourceTab: sourceTab, destTab: destTab,
                item: item, resolution: resolution,
                id: id
            )
        }
    }

    /// Return the index of the record with the given id.
    private func idx(of id: UUID) -> Int? {
        transfers.firstIndex(where: { $0.id == id })
    }

    private func performTransfer(
        sourceTab: SFTPTab, destTab: SFTPTab,
        item: FileItem, resolution: ConflictResolution,
        id: UUID
    ) async {
        guard idx(of: id) != nil else { return }
        let source = sourceTab.browser
        let dest = destTab.browser
        let started = Date()

        // Server → server: try direct, fall back to relay.
        if source.backend is RemoteFileBackend, dest.backend is RemoteFileBackend {
            var ok = await runRemoteTransfer(
                item: item, source: source, dest: dest,
                resolution: resolution, direct: true, id: id
            )
            if !ok, !Task.isCancelled {
                ok = await runRemoteTransfer(
                    item: item, source: source, dest: dest,
                    resolution: resolution, direct: false, id: id
                )
            }
            notifyOutcome(item: item, succeeded: ok,
                          reason: ok ? nil : (dest.error ?? "Transfer failed"),
                          started: started)
            return
        }

        // Local ⇄ remote (or local ⇄ local).
        var failure: String?
        await withProgress(
            item: item, source: source, dest: dest,
            resolution: resolution, direct: false, id: id
        ) {
            try await FileTransfer.copy(
                item: item, from: source.backend, to: dest.backend,
                destDir: dest.path, resolution: resolution
            )
        } onFinish: { await dest.reload() } onError: { failure = $0 }
        notifyOutcome(item: item, succeeded: failure == nil,
                      reason: failure, started: started)
    }

    /// Server→server transfer wrapped with progress.
    @discardableResult
    private func runRemoteTransfer(
        item: FileItem, source: SFTPBrowserModel, dest: SFTPBrowserModel,
        resolution: ConflictResolution, direct: Bool,
        id: UUID
    ) async -> Bool {
        guard idx(of: id) != nil else { return false }
        guard let src = source.backend as? RemoteFileBackend,
              let dst = dest.backend as? RemoteFileBackend else { return false }
        var ok = true
        await withProgress(
            item: item, source: source, dest: dest,
            resolution: resolution, direct: direct, id: id
        ) {
            _ = try await FileTransfer.serverToServer(
                item: item, from: src, to: dst,
                destDir: dest.path, resolution: resolution, direct: direct
            )
        } onFinish: { await dest.reload() } onError: { msg in
            ok = false
            if !direct { dest.error = msg }
        }
        return ok
    }

    /// Wrap a transfer with a progress poller that watches the destination
    /// file's size.  Uses `activeID` so it always updates the correct entry.
    private func withProgress(
        item: FileItem, source: SFTPBrowserModel, dest: SFTPBrowserModel,
        resolution: ConflictResolution, direct: Bool,
        id: UUID,
        _ op: @escaping () async throws -> Void,
        onFinish: @escaping () async -> Void,
        onError: @escaping (String) -> Void
    ) async {
        let destPath = dest.backend.join(
            dest.path,
            FileTransfer.finalName(for: item, resolution: resolution)
        )
        // Progress poller — uses `id` directly so it never confuses records.
        let poller = TransferProgressPoller.start(destBackend: dest.backend, destPath: destPath) { [self, id] size, elapsed in
            guard let idx = transfers.firstIndex(where: { $0.id == id })
            else { return false }
            transfers[idx].transferred = size ?? transfers[idx].transferred
            transfers[idx].bytesPerSecond = Double(transfers[idx].transferred) / elapsed
            return true
        }

        do {
            try await op()
            await onFinish()
            if let idx = transfers.firstIndex(where: { $0.id == id }) {
                if transfers[idx].totalSize > 0 {
                    transfers[idx].transferred = transfers[idx].totalSize
                }
                transfers[idx].status = .completed
            }
            cleanupCompletedRecords()
        } catch {
            if Task.isCancelled {
                if let idx = transfers.firstIndex(where: { $0.id == id }) {
                    transfers[idx].status = .cancelled
                }
            } else {
                let msg = (error as? FileOpError)?.message
                    ?? error.localizedDescription
                onError(msg)
                if let idx = transfers.firstIndex(where: { $0.id == id }) {
                    transfers[idx].status = .failed(msg)
                }
                cleanupCompletedRecords()
            }
        }
        poller.cancel()
    }

    /// Post a finished / failed notification. Quick transfers (< 3s) only
    /// notify on failure.
    private func notifyOutcome(
        item: FileItem, succeeded: Bool, reason: String?, started: Date
    ) {
        if Task.isCancelled { return }
        let elapsed = Date().timeIntervalSince(started)
        Task { @MainActor in
            if succeeded {
                if elapsed >= 3 {
                    SarvNotifications.shared.notify(
                        .sftpFinished(file: item.name, host: nil))
                }
            } else {
                SarvNotifications.shared.notify(
                    .sftpFailed(file: item.name, host: nil,
                                reason: reason ?? "Transfer failed"))
            }
        }
    }
}
