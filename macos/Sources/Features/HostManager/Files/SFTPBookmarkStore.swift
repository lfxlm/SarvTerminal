import Foundation

/// A saved directory path on a specific server (or local).
struct SFTPBookmark: Codable, Identifiable, Equatable {
    let id: String       // the path (acts as unique key per location)
    var name: String     // user‑visible label
    let path: String

    init(name: String, path: String) {
        self.id = path
        self.name = name
        self.path = path
    }
}

/// Per‑location collection of directory bookmarks, persisted to UserDefaults.
///
/// Keyed by a location identifier (`"__local__"` or the host's UUID string)
/// so each server keeps its own set — bookmarks from one host never appear
/// on another.
@MainActor
final class SFTPBookmarkStore: ObservableObject {
    static let shared = SFTPBookmarkStore()

    @Published private var storage: [String: [SFTPBookmark]] = [:]

    /// Bookmarks for the given location identifier.
    func bookmarks(for locationID: String) -> [SFTPBookmark] {
        storage[locationID] ?? []
    }

    /// Add a bookmark. Silently skips if the path already exists for this location.
    func add(_ bookmark: SFTPBookmark, for locationID: String) {
        var list = storage[locationID] ?? []
        if !list.contains(where: { $0.id == bookmark.id }) {
            list.append(bookmark)
            storage[locationID] = list
            save()
        }
    }

    /// Remove a bookmark.
    func remove(_ bookmark: SFTPBookmark, for locationID: String) {
        storage[locationID]?.removeAll { $0.id == bookmark.id }
        save()
    }

    /// Check if a path is already bookmarked for the given location.
    func isBookmarked(path: String, for locationID: String) -> Bool {
        storage[locationID]?.contains(where: { $0.id == path }) ?? false
    }

    // MARK: Persistence

    private static var storageKey: String { "sftp_bookmarks" }

    private func save() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: [SFTPBookmark]].self, from: data)
        else { return }
        storage = decoded
    }
}
