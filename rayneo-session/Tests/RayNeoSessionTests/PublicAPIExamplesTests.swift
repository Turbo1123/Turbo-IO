import XCTest
import RayNeoSession

/// Compile/run the documented public API without @testable or any device/network access.
final class PublicAPIExamplesTests: XCTestCase {
    func testPublicTextConversationExample() {
        var machine = VoiceSessionMachine(configuration: .init(asrPolicy: .preferCloudWithLocalFallback,
                                                               ttsMode: .disabled, nextRoundMode: .manual))
        _ = machine.handle(.connected)
        _ = machine.handle(.networkChanged(isAvailable: true))
        let start = machine.handle(.wake)
        let round = machine.snapshot.currentRound!
        XCTAssertTrue(start.contains(.startCapture(round: round)))
        _ = machine.handle(.audioEnded(round: round))
        let recognized = machine.handle(.asrResult(round: round, source: .cloud,
            result: ASRTranscript(revision: 0, text: "合成测试输入，不是真实识别", isFinal: true)))
        XCTAssertTrue(recognized.contains { if case .requestModel = $0 { return true }; return false })
        _ = machine.handle(.modelText(round: round, update: ModelText(revision: 0, text: "合成模型结果")))
        let completed = machine.handle(.modelFinished(round: round))
        XCTAssertTrue(completed.contains(.responseComplete(round: round)))
        XCTAssertEqual(machine.snapshot.phase, .awaitingNextRound)
    }

    func testPublicApprovalExampleReturnsDecisionNotExecution() {
        var gate = ToolApprovalGate()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let round = RoundToken(sessionID: UUID(), index: 0)
        let request = ToolApprovalRequest(requestID: "public-example", round: round, actionDescription: "仅测试授权接口",
                                         createdAt: now, expiresAt: now.addingTimeInterval(20))
        XCTAssertEqual(gate.register(request, now: now), .registered)
        let choice = VoiceApprovalPhrase.classify("批准了")!
        let result = gate.resolve(requestID: request.requestID, round: round, choice: choice,
                                  evidence: .explicitUserConfirmation, now: now)
        guard case let .resolved(receipt) = result else { return XCTFail("Expected a decision value") }
        XCTAssertEqual(receipt.resolution, .approved)
        XCTAssertEqual(receipt.expiresAt, request.expiresAt)
    }
}
