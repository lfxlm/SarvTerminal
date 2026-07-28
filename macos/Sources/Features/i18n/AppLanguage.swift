import Foundation

/// Supported UI languages. Stored in UserDefaults and observed by the app.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case en = "en"
    case zh = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

/// Return the effective language: if the user picked "System Default", use the
/// system's preferred language (falling back to English).
extension AppLanguage {
    static var effective: AppLanguage {
        let stored = AppLanguageSettings.shared.selected
        switch stored {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh") { return .zh }
            return .en
        case .en, .zh:
            return stored
        }
    }
}
