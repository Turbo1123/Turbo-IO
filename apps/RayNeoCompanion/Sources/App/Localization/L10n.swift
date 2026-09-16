import Foundation

/// Resolves only explicit, app-owned catalog keys. Never pass transcripts, model
/// answers, note titles, or remote error bodies through this lookup.
enum L10n {
    static func text(_ key: String, locale: Locale, bundle: Bundle = .main) -> String {
        let language = AppLanguage.system.resolvedLocale(preferredLanguages: [locale.identifier])
        guard let path = bundle.path(forResource: language.identifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: text(key, locale: locale), locale: locale, arguments: arguments)
    }
}
