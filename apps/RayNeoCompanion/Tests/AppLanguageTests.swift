import XCTest
#if !APP_LANGUAGE_STANDALONE_TESTS
@testable import RayNeoCompanion
#endif

final class AppLanguageTests: XCTestCase {
    func testFirstLaunchDefaultsToEnglishWithoutChangingExistingPreferences() throws {
        try withDefaults { defaults in
            defaults.set("original content", forKey: "saved.notes")
            defaults.set("existing provider", forKey: "model.provider")
            XCTAssertEqual(AppLanguage.current(defaults: defaults), .english)
            XCTAssertNil(defaults.object(forKey: AppLanguage.defaultsKey))
            XCTAssertEqual(defaults.string(forKey: "saved.notes"), "original content")
            XCTAssertEqual(defaults.string(forKey: "model.provider"), "existing provider")
        }
    }

    func testEachSelectionPersistsAndRestoresWithoutChangingOtherKeys() throws {
        try withDefaults { defaults in
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
            defaults.set("keep", forKey: "model.configuration")
            for selection in AppLanguage.allCases {
                selection.save(defaults: defaults)
                XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), selection.rawValue)
                XCTAssertEqual(AppLanguage.current(defaults: defaults), selection)
                XCTAssertEqual(defaults.string(forKey: "model.configuration"), "keep")
                XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
            }
        }
    }

    func testUnsupportedSavedValueFallsBackToEnglish() throws {
        try withDefaults { defaults in
            defaults.set("unsupported", forKey: AppLanguage.defaultsKey)
            XCTAssertEqual(AppLanguage.current(defaults: defaults), .english)
        }
    }

    func testExplicitChoiceOverridesSystemLanguages() {
        XCTAssertEqual(AppLanguage.english.resolvedLocale(preferredLanguages: ["zh-Hans-CN"]).identifier, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedLocale(preferredLanguages: ["en-US"]).identifier, "zh-Hans")
    }

    func testSystemSimplifiedChineseVariants() {
        for identifier in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh-SG", "zh_CN", "zh-Hans-HK"] {
            XCTAssertEqual(AppLanguage.system.resolvedLocale(preferredLanguages: [identifier]).identifier, "zh-Hans", identifier)
        }
    }

    func testSystemUnsupportedAndTraditionalChineseFallbackToEnglish() {
        for identifier in ["en-US", "fi-FI", "zh-Hant", "zh-TW", "zh-HK", "zh-Hant-CN"] {
            XCTAssertEqual(AppLanguage.system.resolvedLocale(preferredLanguages: [identifier]).identifier, "en", identifier)
        }
        XCTAssertEqual(AppLanguage.system.resolvedLocale(preferredLanguages: []).identifier, "en")
        XCTAssertEqual(AppLanguage.system.resolvedLocale(preferredLanguages: ["fi-FI", "zh-Hans"]).identifier, "en")
    }

    func testObservableSettingsPersistAndRestoreChoice() throws {
        try withDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults)
            XCTAssertEqual(settings.language, .english)
            settings.language = .simplifiedChinese
            XCTAssertEqual(settings.locale.identifier, "zh-Hans")
            XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .simplifiedChinese)
        }
    }

    #if DEBUG
    func testDebugLaunchLanguageUsesOnlyIsolatedTestSuite() throws {
        let scope = UUID()
        let suite = "companion.ui-tests.\(scope.uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppLanguageSettings.forCurrentLaunch(arguments: ["--ui-test-scope", scope.uuidString, "--ui-language", "zh-Hans"])
        XCTAssertEqual(settings.language, .simplifiedChinese)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.defaultsKey), "zh-Hans")
        settings.language = .system
        XCTAssertEqual(AppLanguageSettings.forCurrentLaunch(arguments: ["--ui-test-scope", scope.uuidString]).language, .system)
    }
    #endif

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "turboio-language-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

#if APP_LANGUAGE_STANDALONE_TESTS
@main
private enum AppLanguageTestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: AppLanguageTests.self)
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
#endif
