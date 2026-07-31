import SwiftUI
import AppKit

/// Vaults > SMB: saved SMB share connections, managed like SSH hosts.
///
/// List + "New SMB Connection…" button; editing opens the form in the same
/// trailing `VaultsEditorSidebar` the Hosts section uses. The actual file
/// browsing of a connection happens only in the SFTP window's FileHostChooser.
struct SMBConnectionsSectionView: View {
    @ObservedObject private var store = SMBConnectionStore.shared

    /// Connection being edited (nil = not editing).
    @State private var draft: SMBConnection? = nil
    @State private var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.connections.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .overlay {
            if draft != nil {
                VaultsEditorSidebar(onClose: { draft = nil }) {
                    SMBConnectionFormView(
                        connection: isNew ? nil : draft,
                        onCancel: { draft = nil },
                        onSave: { conn in
                            store.upsert(conn)
                            draft = nil
                        }
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.12), value: draft == nil)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(loc(.smb_connections))
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                isNew = true
                draft = SMBConnection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(loc(.smb_new_connection))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(Color.white)
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.connections) { conn in
                    row(conn)
                    Divider().opacity(0.4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func row(_ conn: SMBConnection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill.badge.wifi")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(conn.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                Button {
                    isNew = false
                    draft = conn
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(loc(.edit_permissions))

                Button {
                    confirmDelete(conn)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(loc(.delete))
            }
            .opacity(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.fill.badge.wifi")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(loc(.smb_no_connections))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button(loc(.smb_new_connection)) {
                isNew = true
                draft = SMBConnection()
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(Color.white)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Delete confirmation

    private func confirmDelete(_ conn: SMBConnection) {
        SarvAlert.present(
            title: conn.displayTitle,
            message: loc(.smb_delete_confirm),
            buttons: [
                .init(loc(.cancel), isCancel: true),
                .init(loc(.delete), isDestructive: true),
            ]
        ) { result in
            if result.buttonIndex == 1 {
                store.delete(conn)
            }
        }
    }
}
