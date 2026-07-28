import SwiftUI

/// Settings section: entry point for importing appearance + keybindings from
/// another terminal emulator. The actual work happens in ``ImportSettingsSheet``.
struct ImportSectionView: View {
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: loc(.imp_migrate)) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(loc(.imp_desc))
                        .font(.callout)
                        .foregroundStyle(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(loc(.imp_auto_map),
                          systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondaryText)

                    Label(loc(.imp_not_touched),
                          systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondaryText)

                    Button {
                        showSheet = true
                    } label: {
                        Label(loc(.imp_button), systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.large)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsMetrics.horizontalPadding)
            }

            SettingsCard(title: loc(.imp_what_gets_imported)) {
                VStack(alignment: .leading, spacing: 0) {
                    supportRow(loc(.imp_ghostty_name), loc(.imp_ghostty_desc))
                    SettingsDivider()
                    supportRow(loc(.imp_alacritty_name), loc(.imp_alacritty_desc))
                    SettingsDivider()
                    supportRow(loc(.imp_wezterm_name), loc(.imp_wezterm_desc))
                    SettingsDivider()
                    supportRow(loc(.imp_iterm2_name), loc(.imp_iterm2_desc))
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            ImportSettingsSheet()
        }
    }

    private func supportRow(_ name: String, _ detail: String) -> some View {
        settingsRow(name, alignment: .top) {
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
