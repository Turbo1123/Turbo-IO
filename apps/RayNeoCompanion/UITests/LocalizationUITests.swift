import XCTest

final class LocalizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLanguageSwitchPersistsAndPreservesUserDraft() {
        let app = XCUIApplication()
        let scope = UUID().uuidString
        app.launchArguments = ["--ui-test-scope", scope]
        app.launch()
        XCTAssertTrue(app.staticTexts["My Glasses"].waitForExistence(timeout: 10))
        app.buttons["tab-3"].tap()
        app.buttons["prompter-tool"].tap()
        let editor = app.textViews["prompter-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("My Glasses")
        app.swipeUp()
        let save = app.buttons["prompter-save"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()
        app.terminate(); app.launch()
        app.buttons["screen-settings"].tap()
        app.buttons["language-settings"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "简体中文")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
        capture("language-chinese")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["我的眼镜"].waitForExistence(timeout: 5))
        app.buttons["tab-3"].tap()
        app.buttons["prompter-tool"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "My Glasses", "User text must not be translated")
        app.terminate(); app.launch()
        app.buttons["screen-settings"].tap()
        app.buttons["language-settings"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@", "English")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
        capture("language-english")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["My Glasses"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
