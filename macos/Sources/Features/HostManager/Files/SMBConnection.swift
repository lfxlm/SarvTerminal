import Foundation
import Combine

/// A saved SMB share connection, analogous to `SavedHost` for SSH.
///
/// The password is stored inside this value but the whole file is encrypted
/// at rest (AES-256-GCM via `EncryptedStore` + `LocalDataCrypto`), so it is
/// never written to disk in plaintext.
struct SMBConnection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Display name. Empty means the UI falls back to "server/share".
    var label: String = ""
    /// Server hostname or IP (required).
    var server: String = ""
    /// Share name (required).
    var share: String = ""
    /// SMB username. Empty means the guest account.
    var username: String = ""
    var password: String = ""
    /// Optional SMB workgroup/domain.
    var domain: String = ""

    /// Sort/display title: label if set, otherwise "server/share".
    var displayTitle: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let s = server.trimmingCharacters(in: .whitespaces)
        let sh = share.trimmingCharacters(in: .whitespaces)
        if sh.isEmpty { return s.isEmpty ? loc(.smb_connection) : s }
        return "\(s)/\(sh)"
    }

    /// Subtitle shown under the display title ("server/share" or label+server).
    var subtitle: String {
        var parts: [String] = []
        let s = server.trimmingCharacters(in: .whitespaces)
        let sh = share.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { parts.append(s) }
        if !sh.isEmpty { parts.append(sh) }
        if !domain.isEmpty { parts.append(domain) }
        return parts.joined(separator: "/")
    }
}

/// Owns the persisted list of `SMBConnection`s. Singleton; safe to observe
/// from SwiftUI via `@ObservedObject var store = SMBConnectionStore.shared`.
///
/// Storage: `~/.config/sarvterminal/smb.json` (created lazily, encrypted).
final class SMBConnectionStore: ObservableObject {
    static let shared = SMBConnectionStore()

    @Published private(set) var connections: [SMBConnection] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "SMBConnectionStore.io", qos: .utility)

    private init() {
        fileURL = AppPaths.configDir.appendingPathComponent("smb.json")
        load()
    }

    // MARK: - Public CRUD

    /// Insert or update by `id`. If `password` is empty and the connection
    /// already exists, the stored password is kept (edit form leaves it blank).
    func upsert(_ connection: SMBConnection) {
        var updated = connection
        if updated.password.isEmpty,
           let existing = connections.first(where: { $0.id == connection.id }) {
            updated.password = existing.password
        }
        if let idx = connections.firstIndex(where: { $0.id == updated.id }) {
            connections[idx] = updated
        } else {
            connections.append(updated)
        }
        sortInPlace()
        persist()
    }

    func delete(_ connection: SMBConnection) {
        connections.removeAll { $0.id == connection.id }
        persist()
    }

    func connection(withID id: UUID) -> SMBConnection? {
        connections.first { $0.id == id }
    }

    // MARK: - IO

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        switch EncryptedStore.read([SMBConnection].self, from: fileURL, decoder: decoder) {
        case .none, .failed:
            break // fresh install / unreadable — start empty
        case .loaded(let decoded):
            connections = decoded; sortInPlace()
        case .migrated(let decoded):
            connections = decoded; sortInPlace()
            persist() // rewrite encrypted (backup already taken)
        }
    }

    private func persist() {
        let snapshot = connections
        let url = fileURL
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // If the key is unavailable, skip the write rather than clobber
            // the existing file with plaintext/empty data.
            try? EncryptedStore.write(snapshot, to: url, encoder: encoder)
        }
    }

    private func sortInPlace() {
        connections.sort {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }
}
