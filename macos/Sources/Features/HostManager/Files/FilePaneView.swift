import SwiftUI

/// One file-browser pane: location header + path + file list with a context
/// menu. Reports user intent up via `onAction`; all dialogs live in `SFTPView`.
struct FilePaneView: View {
    @ObservedObject var model: SFTPBrowserModel
    let onAction: (FilePaneAction) -> Void
    /// Whether to show the host/location picker button in the toolbar.
    var showHostPicker: Bool = true
    /// Compact layout: reduces Date/Size width and hides Kind — useful for
    /// side panels where horizontal space is limited.
    var compact: Bool = false
    /// Label for the "copy / download" context menu action.
    var copyActionLabel: String = "Copy to target directory"

    @ObservedObject private var lang = AppLanguageSettings.shared

    /// Editable copy of the current path (synced from `model.path`).
    @State private var pathEdit: String = ""
    @State private var pathEditing = false
    @FocusState private var pathFocused: Bool

    @StateObject private var bookmarkStore = SFTPBookmarkStore.shared
    @State private var showBookmarks = false

    // Column widths shared by the header and rows so they line up.
    private let dateW: CGFloat = 150
    private let sizeW: CGFloat = 78
    private let kindW: CGFloat = 72

    private var effectiveDateW: CGFloat { compact ? 120 : dateW }
    private var effectiveSizeW: CGFloat { compact ? 65 : sizeW }
    private var effectiveKindW: CGFloat { compact ? 0 : kindW }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy, h:mm a"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = model.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondaryText).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
            }
            columnHeader
            Divider()
            fileList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).disabled(!model.canGoBack).hoverTipText(loc(.back_tooltip))
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(!model.canGoForward).hoverTipText(loc(.forward_tooltip))

            if showHostPicker {
                Button { onAction(.chooseHost) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.location.isLocal ? "desktopcomputer" : "server.rack")
                        Text(model.location.title).fontWeight(.medium)
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.secondaryText)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain).hoverTipText(loc(.change_host_tooltip))
            }

            breadcrumbBar

            // Filter the current directory.
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondaryText)
                TextField(loc(.search_files), text: $model.search).textFieldStyle(.plain).font(.system(size: 11))
                    .frame(width: 110)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
            .hoverTipText(loc(.filter_files))

            if model.isLoading { ProgressView().controlSize(.small) }

            // Directory bookmarks (per‑server).
            Button { showBookmarks.toggle() } label: {
                Image(systemName: "bookmark")
                    .foregroundStyle(hasBookmarkForCurrentDir ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .hoverTipText(loc(.bookmarks_tooltip))
            .popover(isPresented: $showBookmarks, arrowEdge: .bottom) {
                bookmarkPopover
            }

            Button { onAction(.newFolder) } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.plain).hoverTipText(loc(.new_folder_tooltip))
            Button { onAction(.refresh) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).hoverTipText(loc(.refresh_tooltip))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Breadcrumb / path bar

    /// Breadcrumb of clickable folders (auto-scrolled to the last folder, like
    /// tabs), plus a button to type a full path.
    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            if pathEditing {
                TextField("", text: $pathEdit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .focused($pathFocused)
                    .onSubmit { commitPathEdit() }
                    .onExitCommand { pathEditing = false }
                    .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        let segs = pathSegments(model.path)
                        HStack(spacing: 3) {
                            ForEach(Array(segs.enumerated()), id: \.element.path) { i, s in
                                crumbButton(name: s.name, path: s.path).id(s.path)
                                if i < segs.count - 1 { crumbSeparator }
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .onAppear { scrollToLast(proxy) }
                    .onChange(of: model.path) { _ in scrollToLast(proxy) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverTipText(loc(.double_click_path))
            }

            // Toggles between breadcrumb and path-entry; the icon reflects what a
            // click will switch TO, so the way back from editing is discoverable.
            Button { pathEditing ? (pathEditing = false) : beginPathEdit() } label: {
                Image(systemName: pathEditing ? "rectangle.split.3x1" : "character.cursor.ibeam")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .hoverTipText(pathEditing ? loc(.show_breadcrumb) : loc(.type_path))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(pathEditing ? 0.18 : 0.08)))
        // Double-click anywhere in the bar's empty space to type a path — the
        // crumb buttons handle their own single clicks, so this only fires on the
        // blank area after the last folder.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !pathEditing { beginPathEdit() } }
        .onChange(of: model.path) { pathEdit = $0 }
        .onChange(of: pathFocused) { if !$0 { pathEditing = false } }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let last = pathSegments(model.path).last else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.path, anchor: .trailing) }
    }

    private func crumbButton(name: String, path: String) -> some View {
        Button { onAction(.navigate(path)) } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor.opacity(0.8))
                Text(name).font(.system(size: 12)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverCursor(.pointingHand)
    }

    private var crumbSeparator: some View {
        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiaryText)
    }

    /// Cumulative (name, absolutePath) pairs for the breadcrumb.
    private func pathSegments(_ path: String) -> [(name: String, path: String)] {
        let parts = path.split(separator: "/").map(String.init)
        if parts.isEmpty { return [(name: "/", path: "/")] }
        var acc = ""
        return parts.map { acc += "/" + $0; return (name: $0, path: acc) }
    }

    private func beginPathEdit() {
        pathEdit = model.path
        pathEditing = true
        DispatchQueue.main.async { pathFocused = true }
    }

    private func commitPathEdit() {
        onAction(.navigate(pathEdit.trimmingCharacters(in: .whitespaces)))
        pathEditing = false
    }

    // MARK: Column header (sortable)

    private var columnHeader: some View {
        HStack(spacing: 10) {
            sortHeader(loc(.name_column), .name).frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                sortHeader(loc(.date_column), .date).frame(width: effectiveDateW, alignment: .leading)
            }
            sortHeader(loc(.size_column), .size).frame(width: effectiveSizeW, alignment: .trailing)
            if !compact {
                sortHeader(loc(.kind_column), .kind).frame(width: effectiveKindW, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func sortHeader(_ title: String, _ col: SFTPBrowserModel.SortColumn) -> some View {
        Button { model.setSort(col) } label: {
            HStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondaryText)
                if model.sortColumn == col {
                    Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTipText(String(format: loc(.sort_by), title))
    }

    // MARK: List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.path != "/" && !model.path.isEmpty {
                    parentRow
                    Divider().opacity(0.4)
                }
                ForEach(model.displayItems) { item in
                    row(item)
                    Divider().opacity(0.4)
                }
            }
        }
        .contextMenu {
            Button(loc(.new_folder)) { onAction(.newFolder) }
            Button(loc(.refresh)) { onAction(.refresh) }
        }
    }

    /// The ".." parent-folder row (double-click to go up).
    private var parentRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill").foregroundStyle(Color.accentColor.opacity(0.7)).frame(width: 18)
            Text("..").frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Text("").frame(width: effectiveDateW)
            }
            Text("").frame(width: effectiveSizeW)
            if !compact {
                Text("").frame(width: effectiveKindW)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onAction(.goUp) }
        .hoverTipText(loc(.parent_folder))
    }

    /// File name with the current search term highlighted for visibility.
    private func nameText(_ name: String) -> Text {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let r = name.range(of: q, options: .caseInsensitive) else {
            return Text(name)
        }
        return Text(String(name[..<r.lowerBound]))
            + Text(String(name[r])).bold().foregroundColor(.orange)
            + Text(String(name[r.upperBound...]))
    }

    /// Whether the current directory is already in this location's bookmarks.
    private var hasBookmarkForCurrentDir: Bool {
        bookmarkStore.isBookmarked(path: model.path, for: model.location.locationID)
    }

    // MARK: Bookmarks popover

    @ViewBuilder
    private var bookmarkPopover: some View {
        let locID = model.location.locationID
        let list = bookmarkStore.bookmarks(for: locID)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(loc(.bookmarks_title))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if !hasBookmarkForCurrentDir {
                    Button { addCurrentDir(locID) } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(loc(.add_current_dir))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if list.isEmpty {
                Text(loc(.no_bookmarks_yet))
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { bookmark in
                            bookmarkRow(bookmark, locID: locID)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 240)
        .padding(.bottom, 6)
    }

    private func addCurrentDir(_ locID: String) {
        let name = (model.path as NSString).lastPathComponent
        let bm = SFTPBookmark(name: name.isEmpty ? "/" : name, path: model.path)
        bookmarkStore.add(bm, for: locID)
    }

    private func bookmarkRow(_ bookmark: SFTPBookmark, locID: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(bookmark.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button { bookmarkStore.remove(bookmark, for: locID) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiaryText)
            }
            .buttonStyle(.plain)
            .help(loc(.remove_bookmark))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            showBookmarks = false
            onAction(.navigate(bookmark.path))
        }
    }

    private func row(_ item: FileItem) -> some View {
        let selected = model.isSelected(item.id)
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    nameText(item.name).lineLimit(1).truncationMode(.middle)
                    if let p = item.permissions {
                        Text(p).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !compact {
                Text(item.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondaryText)
                    .frame(width: effectiveDateW, alignment: .leading)
            }
            Text(item.sizeText).font(.system(size: 11)).foregroundStyle(.secondaryText)
                .frame(width: effectiveSizeW, alignment: .trailing)
            if !compact {
                Text(model.kind(item)).font(.system(size: 11)).foregroundStyle(.secondaryText)
                    .lineLimit(1).frame(width: effectiveKindW, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                model.toggleSelection(item.id)
            } else if flags.contains(.shift) {
                model.selectRange(to: item.id)
            } else {
                model.selectSingle(item.id)
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            model.selectSingle(item.id)
            onAction(.open(item))
        })
        .contextMenu {
            if !item.isDirectory {
                Button(loc(.view)) { onAction(.open(item)) }
                Divider()
            }
            if model.isSelected(item.id), model.selectedIDs.count > 1 {
                Button("\(copyActionLabel) (\(model.selectedIDs.count) \(loc(.items)))") {
                    onAction(.copyToTarget(Array(model.selectedItems)))
                }
                Button("\(loc(.delete)) \(model.selectedIDs.count) \(loc(.items))", role: .destructive) {
                    onAction(.delete(Array(model.selectedItems)))
                }
            } else {
                Button(copyActionLabel) { onAction(.copyToTarget([item])) }
                Button(loc(.delete), role: .destructive) { onAction(.delete([item])) }
            }
            Button(loc(.rename)) { onAction(.rename(item)) }
            Divider()
            Button(loc(.refresh)) { onAction(.refresh) }
            Button(loc(.new_folder)) { onAction(.newFolder) }
            Button(loc(.edit_permissions)) { onAction(.editPermissions(item)) }
        }
    }
}

// MARK: - FileHostChooser

/// Termius-style host chooser: pick Local or a saved host for a pane.
struct FileHostChooser: View {
    let onPick: (FileLocation) -> Void
    let onCancel: () -> Void

    @ObservedObject private var store = SavedHostsStore.shared
    @State private var search = ""
    @ObservedObject private var lang = AppLanguageSettings.shared

    private var hosts: [SavedHost] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.hosts }
        return store.hosts.filter {
            $0.displayLabel.lowercased().contains(q) || $0.hostname.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc(.select_host)).font(.headline)
                Spacer()
                Button { onPick(.local) } label: {
                    Label(loc(.local), systemImage: "desktopcomputer")
                }
                .buttonStyle(.borderedProminent)
                Button(loc(.cancel)) { onCancel() }
            }
            .padding(14)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondaryText)
                TextField(loc(.search_hosts), text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if hosts.isEmpty {
                        Text(loc(.no_saved_hosts)).foregroundStyle(.secondaryText).padding(20)
                    }
                    ForEach(hosts) { host in
                        Button { onPick(.host(host)) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "server.rack").foregroundStyle(.secondaryText).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(host.displayLabel).fontWeight(.medium)
                                    Text(host.subtitle).font(.caption).foregroundStyle(.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - ConflictDialog

/// "File already exists" conflict prompt (Stop / Skip / Replace / Duplicate / Merge).
/// `showApplyToAll` adds an "apply to all remaining" checkbox for batch uploads.
struct ConflictDialog: View {
    let name: String
    var showApplyToAll: Bool = false
    let onResolve: (ConflictResolution, Bool) -> Void

    @ObservedObject private var lang = AppLanguageSettings.shared
    @State private var applyToAll = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text(loc(.file_already_exists)).font(.title3.weight(.semibold))
                Text(String(format: loc(.file_already_exists_detail), name))
                    .foregroundStyle(.secondaryText)
                if showApplyToAll {
                    Toggle("Apply to all remaining files", isOn: $applyToAll)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                HStack(spacing: 10) {
                    Button(loc(.stop), role: .destructive) { onResolve(.stop, applyToAll) }
                        .buttonStyle(.borderedProminent).tint(.red)
                    Button(loc(.skip)) { onResolve(.skip, applyToAll) }.buttonStyle(.plain)
                    Button(loc(.replace)) { onResolve(.replace, applyToAll) }
                    Button(loc(.duplicate)) { onResolve(.duplicate, applyToAll) }.buttonStyle(.borderedProminent)
                    Button(loc(.merge)) { onResolve(.merge, applyToAll) }
                }
            }
            .padding(24)
            .frame(width: 520, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .shadow(radius: 30, y: 10)
        }
    }
}
