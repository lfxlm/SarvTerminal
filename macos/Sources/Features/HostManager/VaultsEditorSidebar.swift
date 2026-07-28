import SwiftUI

/// Trailing side panel that overlays the current screen with a dimmed,
/// click-to-dismiss scrim — the "Edit host" pattern from the SSH connection
/// popup. Hosts any editor content (host editor, group editor, …) so the
/// screen underneath stays visible and navigation is never lost.
/// Supports resizable width via a drag handle on the leading edge.
struct VaultsEditorSidebar<Content: View>: View {
    let onClose: () -> Void
    var initialWidth: CGFloat = 400
    var minWidth: CGFloat = 320
    @ViewBuilder let content: Content

    @State private var panelWidth: CGFloat = 400
    @State private var dragStartWidth: CGFloat = 400

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Dimmed scrim over the rest of the screen; click to dismiss.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                content
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            // Invisible drag handle (wider than the visual divider
                            // so it's easy to grab). Uses .global coordinate space
                            // so the view's own frame changes don't jitter the tracking.
                            Color.clear
                                .frame(width: 6)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() }
                                    else { NSCursor.pop() }
                                }
                                .gesture(
                                    DragGesture(coordinateSpace: .global)
                                        .onChanged { value in
                                            let delta = value.startLocation.x - value.location.x
                                            panelWidth = max(minWidth, min(geo.size.width - 80, dragStartWidth + delta))
                                        }
                                        .onEnded { _ in
                                            dragStartWidth = panelWidth
                                        }
                                )
                            Divider()
                        }
                    }
            }
        }
        .onAppear { panelWidth = initialWidth; dragStartWidth = initialWidth }
    }
}
