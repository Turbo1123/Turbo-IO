import Foundation

/// The stored selection is independent of system preferences and user-authored content.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "app.language"
    var id: String { rawValue }

    static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    func resolvedLocale(preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        guard self == .system else { return Locale(identifier: rawValue) }
        guard let identifier = preferredLanguages.first else { return Locale(identifier: "en") }
        let components = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        let simplified = components.first == "zh" && !components.contains("hant")
            && (components.contains("hans") || components.contains("cn") || components.contains("sg"))
        return Locale(identifier: simplified ? "zh-Hans" : "en")
    }
}
