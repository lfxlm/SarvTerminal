import SwiftUI
import AppKit

/// Vaults → Port Forwarding: save SSH tunnel rules and start/stop them. A rule
/// tunnels through one of your saved hosts; bytes flow over that SSH session.
struct PortForwardingSectionView: View {
    @ObservedObject private var store = PortForwardStore.shared
    @ObservedObject private var manager = PortForwardManager.shared
    @ObservedObject private var hosts = SavedHostsStore.shared
    @State private var search = ""
    @State private var draft: PortForward?
    @State private var isNew = false

    /// Run-state filter for the list.
    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, running, stopped, failed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:      return loc(.pf_filter_all)
            case .running:  return loc(.pf_filter_running)
            case .stopped:  return loc(.pf_filter_stopped)
            case .failed:   return loc(.pf_filter_failed)
            }
        }
    }
    @State private var statusFilter: StatusFilter = .all

    private var filtered: [PortForward] {
        let searched = SearchMatcher.filter(store.forwards, query: search) { [$0.displayName, $0.route] }
        switch statusFilter {
        case .all:
            return searched
        case .running:
            return searched.filter { manager.isRunning($0.id) }
        case .stopped:
            return searched.filter { !manager.isRunning($0.id) && manager.errors[$0.id] == nil }
        case .failed:
            return searched.filter { manager.errors[$0.id] != nil }
        }
    }

    private var runningCount: Int { store.forwards.filter { manager.isRunning($0.id) }.count }
    private var hasStopped: Bool { store.forwards.contains { !manager.isRunning($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            VaultsToolbar(
                primary: .init(title: "New forwarding", icon: "plus") { startNew() },
                actions: [
                    .init(title: runningCount > 0 ? "Stop all" : "Start all",
                          icon: runningCount > 0 ? "stop.circle" : "play.circle",
                          disabled: store.forwards.isEmpty,
                          help: runningCount > 0 ? "Stop all running tunnels" : "Start every stopped tunnel") {
                        if runningCount > 0 {
                            manager.stopAll()
                        } else {
                            manager.startAll(store.forwards)
                        }
                    }
                ])
            Divider()

            if store.loadFailed { VaultsLoadErrorBanner() }

            if store.forwards.isEmpty {
                VaultsEmptyState(
                    icon: "arrow.left.arrow.right",
                    title: "Set up port forwarding",
                    subtitle: "Save tunnels to reach databases, web apps, and other services running behind your servers. Each tunnel runs over a saved host's SSH connection.")
            } else {
                searchBar
                Divider()
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $draft) { forward in
            PortForwardEditorView(
                forward: forward,
                isNew: isNew,
                hosts: hosts.hosts,
                onSave: { store.upsert($0); draft = nil },
                onDelete: isNew ? nil : {
                    DeleteConfirmation.confirm(
                        forward.displayName,
                        detail: "This stops the tunnel (if running) and removes the saved port forward.") { confirmed in
                        guard confirmed else { return }
                        manager.stop(forward.id)
                        store.delete(forward)
                        draft = nil
                    }
                },
                onCancel: { draft = nil })
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondaryText)
                TextField("Search tunnels", text: $search).textFieldStyle(.plain)
                Spacer()
                Text("\(filtered.count) of \(store.forwards.count)").font(.caption).foregroundStyle(.secondaryText)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            // Run-state filter chips.
            HStack(spacing: 6) {
                ForEach(StatusFilter.allCases) { filter in
                    filterChip(filter)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }

    private func filterChip(_ filter: StatusFilter) -> some View {
        let isOn = statusFilter == filter
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { statusFilter = filter }
        } label: {
            Text(filter.label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2)))
                .foregroundStyle(isOn ? Color.accentColor : .secondaryText)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { forward in
                    PortForwardRow(
                        forward: forward,
                        hostLabel: hosts.host(withID: forward.hostID)?.displayLabel,
                        running: manager.isRunning(forward.id),
                        error: manager.errors[forward.id],
                        onToggle: { manager.toggle(forward) },
                        onEdit: { edit(forward) },
                        onDelete: {
                            DeleteConfirmation.confirm(
                                forward.displayName,
                                detail: "This stops the tunnel (if running) and removes the saved port forward.") { confirmed in
                                if confirmed { manager.stop(forward.id); store.delete(forward) }
                            }
                        })
                    Divider().padding(.leading, 52)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private func startNew() {
        var blank = PortForward.blank()
        if let first = hosts.hosts.first { blank.hostID = first.id }
        draft = blank
        isNew = true
    }

    private func edit(_ f: PortForward) { draft = f; isNew = false }
}

// MARK: - Row

private struct PortForwardRow: View {
    let forward: PortForward
    let hostLabel: String?
    let running: Bool
    let error: String?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.teal.opacity(0.15))
                Image(systemName: iconName).foregroundStyle(.teal)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(running ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(forward.displayName).font(.callout).lineLimit(1)
                    badge(forward.kind.short)
                }
                Text(routeLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if hovering {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("Edit")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help("Delete")
            }
            Button(action: onToggle) {
                Text(running ? "Stop" : "Start")
                    .font(.caption.weight(.semibold))
                    .frame(width: 46)
            }
            .buttonStyle(.bordered)
            .tint(running ? .red : .green)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button(running ? "Stop" : "Start", action: onToggle)
            Button("Edit", action: onEdit)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var iconName: String {
        switch forward.kind {
        case .local:   return "arrow.right"
        case .remote:  return "arrow.left"
        case .dynamic: return "network"
        }
    }

    private var routeLine: String {
        if let error { return error }
        let via = hostLabel.map { " · via \($0)" } ?? " · host missing"
        return forward.route + via
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
            .foregroundStyle(.secondaryText)
    }
}

// MARK: - Editor sheet

private struct PortForwardEditorView: View {
    @State var forward: PortForward
    let isNew: Bool
    let hosts: [SavedHost]
    let onSave: (PortForward) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    private var hostValid: Bool { hosts.contains { $0.id == forward.hostID } }
    private func validPort(_ p: Int) -> Bool { p >= 1 && p <= 65535 }
    private var bindAddressValid: Bool {
        let b = forward.bindAddress.trimmingCharacters(in: .whitespaces)
        return !b.isEmpty
    }
    private var destinationValid: Bool {
        !forward.kind.needsDestination
            || (!forward.destinationHost.trimmingCharacters(in: .whitespaces).isEmpty
                && validPort(forward.destinationPort))
    }
    private var canSave: Bool {
        hostValid
            && validPort(forward.listenPort)
            && bindAddressValid
            && destinationValid
    }

    /// First invalid field, for the inline error line under the form.
    private var validationError: String? {
        if !hostValid { return "Pick the host this tunnel runs over." }
        if !validPort(forward.listenPort) { return "Listen port must be between 1 and 65535." }
        if !bindAddressValid { return "Enter a bind address." }
        if forward.kind.needsDestination,
           forward.destinationHost.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a destination host."
        }
        if forward.kind.needsDestination, !validPort(forward.destinationPort) {
            return "Destination port must be between 1 and 65535."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Port Forwarding" : "Edit Port Forwarding").font(.title3.weight(.semibold))

            if hosts.isEmpty {
                Label("Add a host in Vaults → Hosts first — a tunnel runs over a saved host's SSH connection.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("Name") {
                TextField("e.g. Postgres on prod", text: $forward.name).textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                field("Type") {
                    Picker("", selection: $forward.kind) {
                        ForEach(PortForward.Kind.allCases) { Text($0.display).tag($0) }
                    }.labelsHidden()
                }
                field("Through host") {
                    Picker("", selection: $forward.hostID) {
                        if !hostValid { Text("Select a host…").tag(forward.hostID) }
                        ForEach(hosts) { Text($0.displayLabel).tag($0.id) }
                    }.labelsHidden()
                }
            }

            Divider()

            HStack(spacing: 12) {
                field(forward.kind == .remote ? "Server bind address" : "Local bind address",
                      help: "127.0.0.1 = only this machine. 0.0.0.0 = any interface.") {
                    TextField("127.0.0.1", text: $forward.bindAddress).textFieldStyle(.roundedBorder)
                }
                field("Listen port", width: 110) {
                    portField($forward.listenPort)
                }
            }

            if forward.kind.needsDestination {
                HStack(spacing: 12) {
                    field("Destination host", help: destinationHelp) {
                        TextField("localhost", text: $forward.destinationHost).textFieldStyle(.roundedBorder)
                    }
                    field("Destination port", width: 110) {
                        portField($forward.destinationPort)
                    }
                }
            } else {
                Text("A SOCKS proxy will listen on \(forward.bindAddress):\(forward.listenPort). Point your browser/app's SOCKS5 proxy there.")
                    .font(.caption).foregroundStyle(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(forward) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var destinationHelp: String {
        forward.kind == .remote
            ? "Reachable from THIS machine."
            : "Reachable from the server (e.g. localhost or an internal hostname)."
    }

    private func field<Content: View>(_ label: String, help: String? = nil, width: CGFloat? = nil,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondaryText)
            content()
            if let help { Text(help).font(.caption2).foregroundStyle(.tertiaryText) }
        }
        .frame(width: width, alignment: .leading)
    }

    private func portField(_ value: Binding<Int>) -> some View {
        TextField("0", value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
    }
}
