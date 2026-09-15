import Cocoa
import SwiftUI
import Combine

/// Manages the standalone SFTP window — one window, independent of the Vaults
/// window, with its own tabbed dual-pane file browser.
@MainActor
final class SFTPWindowManager: NSWindowController {
    static let shared = SFTPWindowManager()

    private lazy var transferBubble = SFTPTransferBubbleController { [weak self] in
        self?.show()
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SFTP"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 500)

        let hosting = NSHostingView(rootView: SFTPWindowView())
        hosting.frame = window.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        super.init(window: window)
        window.delegate = self
        transferBubble.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    /// Open (or activate) the SFTP window.
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.close()
    }
}

extension SFTPWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Allow the window to be re-opened later; nothing special needed.
    }
}

/// Application-level floating progress indicator for transfers started by the
/// standalone SFTP window. It is independent from the SFTP window, so closing
/// the window does not hide an in-flight transfer.
@MainActor
private final class SFTPTransferBubbleController {
    private let onTap: () -> Void
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var cancellable: AnyCancellable?
    private var expanded = false
    private var pinned = true
    private var userHeight: CGFloat?
    private var resizeStartHeight: CGFloat?

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func start() {
        let manager = SFTPTransferManager.shared
        cancellable = manager.$transfers.sink { [weak self] transfers in
            self?.update(transfers)
        }
        update(manager.transfers)
    }

    private func update(_ transfers: [TransferRecord]) {
        let active = transfers.contains { $0.status == .inProgress }
        if active {
            let wasCreated = panel == nil
            ensurePanel()
            if expanded {
                resizePanel(for: transfers)
            }
            // Raise only when the panel is first created or was hidden. Do
            // not reorder it on every progress tick: that interrupts window
            // interaction and makes a resize drag feel jittery.
            if wasCreated || panel?.isVisible == false {
                panel?.orderFrontRegardless()
            }
        } else {
            panel?.orderOut(nil)
        }
    }

    private func toggleExpanded() {
        expanded.toggle()
        ensurePanel()
        applyPinState()
        updateContent()
        resizePanel(for: SFTPTransferManager.shared.transfers)
        panel?.orderFrontRegardless()
    }

    private func togglePinned() {
        pinned.toggle()
        // Once unpinned, keep a small, discoverable entry point on screen.
        // The full panel is normal-level, while the collapsed bubble remains
        // visible above normal windows and can be clicked to reopen it.
        if !pinned {
            expanded = false
        }
        applyPinState()
        updateContent()
        resizePanel(for: SFTPTransferManager.shared.transfers)
        panel?.orderFrontRegardless()
    }

    private func applyPinState() {
        guard let panel else { return }
        panel.level = (pinned || !expanded) ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        if pinned || !expanded {
            behavior.insert(.canJoinAllSpaces)
        }
        panel.collectionBehavior = behavior
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = expanded ? panelSize(for: SFTPTransferManager.shared.transfers) : NSSize(width: 54, height: 54)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.appearance = NSAppearance(named: .aqua)
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if let screen = NSScreen.main {
            let margin: CGFloat = 24
            let frame = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: frame.maxX - p.frame.width - margin,
                                     y: frame.minY + margin))
        }
        panel = p
        updateContent()
    }

    private func updateContent() {
        guard let panel else { return }
        let root: AnyView
        if expanded {
            root = AnyView(SFTPTransferCenterView(
                onCollapse: { [weak self] in self?.toggleExpanded() },
                onPin: { [weak self] in self?.togglePinned() },
                onOpenWindow: onTap,
                onResizeHeight: { [weak self] translation in self?.resizeHeight(to: translation) },
                onResizeEnded: { [weak self] in self?.finishResize() },
                isPinned: pinned
            ))
        } else {
            root = AnyView(SFTPTransferBubbleView(onTap: { [weak self] in self?.toggleExpanded() }))
        }
        let host = NSHostingView(rootView: root)
        host.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        hosting = host
    }

    private func panelSize(for transfers: [TransferRecord]) -> NSSize {
        guard expanded else { return NSSize(width: 54, height: 54) }
        let automaticHeight = automaticPanelHeight(for: transfers)
        let height = min(680, max(automaticHeight, userHeight ?? automaticHeight))
        return NSSize(width: 480, height: height)
    }

    private func automaticPanelHeight(for transfers: [TransferRecord]) -> CGFloat {
        let count = min(max(transfers.count, 1), 5)
        return min(500, max(260, 165 + CGFloat(count) * 78))
    }

    private func resizePanel(for transfers: [TransferRecord]) {
        guard let panel else { return }
        let newSize = panelSize(for: transfers)
        let oldFrame = panel.frame
        guard abs(oldFrame.width - newSize.width) > 0.5
            || abs(oldFrame.height - newSize.height) > 0.5 else {
            return
        }
        let origin = NSPoint(x: oldFrame.maxX - newSize.width, y: oldFrame.maxY - newSize.height)
        panel.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: true)
    }

    private func resizeHeight(to translation: CGFloat) {
        guard expanded, let panel else { return }
        if resizeStartHeight == nil {
            resizeStartHeight = panel.frame.height
        }
        let minimum = automaticPanelHeight(for: SFTPTransferManager.shared.transfers)
        let proposed = min(680, max(minimum, (resizeStartHeight ?? panel.frame.height) + translation))
        userHeight = proposed
        let oldFrame = panel.frame
        let origin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - proposed)
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: oldFrame.width, height: proposed),
                       display: true, animate: false)
    }

    private func finishResize() {
        resizeStartHeight = nil
    }
}

private struct SFTPTransferBubbleView: View {
    @ObservedObject private var manager = SFTPTransferManager.shared
    @AppStorage("sftpTransferPanelOpacity") private var panelOpacity = 0.72
    let onTap: () -> Void

    private var activeRecords: [TransferRecord] {
        manager.transfers.filter { $0.status == .inProgress }
    }

    private var progress: Double? {
        let known = activeRecords.filter { $0.totalSize > 0 }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(Int64(0)) { $0 + $1.totalSize }
        let done = known.reduce(Int64(0)) { $0 + min($1.transferred, $1.totalSize) }
        return total > 0 ? Double(done) / Double(total) : nil
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                SFTPProgressRing(progress: progress, showsLabel: false)
                    .frame(width: 48, height: 48)
                    .padding(3)
                    .background {
                        SFTPVisualEffectBackground(opacity: CGFloat(panelOpacity))
                            .clipShape(Circle())
                    }
                    .background(Color.white.opacity(0.12 * panelOpacity), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.36), lineWidth: 1)
                    }
                    .overlay {
                        if let progress {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.primary)
                        } else {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                    }
                if activeRecords.count > 1 {
                    Text("\(activeRecords.count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.blue.gradient))
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
        .help("打开 SFTP 传输队列")
    }
}

private struct SFTPVisualEffectBackground: NSViewRepresentable {
    let opacity: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        view.alphaValue = 1
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.state = .active
        nsView.appearance = NSAppearance(named: .aqua)
        nsView.alphaValue = 1
    }
}

/// Expanded version of the floating indicator. This intentionally reads the
/// same shared transfer records as the normal SFTP window, so the floating
/// view never creates a second transfer list or a second polling loop.
private struct SFTPTransferCenterView: View {
    @ObservedObject private var manager = SFTPTransferManager.shared
    @AppStorage("sftpTransferPanelOpacity") private var panelOpacity = 0.72
    @State private var showingAppearanceSettings = false

    let onCollapse: () -> Void
    let onPin: () -> Void
    let onOpenWindow: () -> Void
    let onResizeHeight: (CGFloat) -> Void
    let onResizeEnded: () -> Void
    let isPinned: Bool

    private var activeRecords: [TransferRecord] {
        manager.transfers.filter { $0.status == .inProgress }
    }

    private var progress: Double? {
        let known = activeRecords.filter { $0.totalSize > 0 }
        guard !known.isEmpty else { return nil }
        let total = known.reduce(Int64(0)) { $0 + $1.totalSize }
        let done = known.reduce(Int64(0)) { $0 + min($1.transferred, $1.totalSize) }
        return total > 0 ? min(1, Double(done) / Double(total)) : nil
    }

    private var totalSpeed: Double {
        activeRecords.reduce(0) { $0 + max(0, $1.bytesPerSecond) }
    }

    private var completedCount: Int {
        manager.transfers.filter {
            if case .completed = $0.status { return true }
            return false
        }.count
    }

    private var failedCount: Int {
        manager.transfers.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                header
                summary
                Divider().opacity(0.35)

                if manager.transfers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无传输任务")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(manager.transfers.reversed()) { record in
                                SFTPTransferCenterRow(
                                    record: record,
                                    onCancel: { manager.cancelTransfer(id: record.id) },
                                    onRetry: { manager.retry(id: record.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }

                footer
            }
        }
        .frame(width: 480)
        .background {
            SFTPVisualEffectBackground(opacity: CGFloat(panelOpacity))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .background(Color.white.opacity(0.14 * panelOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            SFTPResizeHandle(onChanged: onResizeHeight, onEnded: onResizeEnded)
                .padding(.bottom, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.34, blue: 0.30)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.18)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.34)).frame(width: 10, height: 10)
            }
            .frame(width: 42, height: 12)

            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.blue)
            Text("传输中心")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Button(action: onPin) {
                Label(isPinned ? "取消置顶" : "置顶", systemImage: isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(SFTPGlassButtonStyle())
            .help(isPinned ? "取消置顶悬浮窗" : "置顶悬浮窗")

            Button(action: onOpenWindow) {
                Label("打开 SFTP", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(SFTPGlassButtonStyle())

            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("收起传输中心")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SFTPProgressRing(progress: progress)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("共 \(manager.transfers.count) 个任务")
                    .font(.system(size: 14, weight: .semibold))
                Text("进行中 \(activeRecords.count)  ·  已完成 \(completedCount)  ·  失败 \(failedCount)")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))

                HStack(spacing: 14) {
                    Label(ByteCountFormatter.string(fromByteCount: Int64(totalSpeed), countStyle: .file) + "/s", systemImage: "speedometer")
                    Text("总速度")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("实时速度")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label("传输", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.blue)
                        .font(.system(size: 9))
                }
                SFTPSpeedChart(samples: manager.speedSamples)
                    .frame(width: 96, height: 32)
            }
            .frame(width: 108, alignment: .leading)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            Button {
                showingAppearanceSettings.toggle()
            } label: {
                Label("外观设置", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .popover(isPresented: $showingAppearanceSettings, arrowEdge: .bottom) {
                SFTPTransferAppearanceSettings()
            }

            Spacer()

            Button("清理已完成") {
                manager.clearCompleted()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(manager.transfers.allSatisfy { $0.status == .inProgress })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct SFTPResizeHandle: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 42, height: 4)
            .frame(width: 86, height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onChanged(value.translation.height)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
            .help("拖动调整窗口高度")
    }
}

private struct SFTPGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.24 : 0.11),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SFTPTransferAppearanceSettings: View {
    @AppStorage("sftpTransferPanelOpacity") private var panelOpacity = 0.72

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("传输中心外观")
                .font(.system(size: 13, weight: .semibold))
            HStack {
                Text("透明度")
                Spacer()
                Text("\(Int(panelOpacity * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $panelOpacity, in: 0.35...0.95, step: 0.05)
            Button("恢复默认") {
                panelOpacity = 0.72
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
        }
        .padding(14)
        .frame(width: 210)
    }
}

private struct SFTPSpeedChart: View {
    let samples: [Double]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.blue.opacity(0.06))
            if samples.count > 1 {
                SFTPSpeedWave(samples: samples)
                    .stroke(Color.blue.opacity(0.9), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            } else {
                Text("等待数据")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SFTPSpeedWave: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let peak = max(samples.max() ?? 0, 1)
        let lastIndex = max(samples.count - 1, 1)
        for index in samples.indices {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(lastIndex)
            let normalized = CGFloat(samples[index] / peak)
            let y = rect.maxY - 3 - normalized * rect.height * 0.82
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private struct SFTPProgressRing: View {
    let progress: Double?
    var showsLabel = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 11)
            Circle()
                .trim(from: 0, to: CGFloat(progress ?? 0.08))
                .stroke(
                    AngularGradient(colors: [.mint, .blue, .cyan, .mint], center: .center),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsLabel, let progress {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(4)
    }
}

private struct SFTPTransferCenterRow: View {
    let record: TransferRecord
    let onCancel: () -> Void
    let onRetry: () -> Void
    @State private var detailsExpanded = false

    private var progress: Double? {
        guard record.totalSize > 0 else { return nil }
        return min(1, max(0, Double(record.transferred) / Double(record.totalSize)))
    }

    private var remainingText: String {
        guard record.totalSize > 0, record.bytesPerSecond > 0 else { return "剩余时间计算中" }
        let seconds = max(0, Double(record.totalSize - min(record.transferred, record.totalSize)) / record.bytesPerSecond)
        if seconds < 60 { return "剩余 \(Int(seconds.rounded())) 秒" }
        return "剩余 \(Int(seconds / 60)) 分 \(Int(seconds.truncatingRemainder(dividingBy: 60))) 秒"
    }

    private var statusColor: Color {
        switch record.status {
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private var statusText: String {
        switch record.status {
        case .inProgress: return "进行中"
        case .completed: return "传输成功"
        case .cancelled: return "已取消"
        case .failed(let reason): return reason.isEmpty ? "传输失败" : "失败: \(reason)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(statusColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .help(record.fileName)
                    Text("\(record.sourceLabel)  →  \(record.destLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("来源: \(record.sourceLabel)\n目标: \(record.destLabel)")
                }

                Spacer(minLength: 8)

                statusLabel
                actionButtons
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        detailsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(detailsExpanded ? "收起任务详情" : "展开任务详情")
            }

            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .frame(height: 4)

                Text(progress.map { "\(Int($0 * 100))%" } ?? "处理中")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Text(ByteCountFormatter.string(fromByteCount: record.transferred, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: record.totalSize, countStyle: .file))
                Spacer()
                if record.bytesPerSecond > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(record.bytesPerSecond), countStyle: .file) + "/s")
                }
                Text(remainingText)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if case .failed(let reason) = record.status, !reason.isEmpty {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(reason)
            }

            if detailsExpanded {
                Divider().opacity(0.35)
                HStack(spacing: 18) {
                    Label(ByteCountFormatter.string(fromByteCount: record.totalSize, countStyle: .file), systemImage: "doc")
                    Label(record.direct ? "服务器直传" : "SFTP 中转", systemImage: "arrow.left.arrow.right")
                    Spacer()
                    Text("ID \(record.id.uuidString.prefix(8))")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            statusColor.opacity(record.status == .inProgress ? 0.10 : 0.03),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(record.status == .inProgress ? 0.45 : 0.16), lineWidth: 1)
        }
    }

    private var iconName: String {
        switch record.status {
        case .inProgress: return record.direct ? "arrow.left.arrow.right" : "arrow.up"
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusText)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(statusColor)
        .help(statusText)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch record.status {
        case .inProgress:
            Button(action: onCancel) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("取消传输")
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
            .help("重新开始")
        case .completed, .cancelled:
            EmptyView()
        }
    }
}
