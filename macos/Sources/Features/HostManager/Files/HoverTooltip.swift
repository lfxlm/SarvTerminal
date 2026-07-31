import AppKit
import SwiftUI

/// A borderless floating tooltip that appears instantly at the mouse cursor
/// and updates live (0.25s ticker) while the pointer stays over the target.
///
/// Rendered in its own window layer, so unlike a SwiftUI `.overlay` it is never
/// clipped by the parent view hierarchy. Unlike the system `.help()` tooltip it
/// has no built-in delay and its content refreshes while shown.
@MainActor
final class HoverTooltip: ObservableObject {
    static let shared = HoverTooltip()

    @Published private(set) var text = ""

    private var panel: NSPanel?
    private var owner: UUID?
    private var provider: (@MainActor () -> String)?
    private var timer: Timer?
    private var resignObserver: NSObjectProtocol?

    private init() {
        // Don't float the tooltip over other apps once the app loses focus.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideAll() }
        }
    }

    /// Start showing the tooltip for the hovered view.
    func show(owner: UUID, provider: @escaping @MainActor () -> String) {
        self.owner = owner
        self.provider = provider
        ensurePanel()
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Re-sync the data provider while hovering. Rows re-render as transfers
    /// progress, so each render hands over a closure that reads fresh values.
    func syncProvider(owner: UUID, provider: @escaping @MainActor () -> String) {
        guard self.owner == owner else { return }
        self.provider = provider
    }

    func hide(owner: UUID) {
        guard self.owner == owner else { return }
        hideAll()
    }

    private func hideAll() {
        timer?.invalidate()
        timer = nil
        owner = nil
        provider = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 22),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TooltipLabel(model: self))
        self.panel = panel
    }

    private func refresh() {
        guard let provider, let panel else { return }
        let newText = provider()
        guard !newText.isEmpty else { return }
        text = newText

        // Hug the text: measure and resize so the pill doesn't stretch.
        let font = NSFont.systemFont(ofSize: 11)
        let measured = (newText as NSString).size(withAttributes: [.font: font])
        panel.setContentSize(NSSize(
            width: max(ceil(measured.width) + 20, 28),
            height: max(ceil(measured.height) + 10, 18)))

        positionNearMouse()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Place the tooltip near the cursor, flipping sides/clamping to the
    /// visible screen so it never goes off-screen.
    private func positionNearMouse() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - 26)
        if let screen = panel.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            if origin.x + size.width > vf.maxX { origin.x = mouse.x - size.width - 14 }
            if origin.y < vf.minY { origin.y = mouse.y + 12 }
            origin.x = max(origin.x, vf.minX + 4)
        }
        panel.setFrameOrigin(origin)
    }
}

/// The pill label rendered inside the floating window.
private struct TooltipLabel: View {
    @ObservedObject var model: HoverTooltip

    var body: some View {
        Text(model.text)
            .font(.system(size: 11))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.15)))
    }
}

/// Shows `text()` in a floating tooltip while the content is hovered.
struct HoverTipModifier: ViewModifier {
    let text: @MainActor () -> String
    @State private var isHovering = false
    @State private var ownerID = UUID()

    func body(content: Content) -> some View {
        // Keep the tooltip's data provider fresh on every render while
        // hovering, so progress/elapsed values stay live.
        if isHovering {
            HoverTooltip.shared.syncProvider(owner: ownerID, provider: text)
        }
        return content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    HoverTooltip.shared.show(owner: ownerID, provider: text)
                } else {
                    HoverTooltip.shared.hide(owner: ownerID)
                }
            }
            .onDisappear {
                HoverTooltip.shared.hide(owner: ownerID)
            }
    }
}

extension View {
    /// Instantly-appearing tooltip whose content is recomputed live while the
    /// pointer stays over the view.
    func hoverTip(_ text: @escaping @MainActor () -> String) -> some View {
        self.modifier(HoverTipModifier(text: text))
    }
}
