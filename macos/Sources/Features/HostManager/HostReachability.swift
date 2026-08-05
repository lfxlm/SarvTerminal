import SwiftUI
import Foundation

/// Whether an SSH host is currently reachable (a quick TCP connect to its port).
enum HostReachability: Equatable {
    case unknown
    case checking
    case online
    case offline
}

/// Tracks reachability per saved host. Probes are async (`nc -z`, one short
/// process per host) and the results are cached so the host list never re-probes
/// on every render. A dot on each card shows the latest status.
@MainActor
final class HostReachabilityStore: ObservableObject {
    static let shared = HostReachabilityStore()

    @Published private(set) var statuses: [UUID: HostReachability] = [:]
    private var inFlight: Set<UUID> = []

    func status(for host: SavedHost) -> HostReachability {
        statuses[host.id] ?? .unknown
    }

    /// Probe hosts that don't already have a fresh result. `force` re-probes
    /// every host (used by the periodic offline re-check and dot taps).
    func refresh(_ hosts: [SavedHost], force: Bool = false) {
        for host in hosts where !host.hostname.isEmpty {
            if !force, let s = statuses[host.id], s != .unknown {
                continue
            }
            probe(host)
        }
    }

    /// Re-probe only hosts that are currently offline — the periodic "is it
    /// back yet?" pass, without churning the online hosts.
    func recheckOffline(_ hosts: [SavedHost]) {
        for host in hosts where status(for: host) == .offline {
            probe(host)
        }
    }

    private func probe(_ host: SavedHost) {
        guard !inFlight.contains(host.id) else { return }
        inFlight.insert(host.id)
        statuses[host.id] = .checking
        let id = host.id
        let hostname = host.hostname
        let port = UInt16(max(1, min(host.port, 65535)))
        Task { @MainActor in
            let ok = await Self.tcpReachable(host: hostname, port: port)
            self.inFlight.remove(id)
            self.statuses[id] = ok ? .online : .offline
        }
    }

    /// Quick TCP reachability via `nc -z` (ships with macOS). `-G 2` bounds the
    /// connection attempt to 2 seconds so a dead host can't hang the list.
    private static func tcpReachable(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
                proc.arguments = ["-z", "-G", "2", host, "\(port)"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    cont.resume(returning: proc.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
}

/// A small status dot for a host card: green = reachable, red = offline,
/// orange = checking, gray = not probed yet. Tapping re-probes that host.
struct HostStatusDot: View {
    let host: SavedHost
    @ObservedObject private var store = HostReachabilityStore.shared

    var body: some View {
        Button {
            store.refresh([host], force: true)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(loc(.host_status_help, host.displayLabel))
        .hoverCursor(.pointingHand)
    }

    private var color: Color {
        switch store.status(for: host) {
        case .online:   return .green
        case .offline:  return .red
        case .checking: return .orange
        case .unknown:  return .gray
        }
    }
}
