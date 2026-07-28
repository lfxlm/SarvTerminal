import Cocoa
import SwiftUI

/// Manages the standalone SFTP window — one window, independent of the Vaults
/// window, with its own tabbed dual-pane file browser.
final class SFTPWindowManager: NSWindowController {
    static let shared = SFTPWindowManager()

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
