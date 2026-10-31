import SwiftUI
import ObjectiveC

/// The language NAGISEN shows, chosen inside the app; `system` follows the iPhone's language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, fr, ar

    static let storageKey = "nagisen.language"

    var id: String { rawValue }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Each language is written in itself, so anyone can find theirs.
    var label: String {
        switch self {
        case .system: String(localized: "Match iPhone")
        case .en: "English"
        case .fr: "Français"
        case .ar: "العربية"
        }
    }

    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    /// Switches the app's text now; dates, numbers and the iPhone's own prompts follow from the next launch.
    func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
        let defaults = UserDefaults.standard
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: "AppleLocale")
        } else {
            // Dates and numbers follow AppleLocale; the region stays the iPhone's own.
            let region = Locale.current.region?.identifier ?? "MA"
            defaults.set([rawValue], forKey: "AppleLanguages")
            defaults.set("\(rawValue)_\(region)", forKey: "AppleLocale")
        }
        LanguageBundle.use(self)
    }
}

extension String {
    /// `String(localized:)` in the language chosen inside NAGISEN, not only the iPhone's. It shadows
    /// Foundation's version (which has extra defaulted arguments), so every call site follows the setting.
    init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: LanguageBundle.strings)
    }
}

/// Makes the app's own string lookups read the chosen language's strings instead of the iPhone's.
final class LanguageBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) private static var chosen: Bundle?

    /// Where translated strings are read from: the chosen language's folder, or the app itself.
    static var strings: Bundle { chosen ?? .main }

    static func use(_ language: AppLanguage) {
        if object_getClass(Bundle.main) != LanguageBundle.self {
            object_setClass(Bundle.main, LanguageBundle.self)
        }
        chosen = language == .system ? nil
            : Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let chosen = Self.chosen {
            return chosen.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
