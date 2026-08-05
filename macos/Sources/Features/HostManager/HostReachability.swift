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
        // A jump-host target is usually NOT directly reachable — probe the JUMP
        // host instead, otherwise every behind-a-bastion host shows red wrongly.
        let target = Self.probeTarget(for: host)
        Task { @MainActor in
            let ok = await Self.tcpReachable(host: target.host, port: target.port)
            self.inFlight.remove(id)
            self.statuses[id] = ok ? .online : .offline
        }
    }

    /// Where to probe for `host`: its own hostname:port, or — when it routes
    /// through a `proxyJump` bastion — the bastion's host:port.
    static func probeTarget(for host: SavedHost) -> (host: String, port: UInt16) {
        if !host.proxyJump.isEmpty {
            let jump = parseJumpHost(host.proxyJump)
            if !jump.host.isEmpty { return (jump.host, jump.port) }
        }
        return (host.hostname, UInt16(max(1, min(host.port, 65535))))
    }

    /// Parse `user@host[:port]` / `host[:port]` into host + port (default 22).
    static func parseJumpHost(_ jump: String) -> (host: String, port: UInt16) {
        var s = jump
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":"), colon > s.startIndex {
            let host = String(s[..<colon])
            if let p = UInt16(s[s.index(after: colon)...]), !host.isEmpty {
                return (host, p)
            }
        }
        return (s, 22)
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
        .help(helpText)
        .hoverCursor(.pointingHand)
    }

    private var helpText: String {
        let target: String
        if !host.proxyJump.isEmpty {
            let jump = HostReachabilityStore.parseJumpHost(host.proxyJump)
            target = "via \(jump.host):\(jump.port)"
        } else {
            target = "\(host.hostname):\(host.port)"
        }
        return loc(.host_status_help, "\(host.displayLabel) (\(target))")
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
