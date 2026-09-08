import XCTest

final class CompanionUITests: XCTestCase {
    private let scope = UUID().uuidString
    private var testArguments: [String] { ["--ui-test-scope", scope] }
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAlwaysOnRequiresConsentAndRealDevice() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "3"]; app.launch()
        let entry = app.buttons["always-on-entry"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["always-on-status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["always-on-start"].isEnabled)
        XCTAssertFalse(app.buttons["always-on-stop"].isEnabled)
        app.switches["always-on-consent"].tap()
        XCTAssertFalse(app.buttons["always-on-start"].isEnabled, "Consent cannot fabricate a connected device")
        XCTAssertTrue(app.staticTexts["always-on-counters"].label.contains("0 包"))
        capture("54-always-on-consent-no-device")
    }

    func testModelToolsCatalogueIsReadOnlyAndShowsActualSchema() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "3"]; app.launch()
        let entry = app.buttons["model-tools-entry"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["model-tools-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["model-tools-count"].label.contains("0 / 3"))
        XCTAssertFalse(app.buttons["model-tools-refresh"].isEnabled)
        capture("52-model-tools-offline-summary")
        for name in ["codex_message", "codex_status", "codex_stop"] {
            let title = app.staticTexts["model-tool-name-" + name]
            reveal(title, in: app); XCTAssertEqual(title.label, name)
        }
        let details = app.buttons["model-tool-details-codex_stop"]
        reveal(details, in: app); details.tap()
        let schema = app.staticTexts["model-tool-schema-codex_stop"]
        XCTAssertTrue(schema.waitForExistence(timeout: 5))
        XCTAssertTrue(schema.label.contains("additionalProperties"))
        reveal(schema, in: app)
        capture("53-model-tools-actual-schema")
    }

    func testModelToolsCanOpenFromConversation() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "1"]; app.launch()
        let entry = app.buttons["model-tools-conversation-entry"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["model-tools-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["model-tools-count"].label.contains("0 / 3"))
    }

    func testCodexConsoleHasOfflineFixtureAndNoImplicitExecution() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "3"]; app.launch()
        let entry = app.buttons["codex-tool"]; reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.textFields["codex-endpoint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["codex-refresh"].isEnabled)
        let fixture = app.buttons["codex-fixture"]; reveal(fixture, in: app); fixture.tap()
        let field = app.descendants(matching: .any).matching(identifier: "codex-prompt").firstMatch
        let first = field.value as? String
        fixture.tap()
        XCTAssertNotNil(first)
        XCTAssertNotEqual(first, field.value as? String)
        XCTAssertFalse(app.buttons["codex-send"].isEnabled)
        capture("48-codex-console-offline-fixture")
    }

    func testAutomaticWeatherDefaultsToBeijingAndPersistsOffWithoutNetwork() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab","3"]
        app.launch()
        let settings = app.buttons["device-settings-tool"]; reveal(settings,in:app); settings.tap()
        let entry = app.buttons["weatherstack-entry"]; reveal(entry,in:app); entry.tap()
        let toggle = app.switches["weather-auto-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout:5))
        XCTAssertEqual(toggle.value as? String,"1")
        XCTAssertTrue(app.staticTexts["已选城市：Beijing, China"].exists)
        XCTAssertTrue(app.staticTexts["weather-auto-status"].label.contains("认证连接"))
        capture("46-automatic-weather-beijing-setup")
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","0"),object:toggle)],timeout:5),.completed)
        XCTAssertTrue(app.staticTexts["weather-auto-status"].label.contains("已关闭"))
        app.terminate(); app.launch(); reveal(settings,in:app); settings.tap(); reveal(entry,in:app); entry.tap()
        XCTAssertEqual(toggle.value as? String,"0")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testQWeatherDashboardEntryIsNotCityCardAndDoesNotQueryWithoutCredentials() {
        let app = XCUIApplication(); app.launchArguments = testArguments; app.launch()
        let entry = app.buttons["device-weather-status"]; reveal(entry,in:app); entry.tap()
        XCTAssertTrue(app.textFields["qweather-host"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["qweather-status"].label.contains("待配置"))
        XCTAssertTrue(app.staticTexts["qweather-reply"].label.contains("尚未发送"))
        XCTAssertEqual(app.textFields["qweather-location"].value as? String,"北京")
        XCTAssertFalse(app.buttons["qweather-test-dashboard"].exists)
        capture("47-qweather-dashboard-configuration")
    }

    func testNotificationDraftSourcesPersistWithoutConnectionOrPermissionPrompt() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch()
        let entry = app.buttons["notification-tool"]; reveal(entry,in:app); entry.tap()
        XCTAssertTrue(app.switches["notification-master"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["notification-apply-master"].isEnabled)
        XCTAssertTrue(app.staticTexts["notification-connection"].label.contains("未连接"))
        app.switches["notification-master"].coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "1"),object:app.switches["notification-master"])],timeout:5),.completed)
        capture("43-notification-offline-master-draft")
        app.buttons["notification-sources-open"].tap()
        let sms = app.switches["notification-source-com.apple.MobileSMS"]; reveal(sms,in:app)
        sms.coordinate(withNormalizedOffset: CGVector(dx:0.93,dy:0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format:"value == %@", "0"), object:sms)], timeout:5), .completed)
        capture("44-notification-source-filters")
        let add = app.buttons["notification-source-add"]; reveal(add,in:app); add.tap()
        app.textFields["notification-source-name"].tap(); app.textFields["notification-source-name"].typeText("Synthetic")
        app.textFields["notification-source-id"].tap(); app.textFields["notification-source-id"].typeText("com.example.synthetic")
        app.buttons["notification-source-save"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate(); app.launch()
        reveal(entry,in:app); entry.tap()
        XCTAssertEqual(app.switches["notification-master"].value as? String,"1")
        app.buttons["notification-sources-open"].tap()
        reveal(sms,in:app); XCTAssertEqual(sms.value as? String,"0")
        let synthetic = app.switches["notification-source-com.example.synthetic"]
        reveal(synthetic,in:app); XCTAssertTrue(synthetic.exists)
    }

    func testNotificationManualComposerUsesRandomSampleAndCannotFakeDeviceSend() {
        let app = XCUIApplication(); app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch()
        let entry = app.buttons["notification-tool"]; reveal(entry,in:app); entry.tap()
        let test = app.buttons["notification-test-open"]; reveal(test,in:app); test.tap()
        let sample = app.buttons["notification-test-sample"]; reveal(sample,in:app); sample.tap()
        let title = app.textFields["notification-test-title"]
        let first = title.value as? String
        XCTAssertTrue(first?.contains("Turbo IO通知测试") == true)
        sample.tap(); XCTAssertNotEqual(first,title.value as? String)
        let send = app.buttons["notification-test-send"]; reveal(send,in:app)
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(app.staticTexts["notification-test-status"].label.contains("尚未发送"))
        XCTAssertFalse(app.staticTexts["notification-test-uid"].exists)
        capture("45-notification-manual-business-test-preview")
    }

    func testSystemReminderEntryDoesNotRequestPermissionOnOpen() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch(); app.buttons["todo-tool"].tap()
        app.buttons["system-reminders-open"].tap()
        XCTAssertTrue(app.buttons["reminders-authorize"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reminders-status"].label.contains("尚未读取"))
        XCTAssertFalse(app.buttons["reminders-import"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("39-system-reminders-before-permission")
    }

    func testSyntheticSystemReminderSelectionImportAndDeduplication() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3", "--ui-reminders-fixture"]
        app.launch(); app.buttons["todo-tool"].tap()
        app.buttons["system-reminders-open"].tap()
        XCTAssertTrue(app.staticTexts["reminders-fixture-banner"].waitForExistence(timeout: 5))
        app.buttons["reminders-authorize"].tap()
        let picker = app.buttons["reminders-list-picker"]
        reveal(picker, in: app); picker.tap()
        app.buttons.matching(identifier: "合成清单 · 不读取系统数据").firstMatch.tap()
        let read = app.buttons["reminders-read-list"]
        reveal(read, in: app); read.tap()
        let row = app.buttons["reminders-row-synthetic-reminder"]
        reveal(row, in: app); row.tap()
        let importButton = app.buttons["reminders-import"]
        reveal(importButton, in: app)
        XCTAssertTrue(importButton.isEnabled)
        capture("40-system-reminders-synthetic-selection")
        importButton.tap(); app.buttons.matching(identifier: "确认仅导入Turbo IO").firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@", "已导入 1 条"), object:app.staticTexts["reminders-status"])], timeout:5), .completed)
        reveal(row, in: app); row.tap()
        reveal(importButton, in: app); importButton.tap()
        app.buttons.matching(identifier: "确认仅导入Turbo IO").firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@", "跳过已导入 1 条"),object:app.staticTexts["reminders-status"])],timeout:5),.completed)
        reveal(app.staticTexts["reminders-status"], in: app)
        capture("41-system-reminders-imported-once")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["合成系统待办 · 导入测试，本机未完成"].waitForExistence(timeout: 5))
        capture("42-system-reminders-local-copy")
    }

    func testTodoDeliveryIsLocalAndRetryDisabledWithoutDevice() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch()
        app.buttons["todo-tool"].tap()
        let entry = app.buttons["todo-delivery-open"]
        reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.staticTexts["todo-delivery-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["todo-retry-pending"].isEnabled)
        capture("34-todo-delivery-local-boundary")
    }

    func testTodoConflictChoicePersistsWithoutSending() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3", "--ui-todo-conflict-fixture"]
        app.launch()
        app.buttons["todo-tool"].tap()
        let entry = app.buttons["todo-delivery-open"]
        reveal(entry, in: app); entry.tap()
        let conflict = app.staticTexts["状态冲突 · 本机修改已保留"]
        reveal(conflict, in: app); XCTAssertTrue(conflict.exists)
        capture("37-todo-synthetic-conflict")
        let choose = app.buttons["采用眼镜状态，保留本机标题"]
        reveal(choose, in: app); choose.tap()
        XCTAssertTrue(app.staticTexts["待发送 · 本机修改已保存"].waitForExistence(timeout: 5))
        XCTAssertFalse(conflict.exists)
        XCTAssertFalse(app.buttons["todo-retry-pending"].isEnabled)
        capture("38-todo-conflict-resolved-not-sent")
        app.terminate(); app.launch()
        app.buttons["todo-tool"].tap()
        reveal(entry, in: app); entry.tap()
        let pending = app.staticTexts["待发送 · 本机修改已保存"]
        reveal(pending, in: app); XCTAssertTrue(pending.exists)
        XCTAssertFalse(conflict.exists)
    }

    func testExportCopyCanMoveAndRestoreWithoutRemovingRecording() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "2", "--ui-archive-fixture"]
        app.launch()
        let fixture = app.buttons["archive-import-fixture"]
        reveal(fixture, in: app); fixture.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archive-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let export = app.buttons["archive-export-bundle"]
        reveal(export, in: app); export.tap()
        let confirm = app.buttons.matching(identifier: "archive-bundle-audio-only").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["仅分享本地文件"].waitForExistence(timeout: 15))
        app.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let entry = app.buttons["export-copies-open"]
        reveal(entry, in: app); entry.tap()
        let move = app.buttons["移入可恢复暂存箱"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        capture("35-export-copy-list")
        reveal(move, in: app); move.tap()
        app.buttons.matching(identifier: "确认移入暂存箱").firstMatch.tap()
        let restore = app.buttons["恢复这份副本"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        capture("36-export-copy-recoverable-trash")
        reveal(restore, in: app); restore.tap()
        app.buttons.matching(identifier: "确认恢复副本").firstMatch.tap()
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(row, in: app); XCTAssertTrue(row.exists)
    }

    func testRecoveryScreenIsLocalAndDoesNotInventRecordings() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab","2"]
        app.launch()
        let entry = app.buttons["recording-recovery"]
        reveal(entry,in:app); entry.tap()
        XCTAssertTrue(app.staticTexts["recovery-empty"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["recovery-status"].label.contains("本机 0 条"))
        XCTAssertTrue(app.buttons["recovery-scan"].isEnabled)
        capture("32-recovery-no-fabricated-files")
    }

    func testNativeArchiveShareAndFilePickerActuallyOpenAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "2", "--ui-archive-fixture"]
        app.launch()
        let fixture = app.buttons["archive-import-fixture"]
        reveal(fixture, in: app); fixture.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archive-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let share = app.buttons["archive-share-audio"]
        reveal(share, in: app); share.tap()
        XCTAssertTrue(app.buttons["archive-system-share"].waitForExistence(timeout: 10))
        app.buttons["archive-system-share"].tap()
        let saveAction = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Save to Files", "存储到文件")).firstMatch
        XCTAssertTrue(saveAction.waitForExistence(timeout: 10), "Native activity must expose a real system action")
        capture("50-native-archive-activity")
        // Use the system action itself; don't send the file to a person or app.
        reveal(saveAction, in: app); saveAction.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        capture("51-native-archive-files")
        cancel.tap()
    }

    func testPortableZIPNeedsSelectionAndOpensOnlyLocalShare() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab","2","--ui-archive-fixture"]
        app.launch()
        let fixture = app.buttons["archive-import-fixture"]
        reveal(fixture,in:app); fixture.tap()
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","archive-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:10)); row.tap()
        let export = app.buttons["archive-export-bundle"]
        reveal(export,in:app); export.tap()
        let confirm = app.buttons.matching(identifier:"archive-bundle-audio-only").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout:5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["仅分享本地文件"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","ZIP 已逐项解包")).firstMatch.exists)
        XCTAssertTrue(app.buttons["archive-system-share"].exists)
        capture("33-portable-zip-local-share")
    }

    func testWeatherstackHistoricalPreviewDoesNotSendOrNeedKey() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab","3"]
        app.launch()
        let entry = app.buttons["device-settings-tool"]
        reveal(entry,in:app); entry.tap()
        let weather = app.buttons["weatherstack-entry"]
        reveal(weather,in:app); weather.tap()
        let sample = app.buttons["weather-sample"]
        reveal(sample,in:app); sample.tap()
        reveal(app.staticTexts["Overcast"],in:app)
        XCTAssertTrue(app.staticTexts["Overcast"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["weather-status"].label.contains("2019"))
        capture("30-weatherstack-historical-preview")
        let send = app.buttons["weather-send"]
        reveal(send,in:app); XCTAssertFalse(send.isEnabled)
        capture("31-weatherstack-sample-send-blocked")
    }

    func testDeviceSettingsAreVisibleButNeverPretendSimulatorConnected() {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab","3"]
        app.launch()
        let entry = app.buttons["device-settings-tool"]
        reveal(entry,in:app); entry.tap()
        XCTAssertTrue(app.staticTexts["尚未连接（模拟器不发包）"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["从眼镜读取状态和设置"].isEnabled)
        capture("28-device-settings-disconnected")
        reveal(app.buttons["发送首页测试天气"],in:app)
        XCTAssertFalse(app.buttons["发送首页测试天气"].isEnabled)
        capture("29-custom-weather-no-network")
    }

    func testBookImportUniformPlaybackAndTimelineBoundary() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3", "--ui-book-fixture"]
        app.launch()
        app.buttons["prompter-tool"].tap()
        app.buttons["book-shelf"].tap()
        let fixture = app.buttons["book-import-fixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "book-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let play = app.buttons["book-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        capture("25-book-reader-before-play")
        play.tap()
        let progress = app.staticTexts["book-progress"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0.0%"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        play.tap()
        XCTAssertTrue(play.label.contains("匀速播放"))
        capture("26-book-reader-paused")
        app.terminate()
        app.launchArguments = testArguments + ["--ui-tab", "1"]
        app.launch()
        let timeline = app.buttons["conversation-timeline"]
        for _ in 0..<4 where !timeline.isHittable { app.swipeUp() }
        timeline.tap()
        XCTAssertTrue(app.staticTexts["还没有对话"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["timeline-export"].isEnabled)
        capture("27-timeline-no-fabricated-history")
    }

    func testFourScreensRemainDisconnected() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["尚未连接"].waitForExistence(timeout: 10))
        capture("01-device-real")
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.staticTexts["麦克风未启用 · 没有音频正在传输"].waitForExistence(timeout: 5))
        capture("02-voice-real")
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.staticTexts["本地录音管理"].waitForExistence(timeout: 5))
        capture("03-archive-real")
        app.buttons["tab-3"].tap()
        XCTAssertTrue(app.staticTexts["待办清单"].waitForExistence(timeout: 5))
        capture("04-tools-real")
        reveal(app.buttons["使用说明"], in: app)
        app.buttons["使用说明"].tap()
        XCTAssertTrue(app.staticTexts["现在可以使用什么？"].waitForExistence(timeout: 5))
        capture("04a-tools-help-after-scroll")
    }

    func testTodoDraftPersistsLocally() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch()
        app.buttons["todo-tool"].tap()
        capture("05a-todo-screen-before-input")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "todo-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        let title = "Simulator QA \(Int(Date().timeIntervalSince1970))"
        // Match the explicit identifier without coupling this check to the growing field's AX type.
        let field = app.descendants(matching: .any).matching(identifier: "todo-input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(title)
        app.buttons["保存到本机"].tap()
        XCTAssertTrue(app.buttons["\(title)，本机未完成"].waitForExistence(timeout: 5))
        app.buttons["\(title)，本机未完成"].tap()
        app.buttons["已完成"].tap()
        XCTAssertTrue(app.buttons["\(title)，本机已完成"].waitForExistence(timeout: 5))
        capture("05-todo-local")
        app.terminate(); app.launch()
        app.buttons["todo-tool"].tap()
        app.buttons["已完成"].tap()
        XCTAssertTrue(app.buttons["\(title)，本机已完成"].waitForExistence(timeout: 5))
    }

    func testModelConfigurationRejectsHTTPWithoutNetwork() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "1"]
        app.launch()
        app.swipeUp()
        app.buttons["model-settings"].tap()
        let endpoint = app.textFields["model-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recognition-strategy-label"].exists)
        XCTAssertTrue(app.staticTexts["speech-output-label"].exists)
        capture("06a-model-settings")
        endpoint.tap(); endpoint.typeText("http://invalid.example")
        app.swipeUp()
        app.buttons["save-model"].tap()
        XCTAssertTrue(app.staticTexts["请输入有效的 HTTPS 服务地址；留空可仅保存草稿。"].waitForExistence(timeout: 5))
        capture("06-model-validation")
    }

    func testVoiceReducerRoundAndStaleCallback() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "1"]
        app.launch()
        app.swipeUp()
        app.buttons["open-session-lab"].tap()
        XCTAssertTrue(app.buttons["lab-connect"].waitForExistence(timeout: 5))
        app.buttons["lab-connect"].tap()
        app.buttons["lab-wake"].tap()
        app.buttons["lab-asr"].tap()
        app.buttons["lab-answer"].tap()
        app.buttons["lab-tts-finish"].tap()
        XCTAssertTrue(app.staticTexts["等待下一轮"].waitForExistence(timeout: 5))
        capture("07-session-round-complete")
        app.buttons["lab-next"].tap()
        app.buttons["lab-stale"].tap()
        XCTAssertTrue(app.staticTexts["旧轮回调被忽略，当前会话未改变"].firstMatch.waitForExistence(timeout: 5))
        capture("08-session-stale-protected")
        app.buttons["lab-exit"].tap()
        XCTAssertTrue(app.staticTexts["会话已收尾"].waitForExistence(timeout: 5))
    }

    func testPrompterAndDemoModeAreExplicit() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "3"]
        app.launch()
        app.buttons["prompter-tool"].tap()
        let editor = app.textViews["prompter-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("This is a local preview, not a glasses screenshot.")
        app.swipeUp()
        app.buttons["prompter-save"].tap()
        app.swipeDown()
        app.buttons["手机预览"].tap()
        capture("09-prompter-phone-preview")
        app.terminate()
        app.launchArguments = testArguments + ["--ui-tab", "0", "--ui-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["演示模式 · 示例数据，不连接眼镜"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚未连接"].exists)
        capture("10-device-explicit-demo")
        app.terminate()
        app.launchArguments = testArguments
        app.launch()
        XCTAssertFalse(app.staticTexts["演示模式 · 示例数据，不连接眼镜"].exists)
        XCTAssertTrue(app.staticTexts["尚未连接"].waitForExistence(timeout: 5))
        capture("11-device-return-to-real")
    }

    func testArchiveManualTextRevisionsAndLocalShareBoundary() throws {
        let app = XCUIApplication()
        app.launchArguments = testArguments + ["--ui-tab", "2", "--ui-archive-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["还没有录音"].waitForExistence(timeout: 10))
        let fixture = app.buttons["archive-import-fixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        capture("12-archive-empty-explicit-fixture")
        reveal(fixture,in:app)
        fixture.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archive-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["evidence-checksum"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["evidence-transcript"].label, "待用户提供文字")
        capture("13-archive-copy-checksum-only")
        app.buttons["文字与修订"].tap()
        let editor = app.textViews["archive-transcript"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Manually supplied synthetic text. Not ASR.")
        app.swipeUp()
        let save = app.buttons["archive-save-note"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        let firstRevision = app.staticTexts["archive-revision-1"]
        XCTAssertTrue(firstRevision.waitForExistence(timeout: 10))
        app.swipeDown()
        for _ in 0..<4 where !editor.isHittable { app.swipeDown() }
        editor.tap(); editor.typeText(" Added manually for revision two.")
        app.swipeUp()
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        save.tap()
        let secondRevision = app.staticTexts["archive-revision-2"]
        XCTAssertTrue(secondRevision.waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(firstRevision.exists)
        capture("14-archive-two-immutable-revisions")
        let share = app.buttons["archive-share-note-1"]
        for _ in 0..<4 where !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(app.staticTexts["仅分享本地文件"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["archive-system-share"].exists)
        capture("15-markdown-local-share-boundary")
        app.buttons["完成"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["evidence-transcript"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["evidence-transcript"].label, "用户文字已入档")
        XCTAssertEqual(app.staticTexts["evidence-note"].label, "本地 Markdown 已生成")
        capture("16-archive-four-local-evidence-layers")
    }

    func testContainerSupportedIsExplicitAndLeavingClearsResult() throws {
        let app = XCUIApplication()
        openContainerFixture("supported", app: app)
        XCTAssertTrue(app.staticTexts["container-idle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["container-outcome"].exists)
        capture("17-container-idle-no-read")
        app.buttons["container-start"].tap()
        let outcome = app.staticTexts["container-outcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 10))
        XCTAssertEqual(outcome.label, "声明子集的结构检查通过")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["container-no-asr"].exists)
        capture("18-container-supported-structure-only")
        app.navigationBars.buttons.firstMatch.tap()
        let entry = app.buttons["archive-open-container-check"]
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.staticTexts["container-idle"].waitForExistence(timeout: 5))
        XCTAssertFalse(outcome.exists)
        capture("19-container-reentry-needs-explicit-start")
    }

    func testContainerInvalidAndUnsupportedHaveDifferentVisibleOutcomes() throws {
        for (fixture, title, screenshot) in [
            ("badCRC", "发现容器结构错误", "20-container-invalid-crc"),
            ("unsupportedVersion", "当前检查器不支持", "21-container-unsupported-version")
        ] {
            let app = XCUIApplication()
            openContainerFixture(fixture, app: app)
            XCTAssertFalse(app.staticTexts["container-outcome"].exists)
            app.buttons["container-start"].tap()
            let outcome = app.staticTexts["container-outcome"]
            XCTAssertTrue(outcome.waitForExistence(timeout: 10)); XCTAssertEqual(outcome.label, title)
            app.swipeUp()
            XCTAssertTrue(app.staticTexts["container-no-asr"].exists)
            capture(screenshot)
            app.terminate()
        }
    }

    private func openContainerFixture(_ fixture: String, app: XCUIApplication) {
        app.launchArguments = ["--ui-test-scope", UUID().uuidString, "--ui-tab", "2", "--ui-archive-fixture"]
        app.launch()
        let menu = app.buttons["container-fixture-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        reveal(menu,in:app)
        menu.tap()
        let choice = app.buttons["container-fixture-\(fixture)"]
        XCTAssertTrue(choice.waitForExistence(timeout:5)); choice.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "archive-row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let entry = app.buttons["archive-open-container-check"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["container-start"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Form/List rows can be absent from the AX tree until scrolled into view.
        // Disabled controls are still visible; isHittable alone is not visibility.
        for _ in 0..<10 {
            let bottom = app.buttons["tab-0"].exists ? app.buttons["tab-0"].frame.minY - 12 : app.frame.maxY - 50
            if element.exists, element.frame.width > 0 {
                if element.frame.minY > 90, element.frame.maxY < bottom { return }
                if element.frame.minY <= 90 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTFail("Could not reveal requested control above the bottom navigation")
    }
}
