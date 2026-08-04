import SwiftUI

struct GeneralSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @AppStorage("SarvRestoreSession") private var restoreSession = true
    @AppStorage("SarvNewTabDirectory") private var newTabDirectory = ""
    @AppStorage(HostConnectClickMode.storageKey)
    private var hostsConnectClick: HostConnectClickMode = .double
    @AppStorage(FileLinkEditor.storageKey)
    private var fileLinkEditor: FileLinkEditor = .systemDefault
    @AppStorage(FileLinkEditor.customTemplateKey)
    private var fileLinkTemplate = ""

    @ObservedObject private var langSettings = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            languageCard
            startupCard
            sessionCard
            behaviorCard
            terminalCard
            hostsCard
            clipboardCard
            scrollbackCard
        }
    }

    private var languageCard: some View {
        SettingsCard(title: loc(.language)) {
            row(loc(.language_description)) {
                Picker("", selection: $langSettings.selected) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .leading)
            }
        }
    }

    private var hostsCard: some View {
        SettingsCard(title: loc(.g_hosts)) {
            row(loc(.g_hosts_connect)) {
                Picker("", selection: $hostsConnectClick) {
                    ForEach(HostConnectClickMode.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .leading)
            }
        }
    }

    private var sessionCard: some View {
        SettingsCard(title: loc(.g_session)) {
            row(loc(.g_restore_tabs)) {
                Toggle(loc(.g_restore_tabs_desc),
                       isOn: $restoreSession)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var terminalCard: some View {
        SettingsCard(title: loc(.g_terminal)) {
            row(loc(.g_progress_bar)) {
                Toggle(loc(.g_progress_bar_desc),
                       isOn: $viewModel.general.showProgressBar)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var startupCard: some View {
        SettingsCard(title: loc(.g_startup)) {
            row(loc(.g_command)) {
                HStack(spacing: 8) {
                    TextField(loc(.g_command_placeholder),
                              text: $viewModel.general.command)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .font(.system(.body, design: .monospaced))
                    if !viewModel.general.command.isEmpty {
                        Button(loc(.g_reset)) { viewModel.general.command = "" }
                            .controlSize(.small)
                    }
                }
            }
            divider
            row(loc(.g_working_dir)) {
                HStack(spacing: 8) {
                    TextField(loc(.g_wd_placeholder), text: $viewModel.general.workingDirectory)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .font(.system(.body, design: .monospaced))
                    if !viewModel.general.workingDirectory.isEmpty {
                        Button(loc(.g_reset)) { viewModel.general.workingDirectory = "" }
                            .controlSize(.small)
                    }
                }
            }
            divider
            row(loc(.g_new_tab_dir)) {
                HStack(spacing: 8) {
                    TextField(loc(.g_ntd_placeholder), text: $newTabDirectory)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .font(.system(.body, design: .monospaced))
                    if !newTabDirectory.isEmpty {
                        Button(loc(.g_reset)) { newTabDirectory = "" }
                            .controlSize(.small)
                    }
                }
            }
            divider
            row(loc(.g_confirm_close)) {
                Picker("", selection: $viewModel.general.confirmClose) {
                    ForEach(ConfirmCloseOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 280, alignment: .leading)
            }
            divider
            row(loc(.g_quit_last_window)) {
                Toggle(loc(.g_quit_desc),
                       isOn: $viewModel.general.quitAfterLastWindowClosed)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var behaviorCard: some View {
        SettingsCard(title: loc(.g_mouse_focus)) {
            row(loc(.g_mouse)) {
                Toggle(loc(.g_hide_mouse),
                       isOn: $viewModel.general.mouseHideWhileTyping)
                    .toggleStyle(.checkbox)
            }
            divider
            row(loc(.g_focus)) {
                Toggle(loc(.g_focus_desc),
                       isOn: $viewModel.general.focusFollowsMouse)
                    .toggleStyle(.checkbox)
            }
            divider
            row(loc(.g_scroll_speed)) {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.general.mouseScrollMultiplier, in: 0.1...10, step: 0.1)
                        .frame(maxWidth: 280)
                    Text(String(format: "%.1f×", viewModel.general.mouseScrollMultiplier))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.secondaryText)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            divider
            row(loc(.g_links)) {
                Toggle(loc(.g_detect_urls),
                       isOn: $viewModel.general.linkURL)
                    .toggleStyle(.checkbox)
            }
            divider
            row(loc(.file_link_editor)) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $fileLinkEditor) {
                        ForEach(FileLinkEditor.allCases) { editor in
                            Text(editor.label).tag(editor)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 220, alignment: .leading)

                    if fileLinkEditor == .custom {
                        TextField(loc(.file_link_editor_template_hint),
                                  text: $fileLinkTemplate)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                            .font(.system(.body, design: .monospaced))
                        Text(loc(.file_link_editor_template_hint))
                            .font(.caption).foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var clipboardCard: some View {
        SettingsCard(title: loc(.g_clipboard_card)) {
            row(loc(.g_copy_select)) {
                Picker("", selection: $viewModel.general.copyOnSelect) {
                    ForEach(CopyOnSelectOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 260, alignment: .leading)
            }
            divider
            row(loc(.g_clipboard_read)) {
                Picker("", selection: $viewModel.general.clipboardRead) {
                    ForEach(ClipboardAccessOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .leading)
            }
            divider
            row(loc(.g_clipboard_write)) {
                Picker("", selection: $viewModel.general.clipboardWrite) {
                    ForEach(ClipboardAccessOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200, alignment: .leading)
            }
            divider
            row(loc(.g_paste_protection)) {
                Toggle(loc(.g_paste_warn),
                       isOn: $viewModel.general.clipboardPasteProtection)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var scrollbackCard: some View {
        SettingsCard(title: loc(.g_scrollback)) {
            row(loc(.g_buffer_size)) {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.general.scrollbackLimitMB, in: 1...100, step: 1)
                        .frame(maxWidth: 320)
                    Text(String(format: "%.0f MB", viewModel.general.scrollbackLimitMB))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryText)
                        .frame(width: 70, alignment: .trailing)
                }
            }
            divider
            row(loc(.g_compression)) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(loc(.g_compress_idle),
                           isOn: $viewModel.general.scrollbackCompression)
                        .toggleStyle(.checkbox)
                    Text(loc(.g_compress_desc))
                        .font(.caption).foregroundStyle(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        settingsRow(label, control: control)
    }

    private var divider: some View { SettingsDivider() }
}
