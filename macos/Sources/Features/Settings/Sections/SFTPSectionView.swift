import SwiftUI

/// SFTP / file-manager preferences. These live in `SFTPSettings` (UserDefaults),
/// independent of the Ghostty config — so changes apply immediately (no Save).
///
/// Layout mirrors the other settings sections: `DetailView` already renders the
/// section title/subtitle and the scroll container, so this view only emits the
/// cards (no own header / ScrollView). Each change flashes the footer's green
/// "Saved automatically" confirmation via the shared view model.
struct SFTPSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var settings = SFTPSettings.shared
    @ObservedObject private var lang = AppLanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: loc(.editing)) {
                row(loc(.auto_save)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(loc(.save_edits_automatically), isOn: $settings.autoSave)
                            .toggleStyle(.checkbox)
                        Text(loc(.save_edits_description))
                            .font(.caption).foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                divider
                row(loc(.indentation)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $settings.indentWidth) {
                            Text(loc(.spaces_2)).tag(2)
                            Text(loc(.spaces_4)).tag(4)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        Text(loc(.indentation_description))
                            .font(.caption).foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsCard(title: loc(.browser)) {
                row(loc(.deleting)) {
                    Toggle(loc(.confirm_delete), isOn: $settings.confirmDelete)
                        .toggleStyle(.checkbox)
                }
                divider
                row(loc(.hidden_files)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(loc(.show_hidden_files), isOn: $settings.showHidden)
                            .toggleStyle(.checkbox)
                        Text(loc(.show_hidden_files_description))
                            .font(.caption).foregroundStyle(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // Each setting applies instantly; mirror that into the footer's green
        // auto-saved confirmation so it's clear the change took effect.
        .onChange(of: settings.autoSave) { _ in viewModel.flashSaved() }
        .onChange(of: settings.confirmDelete) { _ in viewModel.flashSaved() }
        .onChange(of: settings.showHidden) { _ in viewModel.flashSaved() }
        .onChange(of: settings.indentWidth) { _ in viewModel.flashSaved() }
    }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        settingsRow(label, alignment: .top, control: control)
    }

    private var divider: some View { SettingsDivider() }
}
