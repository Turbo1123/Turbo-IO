import Foundation
import RayNeoSession

/// This executable fabricates its connection, ordinary round, action, display and ASR final.
/// It is NOT SessionRuntime integration and must never be presented as glasses or Codex validation.
@main
struct ApprovalDemo {
    enum DemoFailure: Error { case unexpectedSyntheticState }
    static func main() async throws {
        let host = SyntheticApprovalHost()
        try await host.verifyExactVoiceWithoutExtraButton()
        try await host.verifyStrictChallenge()
        try await host.verifyHighRiskPhoneOnly()
        try await host.verifyOrdinaryNextRoundInvalidatesCapture()
        try await host.verifyHostExpiryScheduling()
        print("SYNTHETIC ONLY: exact voice, challenge, phone policy, ordinary-round invalidation and host expiry checks passed. No microphone, model, transport, network or tool execution.")
    }
}

private actor SyntheticApprovalHost {
    private let controller = ApprovalSubsessionController(configuration: .init(captureWindowSeconds: 1))
    private var ordinaryRound = RoundToken(sessionID: UUID(), index: 0)
    private let syntheticConnectionGeneration = UUID()
    private var ordinaryPaused = false
    private var context: ApprovalContextToken?
    private var syntheticRequestCounter = 0

    private func pauseAndPresent(policy: ApprovalConfirmationPolicy, risk: ApprovalRisk = .low) async throws -> ApprovalPresentation {
        guard !ordinaryPaused, context == nil else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        // Synthetic host has no jobs. A real host must cancel AND await original ASR/model/player exits here.
        ordinaryPaused = true
        guard case .established(let token) = await controller.beginSuspendedContext(originRound: ordinaryRound,
            connectionGeneration: syntheticConnectionGeneration, evidence: .ordinaryWorkPausedAndDrained)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        context = token; syntheticRequestCounter += 1
        let now = Date()
        let request = try BoundToolApprovalRequest(requestID: "synthetic-\(syntheticRequestCounter)", originRound: ordinaryRound,
            actionDescription: "仅创建一份合成测试便笺，不实际执行", canonicalActionBytes: Data("{\"synthetic\":true}".utf8),
            risk: risk, createdAt: now, expiresAt: now.addingTimeInterval(30))
        guard case .registered(let presentation) = await controller.register(request, context: token, policy: policy)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        // No UI is opened. This is an explicit synthetic assertion of exact presentation, not a device ACK.
        guard await controller.acknowledgePresentation(binding: presentation.binding, displayed: presentation.content,
            evidence: .trustedHostDisplayedExactContent) == .accepted else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        return presentation
    }

    private func arm(_ presentation: ApprovalPresentation) async throws -> ApprovalCapturePrompt {
        guard ordinaryPaused,
              case .captureStarted(let prompt) = await controller.beginVoiceCapture(binding: presentation.binding,
                interaction: .activeUserConversationAndPresentedRequest)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        return prompt
    }

    private func ordinaryNextRound() async throws {
        guard let old = context else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        // Ordering matters: invalidate approval BEFORE advancing/accepting ordinary audio.
        _ = await controller.invalidateContext(old, reason: .normalNextRound)
        context = nil; ordinaryPaused = false
        ordinaryRound = .init(sessionID: ordinaryRound.sessionID, index: ordinaryRound.index + 1)
    }

    func verifyExactVoiceWithoutExtraButton() async throws {
        let presentation = try await pauseAndPresent(policy: .voiceExact)
        let prompt = try await arm(presentation)
        guard case .resolved(let decision) = await controller.submitVoiceFinal(token: prompt.token, text: "批准了"),
              decision.receipt.resolution == .approved,
              decision.binding.actionDigest == presentation.binding.actionDigest,
              await controller.submitVoiceFinal(token: prompt.token, text: "批准了") == .alreadyResolved(decision)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        // Intentionally do not execute or send this decision anywhere.
        try await ordinaryNextRound()
    }

    func verifyStrictChallenge() async throws {
        let presentation = try await pauseAndPresent(policy: .voiceChallenge)
        let first = try await arm(presentation)
        guard await controller.submitVoiceFinal(token: first.token, text: "批准了") == .rejected(.ambiguousVoice)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        let second = try await arm(presentation)
        guard case .resolved(let decision) = await controller.submitVoiceFinal(token: second.token, text: second.approvePhrase),
              decision.receipt.resolution == .approved else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        try await ordinaryNextRound()
    }

    func verifyHighRiskPhoneOnly() async throws {
        let presentation = try await pauseAndPresent(policy: .voiceExact, risk: .high)
        guard presentation.effectivePolicy == .phoneRequired,
              await controller.beginVoiceCapture(binding: presentation.binding,
                interaction: .activeUserConversationAndPresentedRequest) == .rejected(.phoneRequired),
              case .resolved(let decision) = await controller.confirmOnPhone(binding: presentation.binding,
                displayed: presentation.content, choice: .deny, evidence: .foregroundExplicitConfirmation),
              decision.receipt.resolution == .denied else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        try await ordinaryNextRound()
    }

    func verifyOrdinaryNextRoundInvalidatesCapture() async throws {
        let presentation = try await pauseAndPresent(policy: .voiceExact)
        let prompt = try await arm(presentation)
        try await ordinaryNextRound()
        guard await controller.submitVoiceFinal(token: prompt.token, text: "批准了") == .rejected(.contextRequired)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
    }

    func verifyHostExpiryScheduling() async throws {
        let presentation = try await pauseAndPresent(policy: .voiceExact)
        let prompt = try await arm(presentation)
        // Host-owned cancellable timer. No real capture exists to stop in this executable.
        let expiry = Task { [controller] in
            try await Task.sleep(nanoseconds: 1_050_000_000)
            return await controller.expireDue()
        }
        let snapshot = try await expiry.value
        guard snapshot.capture == nil,
              await controller.submitVoiceFinal(token: prompt.token, text: "批准了") == .rejected(.captureExpired)
        else { throw ApprovalDemo.DemoFailure.unexpectedSyntheticState }
        try await ordinaryNextRound()
    }
}
