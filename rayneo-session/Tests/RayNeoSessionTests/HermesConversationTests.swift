import XCTest
@testable import RayNeoSession

@MainActor final class HermesConversationTests: XCTestCase {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let conversation = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func snapshot(_ status: String = "running", answer: String = "", revision: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["taskId": id.uuidString.lowercased(), "requestId": id.uuidString.lowercased(),
            "conversationId": conversation.uuidString.lowercased(), "agent": "hermes", "status": status,
            "answer": answer, "revision": revision, "summary": "任务处理中", "updatedAt": "2026-09-12T12:00:00.000Z", "approval": NSNull()])
    }
    func configuration() throws -> HermesBridgeConfiguration {
        try .init(endpoint: "https://Bridge.invalid/", token: String(repeating: "t", count: 32))
    }
    func testEndpointRejectsPlaintextCredentialsPathsAndQueries() throws {
        for input in ["http://192.168.0.1", "https://u:p@bridge.invalid", "https://bridge.invalid/?token=x", "https://bridge.invalid/path", "https://bridge.invalid/#fragment"] {
            XCTAssertThrowsError(try HermesBridgeConfiguration(endpoint: input, token: String(repeating: "t", count: 32)))
        }
        XCTAssertEqual(try configuration().endpoint, "https://bridge.invalid")
        XCTAssertThrowsError(try HermesBridgeConfiguration(endpoint: "https://bridge.invalid", token: "short"))
    }
    func testTokenMustMatchEntireInputIncludingTrailingLineTerminators() throws {
        let valid = String(repeating: "t", count: 32)
        XCTAssertNoThrow(try HermesBridgeConfiguration(endpoint: "https://bridge.invalid", token: valid))
        for suffix in ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"] {
            XCTAssertThrowsError(try HermesBridgeConfiguration(endpoint: "https://bridge.invalid", token: valid + suffix))
        }
    }
    func testSelectionCannotChangeDuringRoundOrStandby() {
        var choice = ConversationBackendSelection()
        XCTAssertTrue(choice.select(.hermes, standbyEnabled: false))
        let binding = choice.begin(id: id)!
        XCTAssertFalse(choice.select(.deepSeek, standbyEnabled: false))
        XCTAssertEqual(binding.backend, .hermes)
        choice.finish(id: UUID())
        XCTAssertFalse(choice.select(.deepSeek, standbyEnabled: false))
        choice.finish(id: id)
        XCTAssertFalse(choice.select(.deepSeek, standbyEnabled: true))
        XCTAssertTrue(choice.select(.deepSeek, standbyEnabled: false))
    }
    func testRepeatedSnapshotsDoNotReplayAnswerAndTerminalAppearsOnce() throws {
        var reducer = HermesSnapshotReducer(requestID: id, conversationID: conversation)
        let first = try reducer.accept(snapshot(answer: "你好", revision: 1))
        XCTAssertEqual(first.delta, "你好")
        XCTAssertFalse(first.complete)
        XCTAssertEqual(try reducer.accept(snapshot(answer: "你好", revision: 1)).delta, "")
        let final = try reducer.accept(snapshot("completed", answer: "你好，世界", revision: 2))
        XCTAssertEqual(final.delta, "，世界")
        XCTAssertTrue(final.complete)
        XCTAssertFalse(try reducer.accept(snapshot("completed", answer: "你好，世界", revision: 2)).complete)
    }
    func testSnapshotSuffixPreservesCombiningUnicodeBytes() throws {
        var reducer = HermesSnapshotReducer(requestID: id, conversationID: conversation)
        _ = try reducer.accept(snapshot(answer: "e", revision: 1))
        let update = try reducer.accept(snapshot("completed", answer: "e\u{301}", revision: 2))
        XCTAssertEqual(Array(update.delta.utf8), Array("\u{301}".utf8))
    }
    func testNormalCompletionCallbackCanCloseReceiverWithoutStoppingCompletedTask() async throws {
        var stops = 0
        var operation: HermesConversationOperation!
        operation = HermesConversationOperation(configuration: try configuration(), requestID: id, conversationID: conversation,
            send: { request in
                if request.url!.path.hasSuffix("/stop") { stops += 1 }
                return try self.snapshot("completed", answer: "完成", revision: 2)
            })
        try await operation.run(text: "test") { _, final in if final { operation.cancel() } }
        await operation.waitForStop()
        XCTAssertEqual(stops, 0)
    }
    func testOperationBuffersRunningAnswersAndEmitsCompleteAnswerOnce() async throws {
        var answers: [String] = [], finals: [Bool] = []
        var responses = [try snapshot(answer: "中间正文", revision: 1), try snapshot(answer: "中间正文", revision: 1),
                         try snapshot("completed", answer: "中间正文，完成", revision: 2)]
        let operation = HermesConversationOperation(configuration: try configuration(), requestID: id, conversationID: conversation,
            send: { _ in responses.removeFirst() },
            pause: { XCTAssertTrue(answers.isEmpty, "Running snapshots must remain invisible") })
        try await operation.run(text: "test") { text, final in answers.append(text); finals.append(final) }
        XCTAssertEqual(answers, ["中间正文，完成"])
        XCTAssertEqual(finals, [true])
        XCTAssertTrue(responses.isEmpty)
    }
    func testSnapshotRewriteWrongIdentityAndNonNullApprovalAreRejected() throws {
        var reducer = HermesSnapshotReducer(requestID: id, conversationID: conversation)
        _ = try reducer.accept(snapshot(answer: "原文", revision: 2))
        XCTAssertThrowsError(try reducer.accept(snapshot(answer: "改写", revision: 3)))
        XCTAssertThrowsError(try reducer.accept(snapshot(answer: "原文", revision: 1)))
        var object = try JSONSerialization.jsonObject(with: snapshot()) as! [String: Any]
        object["agent"] = "deepseek"
        XCTAssertThrowsError(try reducer.accept(JSONSerialization.data(withJSONObject: object)))
        object["agent"] = "hermes"; object["approval"] = ["command": "execute"]
        XCTAssertThrowsError(try reducer.accept(JSONSerialization.data(withJSONObject: object)))
    }
    func testUnknownSubmissionStopsKnownRequestWithoutRetryOrFallback() async throws {
        var requests: [URLRequest] = []
        let operation = HermesConversationOperation(configuration: try configuration(), requestID: id, conversationID: conversation,
            send: { request in
                requests.append(request)
                if request.url!.path.hasSuffix("/stop") { return try self.snapshot("cancelled") }
                throw URLError(.networkConnectionLost)
            })
        do { try await operation.run(text: "你好") { _, _ in XCTFail("No answer may be invented") }; XCTFail("Submission must fail") } catch {}
        await operation.waitForStop()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/tasks", "/v1/tasks/\(id.uuidString.lowercased())/stop"])
        let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: String]
        XCTAssertEqual(body["requestId"], id.uuidString.lowercased())
        XCTAssertEqual(body["conversationId"], conversation.uuidString.lowercased())
        XCTAssertEqual(body["agent"], "hermes")
        XCTAssertEqual(body["mode"], "read-only")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer " + String(repeating: "t", count: 32))
    }
    func testCancellationBeforeCreateResponseSendsStopAndIgnoresLateCompletion() async throws {
        var create: CheckedContinuation<Data, Error>?
        var stopped = false
        let operation = HermesConversationOperation(configuration: try configuration(), requestID: id, conversationID: conversation,
            send: { request in
                if request.url!.path.hasSuffix("/stop") { stopped = true; return try self.snapshot("cancelled") }
                return try await withCheckedThrowingContinuation { create = $0 }
            })
        let task = Task { try await operation.run(text: "你好") { _, _ in XCTFail("Late output must be ignored") } }
        while create == nil { await Task.yield() }
        task.cancel()
        while !stopped { await Task.yield() }
        create?.resume(returning: try snapshot("completed", answer: "迟到正文", revision: 2))
        do { try await task.value; XCTFail("Cancelled operation must throw") } catch {}
        await operation.waitForStop()
        XCTAssertTrue(stopped)
    }
    func testStopFailureIsReportedWithoutEchoingRemoteError() async throws {
        var unknown = false
        let operation = HermesConversationOperation(configuration: try configuration(), requestID: id, conversationID: conversation,
            send: { _ in throw URLError(.cannotConnectToHost) }, onStopUnconfirmed: { unknown = true })
        do { try await operation.run(text: "test") { _, _ in }; XCTFail() } catch {}
        await operation.waitForStop()
        XCTAssertTrue(unknown)
    }
}
