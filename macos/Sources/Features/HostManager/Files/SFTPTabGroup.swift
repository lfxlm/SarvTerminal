import SwiftUI

/// One tab in an SFTP pane (left or right). Wraps a browser model with a
/// user-visible title so each tab can point at a different local path or
/// remote server.
@MainActor
final class SFTPTab: ObservableObject, Identifiable {
    let id = UUID()
    let browser: SFTPBrowserModel
    @Published var title: String

    init(location: FileLocation) {
        self.browser = SFTPBrowserModel()
        self.title = location.title
        self.browser.connect(to: location)
    }
}

/// Manages a set of tabs for one side (left or right) of the dual-pane SFTP
/// window. Each tab wraps an independent `SFTPBrowserModel`.
@MainActor
final class SFTPTabGroup: ObservableObject {
    @Published var tabs: [SFTPTab] = []
    @Published var activeIndex: Int = 0

    var activeTab: SFTPTab? {
        guard tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }

    /// Append a new tab pointing at `location` and activate it.
    func newTab(location: FileLocation) {
        let tab = SFTPTab(location: location)
        tabs.append(tab)
        activeIndex = tabs.count - 1
    }

    /// Remove the tab at `index`. If the active tab was removed, the
    /// neighbour (or last remaining tab) becomes active.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeIndex = 0
        } else if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
    }
}
