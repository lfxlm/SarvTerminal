import SwiftUI

struct WindowSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            paddingCard
        }
    }

    // NOTE: window decoration / save-state / step-resize / titlebar settings are
    // intentionally omitted — SarvTerminal uses a single custom window with its
    // own titlebar and tab strip, so those native-chrome knobs have no effect.
    // Only padding (a surface-level render setting) actually applies here.
    private var paddingCard: some View {
        SettingsCard(title: loc(.w_padding)) {
            row(loc(.w_horizontal)) {
                TextField("points (e.g. 8)", text: $viewModel.window.paddingX)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .help("window-padding-x — left/right padding in points.")
            }
            divider
            row(loc(.w_vertical)) {
                TextField("points (e.g. 8)", text: $viewModel.window.paddingY)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .help("window-padding-y — top/bottom padding in points.")
            }
            divider
            row(loc(.w_padding_balance)) {
                Toggle(loc(.w_padding_balance_desc),
                       isOn: $viewModel.window.paddingBalance)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var divider: some View { SettingsDivider() }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        settingsRow(label, control: control)
    }
}
