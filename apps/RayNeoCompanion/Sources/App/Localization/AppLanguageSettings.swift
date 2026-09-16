import Combine
import Foundation

final class AppLanguageSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet { language.save(defaults: defaults) }
    }

    private let defaults: UserDefaults
    private var localeObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage.current(defaults: defaults)
        localeObserver = NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSystemLocale() }
    }

    var locale: Locale { language.resolvedLocale() }

    /// Call when the app becomes active, as system language may change while suspended.
    func refreshSystemLocale() {
        if language == .system { objectWillChange.send() }
    }

    static func forCurrentLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppLanguageSettings {
        #if DEBUG
        if let index = arguments.firstIndex(of: "--ui-test-scope"), arguments.indices.contains(index + 1),
           let scope = UUID(uuidString: arguments[index + 1]),
           let defaults = UserDefaults(suiteName: "companion.ui-tests.\(scope.uuidString)") {
            let settings = AppLanguageSettings(defaults: defaults)
            if let languageIndex = arguments.firstIndex(of: "--ui-language"), arguments.indices.contains(languageIndex + 1),
               let language = AppLanguage(rawValue: arguments[languageIndex + 1]) {
                settings.language = language
            }
            return settings
        }
        #endif
        return AppLanguageSettings()
    }
}
