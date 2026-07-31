import SwiftUI
import AppKit

/// Form for creating/editing a saved SMB connection. Used in two places:
/// - Vaults > SMB section, inside `VaultsEditorSidebar` (side panel)
/// - SFTP window's `FileHostChooser`, as a small sheet ("Connect SMB…")
///
/// Style mirrors `HostEditorView`'s rounded grouped cards, simplified to the
/// fields an SMB share needs. Password stays blank on edit to keep the stored
/// one (the store only replaces it when a new value is typed).
struct SMBConnectionFormView: View {
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (SMBConnection) -> Void

    @State private var label = ""
    @State private var server = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var domain = ""

    /// Keeps the id stable when editing an existing connection.
    private let existingID: UUID?

    @FocusState private var focused: Field?
    private enum Field: Hashable {
        case label, server, share, username, password, domain
    }

    init(connection: SMBConnection?,
         onCancel: @escaping () -> Void,
         onSave: @escaping (SMBConnection) -> Void) {
        self.isNew = connection == nil
        self.existingID = connection?.id
        self.onCancel = onCancel
        self.onSave = onSave
        _label = State(initialValue: connection?.label ?? "")
        _server = State(initialValue: connection?.server ?? "")
        _share = State(initialValue: connection?.share ?? "")
        _username = State(initialValue: connection?.username ?? "")
        _password = State(initialValue: connection?.password ?? "")
        _domain = State(initialValue: connection?.domain ?? "")
    }

    private var canSave: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !share.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    addressCard
                    credentialsCard
                }
                .padding(18)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isNew ? loc(.smb_new_connection) : loc(.smb_edit_title))
                .font(.headline)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(loc(.close))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Cards

    private var addressCard: some View {
        VStack(spacing: 0) {
            fieldRow(loc(.smb_server), text: $server, field: .server, placeholder: "192.168.1.10")
            Divider().opacity(0.5)
            fieldRow(loc(.smb_share), text: $share, field: .share, placeholder: "public")
            Divider().opacity(0.5)
            fieldRow(loc(.smb_domain), text: $domain, field: .domain, placeholder: loc(.smb_domain_optional))
            Divider().opacity(0.5)
            fieldRow(loc(.smb_label), text: $label, field: .label, placeholder: loc(.smb_label_optional))
        }
        .modifier(SMBCard())
    }

    private var credentialsCard: some View {
        VStack(spacing: 0) {
            fieldRow(loc(.smb_username), text: $username, field: .username, placeholder: "guest")
            Divider().opacity(0.5)
            SecureField(loc(.smb_password_placeholder), text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused, equals: .password)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .modifier(SMBCard())
    }

    private func fieldRow(_ title: String,
                          text: Binding<String>,
                          field: Field,
                          placeholder: String = "") -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused, equals: field)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(loc(.cancel)) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(loc(.save)) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func save() {
        var conn = SMBConnection()
        conn.id = existingID ?? UUID()
        conn.label = label.trimmingCharacters(in: .whitespaces)
        conn.server = server.trimmingCharacters(in: .whitespaces)
        conn.share = share.trimmingCharacters(in: .whitespaces)
        conn.username = username.trimmingCharacters(in: .whitespaces)
        conn.password = password
        conn.domain = domain.trimmingCharacters(in: .whitespaces)
        onSave(conn)
    }
}

/// Shared rounded-card container for SMB editor forms (the Hosts editor's
/// `EditorCard` is a generic View wrapper, so this one is a modifier).
struct SMBCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
