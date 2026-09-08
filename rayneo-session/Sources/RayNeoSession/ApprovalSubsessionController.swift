import Foundation

/// Independent approval-only actor. No microphone, provider, timer, wire command or tool is started.
/// The host MUST pause ordinary work, own expiry scheduling, and atomically forward invalidation.
public actor ApprovalSubsessionController {
    public let configuration: ApprovalSubsessionConfiguration
    private var state: ApprovalSubsessionState
    public init(configuration: ApprovalSubsessionConfiguration = .init(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration; state = .init(configuration: configuration, clock: clock)
    }
    public func beginSuspendedContext(originRound: RoundToken, connectionGeneration: UUID,
                                      evidence: ApprovalHostSuspensionEvidence) -> ApprovalContextResult {
        state.beginSuspendedContext(originRound: originRound, connectionGeneration: connectionGeneration, evidence: evidence)
    }
    public func register(_ request: BoundToolApprovalRequest, context: ApprovalContextToken,
                         policy: ApprovalConfirmationPolicy = .phoneRequired) -> ApprovalSubsessionRegistration {
        state.register(request, context: context, policy: policy)
    }
    public func acknowledgePresentation(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                                         evidence: ApprovalPresentationEvidence) -> ApprovalSubsessionResult {
        state.acknowledgePresentation(binding: binding, displayed: displayed, evidence: evidence)
    }
    public func beginVoiceCapture(binding: ApprovalBinding, interaction: ApprovalCaptureInteraction) -> ApprovalSubsessionResult {
        state.beginVoiceCapture(binding: binding, interaction: interaction)
    }
    public func submitVoiceFinal(token: ApprovalCaptureToken, text: String) -> ApprovalSubsessionResult {
        state.submitVoiceFinal(token: token, text: text)
    }
    public func confirmOnPhone(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                               choice: ToolApprovalChoice, evidence: ApprovalPhoneEvidence) -> ApprovalSubsessionResult {
        state.confirmOnPhone(binding: binding, displayed: displayed, choice: choice, evidence: evidence)
    }
    public func cancelCapture(_ token: ApprovalCaptureToken) -> ApprovalSubsessionResult { state.cancelCapture(token) }
    public func invalidateContext(_ context: ApprovalContextToken, reason: ApprovalContextInvalidation) -> ApprovalSubsessionResult {
        state.invalidateContext(context, reason: reason)
    }
    public func expireDue() -> ApprovalSubsessionSnapshot { state.expireDue() }
    public func currentSnapshot() -> ApprovalSubsessionSnapshot { state.currentSnapshot() }
}
