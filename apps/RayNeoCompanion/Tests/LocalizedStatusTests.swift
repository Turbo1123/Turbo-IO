import XCTest
#if !LOCALIZED_STATUS_STANDALONE_TESTS
@testable import RayNeoCompanion
#endif

final class LocalizedStatusTests: XCTestCase {
    private let english = Locale(identifier: "en")

    func testNativeTeleprompterTrialStatusDoesNotClaimVerifiedTracking() {
        XCTAssertEqual(
            L10n.deviceFeatureStatus("已请求原生跟读试验，等待眼镜回应；效果仍需真机验证", locale: english),
            "Native follow trial requested; waiting for glasses response. Speech tracking still needs a hardware test."
        )
    }

    func testTodoDeliveryBranchesAndConflictPrecedence() {
        var todo = LocalTodo(title: "用户原文，不翻译")
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Saved Only on Phone")
        todo.completed = true
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Completed Locally · Not Synced")
        todo.delivery = TodoDelivery()
        todo.delivery?.conflict = .init(completed: false)
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Status Conflict · Local Edits Retained")
        todo.wireID = 1
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Status Conflict · Local Edits Retained")
        todo.delivery?.conflict = nil
        todo.delivery?.submittedAt = Date()
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Pending Send · Local Edits Saved")
        todo.delivery?.pending = false
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Submitted · Items Not Individually Confirmed")
        todo.delivery?.submittedAt = nil
        XCTAssertEqual(L10n.todoDelivery(todo, locale: english), "Linked to Glasses · Awaiting Report")
        XCTAssertEqual(todo.title, "用户原文，不翻译")
    }

    func testKnownToolLabelsAreLocalizedWithoutChangingSchema() {
        let titles = ["Start / Continue Task", "Check Progress and Results", "Stop Current Task"]
        for (tool, title) in zip(CodexToolDescriptor.all, titles) {
            let schemaBefore = tool.schemaJSON
            XCTAssertEqual(L10n.codexToolTitle(tool, locale: english), title)
            XCTAssertNotEqual(L10n.codexToolDescription(tool, locale: english), tool.description)
            XCTAssertNotEqual(L10n.codexToolExample(tool, locale: english), tool.example)
            XCTAssertEqual(tool.schemaJSON, schemaBefore)
        }
    }

    func testUnknownToolPreservesItsOriginalContent() {
        let tool = CodexToolDescriptor(id: "external", title: "来源标题", description: "原始说明", example: "用户示例", requiresText: true)
        XCTAssertEqual(L10n.codexToolTitle(tool, locale: english), tool.title)
        XCTAssertEqual(L10n.codexToolDescription(tool, locale: english), tool.description)
        XCTAssertEqual(L10n.codexToolExample(tool, locale: english), tool.example)
    }

    func testAudioOutcomeTitlesDoNotConsumeAssociatedDiagnosticText() {
        XCTAssertEqual(L10n.audioContainerOutcome(.unsupported("原始供应方详情"), locale: english), "Not Supported by This Inspector")
        XCTAssertEqual(L10n.audioContainerOutcome(.invalid("原始供应方详情"), locale: english), "Container Structure Error Found")
        XCTAssertEqual(L10n.audioContainerOutcome(.limited("原始供应方详情"), locale: english), "Inspection Budget Exceeded")
    }

    func testAppStatusUsesExactWhitelistAndPreservesUnknownStrings() {
        XCTAssertEqual(L10n.appStatus("仪表盘实时天气：待配置和风 Host / Key。", locale: english), "Dashboard weather: configure your QWeather host and key.")
        XCTAssertEqual(L10n.appStatus("和风响应字段、单位或归因信息不完整，未下发。", locale: english), "QWeather response fields, units, or attribution are incomplete. Nothing was sent.")
        for source in ["用户内容", "供应商：仪表盘自动天气已关闭。", "仪表盘自动天气已关闭。 extra", "获取北京实时天气，目标为仪表盘首页。", "和风天气 HTTP 401，请检查服务配置。"] {
            XCTAssertEqual(L10n.appStatus(source, locale: english), source)
        }
    }

    func testQWeatherStatusLocalizesOnlyKnownAppTemplates() {
        XCTAssertEqual(
            L10n.qweatherStatus("获取北京实时天气，目标为仪表盘首页。", locale: english),
            "Fetching live weather for 北京 to show on the dashboard home page."
        )
        XCTAssertEqual(
            L10n.qweatherStatus("北京 22°C · 多云 已获取；请测试候选图标 101，尚未自动下发。", locale: english),
            "北京 22°C · 多云 fetched. Test candidate icon 101; nothing was sent automatically."
        )
        XCTAssertEqual(
            L10n.qweatherStatus("仪表盘已提交：北京 22°C · 多云；图标 101 为待验候选。不是天气卡片更新。", locale: english),
            "Dashboard update submitted: 北京 22°C · 多云; icon 101 is an unverified candidate. This does not update the weather card."
        )
        XCTAssertEqual(
            L10n.qweatherStatus("已记录用户确认：天气码 101 的同号图标；后续认证连接可自动下发此类型。", locale: english),
            "Confirmed matching icon for weather code 101. Future authenticated connections can send this type automatically."
        )
        XCTAssertEqual(
            L10n.qweatherStatus("眼镜回报 current_weather_update value=0（协议成功值）；回执没有请求 ID，镜片内容仍需确认。", locale: english),
            "Glasses reported current_weather_update value=0 (protocol success value). The receipt has no request ID; confirm the displayed content."
        )
        let providerText = "和风天气 HTTP 401，请检查服务配置。"
        XCTAssertEqual(L10n.qweatherStatus(providerText, locale: english), providerText)
        XCTAssertEqual(L10n.qweatherStatus("获取北京实时天气，目标为仪表盘首页。 extra", locale: english), "获取北京实时天气，目标为仪表盘首页。 extra")
        XCTAssertEqual(L10n.qweatherStatus("获取北京实时天气，目标为仪表盘首页。", locale: Locale(identifier: "zh-Hans")), "获取北京实时天气，目标为仪表盘首页。")
    }

    func testHeadControlCountdownIsLocalizedAndKeepsTheReportedSeconds() {
        XCTAssertEqual(
            L10n.headControlStatus("测试卡已发送；等待点头或摇头（30 秒）", locale: english),
            "Test card sent; waiting for nod or shake (30 seconds)"
        )
        XCTAssertEqual(
            L10n.headControlStatus("测试卡已发送；等待点头或摇头（30 秒）", locale: Locale(identifier: "zh-Hans")),
            "测试卡已发送；等待点头或摇头（30 秒）"
        )
    }

    func testDeviceFeatureStatusesKeepProtocolValues() {
        XCTAssertEqual(
            L10n.deviceFeatureStatus("已提交 3 条待办；等待眼镜状态/操作回执，不代表镜片已显示", locale: english),
            "Submitted 3 to-dos; waiting for glasses status or action receipt. Display on the lenses is unconfirmed."
        )
        XCTAssertEqual(
            L10n.deviceFeatureStatus("眼镜拒绝开始，code=7；未自动绕过隐私/冲突", locale: english),
            "Glasses rejected start, code=7; privacy and conflict safeguards were not bypassed."
        )
        XCTAssertEqual(L10n.deviceFeatureStatus("原始眼镜回报：7", locale: english), "原始眼镜回报：7")
    }
}

#if LOCALIZED_STATUS_STANDALONE_TESTS
@main
private enum LocalizedStatusTestRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: LocalizedStatusTests.self)
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
#endif
