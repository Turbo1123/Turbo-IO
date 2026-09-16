import XCTest
@testable import RayNeoSession

@MainActor final class HermesTaskTests: XCTestCase {
    func config(_ host: String = "bridge.invalid") throws -> HermesBridgeConfiguration { try .init(endpoint: "https://" + host, token: String(repeating: "t", count: 48)) }
    func response(_ request: URLRequest, status: String = "running", revision: Int = 1, prompt: [String: Any]? = nil) throws -> Data {
        let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        return try state(input["requestId"] as! String, input["conversationId"] as! String, status: status, revision: revision, prompt: prompt)
    }
    func state(_ id: String, _ conversation: String, status: String = "running", revision: Int = 1, prompt: [String: Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["requestId": id, "conversationId": conversation, "status": status, "answer": "结果", "summary": "任务状态", "revision": revision, "prompt": prompt as Any? ?? NSNull()])
    }
    func testReferencePersistsBeforeNetworkAndRestoresWithoutResubmitting() async throws {
        var saved: Data?, calls = 0
        let client = try HermesTaskClient(configuration: config(), load: { saved }, save: { saved = $0 }, send: { request in
            XCTAssertNotNil(saved); calls += 1; return try self.response(request)
        })
        try await client.submit(text: "创建测试文件")
        let ref = client.reference
        let restored = try HermesTaskClient(configuration: config(), load: { saved }, save: { saved = $0 }, send: { request in
            XCTAssertEqual(request.httpMethod, "GET"); calls += 1
            return try self.state(ref.requestID!.uuidString.lowercased(), ref.conversationID.uuidString.lowercased(), status: "completed", revision: 2)
        })
        XCTAssertEqual(restored.reference, ref)
        try await restored.refresh()
        XCTAssertEqual(restored.snapshot?.status, .completed); XCTAssertEqual(calls, 2)
        XCTAssertFalse(String(data: saved!, encoding: .utf8)!.contains("创建测试文件"))
        XCTAssertFalse(String(data: saved!, encoding: .utf8)!.contains("tttt"))
    }
    func testUnknownDeliveryKeepsOriginalIDAndNeverAutomaticallyReposts() async throws {
        var saved: Data?, paths: [String] = []
        let client = try HermesTaskClient(configuration: config(), load: { saved }, save: { saved = $0 }, send: { request in
            paths.append(request.httpMethod! + " " + request.url!.path); throw URLError(.networkConnectionLost)
        })
        do { try await client.submit(text: "test"); XCTFail() } catch {}
        let id = client.reference.requestID; XCTAssertNotNil(id)
        do { try await client.refresh() } catch {}
        do { try await client.submit(text: "again"); XCTFail() } catch {}
        XCTAssertEqual(client.reference.requestID, id)
        XCTAssertEqual(paths.count, 2); XCTAssertTrue(paths[1].hasPrefix("GET"))
    }
    func testCancellationOfSubmissionNeverSendsStop() async throws {
        var paths: [String] = []
        let client = try HermesTaskClient(configuration: config(), load: { nil }, save: { _ in }, send: { request in
            paths.append(request.url!.path); throw CancellationError()
        })
        do { try await client.submit(text: "test") } catch {}
        XCTAssertEqual(paths, ["/v2/tasks"]); XCTAssertTrue(client.hasUnfinishedTask)
    }
    func testExplicitStopWaitsForServerStateAndDoesNotClearReference() async throws {
        var id = "", conversation = ""
        let client = try HermesTaskClient(configuration: config(), load: { nil }, save: { _ in }, send: { request in
            if request.url!.path.hasSuffix("/stop") { return try self.state(id, conversation, status: "stopping", revision: 2) }
            let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            id = input["requestId"] as! String; conversation = input["conversationId"] as! String
            return try self.response(request)
        })
        try await client.submit(text: "test"); try await client.stop()
        XCTAssertEqual(client.snapshot?.status, .stopping); XCTAssertNotNil(client.reference.requestID)
    }
    func testApprovalUsesBoundPromptAndPersistsDecisionBeforeSending() async throws {
        var saved: Data?, calls = 0
        let promptID = UUID().uuidString.lowercased()
        let client = try HermesTaskClient(configuration: config(), load: { saved }, save: { saved = $0 }, send: { request in
            calls += 1
            if request.url!.path.hasSuffix("/decision") {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(body["promptId"] as? String, promptID); XCTAssertEqual(body["choice"] as? String, "once")
                let stored = try JSONDecoder().decode(HermesTaskReference.self, from: saved!)
                XCTAssertEqual(stored.decisionID?.uuidString.lowercased(), body["decisionId"] as? String)
                throw URLError(.networkConnectionLost)
            }
            return try self.response(request, status: "waiting", prompt: ["id": promptID, "kind": "approval", "title": "执行命令", "options": []])
        })
        try await client.submit(text: "test")
        do { try await client.decide(promptID: promptID, choice: "always"); XCTFail() } catch {}
        do { try await client.decide(promptID: promptID, choice: "once") } catch {}
        do { try await client.decide(promptID: promptID, choice: "once"); XCTFail() } catch {}
        XCTAssertEqual(calls, 2)
    }
    func testEndpointBindingDoesNotReuseOtherHostsSessionOrRequest() throws {
        var saved: Data?
        let first = try HermesTaskClient(configuration: config(), load: { nil }, save: { saved = $0 })
        let second = try HermesTaskClient(configuration: config("different.invalid"), load: { saved }, save: { _ in })
        XCTAssertNotEqual(first.reference.conversationID, second.reference.conversationID)
    }
    func testWrongIdentityStaleRevisionAndMalformedPromptRejected() async throws {
        var corrupt = false, id = "", conversation = ""
        let client = try HermesTaskClient(configuration: config(), load: { nil }, save: { _ in }, send: { request in
            if corrupt { return try self.state(UUID().uuidString.lowercased(), conversation) }
            let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            id = input["requestId"] as! String; conversation = input["conversationId"] as! String
            return try self.response(request, revision: 5)
        })
        try await client.submit(text: "test"); corrupt = true
        do { try await client.refresh(); XCTFail() } catch {}
        XCTAssertEqual(client.snapshot?.requestId, id)
    }
    func testPersistenceFailurePreventsExecution() throws {
        XCTAssertThrowsError(try HermesTaskClient(configuration: config(), load: { nil }, save: { _ in throw URLError(.cannotWriteToFile) }))
    }
    func testDurableReferenceStoreSurvivesReopenAndSeparatesEndpoints() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/hermes-tasks/store-tests/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HermesTaskReferenceStore(directory: directory)
        let endpoint = try config().endpoint
        try store.save(Data("first".utf8), endpoint: endpoint)
        try store.save(Data("second".utf8), endpoint: endpoint)
        let reopened = try HermesTaskReferenceStore(directory: directory)
        XCTAssertEqual(try reopened.load(endpoint: endpoint), Data("second".utf8))
        XCTAssertNil(try reopened.load(endpoint: "https://different.invalid"))
        XCTAssertThrowsError(try store.save(Data(repeating: 1, count: 4097), endpoint: endpoint))
        XCTAssertEqual(try reopened.load(endpoint: endpoint), Data("second".utf8))
    }
    func testGlassesSummaryRespectsUTF8BudgetIncludingComplexGraphemes() {
        let text = String(repeating: "研究结果👩🏽‍🔬e\u{301}", count: 3000)
        let result = HermesTaskPresentation.glassesText(text)
        XCTAssertLessThanOrEqual(result.utf8.count, 6200)
        XCTAssertTrue(result.hasSuffix("完整结果见手机任务卡。"))
        XCTAssertEqual(HermesTaskPresentation.glassesText("完成"), "完成")
    }
    func testRecoveredTerminalMayFillMissingAnswerButCannotRewriteIt() async throws {
        var id = "", conversation = "", revision = 0
        let client = try HermesTaskClient(configuration: config(), load: { nil }, save: { _ in }, send: { request in
            revision += 1
            if let body = request.httpBody {
                let input = try JSONSerialization.jsonObject(with: body) as! [String: Any]
                id = input["requestId"] as! String; conversation = input["conversationId"] as! String
            }
            var value = try JSONSerialization.jsonObject(with: self.state(id, conversation, status: "completed", revision: revision)) as! [String: Any]
            value["answer"] = revision == 1 ? "" : revision == 2 ? "恢复的结果" : "改写的结果"
            return try JSONSerialization.data(withJSONObject: value)
        })
        try await client.submit(text: "test"); XCTAssertEqual(client.snapshot?.answer, "")
        try await client.refresh(); XCTAssertEqual(client.snapshot?.answer, "恢复的结果")
        do { try await client.refresh(); XCTFail("A nonempty terminal answer must not be rewritten") } catch {}
    }
}
