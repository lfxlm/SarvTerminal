import SwiftUI

/// Settings ▸ Notifications: master switch, alert sound, and per-category
/// toggles for SarvTerminal's app-level notifications.
struct NotificationsSettingsView: View {
    @ObservedObject private var settings = SarvNotificationSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            generalCard
            soundCard
            eventsCard
        }
    }

    private var generalCard: some View {
        SettingsCard(title: loc(.n_notifications_card)) {
            row(loc(.n_enable)) {
                Toggle(loc(.n_enable_desc), isOn: $settings.enabled)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var soundCard: some View {
        SettingsCard(title: loc(.n_sound_card)) {
            row(loc(.n_alert_sound)) {
                Toggle(loc(.n_play_sound), isOn: $settings.soundEnabled)
                    .toggleStyle(.checkbox)
                    .disabled(!settings.enabled)
            }
            divider
            row(loc(.n_sound)) {
                HStack(spacing: 8) {
                    Picker("", selection: .constant(0)) {
                        Text("Default").tag(0)
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .fixedSize()
                    .disabled(true)
                    .help(loc(.n_more_sounds))
                    Button {
                        SarvNotifications.shared.previewSound()
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(loc(.n_preview))
                }
            }
        }
    }

    private var eventsCard: some View {
        SettingsCard(title: loc(.n_notify_about)) {
            ForEach(Array(SarvNotificationCategory.allCases.enumerated()), id: \.element.id) { index, category in
                if index > 0 { divider }
                row(category.label) {
                    Toggle(category.detail, isOn: binding(for: category))
                        .toggleStyle(.checkbox)
                        .disabled(!settings.enabled)
                }
            }
        }
    }

    private func binding(for category: SarvNotificationCategory) -> Binding<Bool> {
        Binding(
            get: { settings.categoryOn(category) },
            set: { settings.setCategory($0, category) }
        )
    }

    // MARK: - Row helpers (mirror the other settings sections)

    private func row<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingsRow(label, control: control)
    }

    private var divider: some View { SettingsDivider() }
}
