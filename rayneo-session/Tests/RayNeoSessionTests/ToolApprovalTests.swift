import XCTest
@testable import RayNeoSession

final class ToolApprovalTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let round = RoundToken(sessionID: UUID(), index: 0)
    private func request(_ id: String = "pending-1", round: RoundToken? = nil, expiresIn: TimeInterval = 30) -> ToolApprovalRequest {
        .init(requestID: id, round: round ?? self.round, actionDescription: "批准当前明确展示的测试操作，不执行命令",
              createdAt: now, expiresAt: now.addingTimeInterval(expiresIn))
    }

    func testApprovalRequiresMatchingRequestRoundAndExplicitConfirmation() {
        var gate = ToolApprovalGate()
        XCTAssertEqual(gate.register(request(), now: now), .registered)
        XCTAssertEqual(gate.resolve(requestID: "missing", round: round, choice: .approve, evidence: .explicitUserConfirmation, now: now), .rejected(.unknownRequest))
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: .init(sessionID: round.sessionID, index: 1), choice: .approve,
                                    evidence: .explicitUserConfirmation, now: now), .rejected(.wrongRound))
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: round, choice: .approve, evidence: .unconfirmed, now: now), .rejected(.confirmationRequired))
        guard case let .resolved(receipt) = gate.resolve(requestID: "pending-1", round: round, choice: .approve,
                                                        evidence: .explicitUserConfirmation, now: now) else { return XCTFail("Expected new decision") }
        XCTAssertEqual(receipt.resolution, .approved)
        XCTAssertEqual(receipt.round, round)
        XCTAssertEqual(receipt.expiresAt, now.addingTimeInterval(30))
        XCTAssertNil(gate.pendingRequest(requestID: "pending-1", round: round, now: now))
    }

    func testResolutionIsIdempotentAndCannotFlipApprovalToDenial() {
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        guard case let .resolved(receipt) = gate.resolve(requestID: "pending-1", round: round, choice: .approve,
                                                        evidence: .explicitUserConfirmation, now: now) else { return XCTFail() }
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: round, choice: .deny, evidence: .explicitUserConfirmation,
                                    now: now.addingTimeInterval(1)), .alreadyResolved(receipt))
        XCTAssertEqual(gate.register(request(), now: now), .rejected(.duplicateRequestID))
    }

    func testExpiryAtExactBoundaryFailsClosed() {
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        guard case let .resolved(receipt) = gate.resolve(requestID: "pending-1", round: round, choice: .approve,
            evidence: .explicitUserConfirmation, now: now.addingTimeInterval(30)) else { return XCTFail() }
        XCTAssertEqual(receipt.resolution, .expired)
        XCTAssertNil(gate.pendingRequest(requestID: "pending-1", round: round, now: now.addingTimeInterval(30)))
    }

    func testExpiredOrMalformedRequestCannotRegister() {
        var gate = ToolApprovalGate()
        XCTAssertEqual(gate.register(request(expiresIn: 0), now: now), .rejected(.invalidRequest))
        XCTAssertEqual(gate.register(request("   "), now: now), .rejected(.invalidRequest))
        XCTAssertEqual(gate.register(request(), now: now.addingTimeInterval(-1)), .rejected(.invalidRequest))
        XCTAssertEqual(gate.register(request(), now: Date(timeIntervalSince1970: .nan)), .rejected(.invalidRequest))
    }

    func testClockRollbackCannotApproveBeforeRequestCreation() {
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: round, choice: .approve, evidence: .explicitUserConfirmation,
                                    now: now.addingTimeInterval(-1)), .rejected(.invalidClock))
    }

    func testOpaqueRequestIDUsesExactUTF8NotUnicodeCanonicalEquality() {
        let decomposed = "approval-e\u{0301}"
        let composed = "approval-\u{00e9}"
        XCTAssertEqual(decomposed, composed, "Swift equality normalizes canonical equivalents")
        XCTAssertFalse(decomposed.utf8.elementsEqual(composed.utf8))
        for (original, other) in [(decomposed, composed), (composed, decomposed)] {
            var gate = ToolApprovalGate()
            XCTAssertEqual(gate.register(request(original), now: now), .registered)
            XCTAssertEqual(gate.register(request(other), now: now), .rejected(.duplicateRequestID), "Canonical key collisions fail closed")
            XCTAssertEqual(gate.resolve(requestID: other, round: round, choice: .approve,
                                        evidence: .explicitUserConfirmation, now: now), .rejected(.unknownRequest))
            XCTAssertNil(gate.pendingRequest(requestID: other, round: round, now: now))
            guard case let .resolved(receipt) = gate.resolve(requestID: original, round: round, choice: .approve,
                evidence: .explicitUserConfirmation, now: now) else { return XCTFail() }
            XCTAssertTrue(receipt.requestID.utf8.elementsEqual(original.utf8))
        }
    }

    func testCombiningScalarsCannotBypassApprovalByteLimits() {
        var gate = ToolApprovalGate()
        let oneLongCharacter = "a" + String(repeating: "\u{0301}", count: 8_200)
        XCTAssertEqual(oneLongCharacter.count, 1)
        XCTAssertEqual(gate.register(request(oneLongCharacter), now: now), .rejected(.invalidRequest))
        let action = ToolApprovalRequest(requestID: "valid-id", round: round, actionDescription: oneLongCharacter,
                                        createdAt: now, expiresAt: now.addingTimeInterval(30))
        XCTAssertEqual(gate.register(action, now: now), .rejected(.invalidRequest))
    }

    func testInterruptInvalidatesOnlyItsRoundAndCannotBeReapproved() {
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        let other = RoundToken(sessionID: round.sessionID, index: 1)
        _ = gate.register(request("pending-2", round: other), now: now)
        let receipts = gate.invalidate(round: round, now: now.addingTimeInterval(1))
        XCTAssertEqual(receipts.map(\.resolution), [.invalidated])
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: round, choice: .approve, evidence: .explicitUserConfirmation,
                                    now: now.addingTimeInterval(2)), .alreadyResolved(receipts[0]))
        XCTAssertNotNil(gate.pendingRequest(requestID: "pending-2", round: other, now: now))
        XCTAssertTrue(gate.invalidate(round: round, now: now).isEmpty)
    }

    func testCapacityFailsClosedWithoutEvictingReplayHistory() {
        var gate = ToolApprovalGate(capacity: 1); _ = gate.register(request(), now: now)
        _ = gate.invalidate(round: round, now: now)
        let freshRound = RoundToken(sessionID: round.sessionID, index: 1)
        XCTAssertEqual(gate.register(request("pending-2", round: freshRound), now: now), .rejected(.capacityReached))
        XCTAssertEqual(gate.register(request(), now: now), .rejected(.duplicateRequestID))
        XCTAssertEqual(gate.entryCount, 1)
    }

    func testInvalidateBeforeRegistrationRejectsLateToolRequest() {
        var gate = ToolApprovalGate()
        XCTAssertTrue(gate.invalidate(round: round, now: now).isEmpty)
        XCTAssertEqual(gate.register(request(), now: now), .rejected(.invalidatedRound))
        XCTAssertEqual(gate.resolve(requestID: "pending-1", round: round, choice: .approve,
                                    evidence: .explicitUserConfirmation, now: now), .rejected(.unknownRequest))
        XCTAssertEqual(gate.invalidatedRoundCount, 1)
    }

    func testTombstoneCapacityNeverEvictsOldRoundAndFailsClosedForNewRounds() {
        var gate = ToolApprovalGate(capacity: 1)
        _ = gate.invalidate(round: round, now: now)
        let other = RoundToken(sessionID: round.sessionID, index: 1)
        _ = gate.invalidate(round: other, now: now)
        XCTAssertEqual(gate.invalidatedRoundCount, 1)
        XCTAssertEqual(gate.register(request(), now: now), .rejected(.invalidatedRound))
        XCTAssertEqual(gate.register(request("pending-2", round: other), now: now), .rejected(.capacityReached))
        let future = RoundToken(sessionID: UUID(), index: 0)
        XCTAssertEqual(gate.register(request("pending-3", round: future), now: now), .rejected(.capacityReached))
    }

    func testInvalidationStillFailsClosedWhenClockIsInvalid() {
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        let receipts = gate.invalidate(round: round, now: Date(timeIntervalSince1970: .nan))
        XCTAssertEqual(receipts.first?.resolution, .invalidated)
        XCTAssertEqual(gate.register(request("late"), now: now), .rejected(.invalidatedRound))
        guard case let .alreadyResolved(receipt) = gate.resolve(requestID: "pending-1", round: round, choice: .approve,
            evidence: .explicitUserConfirmation, now: now) else { return XCTFail() }
        XCTAssertEqual(receipt.resolution, .invalidated)
    }

    func testVoicePhraseClassifierIsExactAndHasNoApprovalSideEffect() {
        XCTAssertEqual(VoiceApprovalPhrase.classify(" 批准了 "), .approve)
        XCTAssertEqual(VoiceApprovalPhrase.classify("I APPROVE"), .approve)
        XCTAssertEqual(VoiceApprovalPhrase.classify("不批准"), .deny)
        XCTAssertNil(VoiceApprovalPhrase.classify("不要批准了"))
        XCTAssertNil(VoiceApprovalPhrase.classify("电视说批准了"))
        XCTAssertNil(VoiceApprovalPhrase.classify("是"))
        var gate = ToolApprovalGate(); _ = gate.register(request(), now: now)
        _ = VoiceApprovalPhrase.classify("批准了")
        XCTAssertNotNil(gate.pendingRequest(requestID: "pending-1", round: round, now: now))
    }

    func testConcurrentApprovalsResolveOnlyOnce() async {
        let coordinator = ToolApprovalCoordinator()
        let registration = await coordinator.register(request(), now: now)
        XCTAssertEqual(registration, .registered)
        let round = self.round, now = self.now
        let results = await withTaskGroup(of: ToolApprovalResult.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await coordinator.resolve(requestID: "pending-1", round: round, choice: .approve,
                                              evidence: .explicitUserConfirmation, now: now)
                }
            }
            var result: [ToolApprovalResult] = []
            for await item in group { result.append(item) }
            return result
        }
        XCTAssertEqual(results.filter { if case .resolved = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(results.filter { if case .alreadyResolved = $0 { return true }; return false }.count, 99)
    }
}
