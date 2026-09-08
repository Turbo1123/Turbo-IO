import XCTest
import RayNeoSession
import RayNeoSessionRuntime
import RayNeoSessionRuntimeTestSupport

// Consumes actual synthetic PCM chunks through the Runtime's dedicated stream.
// Does not recognize speech, contact providers, or execute a tool.
private actor ConfirmationFixtureASR: ApprovalASRProvider {
    nonisolated let source: ASRSource = .local
    let answer: String
    private(set) var requests: [ApprovalASRRequest] = []
    private(set) var bytes = 0
    init(answer: String = "批准了") { self.answer = answer }
    func recognize(_ request: ApprovalASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>) async throws -> AsyncThrowingStream<ASRTranscript, Error> {
        requests.append(request)
        for try await chunk in audio { try Task.checkCancellation(); bytes += chunk.data.count }
        try Task.checkCancellation()
        let pair = AsyncThrowingStream<ASRTranscript, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        pair.continuation.yield(.init(revision: 1, text: answer, isFinal: true))
        pair.continuation.finish()
        return pair.stream
    }
    func cancel(capture: ApprovalCaptureToken) async {}
}

final class ApprovalRuntimeIntegrationTests: XCTestCase {
    enum Failure: Error { case timeout, noCapture }
    private let pcm = AudioChunk(data: Data([0, 0, 1, 0]), format: .pcm16LE(sampleRate: 16_000, channels: 1))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func until(_ predicate: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw Failure.timeout
    }
    private func prepared(policy: ApprovalConfirmationPolicy = .voiceExact, answer: String = "批准了") async throws
        -> (SessionRuntime, ConfirmationFixtureASR, SyntheticConversationModel, RecordingGlassesTransport, ApprovalPresentation) {
        let asr = ConfirmationFixtureASR(answer: answer), model = SyntheticConversationModel()
        let transport = RecordingGlassesTransport(), clockDate = now
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: model,
            transport: transport, wallTime: { clockDate }, localApprovalASR: asr))
        _ = await runtime.send(.connected)
        let round = await runtime.send(.wake).session.currentRound!
        _ = await runtime.send(.audioReceived(round: round, chunk: pcm))
        _ = await runtime.send(.audioEnded(round: round))
        try await until { await runtime.currentSnapshot().session.phase == .awaitingNextRound }
        let request = try BoundToolApprovalRequest(requestID: "synthetic-runtime-request", originRound: round,
            actionDescription: "仅显示合成标记，不执行工具", canonicalActionBytes: Data("display-only".utf8),
            risk: .low, createdAt: now, expiresAt: now.addingTimeInterval(60))
        let admission = await runtime.beginToolApproval(request: request, policy: policy)
        guard case .preparing = admission else { XCTFail("Expected preparing, got \(admission)"); throw Failure.noCapture }
        try await until { await runtime.currentSnapshot().approval.presentation != nil }
        let presentation = await runtime.currentSnapshot().approval.presentation!
        return (runtime, asr, model, transport, presentation)
    }
    private func capture(_ runtime: SessionRuntime, _ presentation: ApprovalPresentation) async throws -> ApprovalCaptureToken {
        let shown = await runtime.acknowledgeToolApprovalPresentation(binding: presentation.binding,
            displayed: presentation.content, evidence: .trustedHostDisplayedExactContent)
        XCTAssertEqual(shown, .accepted)
        try await until {
            let snapshot = await runtime.currentSnapshot()
            return snapshot.pendingTransportCommands == 0 && snapshot.activeCleanupTasks == 0
        }
        let result = await runtime.beginToolApprovalCapture(binding: presentation.binding, interaction: .explicitUserButtonOrGesture)
        guard case .captureStarted(let prompt) = result else { XCTFail("Expected capture, got \(result)"); throw Failure.noCapture }
        _ = await runtime.sendApprovalAudio(capture: prompt.token, chunk: pcm)
        _ = await runtime.endApprovalAudio(capture: prompt.token)
        return prompt.token
    }

    func testDedicatedAudioProducesOneBoundDecisionWithoutAnotherModelCall() async throws {
        let (runtime, asr, model, transport, presentation) = try await prepared()
        let capture = try await capture(runtime, presentation)
        try await until { await runtime.currentSnapshot().approval.hasPendingDecision }
        let decision = await runtime.takePendingApprovalDecision()
        XCTAssertEqual(decision?.receipt.resolution, .approved)
        XCTAssertEqual(decision?.binding, presentation.binding)
        let replay = await runtime.takePendingApprovalDecision(), bytes = await asr.bytes
        let requests = await asr.requests, modelRequests = await model.requests
        XCTAssertNil(replay); XCTAssertEqual(bytes, 4)
        XCTAssertEqual(requests.map(\.capture), [capture]); XCTAssertEqual(modelRequests.count, 1)
        let commands = await transport.admittedCommands
        XCTAssertTrue(commands.contains(.showApproval(presentation)))
        let finish = await runtime.finishToolApproval(binding: presentation.binding)
        XCTAssertEqual(finish, .accepted)
        try await until { await runtime.currentSnapshot().approval.phase == .inactive }
        let snapshot = await runtime.currentSnapshot()
        XCTAssertEqual(snapshot.session.phase, .awaitingNextRound)
        XCTAssertEqual(snapshot.session.currentRound, presentation.binding.context.originRound)
        _ = await runtime.shutdown()
    }

    func testDefaultPhonePolicyDoesNotStartConfirmationASR() async throws {
        let (runtime, asr, _, _, presentation) = try await prepared(policy: .phoneRequired)
        _ = await runtime.acknowledgeToolApprovalPresentation(binding: presentation.binding,
            displayed: presentation.content, evidence: .trustedHostDisplayedExactContent)
        let confirmation = await runtime.confirmToolApprovalOnPhone(binding: presentation.binding,
            displayed: presentation.content, choice: .approve, evidence: .foregroundExplicitConfirmation)
        XCTAssertEqual(confirmation, .accepted)
        let decision = await runtime.takePendingApprovalDecision(), requests = await asr.requests
        XCTAssertEqual(decision?.receipt.resolution, .approved); XCTAssertTrue(requests.isEmpty)
        _ = await runtime.shutdown()
    }

    func testUnknownConfirmationFinalDoesNotProduceApprovalOrCallModel() async throws {
        let (runtime, asr, model, _, presentation) = try await prepared(answer: "随便吧")
        _ = try await capture(runtime, presentation)
        try await until {
            let bytes = await asr.bytes, snapshot = await runtime.currentSnapshot()
            return bytes == 4 && snapshot.approval.capture == nil
        }
        let decision = await runtime.takePendingApprovalDecision(), requests = await model.requests
        XCTAssertNil(decision); XCTAssertEqual(requests.count, 1)
        _ = await runtime.shutdown()
    }

    func testDisconnectInvalidatesDecisionBeforeHostClaimsIt() async throws {
        let (runtime, _, _, _, presentation) = try await prepared()
        _ = try await capture(runtime, presentation)
        try await until { await runtime.currentSnapshot().approval.hasPendingDecision }
        _ = await runtime.send(.disconnected)
        let decision = await runtime.takePendingApprovalDecision()
        XCTAssertNil(decision)
        _ = await runtime.shutdown()
    }
}
