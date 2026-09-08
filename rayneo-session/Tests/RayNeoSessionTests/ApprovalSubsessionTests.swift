import XCTest
import RayNeoSession

final class ApprovalSubsessionTests: XCTestCase {
    private enum FixtureFailure: Error { case unexpectedResult }
    private func request(_ round: RoundToken, clock: ApprovalTestClock, id: String = "synthetic-approval",
                         description: String = "创建一份合成便笺", risk: ApprovalRisk = .low,
                         action: Data = Data("abc".utf8), duration: TimeInterval = 60) throws -> BoundToolApprovalRequest {
        try .init(requestID: id, originRound: round, actionDescription: description, canonicalActionBytes: action,
                  risk: risk, createdAt: clock.now, expiresAt: clock.now.addingTimeInterval(duration))
    }
    private func establish(_ controller: ApprovalSubsessionController, round: RoundToken = .init(sessionID: UUID(), index: 3)) async throws -> ApprovalContextToken {
        guard case .established(let token) = await controller.beginSuspendedContext(originRound: round, connectionGeneration: UUID(),
            evidence: .ordinaryWorkPausedAndDrained) else { XCTFail("Expected synthetic suspended context"); throw FixtureFailure.unexpectedResult }
        return token
    }
    private func register(_ controller: ApprovalSubsessionController, context: ApprovalContextToken, clock: ApprovalTestClock,
                          policy: ApprovalConfirmationPolicy = .voiceChallenge, risk: ApprovalRisk = .low,
                          id: String = "synthetic-approval", description: String = "创建一份合成便笺") async throws -> ApprovalPresentation {
        guard case .registered(let presentation) = await controller.register(try request(context.originRound, clock: clock, id: id, description: description, risk: risk),
            context: context, policy: policy) else { XCTFail("Expected synthetic registration"); throw FixtureFailure.unexpectedResult }
        return presentation
    }
    private func present(_ controller: ApprovalSubsessionController, _ presentation: ApprovalPresentation) async {
        let result = await controller.acknowledgePresentation(binding: presentation.binding, displayed: presentation.content,
            evidence: .trustedHostDisplayedExactContent)
        XCTAssertEqual(result, .accepted)
    }
    private func capture(_ controller: ApprovalSubsessionController, _ presentation: ApprovalPresentation) async throws -> ApprovalCapturePrompt {
        guard case .captureStarted(let challenge) = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .explicitUserButtonOrGesture)
        else { XCTFail("Expected synthetic confirmation capture"); throw FixtureFailure.unexpectedResult }
        return challenge
    }
    private func fixture(policy: ApprovalConfirmationPolicy = .voiceChallenge, risk: ApprovalRisk = .low,
                         configuration: ApprovalSubsessionConfiguration = .init()) async throws
        -> (ApprovalSubsessionController, ApprovalTestClock, ApprovalContextToken, ApprovalPresentation) {
        let clock = ApprovalTestClock(), controller = ApprovalSubsessionController(configuration: configuration, clock: { clock.now })
        let context = try await establish(controller)
        let presentation = try await register(controller, context: context, clock: clock, policy: policy, risk: risk)
        return (controller, clock, context, presentation)
    }
    private func isNewApproval(_ result: ApprovalSubsessionResult) -> Bool {
        if case .resolved(let value) = result { return value.receipt.resolution == .approved }
        return false
    }

    func testSDKComputesSHA256AndKeepsActionBytesImmutable() throws {
        let clock = ApprovalTestClock(), round = RoundToken(sessionID: UUID(), index: 1)
        let first = try request(round, clock: clock), changed = try request(round, clock: clock, action: Data("abd".utf8))
        XCTAssertEqual(first.actionDigest.hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(first.canonicalActionBytes, Data("abc".utf8))
        XCTAssertNotEqual(first.actionDigest, changed.actionDigest)
        XCTAssertNotEqual(first, changed)
    }

    func testExplicitSuspensionIsRequiredAndOnlyOneContextExists() async throws {
        let clock = ApprovalTestClock(), controller = ApprovalSubsessionController(clock: { clock.now })
        let round = RoundToken(sessionID: UUID(), index: 0)
        let refused = await controller.beginSuspendedContext(originRound: round, connectionGeneration: UUID(), evidence: .unconfirmed)
        XCTAssertEqual(refused, .rejected(.hostSuspensionRequired))
        _ = try await establish(controller, round: round)
        let busy = await controller.beginSuspendedContext(originRound: round, connectionGeneration: UUID(), evidence: .ordinaryWorkPausedAndDrained)
        XCTAssertEqual(busy, .rejected(.contextBusy))
    }

    func testVoiceChallengeCompletesOneBoundDecisionWithoutAdvancingOrdinaryRound() async throws {
        let (controller, _, context, presentation) = try await fixture()
        await present(controller, presentation)
        let challenge = try await capture(controller, presentation)
        let armed = await controller.currentSnapshot()
        XCTAssertEqual(armed.phase, .capturingConfirmation)
        XCTAssertEqual(armed.context?.originRound, context.originRound)
        let result = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        guard case .resolved(let decision) = result else { return XCTFail("Expected first approval decision only") }
        XCTAssertEqual(decision.receipt.resolution, .approved)
        XCTAssertEqual(decision.binding, presentation.binding)
        XCTAssertEqual(Data(decision.receipt.requestID.utf8), presentation.binding.requestIDBytes)
        XCTAssertEqual(decision.receipt.round, context.originRound)
        XCTAssertEqual(decision.source, .voiceChallenge(challenge.token))
        let replay = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        XCTAssertEqual(replay, .alreadyResolved(decision))
    }

    func testDefaultAndHighRiskAlwaysRequirePhone() async throws {
        for (policy, risk) in [(ApprovalConfirmationPolicy.phoneRequired, ApprovalRisk.low), (.voiceChallenge, .high), (.voiceExact, .high)] {
            let (controller, _, _, presentation) = try await fixture(policy: policy, risk: risk)
            XCTAssertEqual(presentation.effectivePolicy, .phoneRequired)
            await present(controller, presentation)
            let voice = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .explicitUserButtonOrGesture)
            XCTAssertEqual(voice, .rejected(.phoneRequired))
            let unconfirmed = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
                choice: .approve, evidence: .unconfirmed)
            XCTAssertEqual(unconfirmed, .rejected(.confirmationRequired))
            let result = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
                choice: .approve, evidence: .foregroundExplicitConfirmation)
            XCTAssertTrue(isNewApproval(result))
        }
    }

    func testRegisterDefaultPolicyIsPhoneRequired() async throws {
        let clock = ApprovalTestClock(), controller = ApprovalSubsessionController(clock: { clock.now })
        let context = try await establish(controller)
        let result = await controller.register(try request(context.originRound, clock: clock), context: context)
        guard case .registered(let presentation) = result else { return XCTFail("Expected registration") }
        XCTAssertEqual(presentation.effectivePolicy, .phoneRequired)
    }

    func testPresentationAndTrustedGestureCannotBeInferredFromVoice() async throws {
        let (controller, _, _, presentation) = try await fixture()
        let before = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .explicitUserButtonOrGesture)
        XCTAssertEqual(before, .rejected(.presentationRequired))
        let unconfirmed = await controller.acknowledgePresentation(binding: presentation.binding, displayed: presentation.content, evidence: .unconfirmed)
        XCTAssertEqual(unconfirmed, .rejected(.explicitPresentationRequired))
        await present(controller, presentation)
        let ambient = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .unconfirmed)
        XCTAssertEqual(ambient, .rejected(.trustedInteractionRequired))
        let snapshot = await controller.currentSnapshot()
        XCTAssertNil(snapshot.capture); XCTAssertNil(snapshot.decision)
    }

    func testDisplayedRequestDescriptionDigestRiskAndExpiryMustAllMatch() async throws {
        let (controller, clock, context, presentation) = try await fixture()
        let content = presentation.content
        let other = try request(context.originRound, clock: clock, action: Data("different".utf8))
        let changed = [
            ApprovalDisplayedContent(requestID: "wrong-id", actionDescription: content.actionDescription, actionDigest: content.actionDigest, risk: content.risk, expiresAt: content.expiresAt),
            .init(requestID: content.requestID, actionDescription: "悄悄换成别的动作", actionDigest: content.actionDigest, risk: content.risk, expiresAt: content.expiresAt),
            .init(requestID: content.requestID, actionDescription: content.actionDescription, actionDigest: other.actionDigest, risk: content.risk, expiresAt: content.expiresAt),
            .init(requestID: content.requestID, actionDescription: content.actionDescription, actionDigest: content.actionDigest, risk: .high, expiresAt: content.expiresAt),
            .init(requestID: content.requestID, actionDescription: content.actionDescription, actionDigest: content.actionDigest, risk: content.risk, expiresAt: content.expiresAt.addingTimeInterval(1))
        ]
        for displayed in changed {
            let result = await controller.acknowledgePresentation(binding: presentation.binding, displayed: displayed, evidence: .trustedHostDisplayedExactContent)
            XCTAssertEqual(result, .rejected(.presentationMismatch))
        }
        await present(controller, presentation)
        let phoneWrongObject = await controller.confirmOnPhone(binding: presentation.binding, displayed: changed[1], choice: .approve, evidence: .foregroundExplicitConfirmation)
        XCTAssertEqual(phoneWrongObject, .rejected(.presentationMismatch))
    }

    func testNFCAndNFDIdentifiersAndDisplayTextAreNotInterchangeable() async throws {
        let clock = ApprovalTestClock(), controller = ApprovalSubsessionController(clock: { clock.now })
        let context = try await establish(controller)
        let presentation = try await register(controller, context: context, clock: clock, id: "id-e\u{301}", description: "action-e\u{301}")
        let content = presentation.content
        for (id, description) in [("id-é", content.actionDescription), (content.requestID, "action-é")] {
            let display = ApprovalDisplayedContent(requestID: id, actionDescription: description, actionDigest: content.actionDigest, risk: content.risk, expiresAt: content.expiresAt)
            let result = await controller.acknowledgePresentation(binding: presentation.binding, displayed: display, evidence: .trustedHostDisplayedExactContent)
            XCTAssertEqual(result, .rejected(.presentationMismatch))
        }
        await present(controller, presentation)
        let result = await controller.confirmOnPhone(binding: presentation.binding, displayed: content, choice: .approve, evidence: .foregroundExplicitConfirmation)
        guard case .resolved(let decision) = result else { return XCTFail("Expected exact-byte approval") }
        XCTAssertEqual(Data(decision.receipt.requestID.utf8), Data("id-e\u{301}".utf8))
        let duplicate = await controller.register(try request(context.originRound, clock: clock, id: "id-é"), context: context)
        XCTAssertEqual(duplicate, .rejected(.duplicateRequestID), "Canonical collision fails closed in the unchanged legacy gate")
    }

    func testAmbiguousFinalConsumesCaptureAndRetryCannotUseOldTokenOrChallenge() async throws {
        let (controller, _, _, presentation) = try await fixture()
        await present(controller, presentation)
        let first = try await capture(controller, presentation)
        let ambiguous = await controller.submitVoiceFinal(token: first.token, text: "批准了")
        XCTAssertEqual(ambiguous, .rejected(.ambiguousVoice))
        let unarmed = await controller.submitVoiceFinal(token: first.token, text: first.approvePhrase)
        XCTAssertEqual(unarmed, .rejected(.captureRequired))
        let second = try await capture(controller, presentation)
        XCTAssertNotEqual(first.token, second.token); XCTAssertNotEqual(first.approvePhrase, second.approvePhrase)
        XCTAssertEqual(second.token.generation, first.token.generation + 1)
        let old = await controller.submitVoiceFinal(token: first.token, text: first.approvePhrase)
        XCTAssertEqual(old, .rejected(.wrongCapture))
        let wrongChallenge = await controller.submitVoiceFinal(token: second.token, text: first.approvePhrase)
        XCTAssertEqual(wrongChallenge, .rejected(.ambiguousVoice))
        let snapshot = await controller.currentSnapshot()
        XCTAssertNil(snapshot.decision)
    }

    func testDenialIsExactAndOneShot() async throws {
        let (controller, _, _, presentation) = try await fixture()
        await present(controller, presentation)
        let challenge = try await capture(controller, presentation)
        let result = await controller.submitVoiceFinal(token: challenge.token, text: challenge.denyPhrase)
        guard case .resolved(let decision) = result else { return XCTFail("Expected denial decision") }
        XCTAssertEqual(decision.receipt.resolution, .denied)
        let flip = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        XCTAssertEqual(flip, .alreadyResolved(decision))
    }

    func testCancelledCaptureRequiresNewGestureAndAttemptsAreBounded() async throws {
        let (controller, _, _, presentation) = try await fixture(configuration: .init(maximumCaptureAttempts: 2))
        await present(controller, presentation)
        for _ in 0..<2 {
            let challenge = try await capture(controller, presentation)
            let cancelled = await controller.cancelCapture(challenge.token)
            XCTAssertEqual(cancelled, .accepted)
            let late = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
            XCTAssertEqual(late, .rejected(.captureRequired))
        }
        let exhausted = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .explicitUserButtonOrGesture)
        XCTAssertEqual(exhausted, .rejected(.attemptsExhausted))
        let phone = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content, choice: .deny, evidence: .foregroundExplicitConfirmation)
        guard case .resolved(let decision) = phone else { return XCTFail("Phone fallback must remain available") }
        XCTAssertEqual(decision.receipt.resolution, .denied)
    }

    func testCaptureDeadlineIsEnforcedWithoutHostTimerCallback() async throws {
        let (controller, clock, _, presentation) = try await fixture(configuration: .init(captureWindowSeconds: 2))
        await present(controller, presentation)
        let first = try await capture(controller, presentation)
        clock.advance(2)
        let late = await controller.submitVoiceFinal(token: first.token, text: first.approvePhrase)
        XCTAssertEqual(late, .rejected(.captureExpired))
        let next = try await capture(controller, presentation)
        XCTAssertNotEqual(first.token, next.token)
    }

    func testRequestExpiryAtExactBoundaryCannotApproveAndDoesNotExtendCapture() async throws {
        let (controller, clock, _, presentation) = try await fixture()
        await present(controller, presentation)
        clock.advance(55)
        let challenge = try await capture(controller, presentation)
        XCTAssertEqual(challenge.token.expiresAt, presentation.content.expiresAt)
        clock.advance(5)
        let late = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content, choice: .approve, evidence: .foregroundExplicitConfirmation)
        guard case .alreadyResolved(let decision) = late else { return XCTFail("Expiry must resolve before an approval entrance") }
        XCTAssertEqual(decision.receipt.resolution, .expired)
        XCTAssertEqual(decision.source, .expiration)
        let voice = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        XCTAssertFalse(isNewApproval(voice))
    }

    func testExplicitExpiryRefreshEndsPendingCapture() async throws {
        let (controller, clock, _, presentation) = try await fixture()
        await present(controller, presentation); _ = try await capture(controller, presentation)
        clock.advance(60)
        let snapshot = await controller.expireDue()
        XCTAssertEqual(snapshot.phase, .resolved); XCTAssertNil(snapshot.capture)
        XCTAssertEqual(snapshot.decision?.receipt.resolution, .expired)
    }

    func testEveryOrdinaryLifecycleChangeInvalidatesWithoutMigratingOldRequest() async throws {
        for reason in [ApprovalContextInvalidation.normalNextRound, .interruption, .exit, .disconnection, .hostCancellation] {
            let (controller, _, context, presentation) = try await fixture()
            await present(controller, presentation)
            let challenge = try await capture(controller, presentation)
            let invalidated = await controller.invalidateContext(context, reason: reason)
            guard case .resolved(let decision) = invalidated else { XCTFail("Expected invalidation receipt"); continue }
            XCTAssertEqual(decision.receipt.resolution, .invalidated)
            let late = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
            XCTAssertEqual(late, .rejected(.contextRequired))
            let reopened = await controller.beginSuspendedContext(originRound: context.originRound, connectionGeneration: UUID(), evidence: .ordinaryWorkPausedAndDrained)
            XCTAssertEqual(reopened, .rejected(.contextAlreadyUsed))
            let next = try await establish(controller, round: .init(sessionID: context.originRound.sessionID, index: context.originRound.index + 1))
            let stillOld = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
            XCTAssertEqual(stillOld, .rejected(.wrongContext))
            XCTAssertNotEqual(next, context)
        }
    }

    func testWrongControllerContextAndConnectionGenerationCannotCrossBind() async throws {
        let (first, clock, context, presentation) = try await fixture()
        let second = ApprovalSubsessionController(clock: { clock.now })
        let otherContext = try await establish(second, round: context.originRound)
        XCTAssertNotEqual(context.connectionGeneration, otherContext.connectionGeneration)
        let wrongRegister = await first.register(try request(context.originRound, clock: clock), context: otherContext)
        XCTAssertEqual(wrongRegister, .rejected(.wrongContext))
        let foreign = await second.acknowledgePresentation(binding: presentation.binding, displayed: presentation.content, evidence: .trustedHostDisplayedExactContent)
        XCTAssertEqual(foreign, .rejected(.wrongContext))
    }

    func testOldBindingCannotApproveAnotherRequestInSameContext() async throws {
        let (controller, clock, context, first) = try await fixture()
        await present(controller, first)
        let firstCapture = try await capture(controller, first)
        _ = await controller.submitVoiceFinal(token: firstCapture.token, text: firstCapture.denyPhrase)
        let second = try await register(controller, context: context, clock: clock, id: "second-action")
        XCTAssertNotEqual(first.binding.requestDigest, second.binding.requestDigest)
        await present(controller, second)
        let stale = await controller.confirmOnPhone(binding: first.binding, displayed: first.content, choice: .approve, evidence: .foregroundExplicitConfirmation)
        XCTAssertEqual(stale, .rejected(.wrongBinding))
        let staleVoice = await controller.submitVoiceFinal(token: firstCapture.token, text: firstCapture.approvePhrase)
        XCTAssertEqual(staleVoice, .rejected(.wrongBinding))
    }

    func testRegisterCannotReplacePendingActionAndChangedBytesCannotReuseID() async throws {
        let (controller, clock, context, presentation) = try await fixture()
        let changed = try request(context.originRound, clock: clock, action: Data("different action".utf8))
        let busy = await controller.register(changed, context: context)
        XCTAssertEqual(busy, .rejected(.requestBusy))
        await present(controller, presentation)
        _ = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content, choice: .deny, evidence: .foregroundExplicitConfirmation)
        let duplicate = await controller.register(changed, context: context)
        XCTAssertEqual(duplicate, .rejected(.duplicateRequestID))
    }

    func testCapacityNeverEvictsRequestOrContextReplayHistory() async throws {
        let (controller, clock, context, presentation) = try await fixture(configuration: .init(requestCapacity: 1, contextCapacity: 1))
        await present(controller, presentation)
        _ = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content, choice: .deny, evidence: .foregroundExplicitConfirmation)
        let full = await controller.register(try request(context.originRound, clock: clock, id: "new"), context: context)
        XCTAssertEqual(full, .rejected(.capacityReached))
        _ = await controller.invalidateContext(context, reason: .normalNextRound)
        let newContext = await controller.beginSuspendedContext(originRound: .init(sessionID: UUID(), index: 0), connectionGeneration: UUID(), evidence: .ordinaryWorkPausedAndDrained)
        XCTAssertEqual(newContext, .rejected(.capacityReached))
        let snapshot = await controller.currentSnapshot()
        XCTAssertEqual(snapshot.registeredRequestCount, 1); XCTAssertEqual(snapshot.usedContextCount, 1)
    }

    func testConcurrentPhoneConfirmationsProduceOnlyOneNewDecision() async throws {
        let (controller, _, _, presentation) = try await fixture(policy: .phoneRequired)
        await present(controller, presentation)
        let results = await withTaskGroup(of: ApprovalSubsessionResult.self, returning: [ApprovalSubsessionResult].self) { group in
            for _ in 0..<50 { group.addTask { await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
                choice: .approve, evidence: .foregroundExplicitConfirmation) } }
            var values: [ApprovalSubsessionResult] = []; for await value in group { values.append(value) }; return values
        }
        XCTAssertEqual(results.filter(isNewApproval).count, 1)
        XCTAssertEqual(results.filter { if case .alreadyResolved = $0 { return true }; return false }.count, 49)
    }

    func testConcurrentVoiceAndPhoneReturnOneNewApproval() async throws {
        let (controller, _, _, presentation) = try await fixture()
        await present(controller, presentation)
        let challenge = try await capture(controller, presentation)
        async let voice = controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        async let phone = controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
            choice: .approve, evidence: .foregroundExplicitConfirmation)
        let results = await [voice, phone]
        XCTAssertEqual(results.filter(isNewApproval).count, 1)
    }

    func testCancelVersusConfirmationNeverEmitsSameApprovalTwice() async throws {
        let (controller, _, context, presentation) = try await fixture()
        await present(controller, presentation)
        async let approval = controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
            choice: .approve, evidence: .foregroundExplicitConfirmation)
        async let cancellation = controller.invalidateContext(context, reason: .disconnection)
        let results = await [approval, cancellation]
        XCTAssertLessThanOrEqual(results.filter(isNewApproval).count, 1)
        let late = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
            choice: .approve, evidence: .foregroundExplicitConfirmation)
        XCTAssertEqual(late, .rejected(.contextRequired))
    }

    func testInvalidatingResolvedRequestReturnsReplayNotANewApproval() async throws {
        let (controller, _, context, presentation) = try await fixture()
        await present(controller, presentation)
        let result = await controller.confirmOnPhone(binding: presentation.binding, displayed: presentation.content,
            choice: .approve, evidence: .foregroundExplicitConfirmation)
        guard case .resolved(let first) = result else { return XCTFail("Expected approval") }
        let invalidation = await controller.invalidateContext(context, reason: .exit)
        XCTAssertEqual(invalidation, .alreadyResolved(first))
    }

    func testClockRollbackPermanentlyFailsClosed() async throws {
        let (controller, clock, _, presentation) = try await fixture()
        await present(controller, presentation)
        let challenge = try await capture(controller, presentation)
        clock.advance(-1)
        let rollback = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        XCTAssertEqual(rollback, .rejected(.invalidClock))
        clock.advance(2)
        let retry = await controller.submitVoiceFinal(token: challenge.token, text: challenge.approvePhrase)
        XCTAssertEqual(retry, .rejected(.invalidClock))
        let snapshot = await controller.currentSnapshot()
        XCTAssertEqual(snapshot.phase, .inactive); XCTAssertEqual(snapshot.decision?.receipt.resolution, .invalidated)
    }

    func testNonfiniteClockCannotStartContext() async {
        let controller = ApprovalSubsessionController(clock: { Date(timeIntervalSince1970: .nan) })
        let result = await controller.beginSuspendedContext(originRound: .init(sessionID: UUID(), index: 0), connectionGeneration: UUID(), evidence: .ordinaryWorkPausedAndDrained)
        XCTAssertEqual(result, .rejected(.invalidClock))
    }

    func testRequestLifetimeFutureAndWrongOriginAreRejected() async throws {
        let clock = ApprovalTestClock(), controller = ApprovalSubsessionController(clock: { clock.now })
        let context = try await establish(controller)
        let long = await controller.register(try request(context.originRound, clock: clock, duration: 301), context: context)
        XCTAssertEqual(long, .rejected(.invalidRequest))
        let wrong = await controller.register(try request(.init(sessionID: UUID(), index: 0), clock: clock), context: context)
        XCTAssertEqual(wrong, .rejected(.wrongContext))
        let future = try BoundToolApprovalRequest(requestID: "future", originRound: context.originRound, actionDescription: "synthetic",
            canonicalActionBytes: Data([1]), risk: .low, createdAt: clock.now.addingTimeInterval(1), expiresAt: clock.now.addingTimeInterval(2))
        let futureResult = await controller.register(future, context: context)
        XCTAssertEqual(futureResult, .rejected(.invalidRequest))
    }

    func testCombiningUnicodeAndHugeActionCannotBypassByteBounds() async throws {
        let clock = ApprovalTestClock(), round = RoundToken(sessionID: UUID(), index: 0)
        let huge = "a" + String(repeating: "\u{301}", count: 9_000)
        XCTAssertThrowsError(try request(round, clock: clock, id: huge))
        XCTAssertThrowsError(try request(round, clock: clock, description: huge))
        XCTAssertThrowsError(try request(round, clock: clock, action: Data(repeating: 0, count: 65_537)))
        let (controller, _, _, presentation) = try await fixture()
        let invalidDisplay = ApprovalDisplayedContent(requestID: presentation.content.requestID, actionDescription: huge,
            actionDigest: presentation.content.actionDigest, risk: .low, expiresAt: presentation.content.expiresAt)
        let display = await controller.acknowledgePresentation(binding: presentation.binding, displayed: invalidDisplay, evidence: .trustedHostDisplayedExactContent)
        XCTAssertEqual(display, .rejected(.presentationMismatch))
        await present(controller, presentation)
        let challenge = try await capture(controller, presentation)
        let final = await controller.submitVoiceFinal(token: challenge.token, text: huge)
        XCTAssertEqual(final, .rejected(.ambiguousVoice))
    }

    func testExplicitLowRiskExactModeAcceptsApprovedDuringTrustedActiveConversationWithoutButton() async throws {
        let (controller, _, context, presentation) = try await fixture(policy: .voiceExact)
        await present(controller, presentation)
        let start = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .activeUserConversationAndPresentedRequest)
        guard case .captureStarted(let capture) = start else { return XCTFail("Expected host-armed dedicated exact confirmation") }
        XCTAssertEqual(capture.policy, .voiceExact)
        XCTAssertEqual(capture.approvePhrase, "批准了")
        let result = await controller.submitVoiceFinal(token: capture.token, text: "批准了")
        guard case .resolved(let decision) = result else { return XCTFail("Expected exact-mode decision") }
        XCTAssertEqual(decision.source, .voiceExact(capture.token))
        XCTAssertEqual(decision.receipt.resolution, .approved)
        XCTAssertEqual(decision.receipt.round, context.originRound)
        let snapshot = await controller.currentSnapshot()
        XCTAssertEqual(snapshot.context?.originRound, context.originRound, "A confirmation capture is not a new ordinary conversation round")
    }

    func testSameApprovedPhrasePassesExactButFailsChallengeMode() async throws {
        for policy in [ApprovalConfirmationPolicy.voiceExact, .voiceChallenge] {
            let (controller, _, _, presentation) = try await fixture(policy: policy)
            await present(controller, presentation)
            let capture = try await capture(controller, presentation)
            let result = await controller.submitVoiceFinal(token: capture.token, text: "批准了")
            if policy == .voiceExact { XCTAssertTrue(isNewApproval(result)) }
            else { XCTAssertEqual(result, .rejected(.ambiguousVoice)) }
        }
    }

    func testExactModeOnlyAcceptsFiniteLiteralPhrasesNotFuzzyOrTelevisionContext() async throws {
        for phrase in ["好的", "可以", "电视里说批准了", "我不确定是否批准了", "批准了！", "批准", "approve"] {
            let (controller, _, _, presentation) = try await fixture(policy: .voiceExact)
            await present(controller, presentation)
            let capture = try await capture(controller, presentation)
            let result = await controller.submitVoiceFinal(token: capture.token, text: phrase)
            XCTAssertEqual(result, .rejected(.ambiguousVoice))
        }
        for phrase in ["拒绝", "不批准"] {
            let (controller, _, _, presentation) = try await fixture(policy: .voiceExact)
            await present(controller, presentation)
            let capture = try await capture(controller, presentation)
            let result = await controller.submitVoiceFinal(token: capture.token, text: phrase)
            guard case .resolved(let decision) = result else { XCTFail("Expected literal denial"); continue }
            XCTAssertEqual(decision.receipt.resolution, .denied)
        }
    }

    func testExactModeCannotArmFromBackgroundOrUnpresentedConversationAssertion() async throws {
        let (controller, _, _, presentation) = try await fixture(policy: .voiceExact)
        let unpresented = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .activeUserConversationAndPresentedRequest)
        XCTAssertEqual(unpresented, .rejected(.presentationRequired))
        await present(controller, presentation)
        let background = await controller.beginVoiceCapture(binding: presentation.binding, interaction: .unconfirmed)
        XCTAssertEqual(background, .rejected(.trustedInteractionRequired))
        let snapshot = await controller.currentSnapshot()
        XCTAssertNil(snapshot.capture); XCTAssertNil(snapshot.decision)
    }

    func testExactModeOldTokenWrongRequestAndDisconnectedInputStayRejected() async throws {
        let (controller, clock, context, presentation) = try await fixture(policy: .voiceExact)
        await present(controller, presentation)
        let first = try await capture(controller, presentation)
        _ = await controller.cancelCapture(first.token)
        let second = try await capture(controller, presentation)
        let stale = await controller.submitVoiceFinal(token: first.token, text: "批准了")
        XCTAssertEqual(stale, .rejected(.wrongCapture))
        _ = await controller.submitVoiceFinal(token: second.token, text: "拒绝")
        let next = try await register(controller, context: context, clock: clock, policy: .voiceExact, id: "different-pending-request")
        await present(controller, next)
        let wrongRequest = await controller.submitVoiceFinal(token: second.token, text: "批准了")
        XCTAssertEqual(wrongRequest, .rejected(.wrongBinding))
        let current = try await capture(controller, next)
        _ = await controller.invalidateContext(context, reason: .disconnection)
        let disconnected = await controller.submitVoiceFinal(token: current.token, text: "批准了")
        XCTAssertEqual(disconnected, .rejected(.contextRequired))
    }

    func testExactModeCannotUseExpiredCaptureOrReplayNewDecision() async throws {
        let (controller, clock, _, presentation) = try await fixture(policy: .voiceExact, configuration: .init(captureWindowSeconds: 1))
        await present(controller, presentation)
        let expired = try await capture(controller, presentation)
        clock.advance(1)
        let late = await controller.submitVoiceFinal(token: expired.token, text: "批准了")
        XCTAssertEqual(late, .rejected(.captureExpired))
        let current = try await capture(controller, presentation)
        let result = await controller.submitVoiceFinal(token: current.token, text: "确认批准")
        guard case .resolved(let decision) = result else { return XCTFail("Expected one exact decision") }
        let duplicate = await controller.submitVoiceFinal(token: current.token, text: "批准了")
        XCTAssertEqual(duplicate, .alreadyResolved(decision))
    }
}

/// Test-only wall clock. Every read/write is under the same lock; no device or system-clock mutation.
private final class ApprovalTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(seconds) }
}
