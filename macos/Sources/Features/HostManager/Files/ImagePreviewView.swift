import SwiftUI
import AppKit

/// Full-window image preview shown as an overlay in the SFTP window.
/// Loads an image from a local URL and displays it with zoom and pan.
///
/// Zoom: ⌘ + scroll wheel (works on trackpad, Magic Mouse, and regular mouse).
/// Pan: drag. Double‑click to toggle 1× / 2×.
@MainActor
struct ImagePreviewView: View {
    let url: URL
    let fileName: String
    let onClose: () -> Void

    @State private var nsImage: NSImage?
    @State private var isLoading = true
    @State private var error: String?

    @ObservedObject private var lang = AppLanguageSettings.shared

    // Zoom / pan
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var monitor: Any?

    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 8.0

    var body: some View {
        ZStack {
            // Dimmed background — tap to close.
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            if isLoading {
                loadingView
            } else if let error {
                errorView(error)
            } else if let nsImage {
                imageView(nsImage)
            }

            // Keyboard shortcuts for zoom (hidden, zero‑size).
            Button("") { scale = min(maxScale, scale * 1.25) }
                .keyboardShortcut("=", modifiers: .command)
                .frame(width: 0, height: 0).hidden()
            Button("") { scale = max(minScale, scale / 1.25) }
                .keyboardShortcut("-", modifiers: .command)
                .frame(width: 0, height: 0).hidden()
            Button("") { scale = 1; offset = .zero }
                .keyboardShortcut("0", modifiers: .command)
                .frame(width: 0, height: 0).hidden()
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottom) { statusBar }
        .task { await loadImage() }
        .onAppear { installScrollWheelMonitor() }
        .onDisappear { removeScrollWheelMonitor() }
    }

    // MARK: - Event monitors (⌘+scroll zoom, Esc to close)

    private func installScrollWheelMonitor() {
        // ⌘+scroll → zoom
        let scrollMon = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.12 : (1.0 / 1.12)
            self.scale = min(maxScale, max(minScale, self.scale * factor))
            return nil
        }

        // Esc → close
        let keyMon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                self.onClose()
                return nil
            }
            return event
        }

        monitor = [scrollMon, keyMon] as Any
    }

    private func removeScrollWheelMonitor() {
        if let arr = monitor as? [Any] {
            for m in arr { if let obj = m as? AnyObject { NSEvent.removeMonitor(obj) } }
        } else if let m = monitor as? AnyObject {
            NSEvent.removeMonitor(m)
        }
        monitor = nil
    }

    // MARK: - Sub‑views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(loc(.loading_image))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.6))
            Text(msg)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Button(loc(.close)) { onClose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.white.opacity(0.3))
        }
    }

    private func imageView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { value in offset = value.translation }
                    .onEnded { _ in }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if scale > 1 {
                        scale = 1; offset = .zero
                    } else {
                        scale = 2; offset = .zero
                    }
                }
            }
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .padding(16)
        .help(loc(.close))
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundStyle(.white.opacity(0.6))
            Text(fileName)
                .lineLimit(1)
                .truncationMode(.middle)
            if let image = nsImage {
                Text("\(image.size.width, specifier: "%.0f")\u{2009}\u{00d7}\u{2009}\(image.size.height, specifier: "%.0f")")
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text("\u{00b7}").foregroundStyle(.white.opacity(0.3))
            Text(loc(.image_instructions))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    // MARK: - Load

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else {
                error = "Unable to decode image."
                return
            }
            nsImage = image
        } catch {
            self.error = error.localizedDescription
        }
    }
}
