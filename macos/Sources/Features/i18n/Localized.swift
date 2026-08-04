import Foundation

// MARK: - Localized string lookup
//
// Usage:  Text(loc(.upload))
//         Text(loc(.done))
//         Text(loc(.delete_multi_title, count))

/// Return the localized string for `key` in the current effective language.
func loc(_ key: LocalizedKey, _ args: CVarArg...) -> String {
    let raw = localizedString(key)
    if args.isEmpty { return raw }
    return String(format: raw, arguments: args)
}

// MARK: - Keys

enum LocalizedKey: String, CaseIterable {
    // ── Common ──────────────────────────────────────────
    case done
    case failed
    case uploading
    case cancel
    case close
    case clear_completed
    case upload
    case download
    case new_folder
    case rename
    case delete
    case edit_permissions
    case refresh
    case create
    case save
    case view
    case copy
    case apply
    case collapsed
    case expanded
    case find
    case word_wrap
    case refresh_file
    case open_in_editor
    case reveal_in_finder
    case copy_file_path
    case more
    case loading
    case no_results
    case previous
    case next
    case close_find

    // ── File pane ───────────────────────────────────────
    case name_column
    case date_column
    case size_column
    case kind_column
    case search_files
    case filter_files
    case back_tooltip
    case forward_tooltip
    case change_host_tooltip
    case bookmarks_tooltip
    case new_folder_tooltip
    case refresh_tooltip
    case double_click_path
    case show_breadcrumb
    case type_path
    case sort_by
    case parent_folder
    case bookmarks_title
    case add_current_dir
    case no_bookmarks_yet
    case remove_bookmark
    case items

    // ── SFTP side panel ─────────────────────────────────
    case upload_files
    case upload_files_to
    case download_files
    case sftp_panel_close
    case choose_destination
    case choose_download_folder
    case local
    case new_folder_title
    case rename_title
    case delete_confirm_title
    case delete_confirm_detail
    case delete_multi_title
    case delete_multi_message
    case delete_failed_title
    case delete_failed_message
    case cancel_transfer_tip
    case retry
    case retry_transfer_tip
    case cancel_all
    case cancel_all_transfers_tip

    // ── Settings ────────────────────────────────────────
    case auto_save
    case save_edits_automatically
    case save_edits_description
    case indentation
    case indentation_description
    case browser
    case confirm_delete
    case hidden_files
    case show_hidden_files
    case show_hidden_files_description
    case search_settings
    case settings
    case no_settings_match
    case revert
    case reset_defaults
    case saved_automatically
    case editing
    case deleting

    // ── Language ────────────────────────────────────────
    case language
    case language_description
    case system_default

    // ── Unified transfer table ──────────────────────────
    case transfers
    case source_column
    case destination_column
    case file_column
    case size_column_small
    case progress_column
    case cancelled

    // ── File viewer ─────────────────────────────────────
    case edit_file
    case save_changes
    case save_changes_tip
    case rendered
    case raw
    case syntax_highlighting
    case indent
    case spaces_2
    case spaces_4
    case dont_save
    case unsaved_changes_title
    case unsaved_changes_message

    // ── Permissions sheet ───────────────────────────────
    case permissions
    case octal
    case symbolic
    case owner
    case group
    case everyone
    case read_perm
    case write_perm
    case execute_perm

    // ─── SFTP window ────────────────────────────────────
    case no_connection
    case connect_to_host
    case select_host
    case search_hosts
    case no_saved_hosts
    case file_already_exists
    case file_already_exists_detail
    case stop
    case skip
    case replace
    case duplicate
    case merge
    case loading_image
    case image_instructions

    // ── Terminal context menu ───────────────────────────
    case copy_menu
    case paste_menu
    case split_right
    case split_left
    case split_down
    case split_up
    case reset_terminal
    case toggle_inspector
    case terminal_readonly
    case change_tab_title
    case change_terminal_title
    case send_password

    // ── App Delegate / System dialogs ───────────────────
    case notification_show
    case allow_execute
    case allow
    case new_window_menu
    case new_tab_menu
    case failed_set_default_terminal
    case failed_set_default_message
    case ok
    case quit_confirm_title
    case quit_confirm_message
    case review_windows
    case terminate_processes

    // ── Settings - Sections ──────────────────────────
    case settings_general
    case settings_general_sub
    case settings_import
    case settings_import_sub
    case settings_appearance
    case settings_appearance_sub
    case settings_font
    case settings_font_sub
    case settings_window
    case settings_window_sub
    case settings_tabs
    case settings_tabs_sub
    case settings_cursor
    case settings_cursor_sub
    case settings_keybinds
    case settings_keybinds_sub
    case settings_shell_integration
    case settings_shell_integration_sub
    case settings_sftp
    case settings_sftp_sub
    case settings_sync
    case settings_sync_sub
    case settings_ai
    case settings_ai_sub
    case settings_notifications
    case settings_notifications_sub
    case settings_advanced
    case settings_advanced_sub

    // ── Settings - UI ────────────────────────────────
    case settings_heading
    case search_results_label
    case select_settings_section
    case coming_next_iteration
    case saved_label
    case reset_confirm_title
    case reset_confirm_msg
    case reset_to_default_button

    // ── Settings - Enum Labels ───────────────────────
    case cursor_style_block
    case cursor_style_bar
    case cursor_style_underline
    case cursor_style_block_hollow
    case cursor_blink_default
    case cursor_blink_on
    case cursor_blink_off
    case confirm_close_yes
    case confirm_close_no
    case confirm_close_always
    case copy_select_off
    case copy_select_selection
    case copy_select_clipboard
    case clipboard_ask
    case clipboard_allow
    case clipboard_deny
    case window_deco_auto
    case window_deco_none
    case window_deco_server
    case window_deco_client
    case save_state_default
    case save_state_never
    case save_state_always
    case titlebar_native
    case titlebar_transparent
    case titlebar_tabs
    case titlebar_hidden
    case proxy_visible
    case proxy_hidden
    case new_tab_current
    case new_tab_end
    case shell_int_detect
    case shell_int_none
    case shell_int_bash
    case shell_int_zsh
    case shell_int_fish
    case shell_int_elvish
    case shell_int_nushell
    case feature_cursor
    case feature_cursor_detail
    case feature_sudo
    case feature_sudo_detail
    case feature_title
    case feature_title_detail
    case feature_ssh_env
    case feature_ssh_env_detail
    case feature_ssh_terminfo
    case feature_ssh_terminfo_detail
    case feature_path
    case feature_path_detail
    case fit_contain
    case fit_cover
    case fit_stretch
    case fit_none
    case img_pos_top_left
    case img_pos_top
    case img_pos_top_right
    case img_pos_left
    case img_pos_center
    case img_pos_right
    case img_pos_bottom_left
    case img_pos_bottom
    case img_pos_bottom_right
    case blur_off
    case blur_subtle
    case blur_standard
    case blur_strong
    case blur_glass_regular
    case blur_glass_clear
    case theme_system
    case theme_light
    case theme_dark
    case theme_auto
    case theme_ghostty

    // ── Section Views - Appearance ─────────────
    case a_colors
    case a_foreground
    case a_cursor_color
    case a_selection_fg
    case a_selection_bg
    case a_bold_text
    case a_override
    case a_custom
    case a_default
    case a_background
    case a_color
    case a_opacity
    case a_blur
    case a_bg_image
    case a_image
    case a_display
    case a_per_pane
    case a_shared
    case a_image_visibility
    case a_fit
    case a_position
    case a_tile
    case a_repeat_image
    case a_choose_image
    case a_remove
    case a_theme_card
    case a_window_theme
    case a_theme_row
    case a_choose_bg_panel

    // ── Section Views - General ────────────────
    case g_hosts
    case g_hosts_connect
    case g_session
    case g_restore_tabs
    case g_restore_tabs_desc
    case g_terminal
    case g_progress_bar
    case g_progress_bar_desc
    case g_startup
    case g_command
    case g_working_dir
    case g_new_tab_dir
    case g_confirm_close
    case g_quit_last_window
    case g_quit_desc
    case g_mouse_focus
    case g_mouse
    case g_hide_mouse
    case g_focus
    case g_focus_desc
    case g_scroll_speed
    case g_links
    case g_detect_urls
    case file_link_editor
    case file_link_editor_default
    case file_link_editor_custom
    case file_link_editor_template_hint
    case path_not_found_title
    case path_not_found_message
    case copy_path
    case g_clipboard_card
    case g_copy_select
    case g_clipboard_read
    case g_clipboard_write
    case g_paste_protection
    case g_paste_warn
    case g_scrollback
    case g_buffer_size
    case g_compression
    case g_compress_idle
    case g_compress_desc

    // ── Section Views - Cursor ────────────────
    case c_style_card
    case c_cursor_style
    case c_blink
    case c_text_color_card
    case c_under_cursor
    case c_opacity_card
    case c_cursor_opacity
    case c_behavior_card
    case c_click_move
    case c_click_move_desc
    case c_click_move_detail

    // ── Section Views - Font ────────────────
    case f_advanced_card
    case f_auto_weight
    case f_auto_weight_desc
    case f_thicken
    case f_thicken_desc
    case f_cell_width
    case f_cell_height
    case f_family_card
    case f_font_family
    case f_size_card
    case f_font_size
    case f_features_card
    case f_opentype_features

    // ── Section Views - Tabs ────────────────
    case t_titlebar
    case t_style
    case t_proxy_icon
    case t_new_tab_card
    case t_position

    // ── Section Views - Window ────────────────
    case w_padding
    case w_horizontal
    case w_vertical
    case w_padding_balance
    case w_padding_balance_desc

    // ── Section Views - Shell Integration ──────
    case si_integration
    case si_shell
    case si_features

    // ── Section Views - Notifications ──────────
    case n_notifications_card
    case n_enable
    case n_enable_desc
    case n_sound_card
    case n_alert_sound
    case n_play_sound
    case n_sound
    case n_more_sounds
    case n_preview
    case n_notify_about

    // ── Section Views - Sync ───────────────────
    case syn_enable
    case syn_enable_desc
    case syn_secure_entry
    case syn_where_to_store
    case syn_provider
    case syn_repo_url
    case syn_access_token
    case syn_folder
    case syn_choose
    case syn_no_folder
    case syn_encryption
    case syn_master_password
    case syn_set
    case syn_change
    case syn_confirm
    case syn_status
    case syn_state
    case syn_update_available
    case syn_pull_now
    case syn_test_connection
    case syn_pull
    case syn_sync_up
    case syn_save
    case syn_later
    case syn_restart_now
    case syn_history
    case syn_keep_history
    case syn_versions_to_keep
    case syn_unlimited

    // ── Section Views - Advanced ───────────────
    case adv_config_file
    case adv_path
    case adv_copy_path
    case adv_actions
    case adv_edit_config
    case adv_edit_config_detail
    case adv_open_external
    case adv_open_external_detail
    case adv_reveal_finder
    case adv_reveal_finder_detail
    case adv_reload_config
    case adv_reload_config_detail
    case adv_diagnostics
    case adv_no_errors
    case adv_errors

    // ── Section Views - AI ─────────────────────
    case ai_command_assist
    case ai_enable
    case ai_desc
    case ai_provider_model
    case ai_provider
    case ai_api_key
    case ai_api_key_placeholder
    case ai_api_key_saved
    case ai_save_key
    case ai_clear_key
    case ai_get_key
    case ai_model
    case ai_endpoint
    case ai_test
    case ai_testing
    case ai_send_test
    case ai_working
    case ai_stored_encrypted
    case ai_load_models
    case ai_refresh_models

    // ── Section Views - Keybinds ───────────────
    case kb_configure
    case kb_configure_detail
    case kb_commands
    case kb_search
    case kb_no_matches
    case kb_reset_title
    case kb_reset_msg
    case kb_shortcut_in_use
    case kb_shortcut_reserved
    case kb_replace
    case kb_cancel
    case kb_reset
    case kb_fixed_shortcut
    case kb_remove_shortcut
    case kb_add_shortcut
    case kb_ok

    // ── Section Views - Import ─────────────────
    case imp_migrate
    case imp_desc
    case imp_auto_map
    case imp_not_touched
    case imp_button
    case imp_what_gets_imported

    // ── Search Index ───────────────────────────
    case si_default_command
    case si_working_directory
    case si_confirm_close
    case si_quit_last_window
    case si_hide_mouse
    case si_focus_mouse
    case si_scroll_speed
    case si_detect_urls
    case si_copy_on_select
    case si_clipboard_read
    case si_clipboard_write
    case si_paste_protection
    case si_scrollback_limit
    case si_scrollback_compression
    case si_bg_color
    case si_bg_opacity
    case si_bg_blur
    case si_fg_color
    case si_cursor_color
    case si_selection_fg
    case si_selection_bg
    case si_bold_color
    case si_bg_image
    case si_bg_image_opacity
    case si_bg_image_fit
    case si_bg_image_position
    case si_theme
    case si_window_theme
    case si_font_family
    case si_font_size
    case si_font_features
    case si_bold_thicken
    case si_cell_width
    case si_cell_height
    case si_cursor_style
    case si_cursor_blink
    case si_cursor_text_color
    case si_cursor_opacity
    case si_click_to_move
    case si_window_decoration
    case si_window_save_state
    case si_step_resize
    case si_window_padding
    case si_keyboard_shortcuts
    case si_shell_integration
    case si_shell_features
    case si_auto_save_edits
    case si_confirm_delete
    case si_show_hidden
    case si_enable_sync
    case si_sync_provider
    case si_repo_url
    case si_access_token
    case si_master_password
    case si_pull_sync
    case si_edit_config
    case si_open_config

    // ── Section Views - General extras ────────
    case g_command_placeholder
    case g_wd_placeholder
    case g_ntd_placeholder
    case g_reset

    // ── Section Views - Keybinds extras ───────
    case kb_reset_defaults
    case kb_reset_help

    // ── Section Views - AI extras ─────────────
    case ai_save_key_hint

    // ── Vaults / Host Manager ──────────────────
    case v_hosts
    case v_saved_sessions
    case v_teams
    case v_keychain
    case v_port_forwarding
    case v_snippets
    case v_known_hosts
    case v_logs
    case v_smb
    case h_view_grid
    case h_view_list
    case h_sort_az
    case h_sort_za
    case h_sort_newest
    case h_sort_oldest

    // ── Vaults / Host Manager — Dashboard ──────
    case h_quick_connect_placeholder
    case h_clear_help

    // ── SMB Connections ─────────────────────────
    case smb_connection
    case smb_connections
    case smb_new_connection
    case smb_connect
    case smb_server
    case smb_share
    case smb_username
    case smb_password
    case smb_domain
    case smb_label
    case smb_save_and_connect
    case smb_no_permissions
    case smb_mount_failed
    case smb_delete_confirm
    case smb_no_connections
    case smb_edit_title
    case smb_domain_optional
    case smb_label_optional
    case smb_password_placeholder
    case sftp_close_tab_confirm
    case h_connect_button
    case h_connect_as_ssh
    case h_connect_typing
    case h_action_import
    case h_action_terminal
    case h_action_serial
    case h_new_host
    case h_new_group
    case h_cloud_coming

    // ── Import Section support rows ────────────
    case imp_ghostty_name
    case imp_ghostty_desc
    case imp_alacritty_name
    case imp_alacritty_desc
    case imp_wezterm_name
    case imp_wezterm_desc
    case imp_iterm2_name
    case imp_iterm2_desc

    // ── Split chooser / command palette ────────
    case sp_open_in_split
    case sp_pick_hint
    case sp_search_placeholder
    case sp_drag_tip
    case sp_dismiss
    case pal_connect_via_ssh
    case pal_local_terminal
    case pal_serial
    case pal_toggle_scratchpad
    case pal_scratchpad_subtitle
    case pal_section_quick_connect
    case pal_section_hosts
    case pal_search_placeholder
    case pal_footer_hint
    case pal_hint_navigate
    case pal_hint_open
    case pal_hint_cancel
}

// MARK: - Localized dictionary

private func localizedString(_ key: LocalizedKey) -> String {
    switch AppLanguage.effective {
    case .zh: return zhStrings[key] ?? enStrings[key] ?? fallback(key)
    case .en, .system: return enStrings[key] ?? fallback(key)
    }
}

private func fallback(_ key: LocalizedKey) -> String {
    key.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
}

// swiftlint:disable:next identifier_name
private let enStrings: [LocalizedKey: String] = [
    // ── Common ──────────────────────────────────────────
    .done: "Done",
    .failed: "Failed",
    .uploading: "Uploading…",
    .cancel: "Cancel",
    .close: "Close",
    .clear_completed: "Clear completed",
    .upload: "Upload",
    .download: "Download",
    .new_folder: "New Folder",
    .rename: "Rename",
    .delete: "Delete",
    .edit_permissions: "Edit Permissions",
    .refresh: "Refresh",
    .create: "Create",
    .save: "Save",
    .view: "View",
    .copy: "Copy",
    .apply: "Apply",
    .collapsed: "Collapse",
    .expanded: "Expand",
    .find: "Find…",
    .word_wrap: "Word wrap",
    .refresh_file: "Refresh file",
    .open_in_editor: "Open in editor",
    .reveal_in_finder: "Reveal in Finder",
    .copy_file_path: "Copy file path",
    .more: "More",
    .loading: "Loading…",
    .no_results: "No results",
    .previous: "Previous",
    .next: "Next",
    .close_find: "Close (esc)",

    // ── File pane ───────────────────────────────────────
    .name_column: "Name",
    .date_column: "Date Modified",
    .size_column: "Size",
    .kind_column: "Kind",
    .search_files: "Search",
    .filter_files: "Filter files in this folder",
    .back_tooltip: "Back",
    .forward_tooltip: "Forward",
    .change_host_tooltip: "Change host / Local",
    .bookmarks_tooltip: "Bookmarks",
    .new_folder_tooltip: "New Folder",
    .refresh_tooltip: "Refresh",
    .double_click_path: "Double-click to type a path",
    .show_breadcrumb: "Show breadcrumb (Esc)",
    .type_path: "Type a path — or double-click the bar",
    .sort_by: "Sort by %@",
    .parent_folder: "Parent folder",
    .bookmarks_title: "Bookmarks",
    .add_current_dir: "Add current directory",
    .no_bookmarks_yet: "No bookmarks yet",
    .remove_bookmark: "Remove bookmark",
    .items: "items",

    // ── SFTP side panel ─────────────────────────────────
    .upload_files: "Upload files to current directory",
    .upload_files_to: "Upload files to",
    .download_files: "Download",
    .sftp_panel_close: "Close SFTP panel",
    .choose_destination: "Choose destination",
    .choose_download_folder: "Choose a destination folder for the downloaded files",
    .local: "Local",
    .new_folder_title: "New Folder",
    .rename_title: "Rename",
    .delete_confirm_title: "Delete",
    .delete_confirm_detail: "This can't be undone.",
    .delete_multi_title: "Delete %d items?",
    .delete_multi_message: "Are you sure you want to delete %d items? This can't be undone.",
    .delete_failed_title: "Delete Failed",
    .delete_failed_message: "%ld of %ld items couldn't be deleted:",
    .cancel_transfer_tip: "Cancel transfer",
    .retry: "Retry",
    .retry_transfer_tip: "Retry transfer",
    .cancel_all: "Cancel all",
    .cancel_all_transfers_tip: "Cancel all in-flight transfers",

    // ── Settings ────────────────────────────────────────
    .auto_save: "Auto-save",
    .save_edits_automatically: "Save edits automatically",
    .save_edits_description: "A moment after you stop typing. When off, save manually with the Save button or ⌘S.",
    .indentation: "Indentation",
    .indentation_description: "Spaces inserted by Tab. New files open with this; the viewer's dropdown can override it per file.",
    .browser: "Browser",
    .confirm_delete: "Confirm before deleting",
    .hidden_files: "Hidden files",
    .show_hidden_files: "Show hidden files",
    .show_hidden_files_description: "Show dot-files (e.g. .gitconfig) in the file list.",
    .search_settings: "Search settings",
    .settings: "Settings",
    .no_settings_match: "No settings match \"%@\"",
    .revert: "Revert",
    .reset_defaults: "Reset to Default",
    .saved_automatically: "Saved automatically",
    .editing: "Editing",
    .deleting: "Deleting",

    // ── Language ────────────────────────────────────────
    .language: "Language",
    .language_description: "Choose the display language for the interface.",
    .system_default: "System Default",

    // ── Unified transfer table ──────────────────────────
    .transfers: "Transfers",
    .source_column: "Source",
    .destination_column: "Destination",
    .file_column: "File",
    .size_column_small: "Size",
    .progress_column: "Progress",
    .cancelled: "Cancelled",

    // ── File viewer ─────────────────────────────────────
    .edit_file: "Edit file",
    .save_changes: "Save changes",
    .save_changes_tip: "Save changes (⌘S)",
    .rendered: "Rendered",
    .raw: "Raw",
    .syntax_highlighting: "Syntax highlighting",
    .indent: "Indent",
    .spaces_2: "2 spaces",
    .spaces_4: "4 spaces",
    .dont_save: "Don't Save",
    .unsaved_changes_title: "Unsaved Changes",
    .unsaved_changes_message: "\"%@\" has unsaved changes.",

    // ── Permissions sheet ───────────────────────────────
    .permissions: "Permissions",
    .octal: "Octal",
    .symbolic: "Symbolic",
    .owner: "Owner",
    .group: "Group",
    .everyone: "Everyone",
    .read_perm: "Read",
    .write_perm: "Write",
    .execute_perm: "Execute",

    // ─── SFTP window ────────────────────────────────────
    .no_connection: "No connection",
    .connect_to_host: "Connect to host…",
    .select_host: "Select Host",
    .search_hosts: "Search hosts",
    .no_saved_hosts: "No saved hosts",
    .file_already_exists: "File already exists",
    .file_already_exists_detail: "An item named \"%@\" already exists in this location. Do you want to replace it with the one you are moving?",
    .stop: "Stop",
    .skip: "Skip",
    .replace: "Replace",
    .duplicate: "Duplicate",
    .merge: "Merge",
    .loading_image: "Loading image\u{2026}",
    .image_instructions: "⌘±/scroll to zoom  ·  drag to pan  ·  double‑click to fit",

    // ── Terminal context menu ───────────────────────────
    .copy_menu: "Copy",
    .paste_menu: "Paste",
    .split_right: "Split Right",
    .split_left: "Split Left",
    .split_down: "Split Down",
    .split_up: "Split Up",
    .reset_terminal: "Reset Terminal",
    .toggle_inspector: "Toggle Terminal Inspector",
    .terminal_readonly: "Terminal Read-only",
    .change_tab_title: "Change Tab Title...",
    .change_terminal_title: "Change Terminal Title...",
    .send_password: "Send Password",

    // ── App Delegate / System dialogs ───────────────────
    .notification_show: "Show",
    .allow_execute: "Allow Sarv Terminal to execute \"%@\"?",
    .allow: "Allow",
    .new_window_menu: "New Window",
    .new_tab_menu: "New Tab",
    .failed_set_default_terminal: "Failed to Set Default Terminal",
    .failed_set_default_message: "Sarv Terminal could not be set as the default terminal application.\n\nError: %@",
    .ok: "OK",
    .quit_confirm_title: "You have %ld windows with running processes. Do you want to review these windows before quitting?",
    .quit_confirm_message: "If you don't review your windows, any running processes will be terminated",
    .review_windows: "Review Windows...",
    .terminate_processes: "Terminate Processes",

    // ── Settings - Sections ──────────────────────────
    .settings_general: "General",
    .settings_general_sub: "Startup behaviour, default command, shell.",
    .settings_import: "Import",
    .settings_import_sub: "Bring settings from another terminal.",
    .settings_appearance: "Appearance",
    .settings_appearance_sub: "Theme, colors, transparency, background.",
    .settings_font: "Font",
    .settings_font_sub: "Family, size, weight, ligatures, variations.",
    .settings_window: "Window",
    .settings_window_sub: "Decorations, size, padding, fullscreen.",
    .settings_tabs: "Tabs",
    .settings_tabs_sub: "Tab bar style, position, behavior.",
    .settings_cursor: "Cursor",
    .settings_cursor_sub: "Style, blinking, color, thickness.",
    .settings_keybinds: "Keybinds",
    .settings_keybinds_sub: "Keyboard shortcuts and key tables.",
    .settings_shell_integration: "Shell Integration",
    .settings_shell_integration_sub: "Auto-cd, prompts, SSH features.",
    .settings_sftp: "SFTP",
    .settings_sftp_sub: "File transfer: save behavior, deletes, hidden files.",
    .settings_sync: "Sync",
    .settings_sync_sub: "Encrypted backup of your settings, keybinds, and hosts.",
    .settings_ai: "AI",
    .settings_ai_sub: "Explain and fix failed commands with your own AI key.",
    .settings_notifications: "Notifications",
    .settings_notifications_sub: "Which events notify you, and the alert sound.",
    .settings_advanced: "Advanced",
    .settings_advanced_sub: "Raw config editor and power-user options.",

    // ── Settings - UI ────────────────────────────────
    .settings_heading: "Settings",
    .search_results_label: "%ld result",
    .select_settings_section: "Select a settings section",
    .coming_next_iteration: "Coming next iteration",
    .saved_label: "Saved",
    .reset_confirm_title: "Reset \"%@\" to defaults?",
    .reset_confirm_msg: "This restores every option in this section to its default value. You can undo it with Revert until you close Settings.",
    .reset_to_default_button: "Reset to Default",

    // ── Settings - Enum Labels ───────────────────────
    .cursor_style_block: "Block",
    .cursor_style_bar: "Bar (I-beam)",
    .cursor_style_underline: "Underline",
    .cursor_style_block_hollow: "Hollow Block",
    .cursor_blink_default: "System default",
    .cursor_blink_on: "Always blink",
    .cursor_blink_off: "Don't blink",
    .confirm_close_yes: "If process is running",
    .confirm_close_no: "Never",
    .confirm_close_always: "Always",
    .copy_select_off: "Off",
    .copy_select_selection: "Selection buffer only",
    .copy_select_clipboard: "System clipboard",
    .clipboard_ask: "Ask each time",
    .clipboard_allow: "Always allow",
    .clipboard_deny: "Always deny",
    .window_deco_auto: "Auto (per-platform)",
    .window_deco_none: "None",
    .window_deco_server: "Server (OS)",
    .window_deco_client: "Client (in-window)",
    .save_state_default: "Default",
    .save_state_never: "Never",
    .save_state_always: "Always",
    .titlebar_native: "Native",
    .titlebar_transparent: "Transparent (blends with background)",
    .titlebar_tabs: "Tabs in titlebar",
    .titlebar_hidden: "Hidden",
    .proxy_visible: "Visible",
    .proxy_hidden: "Hidden",
    .new_tab_current: "Right of current tab",
    .new_tab_end: "End of tab bar",
    .shell_int_detect: "Auto-detect",
    .shell_int_none: "Disabled",
    .shell_int_bash: "Bash",
    .shell_int_zsh: "Zsh",
    .shell_int_fish: "Fish",
    .shell_int_elvish: "Elvish",
    .shell_int_nushell: "Nushell",
    .feature_cursor: "Cursor",
    .feature_cursor_detail: "Restore cursor to a bar at the prompt.",
    .feature_sudo: "Sudo",
    .feature_sudo_detail: "Wrap sudo to preserve terminfo.",
    .feature_title: "Title",
    .feature_title_detail: "Update window title via shell integration.",
    .feature_ssh_env: "SSH env",
    .feature_ssh_env_detail: "Forward TERM and color env vars over SSH.",
    .feature_ssh_terminfo: "SSH terminfo",
    .feature_ssh_terminfo_detail: "Install Ghostty's terminfo on remote hosts (off by default — TERM falls back to xterm-256color).",
    .feature_path: "PATH",
    .feature_path_detail: "Add Ghostty's binary directory to PATH.",
    .fit_contain: "Contain (fit inside)",
    .fit_cover: "Cover (fill, may crop)",
    .fit_stretch: "Stretch",
    .fit_none: "Original size",
    .img_pos_top_left: "Top Left",
    .img_pos_top: "Top",
    .img_pos_top_right: "Top Right",
    .img_pos_left: "Left",
    .img_pos_center: "Center",
    .img_pos_right: "Right",
    .img_pos_bottom_left: "Bottom Left",
    .img_pos_bottom: "Bottom",
    .img_pos_bottom_right: "Bottom Right",
    .blur_off: "Off",
    .blur_subtle: "Subtle",
    .blur_standard: "Standard",
    .blur_strong: "Strong",
    .blur_glass_regular: "Liquid Glass (Regular)",
    .blur_glass_clear: "Liquid Glass (Clear)",
    .theme_system: "Follow System",
    .theme_light: "Light",
    .theme_dark: "Dark",
    .theme_auto: "Auto (by background color)",
    .theme_ghostty: "Use Active Theme",

    // ── Section Views - Appearance ─────────────
    .a_colors: "Colors",
    .a_foreground: "Foreground",
    .a_cursor_color: "Cursor",
    .a_selection_fg: "Selection FG",
    .a_selection_bg: "Selection BG",
    .a_bold_text: "Bold text",
    .a_override: "Override",
    .a_custom: "Custom",
    .a_default: "Default",
    .a_background: "Background",
    .a_color: "Color",
    .a_opacity: "Opacity",
    .a_blur: "Blur",
    .a_bg_image: "Background Image",
    .a_image: "Image",
    .a_display: "Display",
    .a_per_pane: "Per-pane",
    .a_shared: "Shared",
    .a_image_visibility: "Image visibility",
    .a_fit: "Fit",
    .a_position: "Position",
    .a_tile: "Tile",
    .a_repeat_image: "Repeat image to fill",
    .a_choose_image: "Choose image…",
    .a_remove: "Remove",
    .a_theme_card: "Theme",
    .a_window_theme: "Window theme",
    .a_theme_row: "Theme",
    .a_choose_bg_panel: "Choose Background Image",

    // ── Section Views - General ────────────────
    .g_hosts: "Hosts",
    .g_hosts_connect: "Hosts & sessions connect on",
    .g_session: "Session",
    .g_restore_tabs: "Restore tabs",
    .g_restore_tabs_desc: "Reopen last session's tabs when SarvTerminal launches",
    .g_terminal: "Terminal",
    .g_progress_bar: "Progress bar",
    .g_progress_bar_desc: "Show a running-command progress bar under the tab",
    .g_startup: "Startup",
    .g_command: "Command",
    .g_working_dir: "Working directory",
    .g_new_tab_dir: "New tab directory",
    .g_confirm_close: "Confirm close",
    .g_quit_last_window: "Quit after last window",
    .g_quit_desc: "Quit Ghostty when the last window closes",
    .g_mouse_focus: "Mouse & Focus",
    .g_mouse: "Mouse",
    .g_hide_mouse: "Hide mouse pointer while typing",
    .g_focus: "Focus",
    .g_focus_desc: "Focus follows mouse",
    .g_scroll_speed: "Scroll speed",
    .g_links: "Links",
    .g_detect_urls: "Detect URLs (⌘-click to open)",
    .file_link_editor: "Open file links with",
    .file_link_editor_default: "System Default",
    .file_link_editor_custom: "Custom…",
    .file_link_editor_template_hint: "URL template, e.g. vscode://file${file}:${line}:${column}",
    .path_not_found_title: "File Not Found",
    .path_not_found_message: "This path doesn't exist on your Mac. It may only exist on a remote server.",
    .copy_path: "Copy Path",
    .g_clipboard_card: "Clipboard",
    .g_copy_select: "Copy on select",
    .g_clipboard_read: "Clipboard read",
    .g_clipboard_write: "Clipboard write",
    .g_paste_protection: "Paste protection",
    .g_paste_warn: "Warn before pasting multi-line text that could run commands",
    .g_scrollback: "Scrollback",
    .g_buffer_size: "Buffer size",
    .g_compression: "Compression",
    .g_compress_idle: "Compress idle scrollback to save memory",
    .g_compress_desc: "Compresses off-screen history while the terminal is idle, cutting memory use. It's restored automatically when you scroll back.",

    // ── Section Views - Cursor ────────────────
    .c_style_card: "Style",
    .c_cursor_style: "Cursor style",
    .c_blink: "Blink",
    .c_text_color_card: "Text Color",
    .c_under_cursor: "Under-cursor text",
    .c_opacity_card: "Opacity",
    .c_cursor_opacity: "Cursor opacity",
    .c_behavior_card: "Behavior",
    .c_click_move: "Click to move",
    .c_click_move_desc: "Move cursor by clicking in the prompt line",
    .c_click_move_detail: "Requires shell integration. Sends arrow keys to move from the current cursor position to where you clicked.",

    // ── Section Views - Font ────────────────
    .f_advanced_card: "Advanced",
    .f_auto_weight: "Auto weight",
    .f_auto_weight_desc: "Adjust weight automatically for the screen (thicker on low-DPI, lighter on Retina)",
    .f_thicken: "Thicken",
    .f_thicken_desc: "Synthetic bold — thicken glyphs (helps thin fonts)",
    .f_cell_width: "Cell width",
    .f_cell_height: "Cell height",
    .f_family_card: "Family",
    .f_font_family: "Font family",
    .f_size_card: "Size",
    .f_font_size: "Font size",
    .f_features_card: "Features",
    .f_opentype_features: "OpenType features",

    // ── Section Views - Tabs ────────────────
    .t_titlebar: "macOS Titlebar",
    .t_style: "Style",
    .t_proxy_icon: "Proxy icon",
    .t_new_tab_card: "New Tab",
    .t_position: "Position",

    // ── Section Views - Window ────────────────
    .w_padding: "Padding",
    .w_horizontal: "Horizontal",
    .w_vertical: "Vertical",
    .w_padding_balance: "Padding balance",
    .w_padding_balance_desc: "Balance padding so the terminal grid stays centered",

    // ── Section Views - Shell Integration ──────
    .si_integration: "Integration",
    .si_shell: "Shell",
    .si_features: "Features",

    // ── Section Views - Notifications ──────────
    .n_notifications_card: "Notifications",
    .n_enable: "Enable",
    .n_enable_desc: "Show macOS notifications for app events",
    .n_sound_card: "Sound",
    .n_alert_sound: "Alert sound",
    .n_play_sound: "Play a sound when a notification arrives",
    .n_sound: "Sound",
    .n_more_sounds: "More sounds coming soon.",
    .n_preview: "Preview this sound",
    .n_notify_about: "Notify me about",

    // ── Section Views - Sync ───────────────────
    .syn_enable: "Settings Sync",
    .syn_enable_desc: "Back up your terminal customization, keybinds, and saved hosts — encrypted with a master password — to GitHub or a synced folder.",
    .syn_secure_entry: "Secure Keyboard Entry (in the app menu) is a per-machine security setting and is **not** synced.",
    .syn_where_to_store: "Where to store",
    .syn_provider: "Provider",
    .syn_repo_url: "Repository URL",
    .syn_access_token: "Access token",
    .syn_folder: "Folder",
    .syn_choose: "Choose…",
    .syn_no_folder: "No folder chosen",
    .syn_encryption: "Encryption",
    .syn_master_password: "Master password",
    .syn_set: "Set",
    .syn_change: "Change…",
    .syn_confirm: "Confirm",
    .syn_status: "Status",
    .syn_state: "State",
    .syn_update_available: "Update available",
    .syn_pull_now: "Pull now",
    .syn_test_connection: "Test Connection",
    .syn_pull: "Pull",
    .syn_sync_up: "Sync ↑",
    .syn_save: "Save",
    .syn_later: "Later",
    .syn_restart_now: "Restart Now",
    .syn_history: "Version History",
    .syn_keep_history: "Keep history",
    .syn_versions_to_keep: "Versions to keep",
    .syn_unlimited: "Unlimited",

    // ── Section Views - Advanced ───────────────
    .adv_config_file: "Configuration File",
    .adv_path: "Path",
    .adv_copy_path: "Copy path to clipboard",
    .adv_actions: "Actions",
    .adv_edit_config: "Edit config file",
    .adv_edit_config_detail: "Opens the config in the inbuilt editor (syntax highlighting, ⌘S to save).",
    .adv_open_external: "Open in external editor",
    .adv_open_external_detail: "Opens the config in your default text editor (e.g., $EDITOR or TextEdit).",
    .adv_reveal_finder: "Reveal in Finder",
    .adv_reveal_finder_detail: "Highlights the config file in a Finder window.",
    .adv_reload_config: "Reload configuration",
    .adv_reload_config_detail: "Re-reads the file and applies changes without restarting.",
    .adv_diagnostics: "Diagnostics",
    .adv_no_errors: "No configuration errors",
    .adv_errors: "%ld error",

    // ── Section Views - AI ─────────────────────
    .ai_command_assist: "AI Command Assist",
    .ai_enable: "Enable",
    .ai_desc: "When a command exits with a non-zero status, Sarv Terminal offers to explain the failure and suggest a fix using your chosen model.",
    .ai_provider_model: "Provider & Model",
    .ai_provider: "Provider",
    .ai_api_key: "API key",
    .ai_api_key_placeholder: "Paste your API key",
    .ai_api_key_saved: "•••••• saved — type to replace",
    .ai_save_key: "Save",
    .ai_clear_key: "Clear",
    .ai_get_key: "Get a key: %@",
    .ai_model: "Model",
    .ai_endpoint: "Endpoint",
    .ai_test: "Test",
    .ai_testing: "Testing…",
    .ai_send_test: "Send a test request",
    .ai_working: "Working",
    .ai_stored_encrypted: "Stored encrypted on this Mac. Never synced, backed up, or sent anywhere except %@.",
    .ai_load_models: "Load models",
    .ai_refresh_models: "Refresh model list",

    // ── Section Views - Keybinds ───────────────
    .kb_configure: "Configure keyboard shortcuts",
    .kb_configure_detail: "Click the + on any action to record a shortcut. Multiple shortcuts can map to the same action. Sarv Terminal's own shortcuts (command palette, local terminal) are rebindable too — e.g. you can swap ⌘T and ⌘L.",
    .kb_commands: "Commands",
    .kb_search: "Search by action or keys (e.g. \"cmd t\")",
    .kb_no_matches: "No matches",
    .kb_reset_title: "Reset all keybindings to defaults?",
    .kb_reset_msg: "All your custom keybindings will be removed from the config file. The built-in defaults (Copy ⌘C, Paste ⌘V, …) will take effect again. This can't be undone.",
    .kb_shortcut_in_use: "Shortcut already in use",
    .kb_shortcut_reserved: "Shortcut reserved",
    .kb_replace: "Replace",
    .kb_cancel: "Cancel",
    .kb_reset: "Reset",
    .kb_fixed_shortcut: "Fixed shortcut — can't be changed",
    .kb_remove_shortcut: "Remove this shortcut",
    .kb_add_shortcut: "Add a shortcut for %@",
    .kb_ok: "OK",

    // ── Section Views - Import ─────────────────
    .imp_migrate: "Migrate from another terminal",
    .imp_desc: "Coming from WezTerm, iTerm2, kitty, Alacritty, or Ghostty? Import your theme, colors, font, padding, and keybindings so SarvTerminal feels like home from the first launch.",
    .imp_auto_map: "Appearance is mapped automatically; you review and confirm keybindings.",
    .imp_not_touched: "Your hosts, vaults, SFTP, and sync are never touched.",
    .imp_button: "Import from another terminal…",
    .imp_what_gets_imported: "What gets imported",

    // ── Search Index ───────────────────────────
    .si_default_command: "Default command",
    .si_working_directory: "Working directory",
    .si_confirm_close: "Confirm close",
    .si_quit_last_window: "Quit after last window",
    .si_hide_mouse: "Hide mouse while typing",
    .si_focus_mouse: "Focus follows mouse",
    .si_scroll_speed: "Scroll speed",
    .si_detect_urls: "Detect URLs",
    .si_copy_on_select: "Copy on select",
    .si_clipboard_read: "Clipboard read",
    .si_clipboard_write: "Clipboard write",
    .si_paste_protection: "Paste protection",
    .si_scrollback_limit: "Scrollback limit",
    .si_scrollback_compression: "Scrollback compression",
    .si_bg_color: "Background color",
    .si_bg_opacity: "Background opacity",
    .si_bg_blur: "Background blur",
    .si_fg_color: "Foreground color",
    .si_cursor_color: "Cursor color",
    .si_selection_fg: "Selection foreground",
    .si_selection_bg: "Selection background",
    .si_bold_color: "Bold color",
    .si_bg_image: "Background image",
    .si_bg_image_opacity: "Background image opacity",
    .si_bg_image_fit: "Background image fit",
    .si_bg_image_position: "Background image position",
    .si_theme: "Theme",
    .si_window_theme: "Window theme",
    .si_font_family: "Font family",
    .si_font_size: "Font size",
    .si_font_features: "Font features / ligatures",
    .si_bold_thicken: "Bold text thickening",
    .si_cell_width: "Cell width",
    .si_cell_height: "Cell height",
    .si_cursor_style: "Cursor style",
    .si_cursor_blink: "Cursor blink",
    .si_cursor_text_color: "Cursor text color",
    .si_cursor_opacity: "Cursor opacity",
    .si_click_to_move: "Click to move cursor",
    .si_window_decoration: "Window decoration",
    .si_window_save_state: "Window save state",
    .si_step_resize: "Step resize",
    .si_window_padding: "Window padding",
    .si_keyboard_shortcuts: "Keyboard shortcuts",
    .si_shell_integration: "Shell integration",
    .si_shell_features: "Shell integration features",
    .si_auto_save_edits: "Auto-save edits",
    .si_confirm_delete: "Confirm before deleting",
    .si_show_hidden: "Show hidden files",
    .si_enable_sync: "Enable sync",
    .si_sync_provider: "Sync provider",
    .si_repo_url: "Repository URL",
    .si_access_token: "Access token",
    .si_master_password: "Master password",
    .si_pull_sync: "Pull / Sync now",
    .si_edit_config: "Edit config file",
    .si_open_config: "Open config externally",

    // ── Section Views - General extras ────────
    .g_command_placeholder: "/bin/zsh, /opt/homebrew/bin/fish, …",
    .g_wd_placeholder: "home, inherit, or a path",
    .g_ntd_placeholder: "home (default), or a path",
    .g_reset: "Reset",

    // ── Section Views - Keybinds extras ───────
    .kb_reset_defaults: "Reset to defaults",
    .kb_reset_help: "Remove all your custom keybindings; restores Ghostty's defaults.",

    // ── Section Views - AI extras ─────────────
    .ai_save_key_hint: "Save your API key to load the available models.",

    // ── Vaults / Host Manager ──────────────────
    .v_hosts: "Hosts",
    .v_saved_sessions: "Saved Sessions",
    .v_smb: "SMB",
    .v_teams: "Teams",
    .v_keychain: "Keychain",
    .v_port_forwarding: "Port Forwarding",
    .v_snippets: "Snippets",
    .v_known_hosts: "Known Hosts",
    .v_logs: "Logs",
    .smb_connection: "SMB Connection",
    .smb_connections: "SMB Connections",
    .smb_new_connection: "New SMB Connection…",
    .smb_connect: "Connect SMB…",
    .smb_server: "Server",
    .smb_share: "Share",
    .smb_username: "Username",
    .smb_password: "Password",
    .smb_domain: "Domain",
    .smb_label: "Label",
    .smb_save_and_connect: "Save & Connect",
    .smb_no_permissions: "SMB shares do not support changing permissions.",
    .smb_mount_failed: "Failed to connect to SMB share: %@",
    .smb_delete_confirm: "Delete this SMB connection?",
    .smb_no_connections: "No saved SMB connections",
    .smb_edit_title: "Edit SMB Connection",
    .smb_domain_optional: "Optional — leave empty for workgroup default",
    .smb_label_optional: "Optional display name",
    .smb_password_placeholder: "Password (stored encrypted)",
    .sftp_close_tab_confirm: "Closing this tab disconnects the connection. Continue?",
    .h_view_grid: "Grid",
    .h_view_list: "List",
    .h_sort_az: "A–Z",
    .h_sort_za: "Z–A",
    .h_sort_newest: "Newest first",
    .h_sort_oldest: "Oldest first",

    // ── Vaults / Host Manager — Dashboard ──────
    .h_quick_connect_placeholder: "Find a host or ssh user@hostname…",
    .h_clear_help: "Clear",
    .h_connect_button: "Connect",
    .h_connect_as_ssh: "Run as ssh command",
    .h_connect_typing: "Type ssh user@hostname to connect",
    .h_action_import: "Import",
    .h_action_terminal: "Terminal",
    .h_action_serial: "Serial",
    .h_new_host: "New host",
    .h_new_group: "New Group",
    .h_cloud_coming: "Cloud (coming soon)",

    // ── Import Section support rows ────────────
    .imp_ghostty_name: "Ghostty",
    .imp_ghostty_desc: "Theme, colors, font, padding, cursor, keybinds — near 1:1.",
    .imp_alacritty_name: "Alacritty · kitty",
    .imp_alacritty_desc: "Colors, font, opacity, padding, cursor, keybinds.",
    .imp_wezterm_name: "WezTerm",
    .imp_wezterm_desc: "Best-effort scrape of a Lua config (colors, font, keybinds).",
    .imp_iterm2_name: "iTerm2",
    .imp_iterm2_desc: "Colors from an exported .itermcolors file.",

    // ── Split chooser / command palette ────────
    .sp_open_in_split: "Open in this split",
    .sp_pick_hint: "Pick a host, quick-connect, or use a local terminal",
    .sp_search_placeholder: "Search hosts or ssh user@host",
    .sp_drag_tip: "Tip: drag a tab here to open it in this split",
    .sp_dismiss: "Dismiss",
    .pal_connect_via_ssh: "Connect via SSH",
    .pal_local_terminal: "Local Terminal",
    .pal_serial: "Serial",
    .pal_toggle_scratchpad: "Toggle Scratchpad",
    .pal_scratchpad_subtitle: "Stage & send commands",
    .pal_section_quick_connect: "Quick connect",
    .pal_section_hosts: "Hosts",
    .pal_search_placeholder: "Search hosts or tabs",
    .pal_footer_hint: "Quick connect, or pick a saved host",
    .pal_hint_navigate: "↑↓ navigate",
    .pal_hint_open: "⏎ open",
    .pal_hint_cancel: "Esc cancel",
]

// swiftlint:disable:next identifier_name
private let zhStrings: [LocalizedKey: String] = [
    // ── Common ──────────────────────────────────────────
    .done: "完成",
    .failed: "失败",
    .uploading: "上传中…",
    .cancel: "取消",
    .close: "关闭",
    .clear_completed: "清除已完成",
    .upload: "上传",
    .download: "下载",
    .new_folder: "新建文件夹",
    .rename: "重命名",
    .delete: "删除",
    .edit_permissions: "编辑权限",
    .refresh: "刷新",
    .create: "创建",
    .save: "保存",
    .view: "查看",
    .copy: "复制",
    .apply: "应用",
    .collapsed: "折叠",
    .expanded: "展开",
    .find: "查找…",
    .word_wrap: "自动换行",
    .refresh_file: "刷新文件",
    .open_in_editor: "在编辑器中打开",
    .reveal_in_finder: "在 Finder 中显示",
    .copy_file_path: "复制文件路径",
    .more: "更多",
    .loading: "加载中…",
    .no_results: "无结果",
    .previous: "上一个",
    .next: "下一个",
    .close_find: "关闭 (esc)",

    // ── File pane ───────────────────────────────────────
    .name_column: "名称",
    .date_column: "修改日期",
    .size_column: "大小",
    .kind_column: "类型",
    .search_files: "搜索",
    .filter_files: "过滤当前文件夹中的文件",
    .back_tooltip: "后退",
    .forward_tooltip: "前进",
    .change_host_tooltip: "切换主机 / 本地",
    .bookmarks_tooltip: "书签",
    .new_folder_tooltip: "新建文件夹",
    .refresh_tooltip: "刷新",
    .double_click_path: "双击输入路径",
    .show_breadcrumb: "显示面包屑导航 (Esc)",
    .type_path: "输入路径 — 或双击导航栏",
    .sort_by: "按 %@ 排序",
    .parent_folder: "上级文件夹",
    .bookmarks_title: "书签",
    .add_current_dir: "添加当前目录",
    .no_bookmarks_yet: "暂无书签",
    .remove_bookmark: "移除书签",
    .items: "项",

    // ── SFTP side panel ─────────────────────────────────
    .upload_files: "上传文件到当前目录",
    .upload_files_to: "上传文件到",
    .download_files: "下载",
    .sftp_panel_close: "关闭 SFTP 面板",
    .choose_destination: "选择目标",
    .choose_download_folder: "选择下载文件的目标文件夹",
    .local: "本地",
    .new_folder_title: "新建文件夹",
    .rename_title: "重命名",
    .delete_confirm_title: "删除",
    .delete_confirm_detail: "此操作不可撤销。",
    .delete_multi_title: "删除 %d 个项目？",
    .delete_multi_message: "确定要删除 %d 个项目吗？此操作不可撤销。",
    .delete_failed_title: "删除失败",
    .delete_failed_message: "有 %ld/%ld 个项目删除失败：",
    .cancel_transfer_tip: "取消传输",
    .retry: "重试",
    .retry_transfer_tip: "重试传输",
    .cancel_all: "取消全部",
    .cancel_all_transfers_tip: "取消所有进行中的传输",

    // ── Settings ────────────────────────────────────────
    .auto_save: "自动保存",
    .save_edits_automatically: "自动保存编辑",
    .save_edits_description: "停止输入后自动保存。关闭时需手动点击保存按钮或 ⌘S。",
    .indentation: "缩进",
    .indentation_description: "Tab 键插入的空格数。新文件默认使用此设置；查看器的下拉菜单可为单个文件覆盖。",
    .browser: "文件浏览",
    .confirm_delete: "删除前确认",
    .hidden_files: "隐藏文件",
    .show_hidden_files: "显示隐藏文件",
    .show_hidden_files_description: "在文件列表中显示点开头的文件（如 .gitconfig）。",
    .search_settings: "搜索设置",
    .settings: "设置",
    .no_settings_match: "没有匹配 \"%@\" 的设置",
    .revert: "撤销",
    .reset_defaults: "重置为默认值",
    .saved_automatically: "已自动保存",
    .editing: "编辑",
    .deleting: "删除",

    // ── Language ────────────────────────────────────────
    .language: "语言",
    .language_description: "选择界面显示语言。",
    .system_default: "跟随系统",

    // ── Unified transfer table ──────────────────────────
    .transfers: "传输队列",
    .source_column: "来源",
    .destination_column: "目标",
    .file_column: "文件",
    .size_column_small: "大小",
    .progress_column: "进度",
    .cancelled: "已取消",

    // ── File viewer ─────────────────────────────────────
    .edit_file: "编辑文件",
    .save_changes: "保存更改",
    .save_changes_tip: "保存更改 (⌘S)",
    .rendered: "渲染",
    .raw: "原始",
    .syntax_highlighting: "语法高亮",
    .indent: "缩进",
    .spaces_2: "2 空格",
    .spaces_4: "4 空格",
    .dont_save: "不保存",
    .unsaved_changes_title: "未保存的更改",
    .unsaved_changes_message: "“%@” 有未保存的更改。",

    // ── Permissions sheet ───────────────────────────────
    .permissions: "权限",
    .octal: "八进制",
    .symbolic: "符号",
    .owner: "所有者",
    .group: "群组",
    .everyone: "所有人",
    .read_perm: "读取",
    .write_perm: "写入",
    .execute_perm: "执行",

    // ─── SFTP window ────────────────────────────────────
    .no_connection: "未连接",
    .connect_to_host: "连接到主机…",
    .select_host: "选择主机",
    .search_hosts: "搜索主机",
    .no_saved_hosts: "没有已保存的主机",
    .file_already_exists: "文件已存在",
    .file_already_exists_detail: "名为 \"%@\" 的项目已存在。是否要替换它？",
    .stop: "停止",
    .skip: "跳过",
    .replace: "替换",
    .duplicate: "保留副本",
    .merge: "合并",
    .loading_image: "加载图片\u{2026}",
    .image_instructions: "⌘±/滚轮缩放  ·  拖拽平移  ·  双击适应",

    // ── Terminal context menu ───────────────────────────
    .copy_menu: "复制",
    .paste_menu: "粘贴",
    .split_right: "向右分屏",
    .split_left: "向左分屏",
    .split_down: "向下分屏",
    .split_up: "向上分屏",
    .reset_terminal: "重置终端",
    .toggle_inspector: "切换终端检查器",
    .terminal_readonly: "终端只读",
    .change_tab_title: "更改标签页标题…",
    .change_terminal_title: "更改终端标题…",
    .send_password: "发送密码",

    // ── App Delegate / System dialogs ───────────────────
    .notification_show: "显示",
    .allow_execute: "允许 Sarv Terminal 执行「%@」？",
    .allow: "允许",
    .new_window_menu: "新建窗口",
    .new_tab_menu: "新建标签页",
    .failed_set_default_terminal: "设置默认终端失败",
    .failed_set_default_message: "Sarv Terminal 无法被设为默认终端应用程序。\n\n错误：%@",
    .ok: "好",
    .quit_confirm_title: "您有 %ld 个正在运行进程的窗口，是否在退出前查看？",
    .quit_confirm_message: "如果不查看这些窗口，正在运行的进程将被终止",
    .review_windows: "查看窗口…",
    .terminate_processes: "终止进程",

    // ── Settings - Sections ──────────────────────────
    .settings_general: "通用",
    .settings_general_sub: "启动行为、默认命令、Shell。",
    .settings_import: "导入",
    .settings_import_sub: "从其他终端导入设置。",
    .settings_appearance: "外观",
    .settings_appearance_sub: "主题、颜色、透明度、背景。",
    .settings_font: "字体",
    .settings_font_sub: "字族、字号、字重、连字、变体。",
    .settings_window: "窗口",
    .settings_window_sub: "装饰、尺寸、内边距、全屏。",
    .settings_tabs: "标签页",
    .settings_tabs_sub: "标签栏样式、位置、行为。",
    .settings_cursor: "光标",
    .settings_cursor_sub: "样式、闪烁、颜色、粗细。",
    .settings_keybinds: "快捷键",
    .settings_keybinds_sub: "键盘快捷键和按键表。",
    .settings_shell_integration: "Shell 集成",
    .settings_shell_integration_sub: "自动 cd、提示符、SSH 功能。",
    .settings_sftp: "SFTP",
    .settings_sftp_sub: "文件传输：保存行为、删除、隐藏文件。",
    .settings_sync: "同步",
    .settings_sync_sub: "设置、快捷键和主机的加密备份。",
    .settings_ai: "AI",
    .settings_ai_sub: "用你自己的 AI 密钥解释和修复失败的命令。",
    .settings_notifications: "通知",
    .settings_notifications_sub: "哪些事件通知你，以及提醒声音。",
    .settings_advanced: "高级",
    .settings_advanced_sub: "原始配置编辑器和高级选项。",

    // ── Settings - UI ────────────────────────────────
    .settings_heading: "设置",
    .search_results_label: "%ld 个结果",
    .select_settings_section: "请选择一个设置分类",
    .coming_next_iteration: "下个迭代实现",
    .saved_label: "已保存",
    .reset_confirm_title: "重置「%@」为默认值？",
    .reset_confirm_msg: "这将把此分类中的所有选项恢复为默认值。在关闭设置前可以使用「撤销」来恢复。",
    .reset_to_default_button: "重置为默认值",

    // ── Settings - Enum Labels ───────────────────────
    .cursor_style_block: "方块",
    .cursor_style_bar: "竖线（I 型）",
    .cursor_style_underline: "下划线",
    .cursor_style_block_hollow: "空心方块",
    .cursor_blink_default: "跟随系统",
    .cursor_blink_on: "始终闪烁",
    .cursor_blink_off: "不闪烁",
    .confirm_close_yes: "有进程运行时确认",
    .confirm_close_no: "从不",
    .confirm_close_always: "总是",
    .copy_select_off: "关闭",
    .copy_select_selection: "仅选择缓冲区",
    .copy_select_clipboard: "系统剪贴板",
    .clipboard_ask: "每次询问",
    .clipboard_allow: "始终允许",
    .clipboard_deny: "始终拒绝",
    .window_deco_auto: "自动（按平台）",
    .window_deco_none: "无",
    .window_deco_server: "服务端（操作系统）",
    .window_deco_client: "客户端（窗口内）",
    .save_state_default: "默认",
    .save_state_never: "从不",
    .save_state_always: "始终",
    .titlebar_native: "原生",
    .titlebar_transparent: "透明（与背景融合）",
    .titlebar_tabs: "标签栏在标题栏中",
    .titlebar_hidden: "隐藏",
    .proxy_visible: "显示",
    .proxy_hidden: "隐藏",
    .new_tab_current: "当前标签右侧",
    .new_tab_end: "标签栏末尾",
    .shell_int_detect: "自动检测",
    .shell_int_none: "禁用",
    .shell_int_bash: "Bash",
    .shell_int_zsh: "Zsh",
    .shell_int_fish: "Fish",
    .shell_int_elvish: "Elvish",
    .shell_int_nushell: "Nushell",
    .feature_cursor: "光标",
    .feature_cursor_detail: "在提示符处将光标恢复为竖线。",
    .feature_sudo: "Sudo",
    .feature_sudo_detail: "包装 sudo 以保留 terminfo。",
    .feature_title: "标题",
    .feature_title_detail: "通过 shell 集成更新窗口标题。",
    .feature_ssh_env: "SSH 环境",
    .feature_ssh_env_detail: "通过 SSH 转发 TERM 和颜色环境变量。",
    .feature_ssh_terminfo: "SSH terminfo",
    .feature_ssh_terminfo_detail: "在远程主机上安装 Ghostty 的 terminfo（默认关闭 — TERM 回退到 xterm-256color）。",
    .feature_path: "PATH",
    .feature_path_detail: "将 Ghostty 的二进制目录添加到 PATH。",
    .fit_contain: "适配（适合内部）",
    .fit_cover: "覆盖（填充，可能裁剪）",
    .fit_stretch: "拉伸",
    .fit_none: "原始尺寸",
    .img_pos_top_left: "左上",
    .img_pos_top: "顶部",
    .img_pos_top_right: "右上",
    .img_pos_left: "左侧",
    .img_pos_center: "居中",
    .img_pos_right: "右侧",
    .img_pos_bottom_left: "左下",
    .img_pos_bottom: "底部",
    .img_pos_bottom_right: "右下",
    .blur_off: "关闭",
    .blur_subtle: "微弱",
    .blur_standard: "标准",
    .blur_strong: "强烈",
    .blur_glass_regular: "液态玻璃（常规）",
    .blur_glass_clear: "液态玻璃（清澈）",
    .theme_system: "跟随系统",
    .theme_light: "浅色",
    .theme_dark: "深色",
    .theme_auto: "自动（按背景色）",
    .theme_ghostty: "使用活动主题",

    // ── Section Views - Appearance ─────────────
    .a_colors: "颜色",
    .a_foreground: "前景色",
    .a_cursor_color: "光标",
    .a_selection_fg: "选中前景色",
    .a_selection_bg: "选中背景色",
    .a_bold_text: "粗体文字",
    .a_override: "覆盖",
    .a_custom: "自定义",
    .a_default: "默认",
    .a_background: "背景",
    .a_color: "颜色",
    .a_opacity: "不透明度",
    .a_blur: "模糊",
    .a_bg_image: "背景图片",
    .a_image: "图片",
    .a_display: "显示",
    .a_per_pane: "每个面板",
    .a_shared: "共享",
    .a_image_visibility: "图片可见度",
    .a_fit: "适配",
    .a_position: "位置",
    .a_tile: "平铺",
    .a_repeat_image: "重复图片以填充",
    .a_choose_image: "选择图片…",
    .a_remove: "移除",
    .a_theme_card: "主题",
    .a_window_theme: "窗口主题",
    .a_theme_row: "主题",
    .a_choose_bg_panel: "选择背景图片",

    // ── Section Views - General ────────────────
    .g_hosts: "主机",
    .g_hosts_connect: "主机和会话连接方式",
    .g_session: "会话",
    .g_restore_tabs: "恢复标签页",
    .g_restore_tabs_desc: "SarvTerminal 启动时重新打开上次会话的标签页",
    .g_terminal: "终端",
    .g_progress_bar: "进度条",
    .g_progress_bar_desc: "在标签页下方显示运行中命令的进度条",
    .g_startup: "启动",
    .g_command: "命令",
    .g_working_dir: "工作目录",
    .g_new_tab_dir: "新标签页目录",
    .g_confirm_close: "关闭时确认",
    .g_quit_last_window: "关闭最后一个窗口时退出",
    .g_quit_desc: "当最后一个窗口关闭时退出程序",
    .g_mouse_focus: "鼠标和焦点",
    .g_mouse: "鼠标",
    .g_hide_mouse: "输入时隐藏鼠标指针",
    .g_focus: "焦点",
    .g_focus_desc: "鼠标悬停切换焦点",
    .g_scroll_speed: "滚动速度",
    .g_links: "链接",
    .g_detect_urls: "检测 URL（⌘-点击打开）",
    .file_link_editor: "文件路径链接打开方式",
    .file_link_editor_default: "系统默认",
    .file_link_editor_custom: "自定义…",
    .file_link_editor_template_hint: "URL 模板，例如 vscode://file${file}:${line}:${column}",
    .path_not_found_title: "文件不存在",
    .path_not_found_message: "此路径在你的 Mac 上不存在，它可能只存在于远程服务器。",
    .copy_path: "复制路径",
    .g_clipboard_card: "剪贴板",
    .g_copy_select: "选择时复制",
    .g_clipboard_read: "剪贴板读取",
    .g_clipboard_write: "剪贴板写入",
    .g_paste_protection: "粘贴保护",
    .g_paste_warn: "在粘贴可能运行命令的多行文本之前发出警告",
    .g_scrollback: "回滚缓冲区",
    .g_buffer_size: "缓冲区大小",
    .g_compression: "压缩",
    .g_compress_idle: "压缩空闲回滚以节省内存",
    .g_compress_desc: "终端空闲时压缩屏幕外历史记录，减少内存占用。滚动回时自动恢复。",

    // ── Section Views - Cursor ────────────────
    .c_style_card: "样式",
    .c_cursor_style: "光标样式",
    .c_blink: "闪烁",
    .c_text_color_card: "文字颜色",
    .c_under_cursor: "光标下文字",
    .c_opacity_card: "不透明度",
    .c_cursor_opacity: "光标不透明度",
    .c_behavior_card: "行为",
    .c_click_move: "点击移动",
    .c_click_move_desc: "通过点击提示行中的位置来移动光标",
    .c_click_move_detail: "需要 Shell 集成。从当前光标位置向点击位置发送方向键移动。",

    // ── Section Views - Font ────────────────
    .f_advanced_card: "高级",
    .f_auto_weight: "自动字重",
    .f_auto_weight_desc: "根据屏幕自动调整字重（低 DPI 更粗，Retina 更细）",
    .f_thicken: "加粗",
    .f_thicken_desc: "合成粗体 — 加粗字形（帮助细体字体）",
    .f_cell_width: "单元格宽度",
    .f_cell_height: "单元格高度",
    .f_family_card: "字族",
    .f_font_family: "字体",
    .f_size_card: "字号",
    .f_font_size: "字体大小",
    .f_features_card: "特性",
    .f_opentype_features: "OpenType 特性",

    // ── Section Views - Tabs ────────────────
    .t_titlebar: "macOS 标题栏",
    .t_style: "样式",
    .t_proxy_icon: "代理图标",
    .t_new_tab_card: "新标签页",
    .t_position: "位置",

    // ── Section Views - Window ────────────────
    .w_padding: "内边距",
    .w_horizontal: "水平",
    .w_vertical: "垂直",
    .w_padding_balance: "内边距平衡",
    .w_padding_balance_desc: "平衡内边距以使终端网格居中",

    // ── Section Views - Shell Integration ──────
    .si_integration: "集成",
    .si_shell: "Shell",
    .si_features: "特性",

    // ── Section Views - Notifications ──────────
    .n_notifications_card: "通知",
    .n_enable: "启用",
    .n_enable_desc: "显示应用事件的 macOS 通知",
    .n_sound_card: "声音",
    .n_alert_sound: "提醒声音",
    .n_play_sound: "收到通知时播放声音",
    .n_sound: "声音",
    .n_more_sounds: "更多声音即将推出。",
    .n_preview: "预览此声音",
    .n_notify_about: "通知我",

    // ── Section Views - Sync ───────────────────
    .syn_enable: "设置同步",
    .syn_enable_desc: "使用主密码加密备份你的终端配置、快捷键和已保存的主机到 GitHub 或同步文件夹。",
    .syn_secure_entry: "安全键盘输入（应用菜单中）是每台机器的独立安全设置，**不会**同步。",
    .syn_where_to_store: "存储位置",
    .syn_provider: "提供商",
    .syn_repo_url: "仓库 URL",
    .syn_access_token: "访问令牌",
    .syn_folder: "文件夹",
    .syn_choose: "选择…",
    .syn_no_folder: "未选择文件夹",
    .syn_encryption: "加密",
    .syn_master_password: "主密码",
    .syn_set: "设置",
    .syn_change: "更改…",
    .syn_confirm: "确认",
    .syn_status: "状态",
    .syn_state: "状态",
    .syn_update_available: "有可用更新",
    .syn_pull_now: "立即拉取",
    .syn_test_connection: "测试连接",
    .syn_pull: "拉取",
    .syn_sync_up: "同步上传",
    .syn_save: "保存",
    .syn_later: "稍后",
    .syn_restart_now: "立即重启",
    .syn_history: "版本历史",
    .syn_keep_history: "保留历史",
    .syn_versions_to_keep: "保留版本数",
    .syn_unlimited: "无限制",

    // ── Section Views - Advanced ───────────────
    .adv_config_file: "配置文件",
    .adv_path: "路径",
    .adv_copy_path: "复制路径到剪贴板",
    .adv_actions: "操作",
    .adv_edit_config: "编辑配置文件",
    .adv_edit_config_detail: "在内置编辑器中打开配置（语法高亮，⌘S 保存）。",
    .adv_open_external: "在外部编辑器中打开",
    .adv_open_external_detail: "在默认文本编辑器中打开配置（如 $EDITOR 或 TextEdit）。",
    .adv_reveal_finder: "在 Finder 中显示",
    .adv_reveal_finder_detail: "在 Finder 窗口中高亮显示配置文件。",
    .adv_reload_config: "重新加载配置",
    .adv_reload_config_detail: "重新读取文件并应用更改，无需重启。",
    .adv_diagnostics: "诊断",
    .adv_no_errors: "没有配置错误",
    .adv_errors: "%ld 个错误",

    // ── Section Views - AI ─────────────────────
    .ai_command_assist: "AI 命令助手",
    .ai_enable: "启用",
    .ai_desc: "当命令以非零状态退出时，Sarv Terminal 会提供解释失败原因并使用你选择的模型建议修复方案。",
    .ai_provider_model: "提供商和模型",
    .ai_provider: "提供商",
    .ai_api_key: "API 密钥",
    .ai_api_key_placeholder: "粘贴你的 API 密钥",
    .ai_api_key_saved: "•••••• 已保存 — 输入以替换",
    .ai_save_key: "保存",
    .ai_clear_key: "清除",
    .ai_get_key: "获取密钥：%@",
    .ai_model: "模型",
    .ai_endpoint: "端点",
    .ai_test: "测试",
    .ai_testing: "测试中…",
    .ai_send_test: "发送测试请求",
    .ai_working: "工作正常",
    .ai_stored_encrypted: "在此 Mac 上加密存储。除 %@ 外，不会同步、备份或发送到任何地方。",
    .ai_load_models: "加载模型",
    .ai_refresh_models: "刷新模型列表",

    // ── Section Views - Keybinds ───────────────
    .kb_configure: "配置键盘快捷键",
    .kb_configure_detail: "点击任意操作的 + 按钮录制快捷键。多个快捷键可以映射到同一个操作。Sarv Terminal 自带的快捷键（命令面板、本地终端）也是可重绑定的 — 例如可以交换 ⌘T 和 ⌘L。",
    .kb_commands: "命令",
    .kb_search: "按操作或按键搜索（如「cmd t」）",
    .kb_no_matches: "无匹配",
    .kb_reset_title: "将所有快捷键重置为默认值？",
    .kb_reset_msg: "所有自定义快捷键将从配置文件中移除。内置默认值（复制 ⌘C、粘贴 ⌘V…）将重新生效。此操作不可撤销。",
    .kb_shortcut_in_use: "快捷键已被使用",
    .kb_shortcut_reserved: "快捷键已保留",
    .kb_replace: "替换",
    .kb_cancel: "取消",
    .kb_reset: "重置",
    .kb_fixed_shortcut: "固定快捷键 — 无法更改",
    .kb_remove_shortcut: "移除此快捷键",
    .kb_add_shortcut: "为 %@ 添加快捷键",
    .kb_ok: "好",

    // ── Section Views - Import ─────────────────
    .imp_migrate: "从其他终端迁移",
    .imp_desc: "从 WezTerm、iTerm2、kitty、Alacritty 或 Ghostty 迁移？导入主题、颜色、字体、内边距和快捷键，让 SarvTerminal 从第一次启动就感觉熟悉。",
    .imp_auto_map: "外观会自动映射；你可以审查并确认快捷键。",
    .imp_not_touched: "你的主机、保险库、SFTP 和同步配置不会受到影响。",
    .imp_button: "从其他终端导入…",
    .imp_what_gets_imported: "可导入的内容",

    // ── Search Index ───────────────────────────
    .si_default_command: "默认命令",
    .si_working_directory: "工作目录",
    .si_confirm_close: "关闭时确认",
    .si_quit_last_window: "关闭最后一个窗口时退出",
    .si_hide_mouse: "输入时隐藏鼠标",
    .si_focus_mouse: "鼠标悬停切换焦点",
    .si_scroll_speed: "滚动速度",
    .si_detect_urls: "检测 URL",
    .si_copy_on_select: "选择时复制",
    .si_clipboard_read: "剪贴板读取",
    .si_clipboard_write: "剪贴板写入",
    .si_paste_protection: "粘贴保护",
    .si_scrollback_limit: "回滚限制",
    .si_scrollback_compression: "回滚压缩",
    .si_bg_color: "背景色",
    .si_bg_opacity: "背景不透明度",
    .si_bg_blur: "背景模糊",
    .si_fg_color: "前景色",
    .si_cursor_color: "光标颜色",
    .si_selection_fg: "选中前景色",
    .si_selection_bg: "选中背景色",
    .si_bold_color: "粗体颜色",
    .si_bg_image: "背景图片",
    .si_bg_image_opacity: "背景图片不透明度",
    .si_bg_image_fit: "背景图片适配",
    .si_bg_image_position: "背景图片位置",
    .si_theme: "主题",
    .si_window_theme: "窗口主题",
    .si_font_family: "字体",
    .si_font_size: "字号",
    .si_font_features: "字体特性/连字",
    .si_bold_thicken: "粗体加粗",
    .si_cell_width: "单元格宽度",
    .si_cell_height: "单元格高度",
    .si_cursor_style: "光标样式",
    .si_cursor_blink: "光标闪烁",
    .si_cursor_text_color: "光标文字颜色",
    .si_cursor_opacity: "光标不透明度",
    .si_click_to_move: "点击移动光标",
    .si_window_decoration: "窗口装饰",
    .si_window_save_state: "窗口保存状态",
    .si_step_resize: "按步调整大小",
    .si_window_padding: "窗口内边距",
    .si_keyboard_shortcuts: "键盘快捷键",
    .si_shell_integration: "Shell 集成",
    .si_shell_features: "Shell 集成特性",
    .si_auto_save_edits: "自动保存编辑",
    .si_confirm_delete: "删除前确认",
    .si_show_hidden: "显示隐藏文件",
    .si_enable_sync: "启用同步",
    .si_sync_provider: "同步提供商",
    .si_repo_url: "仓库 URL",
    .si_access_token: "访问令牌",
    .si_master_password: "主密码",
    .si_pull_sync: "拉取/同步",
    .si_edit_config: "编辑配置文件",
    .si_open_config: "外部打开配置",

    // ── Section Views - General extras ────────
    .g_command_placeholder: "/bin/zsh、/opt/homebrew/bin/fish 等",
    .g_wd_placeholder: "home、inherit 或路径",
    .g_ntd_placeholder: "home（默认）或路径",
    .g_reset: "重置",

    // ── Section Views - Keybinds extras ───────
    .kb_reset_defaults: "重置为默认值",
    .kb_reset_help: "移除所有自定义快捷键，恢复 Ghostty 的默认设置。",

    // ── Section Views - AI extras ─────────────
    .ai_save_key_hint: "保存你的 API 密钥以加载可用模型。",

    // ── Vaults / Host Manager ──────────────────
    .v_hosts: "主机",
    .v_saved_sessions: "已保存的会话",
    .v_smb: "SMB",
    .v_teams: "团队",
    .v_keychain: "钥匙串",
    .v_port_forwarding: "端口转发",
    .v_snippets: "代码片段",
    .v_known_hosts: "已知主机",
    .v_logs: "日志",
    .smb_connection: "SMB 连接",
    .smb_connections: "SMB 连接",
    .smb_new_connection: "新建 SMB 连接…",
    .smb_connect: "连接 SMB…",
    .smb_server: "服务器",
    .smb_share: "共享",
    .smb_username: "用户名",
    .smb_password: "密码",
    .smb_domain: "域",
    .smb_label: "标签",
    .smb_save_and_connect: "保存并连接",
    .smb_no_permissions: "SMB 共享不支持修改权限。",
    .smb_mount_failed: "SMB 共享连接失败：%@",
    .smb_delete_confirm: "删除此 SMB 连接？",
    .smb_no_connections: "暂无已保存的 SMB 连接",
    .smb_edit_title: "编辑 SMB 连接",
    .smb_domain_optional: "可选 — 留空使用工作组默认值",
    .smb_label_optional: "可选显示名称",
    .smb_password_placeholder: "密码（加密存储）",
    .sftp_close_tab_confirm: "关闭此标签页将断开连接，是否继续？",
    .h_view_grid: "网格",
    .h_view_list: "列表",
    .h_sort_az: "A–Z",
    .h_sort_za: "Z–A",
    .h_sort_newest: "最新在前",
    .h_sort_oldest: "最旧在前",

    // ── Vaults / Host Manager — Dashboard ──────
    .h_quick_connect_placeholder: "搜索主机或 ssh user@hostname…",
    .h_clear_help: "清除",
    .h_connect_button: "连接",
    .h_connect_as_ssh: "作为 ssh 命令运行",
    .h_connect_typing: "输入 ssh user@hostname 进行连接",
    .h_action_import: "导入",
    .h_action_terminal: "终端",
    .h_action_serial: "串口",
    .h_new_host: "新建主机",
    .h_new_group: "新建组",
    .h_cloud_coming: "云（即将推出）",

    // ── Import Section support rows ────────────
    .imp_ghostty_name: "Ghostty",
    .imp_ghostty_desc: "主题、颜色、字体、内边距、光标、快捷键 — 近乎 1:1。",
    .imp_alacritty_name: "Alacritty · kitty",
    .imp_alacritty_desc: "颜色、字体、不透明度、内边距、光标、快捷键。",
    .imp_wezterm_name: "WezTerm",
    .imp_wezterm_desc: "尽力从 Lua 配置中抓取（颜色、字体、快捷键）。",
    .imp_iterm2_name: "iTerm2",
    .imp_iterm2_desc: "从导出的 .itermcolors 文件中导入颜色。",

    // ── Split chooser / command palette ────────
    .sp_open_in_split: "在此分屏中打开",
    .sp_pick_hint: "选择主机、快速连接，或使用本地终端",
    .sp_search_placeholder: "搜索主机或 ssh user@host",
    .sp_drag_tip: "提示：把标签页拖到这里可在此分屏中打开",
    .sp_dismiss: "关闭",
    .pal_connect_via_ssh: "通过 SSH 连接",
    .pal_local_terminal: "本地终端",
    .pal_serial: "串口",
    .pal_toggle_scratchpad: "切换草稿板",
    .pal_scratchpad_subtitle: "暂存并发送命令",
    .pal_section_quick_connect: "快速连接",
    .pal_section_hosts: "主机",
    .pal_search_placeholder: "搜索主机或标签页",
    .pal_footer_hint: "快速连接，或选择已保存的主机",
    .pal_hint_navigate: "↑↓ 导航",
    .pal_hint_open: "⏎ 打开",
    .pal_hint_cancel: "Esc 取消",
]
