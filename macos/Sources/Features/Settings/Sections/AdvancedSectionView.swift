import SwiftUI

/// Advanced section — config-file actions for power users.
///
/// Surfaces the config file path, links to open/reveal/reload, lists any
/// configuration errors Ghostty reported, and an option to reset the
/// GUI-written keys (preserves user-added content outside the GUI block).
struct AdvancedSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            fileCard
            actionsCard
            errorsCard
        }
    }

    // MARK: - Config file card

    private var fileCard: some View {
        SettingsCard(title: loc(.adv_config_file)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(loc(.adv_path))
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
                HStack {
                    Text(configFilePath)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        copyPath()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help(loc(.adv_copy_path))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Actions card

    private var actionsCard: some View {
        SettingsCard(title: loc(.adv_actions)) {
            VStack(alignment: .leading, spacing: 0) {
                actionRow(
                    title: loc(.adv_edit_config),
                    detail: loc(.adv_edit_config_detail),
                    systemImage: "doc.text",
                    action: editConfig
                )
                divider
                actionRow(
                    title: loc(.adv_open_external),
                    detail: loc(.adv_open_external_detail),
                    systemImage: "arrow.up.forward.app",
                    action: openInEditor
                )
                divider
                actionRow(
                    title: loc(.adv_reveal_finder),
                    detail: loc(.adv_reveal_finder_detail),
                    systemImage: "folder",
                    action: revealInFinder
                )
                divider
                actionRow(
                    title: loc(.adv_reload_config),
                    detail: loc(.adv_reload_config_detail),
                    systemImage: "arrow.clockwise",
                    action: reloadConfig
                )
            }
        }
    }

    private func actionRow(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Errors card

    private var errorsCard: some View {
        SettingsCard(title: loc(.adv_diagnostics)) {
            let errors = configErrors
            if errors.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(loc(.adv_no_errors))
                        .foregroundStyle(.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(errors.count) \(loc(.adv_errors, errors.count))")
                            .fontWeight(.semibold)
                    }
                    ForEach(errors.indices, id: \.self) { i in
                        Text(errors[i])
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Data + actions

    private var configErrors: [String] {
        (NSApp.delegate as? AppDelegate)?.ghostty.config.errors ?? []
    }

    private var configFilePath: String {
        return AppPaths.ghosttyConfigFile.path
    }

    private func editConfig() {
        FileEditorWindowController.shared.open(path: configFilePath)
    }

    private func openInEditor() {
        (NSApp.delegate as? AppDelegate)?.openConfig(nil)
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: configFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func reloadConfig() {
        (NSApp.delegate as? AppDelegate)?.reloadConfig(nil)
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configFilePath, forType: .string)
    }

    private var divider: some View { Divider().padding(.leading, 16) }
}
