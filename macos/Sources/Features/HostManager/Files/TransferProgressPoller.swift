import Foundation

/// Shared destination-size poller for transfer progress rows.
///
/// Three transfer surfaces (side-panel uploads, SFTPView transfers,
/// SFTPTransferManager) used to each hand-roll an 800ms polling loop that
/// stats the destination file. This centralizes the tick cadence and the
/// cancellation semantics; the caller's `onUpdate` closure returns `false`
/// to stop (e.g. its record disappeared or the transfer finished).
enum TransferProgressPoller {
    /// Begin polling `destPath`'s file size on the main actor.
    ///
    /// - `start`/`interval`: timing knobs (defaults match the historical
    ///   behavior: 800ms ticks since the transfer began).
    /// - `onUpdate(size, elapsed)`: called on the main actor each tick.
    ///   `size` is `nil` when the destination can't be stat'ed (the caller
    ///   keeps its current transferred count in that case). Return `false`
    ///   to stop polling.
    static func start(
        destBackend: FileBackend,
        destPath: String,
        start: Date = Date(),
        interval: UInt64 = 800_000_000,
        onUpdate: @escaping @MainActor (_ size: Int64?, _ elapsed: TimeInterval) -> Bool
    ) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                let size = await destBackend.fileSize(destPath)
                let elapsed = max(0.001, Date().timeIntervalSince(start))
                if !onUpdate(size, elapsed) { break }
            }
        }
    }
}
