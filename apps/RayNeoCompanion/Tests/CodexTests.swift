import XCTest
@testable import RayNeoCompanion

@MainActor final class CodexTests: XCTestCase {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "CodexTests.\(UUID())")! }
    func testEndpointRejectsCredentialLeakAndDevicePlaintext() throws {
        for bad in ["http://192.168.1.5:8787", "https://user:pass@test.invalid", "https://test.invalid/?token=secret", "https://test.invalid/#key", "https://test.invalid/path"] {
            XCTAssertThrowsError(try CodexEndpoint.normalize(bad))
        }
        XCTAssertEqual(try CodexEndpoint.normalize("https://Bridge.invalid/"), "https://bridge.invalid")
        XCTAssertThrowsError(try CodexEndpoint.normalize("http://127.0.0.1:8787"))
        XCTAssertEqual(try CodexEndpoint.normalize("http://127.0.0.1:8787", allowLoopback: true), "http://127.0.0.1:8787")
    }
    func testNoKeysNoNetworkAndNoTools() async {
        var calls = 0
        let c = CodexCompanion(defaults: defaults(), key: { _ in nil }, send: { _, _, _, _ in calls += 1; return Data() })
        await c.refresh(); XCTAssertEqual(calls, 0); XCTAssertTrue(c.toolDefinitions.isEmpty)
    }
    func testEnabledToolsNeverExposeApprovalOrShell() {
        let d = defaults(); d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint"); d.set(true, forKey: "companion.codex.v1.voiceTools")
        let c = CodexCompanion(defaults: d, key: { _ in "synthetic" })
        let names = c.toolDefinitions.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, ["codex_message", "codex_status", "codex_stop"])
    }
    func testToolFragmentsAndUTF8AreReassembled() throws {
        var a = VoiceToolCallAccumulator()
        try a.append([["index": 0, "type": "function", "function": ["name": "codex_message", "arguments": "{\"text\":\"检查"]]])
        try a.append([["index": 0, "function": ["arguments": "断连\"}"]]])
        let (name, args) = try a.validated(allowed: ["codex_message"], finishReason: "tool_calls")
        XCTAssertEqual(name, "codex_message"); XCTAssertEqual(args, "{\"text\":\"检查断连\"}")
    }
    func testCatalogueMatchesModelDefinitionsAndSchemas() throws {
        let d = defaults()
        d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint")
        d.set(true, forKey: "companion.codex.v1.voiceTools")
        let c = CodexCompanion(defaults: d, key: { _ in "synthetic" })
        XCTAssertEqual(c.toolDefinitions.count, CodexToolDescriptor.all.count)
        for (descriptor, definition) in zip(CodexToolDescriptor.all, c.toolDefinitions) {
            let json = try XCTUnwrap(descriptor.schemaJSON.data(using: .utf8))
            let displayed = try JSONSerialization.jsonObject(with: json) as! NSDictionary
            XCTAssertEqual(displayed, definition as NSDictionary)
            let function = definition["function"] as! [String: Any]
            let parameters = function["parameters"] as! [String: Any]
            XCTAssertEqual(parameters["required"] as? [String], descriptor.requiresText ? ["text"] : [])
            XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
            XCTAssertFalse(descriptor.example.isEmpty)
        }
        XCTAssertEqual(Set(CodexToolDescriptor.all.map(\.id)).count, 3)
    }
    func testCatalogueVisibleWithoutEnablingOrExecutingTools() async {
        for enabled in [false, true] {
            let d = defaults()
            d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint")
            d.set(enabled, forKey: "companion.codex.v1.voiceTools")
            var calls = 0
            let c = CodexCompanion(defaults: d, key: { _ in nil }, send: { _, _, _, _ in calls += 1; return Data() })
            XCTAssertEqual(CodexToolDescriptor.all.count, 3)
            XCTAssertTrue(c.toolDefinitions.isEmpty)
            XCTAssertNil(c.state)
            XCTAssertEqual(calls, 0)
        }
        let d = defaults(); d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint")
        let disabled = CodexCompanion(defaults: d, key: { _ in "synthetic" })
        XCTAssertTrue(disabled.configured); XCTAssertTrue(disabled.toolDefinitions.isEmpty)
    }
    func testMultipleToolsUnknownNamesExtraArgumentsAndTruncationRefused() throws {
        var a = VoiceToolCallAccumulator()
        XCTAssertThrowsError(try a.append([["index": 1]]))
        try a.append([["index": 0, "function": ["name": "codex_approve", "arguments": "{}"]]])
        XCTAssertThrowsError(try a.validated(allowed: ["codex_message"], finishReason: "tool_calls"))
        a = VoiceToolCallAccumulator()
        try a.append([["index": 0, "function": ["name": "codex_stop", "arguments": "{\"command\":\"bad\"}"]]])
        XCTAssertThrowsError(try a.validated(allowed: ["codex_stop"], finishReason: "tool_calls"))
        XCTAssertThrowsError(try a.validated(allowed: ["codex_stop"], finishReason: "length"))
    }
    func testUnknownDeliveryPersistsAndRetryUsesSameID() async throws {
        let d = defaults(); d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint")
        var ids: [String] = []
        let c = CodexCompanion(defaults: d, key: { _ in "synthetic" }, send: { _, _, _, body in
            let object = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            ids.append(object["requestId"] as! String); throw CodexBridgeError.offline
        })
        do { _ = try await c.message("synthetic") } catch {}
        XCTAssertTrue(c.hasUnknownDelivery)
        do { _ = try await c.message("do not duplicate") } catch {}
        XCTAssertEqual(ids.count, 1); await c.retryPending(); XCTAssertEqual(ids.count, 2); XCTAssertEqual(ids[0], ids[1])
        let restored = CodexCompanion(defaults: d, key: { _ in nil }); XCTAssertTrue(restored.hasUnknownDelivery)
    }
    func testUnknownToolDoesNotSend() async {
        let d = defaults(); d.set("https://test.invalid", forKey: "companion.codex.v1.endpoint"); d.set(true, forKey: "companion.codex.v1.voiceTools")
        var calls = 0
        let c = CodexCompanion(defaults: d, key: { _ in "synthetic" }, send: { _, _, _, _ in calls += 1; return Data() })
        let result = await c.executeTool(name: "codex_approve", arguments: "{}", requestID: UUID())
        XCTAssertEqual(calls, 0); XCTAssertTrue(result.contains("未执行"))
    }
}
