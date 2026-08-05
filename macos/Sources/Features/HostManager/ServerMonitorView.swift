import SwiftUI
import AppKit

// MARK: - Service

/// Fetches host metrics (CPU / memory / disk / GPU) over SSH in ONE round-trip,
/// parsing a set of `KEY:value` lines printed by a small remote shell script.
/// Reference metric set mirrors common server-monitoring UIs (Termius-style
/// host stats / cloud consoles / htop + nvtop): CPU%, load, cores, memory,
/// disk, and NVIDIA GPU state when present.
enum ServerMonitorService {
    struct MetricRow {
        let key: String
        let value: String
    }

    /// The remote script — one labeled line per metric so a single ssh call
    /// returns everything. All pieces are POSIX-portable; memory comes from
    /// `/proc/meminfo` (present on every Linux), not `free` (absent on minimal
    /// images / busybox). Values: CPU%, load, cores, MEM=totalKB usedKB,
    /// DISK, GPU.
    private static let script = """
    echo "HOST:$(hostname 2>/dev/null)"
    echo "OS:$(sed -n 's/^PRETTY_NAME="\\(.*\\)"/\\1/p' /etc/os-release 2>/dev/null)"
    echo "UPTIME:$(uptime -p 2>/dev/null | sed 's/^up //')"
    echo "LOAD:$(uptime | sed 's/.*load average: //' 2>/dev/null)"
    echo "CORES:$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)"
    echo "CPU:$(top -bn1 2>/dev/null | awk '/%Cpu/{print 100-$8}')"
    echo "MEM:$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t, t-a}' /proc/meminfo 2>/dev/null)"
    echo "DISK:$(df -h / 2>/dev/null | awk 'NR==2{print $2,$3,$5}')"
    echo "GPU:$(nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)"
    echo "GPUERR:$(nvidia-smi 2>&1 >/dev/null | head -1)"
    """

    static func fetch(host: SavedHost) async -> ServerMetrics {
        var m = ServerMetrics()
        m.hostname = host.displayLabel
        let res = await RemoteCommand.run(host: host, command: script)
        guard res.status == 0 else {
            m.error = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if (m.error ?? "").isEmpty { m.error = "Couldn't reach \(host.displayLabel)." }
            return m
        }
        var rows: [String: String] = [:]
        for line in res.stdout.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                rows[key] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        m.os = rows["OS"] ?? ""
        m.uptime = rows["UPTIME"] ?? ""
        m.load = rows["LOAD"] ?? ""
        m.cores = rows["CORES"] ?? ""
        if let cpu = rows["CPU"]?.replacingOccurrences(of: ",", with: "."),
           let pct = Double(cpu) { m.cpuPercent = min(max(pct, 0), 100) }
        if let mem = rows["MEM"] {
            // `/proc/meminfo` gives kB: `total used`.
            let parts = mem.split(separator: " ")
            if parts.count >= 2,
               let totalKB = Int64(parts[0]), let usedKB = Int64(parts[1]) {
                m.memTotalMB = totalKB / 1024
                m.memUsedMB = usedKB / 1024
            }
        }
        if let disk = rows["DISK"] {
            let parts = disk.split(separator: " ")
            if parts.count >= 3 {
                m.diskTotal = String(parts[0])
                m.diskUsed = String(parts[1])
                m.diskPercent = String(parts[2])
            }
        }
        if let gpu = rows["GPU"], !gpu.isEmpty {
            let parts = gpu.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 5 {
                m.gpuName = parts[0]
                m.gpuMemUsed = parts[1]
                m.gpuMemTotal = parts[2]
                m.gpuUtil = parts[3]
                m.gpuTemp = parts[4]
            } else {
                m.gpuName = gpu
            }
        }
        return m
    }
}

// MARK: - Model

/// One snapshot of a server's resource usage.
struct ServerMetrics: Equatable {
    var hostname: String = ""
    var os: String = ""
    var uptime: String = ""
    var load: String = ""
    var cores: String = ""
    var cpuPercent: Double?
    var memTotalMB: Int64 = 0
    var memUsedMB: Int64 = 0
    var diskTotal: String = ""
    var diskUsed: String = ""
    var diskPercent: String = ""
    var gpuName: String = ""
    var gpuMemUsed: String = ""
    var gpuMemTotal: String = ""
    var gpuUtil: String = ""
    var gpuTemp: String = ""
    var error: String?

    var memPercent: Double? {
        guard memTotalMB > 0 else { return nil }
        return min(Double(memUsedMB) / Double(memTotalMB), 1.0)
    }
    var memText: String {
        guard memTotalMB > 0 else { return "—" }
        let total = ByteCountFormatter.string(fromByteCount: memTotalMB * 1_048_576, countStyle: .memory)
        let used = ByteCountFormatter.string(fromByteCount: memUsedMB * 1_048_576, countStyle: .memory)
        return "\(used) / \(total)"
    }
    var diskPercentNum: Double? {
        Double(diskPercent.dropLast())
    }
}

@MainActor
final class ServerMonitorModel: ObservableObject {
    static let shared = ServerMonitorModel()

    /// Selected host id. nil = AUTO: follow the SSH server the user is
    /// currently connected to (the focused terminal's session).
    @Published var hostID: UUID? = nil
    @Published private(set) var metrics = ServerMetrics()
    @Published private(set) var loading = false
    @Published private(set) var lastUpdated: Date?
    /// Auto-refresh the metrics every `interval` seconds while the pane is open.
    @Published var autoRefresh = true
    let interval: TimeInterval = 3

    /// The host being monitored: the explicit pick, else the active SSH server.
    var resolvedHost: SavedHost? {
        if let id = hostID { return SavedHostsStore.shared.host(withID: id) }
        return VaultsTabsModel.shared.activeSSHHost
    }

    func selectHost(_ id: UUID?) {
        hostID = id
        metrics = ServerMetrics()
        lastUpdated = nil
        refresh()
    }

    func refresh() {
        guard let host = resolvedHost else {
            metrics = ServerMetrics()
            lastUpdated = nil
            return
        }
        guard !loading else { return }
        loading = true
        Task { @MainActor in
            self.metrics = await ServerMonitorService.fetch(host: host)
            self.loading = false
            self.lastUpdated = Date()
        }
    }
}

// MARK: - View

/// Vaults → Monitor: live CPU / memory / disk / GPU stats for a saved SSH host.
struct ServerMonitorView: View {
    @ObservedObject private var model = ServerMonitorModel.shared
    @ObservedObject private var hostsStore = SavedHostsStore.shared
    @ObservedObject private var tabs = VaultsTabsModel.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.resolvedHost == nil {
                        emptyState
                    } else if let error = model.metrics.error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                            Text(error).font(.callout).foregroundStyle(.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        hostHeader
                        cpuSection
                        memorySection
                        diskSection
                        gpuSection
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.hostID) { _ in model.refresh() }
        // Auto mode follows the server the user is actually connected to.
        .onChange(of: tabs.activeSSHHost?.id) { _ in
            if model.hostID == nil { model.refresh() }
        }
        .task {
            // Auto-refresh loop while the pane is visible.
            while !Task.isCancelled {
                if model.autoRefresh, model.resolvedHost != nil, !model.loading {
                    model.refresh()
                }
                try? await Task.sleep(nanoseconds: UInt64(model.interval * 1_000_000_000))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                // Auto: follow the server the user is connected to.
                if let active = tabs.activeSSHHost {
                    Button { model.selectHost(nil) } label: {
                        Label("Current server: \(active.displayLabel)", systemImage: "bolt")
                    }
                } else {
                    Button { model.selectHost(nil) } label: { Label("Select a host…", systemImage: "questionmark") }
                        .disabled(true)
                }
                Divider()
                ForEach(hostsStore.hosts) { host in
                    Button { model.selectHost(host.id) } label: {
                        if model.hostID == host.id {
                            Label(host.displayLabel, systemImage: "checkmark")
                        } else {
                            Text(host.displayLabel)
                        }
                    }
                }
            }             label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu").font(.system(size: 11))
                    Text(monitorHostLabel)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(.secondaryText)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Toggle("", isOn: $model.autoRefresh)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(loc(.monitor_auto_refresh))

            Spacer()

            Button { model.refresh() } label: {
                if model.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(model.loading)
            .hoverTipText("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var monitorHostLabel: String {
        if let id = model.hostID {
            return hostsStore.host(withID: id)?.displayLabel ?? loc(.monitor_placeholder)
        }
        if let active = tabs.activeSSHHost { return active.displayLabel }
        return loc(.monitor_placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 30)).foregroundStyle(.secondaryText)
            Text(loc(.monitor_placeholder)).font(.headline)
            Text(loc(.monitor_empty_hint))
                .font(.caption).foregroundStyle(.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var hostHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.metrics.hostname).font(.callout.weight(.semibold))
                Text([model.metrics.os, model.metrics.uptime.isEmpty ? nil : "up \(model.metrics.uptime)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private var cpuSection: some View {
        let pct = model.metrics.cpuPercent
        return metricCard(
            icon: "cpu",
            title: "CPU",
            detail: pct.map { String(format: "%.0f%%", $0) } ?? "—"
        ) {
            gauge(value: pct, color: .accentColor)
            HStack {
                Text("Load: \(model.metrics.load)")
                Spacer()
                Text("\(model.metrics.cores) cores")
            }
            .font(.caption).foregroundStyle(.secondaryText)
        }
    }

    private var memorySection: some View {
        metricCard(
            icon: "memorychip",
            title: "Memory",
            detail: model.metrics.memText
        ) {
            gauge(value: model.metrics.memPercent, color: .blue)
        }
    }

    private var diskSection: some View {
        metricCard(
            icon: "internaldrive",
            title: "Disk",
            detail: model.metrics.diskTotal.isEmpty ? "" : "\(model.metrics.diskUsed) used of \(model.metrics.diskTotal)"
        ) {
            gauge(value: model.metrics.diskPercentNum.map { $0 / 100 }, color: .teal)
        }
    }

    private var gpuSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.metrics.gpuName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "gpu").foregroundStyle(.secondaryText)
                    Text("No NVIDIA GPU detected").font(.caption).foregroundStyle(.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            } else {
                metricCard(
                    icon: "gpu",
                    title: "GPU — \(model.metrics.gpuName)",
                    detail: "\(model.metrics.gpuMemUsed) / \(model.metrics.gpuMemTotal) GB · \(model.metrics.gpuTemp)°C"
                ) {
                    gauge(value: Double(model.metrics.gpuUtil).map { $0 / 100 }, color: .purple)
                    Text("Utilization: \(model.metrics.gpuUtil)%")
                        .font(.caption).foregroundStyle(.secondaryText)
                }
            }
        }
    }

    private func gauge(value: Double?, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value ?? 0, 0), 1)))
            }
        }
        .frame(height: 8)
    }

    private func metricCard<Content: View>(icon: String, title: String, detail: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondaryText)
                Text(title).font(.callout.weight(.medium))
                Spacer()
                if !detail.isEmpty {
                    Text(detail).font(.caption.monospaced()).foregroundStyle(.secondaryText)
                }
            }
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }
}
