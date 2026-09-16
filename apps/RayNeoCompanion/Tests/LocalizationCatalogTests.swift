import XCTest
@testable import RayNeoCompanion

final class LocalizationCatalogTests: XCTestCase {
    func testSelectedLocaleUsesBundledCatalogIndependentlyOfSystemLanguage() {
        XCTAssertEqual(L10n.text("Language", locale: Locale(identifier: "en")), "Language")
        XCTAssertEqual(L10n.text("Language", locale: Locale(identifier: "zh-Hans")), "语言")
        XCTAssertEqual(L10n.text("Language", locale: Locale(identifier: "fr")), "Language")
    }

    func testMissingKeysFallBackToEnglishKey() {
        XCTAssertEqual(L10n.text("Missing test key", locale: Locale(identifier: "zh-Hans")), "Missing test key")
    }
}
