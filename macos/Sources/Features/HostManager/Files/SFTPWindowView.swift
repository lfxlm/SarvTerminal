import SwiftUI

/// Root view for the standalone SFTP window. Provides a left/right dual-pane
/// file browser, each side with its own tab bar, and a unified transfer table
/// at the bottom.
struct SFTPWindowView: View {
    @StateObject private var leftTabs = SFTPTabGroup()
    @StateObject private var rightTabs = SFTPTabGroup()

    // Dialog state (mirrors the former SFTPView's per-view dialogs).
    @State private var hostPickerSide: Side?
    @State private var newFolderSide: Side?
    @State private var newFolderName = ""
    @State private var renameTarget: (side: Side, item: FileItem)?
    @State private var renameText = ""
    @State private var permTarget: (side: Side, item: FileItem)?
    @State private var conflict: ConflictRequest?
    @State private var pendingDeletion: PendingDeletion?
    @State private var imagePreview: ImagePreviewData?

    enum Side: String, Identifiable { case left, right; var id: String { rawValue } }

    struct PendingDeletion: Identifiable {
        let id = UUID()
        let side: Side
        let items: [FileItem]
    }

    struct ImagePreviewData: Identifiable {
        let id = UUID()
        let url: URL
        let fileName: String
    }

    struct ConflictRequest: Identifiable {
        let id = UUID()
        let item: FileItem
        let fromSide: Side
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pane tab bars
            HStack(spacing: 0) {
                paneTabBar(side: .left, group: leftTabs)
                Divider()
                paneTabBar(side: .right, group: rightTabs)
            }
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Dual-pane file browser
            HStack(spacing: 0) {
                if let tab = leftTabs.activeTab {
                    FilePaneView(model: tab.browser) { handle($0, on: .left) }
                } else {
                    emptyPane(side: .left)
                }

                Divider()

                if let tab = rightTabs.activeTab {
                    FilePaneView(model: tab.browser) { handle($0, on: .right) }
                } else {
                    emptyPane(side: .right)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Unified transfer table
            Divider()
            UnifiedTransferTable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if leftTabs.tabs.isEmpty { leftTabs.newTab(location: .local) }
        }
        // Dialogs
        .sheet(item: $hostPickerSide) { side in
            FileHostChooser { location in
                let group = side == .left ? leftTabs : rightTabs
                group.newTab(location: location)
                hostPickerSide = nil
            } onCancel: { hostPickerSide = nil }
        }
        .onChange(of: newFolderSide) { side in
            guard let side else { return }
            SarvAlert.present(
                title: "New Folder",
                buttons: [
                    .init("Create", isDefault: true),
                    .init("Cancel", isCancel: true),
                ],
                inputInitial: "") { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await model(side).newFolder(named: result.inputText) }
                }
            }
            newFolderSide = nil
        }
        .onChange(of: renameTarget?.item.name) { _ in
            guard let target = renameTarget else { return }
            SarvAlert.present(
                title: "Rename",
                buttons: [
                    .init("Rename", isDefault: true),
                    .init("Cancel", isCancel: true),
                ],
                inputInitial: renameText) { result in
                if result.buttonIndex == 0, !result.inputText.isEmpty {
                    Task { await model(target.side).rename(target.item, to: result.inputText) }
                }
            }
            renameTarget = nil
        }
        .sheet(isPresented: Binding(
            get: { permTarget != nil },
            set: { if !$0 { permTarget = nil } }
        )) {
            if let t = permTarget {
                PermissionsSheet(
                    fileName: t.item.name,
                    isDirectory: t.item.isDirectory,
                    octal: octalGuess(t.item),
                    onApply: { octal in
                        Task { await model(t.side).setPermissions(t.item, octal: octal) }
                        permTarget = nil
                    },
                    onCancel: { permTarget = nil }
                )
            }
        }
        .onChange(of: pendingDeletion?.id) { _ in
            guard let d = pendingDeletion else { return }
            let names = d.items.map(\.name)
            if names.count == 1 {
                DeleteConfirmation.confirm(names[0], detail: "This can't be undone.") { confirmed in
                    if confirmed { Task { await performDelete(d.items, model: model(d.side)) } }
                }
            } else {
                SarvAlert.present(
                    title: "Delete \(names.count) items?",
                    message: "Are you sure you want to delete \(names.count) items? This can't be undone.",
                    buttons: [
                        .init("Delete", isDefault: true, isDestructive: true),
                        .init("Cancel", isCancel: true),
                    ]
                ) { result in
                    if result.buttonIndex == 0 {
                        Task { await performDelete(d.items, model: model(d.side)) }
                    }
                }
            }
            pendingDeletion = nil
        }
        .overlay {
            if let c = conflict {
                ConflictDialog(name: c.item.name) { resolve(c, $0) }
            }
        }
        .overlay {
            if let p = imagePreview {
                ImagePreviewView(url: p.url, fileName: p.fileName) {
                    imagePreview = nil
                }
            }
        }
    }

    // MARK: - Pane tab bar

    private func paneTabBar(side: Side, group: SFTPTabGroup) -> some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(group.tabs.enumerated()), id: \.element.id) { idx, tab in
                        tabPill(tab: tab, isActive: idx == group.activeIndex) {
                            group.activeIndex = idx
                        } onClose: {
                            group.closeTab(at: idx)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)

            // New tab (+) / choose host
            Button {
                hostPickerSide = side
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Connect to host…")
            .padding(.trailing, 4)
        }
    }

    private func tabPill(
        tab: SFTPTab,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()

            if tab.title != "Local" {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isActive
                      ? Color.primary.opacity(0.1)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    // MARK: - Empty pane

    private func emptyPane(side: Side) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiaryText)
            Text("No connection")
                .font(.callout)
                .foregroundStyle(.secondaryText)
            Button("Connect to host…") { hostPickerSide = side }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Coordination

    private func model(_ side: Side) -> SFTPBrowserModel {
        let group = side == .left ? leftTabs : rightTabs
        return group.activeTab?.browser ?? SFTPBrowserModel()
    }

    private func otherGroup(_ side: Side) -> SFTPTabGroup {
        side == .left ? rightTabs : leftTabs
    }

    private func handle(_ action: FilePaneAction, on side: Side) {
        let m = model(side)
        switch action {
        case .chooseHost:
            hostPickerSide = side
        case .open(let item):
            if item.isDirectory {
                m.open(item)
            } else if isImageFile(item.name) {
                openImagePreview(item, model: m)
            } else {
                FileEditorWindowController.shared.open(
                    model: FileViewerModel(item: item, backend: m.backend),
                    onDismiss: { SFTPWindowManager.shared.show() })
            }
        case .goUp: m.goUp()
        case .navigate(let p): Task { await m.load(p) }
        case .refresh: Task { await m.reload() }
        case .newFolder: newFolderName = ""; newFolderSide = side
        case .rename(let item): renameText = item.name; renameTarget = (side, item)
        case .delete(let items): deleteItems(items, on: side)
        case .editPermissions(let item): permTarget = (side, item)
        case .copyToTarget(let items): copyItems(items, from: side)
        }
    }

    /// Common image file extensions recognised by the system.
    private func isImageFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "icns"].contains(ext)
    }

    /// Download a remote image to a temp file and show the preview overlay.
    private func openImagePreview(_ item: FileItem, model: SFTPBrowserModel) {
        Task {
            do {
                let url = try await model.backend.localCopy(of: item)
                imagePreview = ImagePreviewData(url: url, fileName: item.name)
            } catch {
                // Fall back to the text viewer (will show its own error).
                FileEditorWindowController.shared.open(
                    model: FileViewerModel(item: item, backend: model.backend),
                    onDismiss: { SFTPWindowManager.shared.show() })
            }
        }
    }

    private func deleteItems(_ items: [FileItem], on side: Side) {
        if SFTPSettings.shared.confirmDelete {
            pendingDeletion = PendingDeletion(side: side, items: items)
        } else {
            Task { await performDelete(items, model: model(side)) }
        }
    }

    @MainActor
    private func performDelete(_ items: [FileItem], model: SFTPBrowserModel) async {
        for item in items { try? await model.delete(item) }
        await model.reload()
    }

    private func copyItems(_ items: [FileItem], from side: Side) {
        guard let sourceTab = (side == .left ? leftTabs : rightTabs).activeTab,
              let destTab = otherGroup(side).activeTab else { return }
        for item in items {
            beginTransfer(item, from: side, resolution: .replace)
        }
    }

    private func resolve(_ request: ConflictRequest, _ resolution: ConflictResolution) {
        conflict = nil
        guard resolution != .stop, resolution != .skip else { return }
        beginTransfer(request.item, from: request.fromSide, resolution: resolution)
    }

    private func beginTransfer(_ item: FileItem, from side: Side, resolution: ConflictResolution) {
        guard let sourceTab = (side == .left ? leftTabs : rightTabs).activeTab,
              let destTab = otherGroup(side).activeTab else { return }
        SFTPTransferManager.shared.startTransfer(
            from: sourceTab, to: destTab, item: item, resolution: resolution)
    }

    /// Best-effort octal from "rwxr-xr-x".
    private func octalGuess(_ item: FileItem) -> String {
        guard let p = item.permissions, p.count == 9 else {
            return item.isDirectory ? "755" : "644"
        }
        let chars = Array(p)
        var digits = ""
        for chunk in stride(from: 0, to: 9, by: 3) {
            var v = 0
            if chars[chunk] == "r" { v += 4 }
            if chars[chunk + 1] == "w" { v += 2 }
            if chars[chunk + 2] == "x" { v += 1 }
            digits += "\(v)"
        }
        return digits
    }
}
