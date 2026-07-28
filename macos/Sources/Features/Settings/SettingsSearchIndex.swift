import Foundation

/// A single searchable setting. Searching the Settings window matches against
/// these so typing "opacity", "ligature", "master password", etc. surfaces the
/// actual control and the section it lives in — not just section names.
///
/// This catalog is hand-maintained alongside the section views (the same way
/// `SettingsSection.keywords` already is). Keep an entry per user-facing control.
struct SettingsSearchEntry: Identifiable {
    let title: String
    let section: SettingsSection
    let keywords: [String]

    var id: String { "\(section.rawValue).\(title)" }

    func matches(_ query: String) -> Bool {
        if title.lowercased().contains(query) { return true }
        if section.title.lowercased().contains(query) { return true }
        return keywords.contains { $0.contains(query) }
    }

    static func e(_ title: String, _ section: SettingsSection, _ keywords: String...) -> SettingsSearchEntry {
        SettingsSearchEntry(title: title, section: section, keywords: keywords)
    }

    /// Every searchable setting across the visible sections.
    static let all: [SettingsSearchEntry] = [
        // General
        e(loc(.si_default_command), .general, "command", "shell", "program", "executable"),
        e(loc(.si_working_directory), .general, "cwd", "directory", "folder", "path", "home"),
        e(loc(.si_confirm_close), .general, "quit", "close", "confirm", "surface"),
        e(loc(.si_quit_last_window), .general, "quit", "exit", "last window"),
        e(loc(.si_hide_mouse), .general, "mouse", "pointer", "cursor", "hide"),
        e(loc(.si_focus_mouse), .general, "focus", "mouse", "hover"),
        e(loc(.si_scroll_speed), .general, "scroll", "speed", "multiplier", "wheel"),
        e(loc(.si_detect_urls), .general, "link", "url", "hyperlink", "open"),
        e(loc(.si_copy_on_select), .general, "copy", "selection", "clipboard"),
        e(loc(.si_clipboard_read), .general, "clipboard", "paste", "read", "access"),
        e(loc(.si_clipboard_write), .general, "clipboard", "copy", "write", "access"),
        e(loc(.si_paste_protection), .general, "paste", "protection", "safe", "warn"),
        e(loc(.si_scrollback_limit), .general, "scrollback", "buffer", "history", "memory", "lines"),
        e(loc(.si_scrollback_compression), .general, "scrollback", "compression", "compress", "memory", "ram"),

        // Appearance
        e(loc(.si_bg_color), .appearance, "background", "color", "bg"),
        e(loc(.si_bg_opacity), .appearance, "opacity", "transparency", "alpha", "translucent"),
        e(loc(.si_bg_blur), .appearance, "blur", "vibrancy", "glass", "frosted"),
        e(loc(.si_fg_color), .appearance, "foreground", "text", "color"),
        e(loc(.si_cursor_color), .appearance, "cursor", "caret", "color"),
        e(loc(.si_selection_fg), .appearance, "selection", "highlight", "foreground", "color"),
        e(loc(.si_selection_bg), .appearance, "selection", "highlight", "background", "color"),
        e(loc(.si_bold_color), .appearance, "bold", "bright", "color"),
        e(loc(.si_bg_image), .appearance, "image", "wallpaper", "picture", "photo", "background"),
        e(loc(.si_bg_image_opacity), .appearance, "image", "opacity", "wallpaper"),
        e(loc(.si_bg_image_fit), .appearance, "image", "fit", "cover", "contain", "stretch", "scale"),
        e(loc(.si_bg_image_position), .appearance, "image", "position", "align", "center"),
        e(loc(.si_theme), .appearance, "theme", "scheme", "palette", "colors", "preset"),
        e(loc(.si_window_theme), .appearance, "window", "theme", "light", "dark", "appearance", "mode"),

        // Font
        e(loc(.si_font_family), .font, "font", "family", "typeface", "monospace"),
        e(loc(.si_font_size), .font, "font", "size", "points", "scale", "bigger", "smaller"),
        e(loc(.si_font_features), .font, "ligature", "feature", "opentype", "calt"),
        e(loc(.si_bold_thicken), .font, "thicken", "bold", "weight", "heavy"),
        e(loc(.si_cell_width), .font, "cell", "width", "spacing", "horizontal"),
        e(loc(.si_cell_height), .font, "cell", "height", "line", "spacing", "vertical"),

        // Cursor
        e(loc(.si_cursor_style), .cursor, "cursor", "caret", "block", "bar", "underline", "beam"),
        e(loc(.si_cursor_blink), .cursor, "cursor", "blink", "flash"),
        e(loc(.si_cursor_text_color), .cursor, "cursor", "text", "color"),
        e(loc(.si_cursor_opacity), .cursor, "cursor", "opacity", "transparency"),
        e(loc(.si_click_to_move), .cursor, "cursor", "click", "move", "prompt"),

        // Window
        e(loc(.si_window_decoration), .window, "decoration", "titlebar", "border", "chrome"),
        e(loc(.si_window_save_state), .window, "save", "restore", "state", "session"),
        e(loc(.si_step_resize), .window, "resize", "step", "cell", "snap"),
        e(loc(.si_window_padding), .window, "padding", "margin", "inset", "spacing"),

        // Keybinds
        e(loc(.si_keyboard_shortcuts), .keybinds, "keybind", "shortcut", "hotkey", "binding", "key", "chord"),

        // Shell Integration
        e(loc(.si_shell_integration), .shellIntegration, "shell", "integration", "bash", "zsh", "fish", "detect"),
        e(loc(.si_shell_features), .shellIntegration, "cursor", "sudo", "title", "ssh", "terminfo", "path", "prompt"),

        // SFTP
        e(loc(.si_auto_save_edits), .sftp, "sftp", "autosave", "auto-save", "save", "editor"),
        e(loc(.si_confirm_delete), .sftp, "sftp", "delete", "confirm", "trash"),
        e(loc(.si_show_hidden), .sftp, "sftp", "hidden", "dotfiles", "show"),

        // Sync
        e(loc(.si_enable_sync), .sync, "sync", "backup", "enable", "cloud"),
        e(loc(.si_sync_provider), .sync, "sync", "github", "folder", "provider", "icloud", "dropbox"),
        e(loc(.si_repo_url), .sync, "sync", "github", "repo", "url", "repository"),
        e(loc(.si_access_token), .sync, "sync", "github", "token", "pat", "credential"),
        e(loc(.si_master_password), .sync, "sync", "master", "password", "encrypt", "key"),
        e(loc(.si_pull_sync), .sync, "sync", "pull", "push", "upload", "download"),

        // Advanced
        e(loc(.si_edit_config), .advanced, "config", "edit", "file", "raw", "editor"),
        e(loc(.si_open_config), .advanced, "config", "external", "editor", "open"),
    ]
}
