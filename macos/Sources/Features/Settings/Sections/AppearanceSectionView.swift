import SwiftUI

/// Form for the Appearance section.
///
/// **B.1 scope (current):** background color / opacity / blur + window theme.
/// **B.1.1 follow-up:** theme picker (with discovery of built-in + user themes),
/// foreground / cursor / selection color overrides, palette editor.
/// **B.3:** Save actually writes these to `~/.config/sarvterminal/config` and reloads.
struct AppearanceSectionView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            backgroundCard
            colorsCard
            backgroundImageCard
            themeCard
        }
    }

    // MARK: - Colors card

    private var colorsCard: some View {
        SettingsCard(title: loc(.a_colors)) {
            row(loc(.a_foreground)) {
                ColorSwatchPicker(color: $viewModel.appearance.foregroundColor)
            }
            divider
            optionalColorRow(
                label: loc(.a_cursor_color),
                useOverride: $viewModel.appearance.useCursorColor,
                color: $viewModel.appearance.cursorColor
            )
            divider
            optionalColorRow(
                label: loc(.a_selection_fg),
                useOverride: $viewModel.appearance.useSelectionForeground,
                color: $viewModel.appearance.selectionForeground
            )
            divider
            optionalColorRow(
                label: loc(.a_selection_bg),
                useOverride: $viewModel.appearance.useSelectionBackground,
                color: $viewModel.appearance.selectionBackground
            )
            divider
            optionalColorRow(
                label: loc(.a_bold_text),
                useOverride: $viewModel.appearance.useBoldColor,
                color: $viewModel.appearance.boldColor
            )
        }
    }

    private func optionalColorRow(
        label: String,
        useOverride: Binding<Bool>,
        color: Binding<Color>
    ) -> some View {
        row(label) {
            HStack(spacing: 12) {
                Toggle(loc(.a_override), isOn: useOverride)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(useOverride.wrappedValue ? loc(.a_custom) : loc(.a_default))
                    .font(.callout)
                    .foregroundStyle(.secondaryText)
                    .frame(width: 60, alignment: .leading)
                if useOverride.wrappedValue {
                    ColorSwatchPicker(color: color)
                }
            }
        }
    }

    // MARK: - Background card

    private var backgroundCard: some View {
        SettingsCard(title: loc(.a_background)) {
            row(loc(.a_color)) {
                ColorSwatchPicker(color: $viewModel.appearance.backgroundColor)
            }
            divider
            row(loc(.a_opacity)) {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.appearance.backgroundOpacity, in: 0...1)
                        .frame(maxWidth: 320)
                    Text(String(format: "%.0f%%", viewModel.appearance.backgroundOpacity * 100))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryText)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            divider
            row(loc(.a_blur)) {
                Picker("", selection: $viewModel.appearance.backgroundBlur) {
                    ForEach(BackgroundBlurOption.availableOptions) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    // MARK: - Background image card

    private var backgroundImageCard: some View {
        SettingsCard(title: loc(.a_bg_image)) {
            row(loc(.a_image)) {
                imagePicker
            }

            divider
            row(loc(.a_display)) {
                Picker("", selection: $viewModel.appearance.backgroundDisplayShared) {
                    Text(loc(.a_per_pane)).tag(false)
                    Text(loc(.a_shared)).tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .help("Per-pane: each terminal draws its own copy. Shared: one image behind all panes.")
            }

            // Shared mode: a single image behind translucent panes. The only
            // knob that applies is how translucent the panes are.
            if viewModel.appearance.hasBackgroundImage && viewModel.appearance.backgroundDisplayShared {
                divider
                row(loc(.a_image_visibility)) {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.appearance.sharedImageVisibility, in: 0...1)
                            .frame(maxWidth: 320)
                        Text(String(format: "%.0f%%", viewModel.appearance.sharedImageVisibility * 100))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryText)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            // Per-pane mode: Ghostty's native background-image knobs. Only show
            // when an image is selected — keeps the card compact when not in use.
            if viewModel.appearance.hasBackgroundImage && !viewModel.appearance.backgroundDisplayShared {
                divider
                row(loc(.a_opacity)) {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.appearance.backgroundImageOpacity, in: 0...1)
                            .frame(maxWidth: 320)
                        Text(String(format: "%.0f%%", viewModel.appearance.backgroundImageOpacity * 100))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryText)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                divider
                row(loc(.a_fit)) {
                    Picker("", selection: $viewModel.appearance.backgroundImageFit) {
                        ForEach(BackgroundImageFit.allCases) { fit in
                            Text(fit.label).tag(fit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }
                divider
                row(loc(.a_position)) {
                    Picker("", selection: $viewModel.appearance.backgroundImagePosition) {
                        ForEach(BackgroundImagePosition.allCases) { pos in
                            Text(pos.label).tag(pos)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200, alignment: .leading)
                }
                divider
                row(loc(.a_tile)) {
                    Toggle(loc(.a_repeat_image), isOn: $viewModel.appearance.backgroundImageRepeat)
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    /// File-picker button. If an image is set, shows the filename + a Remove
    /// button. Otherwise, "Choose image…".
    private var imagePicker: some View {
        HStack(spacing: 8) {
            Button {
                pickBackgroundImage()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.appearance.hasBackgroundImage
                          ? "photo.fill"
                          : "photo")
                    Text(viewModel.appearance.hasBackgroundImage
                         ? (viewModel.appearance.backgroundImagePath as NSString).lastPathComponent
                         : loc(.a_choose_image))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 140, alignment: .leading)
            }
            .controlSize(.regular)

            if viewModel.appearance.hasBackgroundImage {
                Button(loc(.a_remove)) {
                    viewModel.appearance.backgroundImagePath = ""
                }
                .controlSize(.regular)
            }
        }
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.title = loc(.a_choose_bg_panel)
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentImageDirectory()

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.appearance.backgroundImagePath = url.path
        }
    }

    private func currentImageDirectory() -> URL? {
        let path = viewModel.appearance.backgroundImagePath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    // MARK: - Theme card

    private var themeCard: some View {
        SettingsCard(title: loc(.a_theme_card)) {
            row(loc(.a_window_theme)) {
                Picker("", selection: $viewModel.appearance.windowTheme) {
                    ForEach(WindowThemeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .leading)
            }
            divider
            row(loc(.a_theme_row)) {
                HStack(spacing: 8) {
                    ThemePicker(themeName: $viewModel.appearance.themeName)
                    ThemePreviewButton(themeName: viewModel.appearance.themeName)
                }
            }
        }
    }

    // MARK: - Row + divider helpers

    private func row<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingsRow(label, control: control)
    }

    private var divider: some View { SettingsDivider() }
}

// MARK: - BackgroundBlurOption availability

extension BackgroundBlurOption {
    /// Filters glass options out when running on older macOS.
    static var availableOptions: [BackgroundBlurOption] {
        var opts: [BackgroundBlurOption] = [.off, .subtle, .standard, .strong]
        if #available(macOS 26.0, *) {
            opts.append(.glassRegular)
            opts.append(.glassClear)
        }
        return opts
    }
}
