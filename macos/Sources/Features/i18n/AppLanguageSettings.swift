import SwiftUI

/// Persists the user's language preference to UserDefaults. Follows the same
/// pattern as `SFTPSettings` so it integrates cleanly with the Settings UI.
final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()

    private enum Keys {
        static let selected = "SarvAppLanguage"
    }

    /// User's chosen language. Changing it posts a notification so the app can
    /// refresh UI strings.
    @Published var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Keys.selected)
            NotificationCenter.default.post(name: .sarvLanguageDidChange, object: nil)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.selected) ?? AppLanguage.system.rawValue
        selected = AppLanguage(rawValue: raw) ?? .system
    }
}

extension Notification.Name {
    /// Posted when the user changes the UI language. Observers should refresh
    /// any cached/displayed strings.
    static let sarvLanguageDidChange = Notification.Name("SarvLanguageDidChange")
}
