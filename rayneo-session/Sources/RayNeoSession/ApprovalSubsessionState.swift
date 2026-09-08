import Foundation

/// Synchronous state shared by the public actor and SessionRuntime. The owner must serialize access.
@_spi(ApprovalRuntime) public struct ApprovalSubsessionState: Sendable {
    private struct ActiveRequest {
        let request: BoundToolApprovalRequest
        let presentation: ApprovalPresentation
        var presented = false
        var attempts: UInt64 = 0
        var usedChallenges: Set<String> = []
        var capture: ApprovalCapturePrompt?
        var lastCapture: ApprovalCaptureToken?
        var decision: ApprovalDecision?
    }
    public let configuration: ApprovalSubsessionConfiguration
    private let clock: @Sendable () -> Date
    private var gate: ToolApprovalGate
    private var boundOnlyIDs: Set<Data> = []
    private var pendingLegacy: [Data: RoundToken] = [:]
    private var registeredIDs: Set<String> = []
    private var context: ApprovalContextToken?
    private var usedRounds: Set<RoundToken> = []
    private var active: ActiveRequest?
    private var phase: ApprovalSubsessionPhase = .inactive
    private var lastTime: Date?
    private var clockFailed = false
    private var lastRejection: ApprovalSubsessionRejection?
    private var lastInvalidation: ApprovalContextInvalidation?

    public init(configuration: ApprovalSubsessionConfiguration = .init(), ledgerCapacity: Int? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration; self.clock = clock
        gate = .init(capacity: ledgerCapacity ?? configuration.requestCapacity)
    }

    public var hasPendingLegacyRequests: Bool { !pendingLegacy.isEmpty }

    public mutating func boundAdmissionRejection(_ request: BoundToolApprovalRequest) -> ApprovalSubsessionRejection? {
        guard let now = checkedNow() else { return .invalidClock }
        guard context == nil, pendingLegacy.isEmpty else { return .requestBusy }
        guard !registeredIDs.contains(request.requestID) else { return .duplicateRequestID }
        guard !usedRounds.contains(request.originRound) else { return .contextAlreadyUsed }
        guard usedRounds.count < configuration.contextCapacity, gate.entryCount < gate.capacity,
              boundOnlyIDs.count < configuration.requestCapacity else { return .capacityReached }
        guard request.createdAt <= now, request.expiresAt > now,
              request.expiresAt.timeIntervalSince(request.createdAt) <= configuration.maximumRequestLifetimeSeconds else { return .invalidRequest }
        return nil
    }

    public mutating func registerLegacy(_ request: ToolApprovalRequest) -> ToolApprovalRegistration {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        guard context == nil else { return .rejected(.confirmationRequired) }
        let result = gate.register(request, now: now)
        if result == .registered {
            pendingLegacy[Data(request.requestID.utf8)] = request.round; registeredIDs.insert(request.requestID)
        }
        return result
    }

    public mutating func resolveLegacy(requestID: String, round: RoundToken, choice: ToolApprovalChoice,
                                       evidence: ToolConfirmationEvidence) -> ToolApprovalResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        guard context == nil, !boundOnlyIDs.contains(Data(requestID.utf8)) else { return .rejected(.confirmationRequired) }
        let result = gate.resolve(requestID: requestID, round: round, choice: choice, evidence: evidence, now: now)
        if case .resolved = result { pendingLegacy.removeValue(forKey: Data(requestID.utf8)) }
        return result
    }

    public mutating func invalidateOrdinaryRound(_ round: RoundToken, reason: ApprovalContextInvalidation) {
        let now = checkedNow() ?? lastTime ?? Date(timeIntervalSince1970: 0)
        if context?.originRound == round { invalidateCurrent(reason: reason, now: now) }
        else { _ = gate.invalidate(round: round, now: now) }
        pendingLegacy = pendingLegacy.filter { $0.value != round }
    }

    public mutating func isDecisionDispatchable(_ binding: ApprovalBinding) -> Bool {
        guard let now = checkedNow() else { return false }
        refresh(now)
        return context == binding.context && active?.presentation.binding == binding
            && active?.decision != nil && now < (active?.request.expiresAt ?? now)
    }

    public mutating func beginSuspendedContext(originRound: RoundToken, connectionGeneration: UUID,
                                      evidence: ApprovalHostSuspensionEvidence) -> ApprovalContextResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        guard case .ordinaryWorkPausedAndDrained = evidence else { return rejectContext(.hostSuspensionRequired) }
        guard context == nil else { return rejectContext(.contextBusy) }
        guard !usedRounds.contains(originRound) else { return rejectContext(.contextAlreadyUsed) }
        guard usedRounds.count < configuration.contextCapacity else { return rejectContext(.capacityReached) }
        let token = ApprovalContextToken(originRound: originRound, connectionGeneration: connectionGeneration)
        usedRounds.insert(originRound); context = token; active = nil; phase = .idle
        lastInvalidation = nil; lastRejection = nil
        return .established(token)
    }

    public mutating func register(_ request: BoundToolApprovalRequest, context token: ApprovalContextToken,
                         policy: ApprovalConfirmationPolicy = .phoneRequired) -> ApprovalSubsessionRegistration {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        guard context == token, request.originRound == token.originRound else { return rejectRegistration(.wrongContext) }
        guard active == nil || active?.decision != nil else { return rejectRegistration(.requestBusy) }
        guard boundOnlyIDs.count < configuration.requestCapacity else { return rejectRegistration(.capacityReached) }
        guard request.createdAt <= now, request.expiresAt > now,
              request.expiresAt.timeIntervalSince(request.createdAt) <= configuration.maximumRequestLifetimeSeconds,
              request.actionDigest == ApprovalActionDigest(hashing: request.canonicalActionBytes) else { return rejectRegistration(.invalidRequest) }
        switch gate.register(request.legacyRequest, now: now) {
        case .rejected(let rejection):
            let mapped: ApprovalSubsessionRejection = rejection == .duplicateRequestID ? .duplicateRequestID
                : rejection == .capacityReached ? .capacityReached : .gateRejected
            return rejectRegistration(mapped)
        case .registered: break
        }
        boundOnlyIDs.insert(Data(request.requestID.utf8))
        registeredIDs.insert(request.requestID)
        let effectivePolicy: ApprovalConfirmationPolicy = request.risk == .high ? .phoneRequired : policy
        let binding = ApprovalBinding(request: request, context: token, policy: effectivePolicy)
        let presentation = ApprovalPresentation(request: request, binding: binding, policy: effectivePolicy)
        active = .init(request: request, presentation: presentation); phase = .awaitingPresentation; lastRejection = nil
        return .registered(presentation)
    }

    public mutating func acknowledgePresentation(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                                         evidence: ApprovalPresentationEvidence) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        if let failure = validate(binding) { return reject(failure) }
        if let decision = active?.decision { return .alreadyResolved(decision) }
        guard case .trustedHostDisplayedExactContent = evidence else { return reject(.explicitPresentationRequired) }
        guard bounded(displayed), active?.presentation.content == displayed else { return reject(.presentationMismatch) }
        guard phase == .awaitingPresentation else { return reject(.requestBusy) }
        active?.presented = true
        phase = active?.presentation.effectivePolicy == .phoneRequired ? .awaitingPhoneConfirmation : .awaitingToolApproval
        lastRejection = nil; return .accepted
    }

    public mutating func beginVoiceCapture(binding: ApprovalBinding, interaction: ApprovalCaptureInteraction) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        if let failure = validate(binding) { return reject(failure) }
        if let decision = active?.decision { return .alreadyResolved(decision) }
        guard var entry = active, entry.presented else { return reject(.presentationRequired) }
        guard entry.presentation.effectivePolicy != .phoneRequired, entry.request.risk == .low else { return reject(.phoneRequired) }
        switch interaction {
        case .explicitUserButtonOrGesture, .activeUserConversationAndPresentedRequest: break
        case .unconfirmed: return reject(.trustedInteractionRequired)
        }
        guard entry.capture == nil else { return reject(.requestBusy) }
        guard entry.attempts < configuration.maximumCaptureAttempts else { return reject(.attemptsExhausted) }
        var digits: String?
        if entry.presentation.effectivePolicy == .voiceChallenge {
            for _ in 0..<16 {
                let value = String(Int.random(in: 10_000_000...99_999_999))
                if !entry.usedChallenges.contains(value) { digits = value; break }
            }
            guard let value = digits else { return reject(.challengeUnavailable) }
            entry.usedChallenges.insert(value)
        }
        entry.attempts += 1
        let deadline = min(entry.request.expiresAt, now.addingTimeInterval(configuration.captureWindowSeconds))
        let token = ApprovalCaptureToken(binding: binding, generation: entry.attempts, expiresAt: deadline)
        let challenge = ApprovalCapturePrompt(token: token, policy: entry.presentation.effectivePolicy, digits: digits)
        entry.capture = challenge; entry.lastCapture = token; active = entry; phase = .capturingConfirmation
        lastRejection = nil; return .captureStarted(challenge)
    }

    /// Only a final from this armed capture is accepted. Never run VoiceApprovalPhrase/LLM on ambient audio.
    public mutating func submitVoiceFinal(token: ApprovalCaptureToken, text: String) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        if let failure = validate(token.binding) { return reject(failure) }
        if let decision = active?.decision {
            let consumed: ApprovalCaptureToken?
            switch decision.source {
            case .voiceExact(let value), .voiceChallenge(let value): consumed = value
            default: consumed = nil
            }
            guard consumed == token else { return reject(.wrongCapture) }
            return .alreadyResolved(decision)
        }
        guard let capture = active?.capture else {
            return reject(active?.lastCapture == token && now >= token.expiresAt ? .captureExpired : .captureRequired)
        }
        guard capture.token == token else { return reject(.wrongCapture) }
        // Every final consumes this capture, even if it is ambiguous. Retry needs a new gesture/token.
        active?.capture = nil; phase = .awaitingToolApproval
        guard TextBounds.contains(text, maximumCharacters: 64, maximumUTF8Bytes: 256) else { return reject(.ambiguousVoice) }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let choice: ToolApprovalChoice
        if capture.acceptedApprovalPhrases.contains(where: { phrase.utf8.elementsEqual($0.utf8) }) { choice = .approve }
        else if capture.acceptedDenialPhrases.contains(where: { phrase.utf8.elementsEqual($0.utf8) }) { choice = .deny }
        else { return reject(.ambiguousVoice) }
        let source: ApprovalDecisionSource = capture.policy == .voiceExact ? .voiceExact(token) : .voiceChallenge(token)
        return resolve(binding: token.binding, choice: choice, source: source, now: now)
    }

    public mutating func confirmOnPhone(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                               choice: ToolApprovalChoice, evidence: ApprovalPhoneEvidence) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        if let failure = validate(binding) { return reject(failure) }
        if let decision = active?.decision { return .alreadyResolved(decision) }
        guard active?.presented == true else { return reject(.presentationRequired) }
        guard bounded(displayed), displayed == active?.presentation.content else { return reject(.presentationMismatch) }
        guard case .foregroundExplicitConfirmation = evidence else { return reject(.confirmationRequired) }
        return resolve(binding: binding, choice: choice, source: .phone, now: now)
    }

    public mutating func cancelCapture(_ token: ApprovalCaptureToken) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        if let failure = validate(token.binding) { return reject(failure) }
        guard active?.capture?.token == token else { return reject(.wrongCapture) }
        active?.capture = nil; phase = .awaitingToolApproval; lastRejection = nil
        return .accepted
    }

    /// Host calls on EVERY ordinary nextRound/interrupt/exit/disconnect before handling more audio.
    public mutating func invalidateContext(_ token: ApprovalContextToken, reason: ApprovalContextInvalidation) -> ApprovalSubsessionResult {
        guard let now = checkedNow() else { return .rejected(.invalidClock) }
        refresh(now)
        guard context == token else { return reject(.wrongContext) }
        let wasResolved = active?.decision != nil
        invalidateCurrent(reason: reason, now: now)
        if let decision = active?.decision { return wasResolved ? .alreadyResolved(decision) : .resolved(decision) }
        return .accepted
    }

    /// The host owns actual timer/capture cancellation. All decision entrances also enforce deadlines.
    public mutating func expireDue() -> ApprovalSubsessionSnapshot { currentSnapshot() }

    public mutating func currentSnapshot() -> ApprovalSubsessionSnapshot {
        if let now = checkedNow() { refresh(now) }
        return storedSnapshot
    }

    public var storedSnapshot: ApprovalSubsessionSnapshot {
        .init(phase: phase, context: context, presentation: active?.presentation, capture: active?.capture,
                     decision: active?.decision, captureAttempts: active?.attempts ?? 0,
                     registeredRequestCount: gate.entryCount, usedContextCount: usedRounds.count,
                     lastRejection: lastRejection, lastInvalidation: lastInvalidation)
    }

    private mutating func validate(_ binding: ApprovalBinding) -> ApprovalSubsessionRejection? {
        guard let context else { return .contextRequired }
        guard context == binding.context else { return .wrongContext }
        guard let active else { return .unknownRequest }
        return active.presentation.binding == binding ? nil : .wrongBinding
    }

    private mutating func bounded(_ content: ApprovalDisplayedContent) -> Bool {
        TextBounds.contains(content.requestID, maximumCharacters: 256, maximumUTF8Bytes: ToolApprovalGate.maximumRequestIDUTF8Bytes)
            && TextBounds.contains(content.actionDescription, maximumCharacters: 4_096,
                                   maximumUTF8Bytes: ToolApprovalGate.maximumActionDescriptionUTF8Bytes)
    }

    private mutating func resolve(binding: ApprovalBinding, choice: ToolApprovalChoice, source: ApprovalDecisionSource, now: Date) -> ApprovalSubsessionResult {
        let result = gate.resolve(requestID: binding.requestID, round: binding.context.originRound,
                                  choice: choice, evidence: .explicitUserConfirmation, now: now)
        switch result {
        case .resolved(let receipt):
            let decision = ApprovalDecision(binding: binding, receipt: receipt, source: source)
            active?.decision = decision; active?.capture = nil; phase = .resolved; lastRejection = nil
            return .resolved(decision)
        case .alreadyResolved:
            if let decision = active?.decision { return .alreadyResolved(decision) }
            return reject(.gateRejected)
        case .rejected: return reject(.gateRejected)
        }
    }

    private mutating func refresh(_ now: Date) {
        guard let entry = active, entry.decision == nil else { return }
        if now >= entry.request.expiresAt {
            _ = resolve(binding: entry.presentation.binding, choice: .deny, source: .expiration, now: now)
        } else if let capture = entry.capture, now >= capture.token.expiresAt {
            active?.capture = nil; phase = .awaitingToolApproval; lastRejection = .captureExpired
        }
    }

    private mutating func checkedNow() -> Date? {
        guard !clockFailed else { return nil }
        let now = clock()
        guard now.timeIntervalSinceReferenceDate.isFinite, lastTime.map({ now >= $0 }) ?? true else {
            clockFailed = true; lastRejection = .invalidClock
            invalidateCurrent(reason: .clockFailure, now: lastTime ?? Date(timeIntervalSince1970: 0))
            return nil
        }
        lastTime = now; return now
    }

    private mutating func invalidateCurrent(reason: ApprovalContextInvalidation, now: Date) {
        guard let context else { return }
        let receipts = gate.invalidate(round: context.originRound, now: now)
        if let entry = active, entry.decision == nil,
           let receipt = receipts.first(where: { $0.requestID.utf8.elementsEqual(entry.request.requestID.utf8) }) {
            active?.decision = .init(binding: entry.presentation.binding, receipt: receipt, source: .invalidation(reason))
        }
        active?.capture = nil; self.context = nil; phase = .inactive; lastInvalidation = reason
    }

    private mutating func reject(_ reason: ApprovalSubsessionRejection) -> ApprovalSubsessionResult {
        lastRejection = reason; return .rejected(reason)
    }
    private mutating func rejectContext(_ reason: ApprovalSubsessionRejection) -> ApprovalContextResult {
        lastRejection = reason; return .rejected(reason)
    }
    private mutating func rejectRegistration(_ reason: ApprovalSubsessionRejection) -> ApprovalSubsessionRegistration {
        lastRejection = reason; return .rejected(reason)
    }
}
