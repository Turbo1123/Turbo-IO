import XCTest
@testable import RayNeoSession

@MainActor final class TypedConversationTests: XCTestCase {
    func testTypedDeepSeekNeedsOnlyModelKeyAndSendsNoASRRequest() async throws {
        var calls: [URLRequest] = []
        let answer = try await DeepSeekTypedConversation.respond(text: "解释一下", key: "sk-synthetic", history: [], send: { request in
            calls.append(request)
            return Data(#"{"choices":[{"message":{"content":"这是回答"},"finish_reason":"stop"}]}"#.utf8)
        })
        XCTAssertEqual(answer, "这是回答")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].url?.absoluteString, "https://api.deepseek.com/chat/completions")
        let body = try JSONSerialization.jsonObject(with: calls[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
        XCTAssertNil(body["tools"])
        XCTAssertEqual((body["messages"] as? [[String: String]])?.last?["content"], "解释一下")
    }
    func testExplicitHermesRouteNeverFallsBackWhenUnavailable() async {
        var deepSeekCalls = 0
        do {
            try await ConversationBackendRouter.respond(backend: .hermes, deepSeek: { deepSeekCalls += 1 }, hermes: { throw HermesConversationError.unavailable })
            XCTFail("Unavailable selection must fail")
        } catch {}
        XCTAssertEqual(deepSeekCalls, 0)
    }
    func testTypedRejectsEmptyAnswerWithoutInventingCompletion() async throws {
        do {
            _ = try await DeepSeekTypedConversation.respond(text: "test", key: "sk-synthetic", history: [], send: { _ in
                Data(#"{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}"#.utf8)
            })
            XCTFail("Empty answer must fail")
        } catch {}
    }
}
