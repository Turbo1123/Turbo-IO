import Foundation
@_spi(ApprovalRuntime) import RayNeoSession

extension SessionRuntime {
    struct ApprovalOperation {
        let id: UUID
        let request: BoundToolApprovalRequest
        let policy: ApprovalConfirmationPolicy
        var presentation: ApprovalPresentation?
        var capture: ApprovalCapturePrompt?
        var revision: UInt64?
        var inputEnded = false
        var decisionRecorded = false
        var draining = false
        var deferredOrdinaryEvent: VoiceSessionEvent?
    }

    public func beginToolApproval(request: BoundToolApprovalRequest,
                                  policy: ApprovalConfirmationPolicy = .phoneRequired) -> RuntimeApprovalAdmission {
        progressApprovalHandoff()
        guard !stopped, machine.accepts(request.originRound),
              [.generating, .speaking, .awaitingNextRound].contains(machine.snapshot.phase) else { return .rejected(.wrongContext) }
        guard approvalOperation == nil, pendingApprovalDecision == nil else { return .rejected(.requestBusy) }
        if let rejection = approvalCore.boundAdmissionRejection(request) { return .rejected(rejection) }
        let id = UUID()
        approvalOperation = .init(id: id, request: request, policy: policy); lastApprovalRejection = nil
        pendingEvents.append(.suspendForToolApproval(round: request.originRound, suspensionID: id))
        scheduleApprovalTimer(.init(round: request.originRound, stage: .model, approvalID: id),
                              nanoseconds: configuration.approvalHandoffTimeoutMilliseconds * 1_000_000)
        drainEvents(); progressApprovalHandoff(); publish()
        return approvalOperation?.id == id ? .preparing(suspensionID: id) : .rejected(.invalidated)
    }

    public func acknowledgeToolApprovalPresentation(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                                                    evidence: ApprovalPresentationEvidence) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        guard approvalOperation?.presentation?.binding == binding, approvalOperation?.draining == false else { return .rejected(.wrongBinding) }
        let result = approvalCore.acknowledgePresentation(binding: binding, displayed: displayed, evidence: evidence)
        progressApprovalHandoff(); publish(); return withoutDecisionPayload(result)
    }

    public func beginToolApprovalCapture(binding: ApprovalBinding, interaction: ApprovalCaptureInteraction,
                                         source: ASRSource = .local) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        guard approvalOperation?.presentation?.binding == binding, approvalOperation?.draining == false else { return .rejected(.wrongBinding) }
        guard approvalQuiescent else { return .rejected(.requestBusy) }
        let result = approvalCore.beginVoiceCapture(binding: binding, interaction: interaction)
        guard case .captureStarted(let prompt) = result else { publish(); return withoutDecisionPayload(result) }
        let provider = source == .local ? dependencies.localApprovalASR : dependencies.cloudApprovalASR
        guard let provider, provider.source == source,
              source != .cloud || machine.snapshot.networkAvailable else {
            _ = approvalCore.cancelCapture(prompt.token); lastIssue = .missingApprovalASR(source)
            publish(); return .rejected(.captureRequired)
        }
        guard reserveCleanupCapacity() else {
            _ = approvalCore.cancelCapture(prompt.token); drainEvents(); publish(); return .rejected(.capacityReached)
        }
        approvalOperation?.capture = prompt; approvalOperation?.revision = nil; approvalOperation?.inputEnded = false
        startApprovalASR(prompt, source: source, provider: provider)
        scheduleApprovalTimer(approvalKey(prompt.token), nanoseconds: nanosUntil(prompt.token.expiresAt))
        enqueue(.startApprovalCapture(prompt.token), policy: .currentRoundWork)
        drainEvents(); progressApprovalHandoff(); publish()
        return isApprovalCaptureActive(prompt.token) ? result : .rejected(.invalidated)
    }

    @discardableResult
    public func sendApprovalAudio(capture: ApprovalCaptureToken, chunk: AudioChunk) -> SessionRuntimeSnapshot {
        progressApprovalHandoff()
        guard isApprovalCaptureActive(capture), approvalOperation?.inputEnded == false,
              let input = approvalAudioInputs[capture.id] else { return makeSnapshot() }
        guard chunk.isValid else { failApprovalCapture(capture, issue: .approvalInvalidAudio); return makeSnapshot() }
        switch input.yield(chunk) {
        case .enqueued: break
        case .dropped: failApprovalCapture(capture, issue: .approvalAudioBackpressure)
        case .terminated: failApprovalCapture(capture, issue: .approvalASRFailed)
        @unknown default: failApprovalCapture(capture, issue: .approvalASRFailed)
        }
        publish(); return makeSnapshot()
    }

    @discardableResult
    public func endApprovalAudio(capture: ApprovalCaptureToken) -> SessionRuntimeSnapshot {
        progressApprovalHandoff()
        guard isApprovalCaptureActive(capture), approvalOperation?.inputEnded == false else { return makeSnapshot() }
        approvalOperation?.inputEnded = true
        approvalAudioInputs.removeValue(forKey: capture.id)?.finish()
        publish(); return makeSnapshot()
    }

    /// Admission only. New decisions are available through the SINGLE takePendingApprovalDecision channel.
    public func confirmToolApprovalOnPhone(binding: ApprovalBinding, displayed: ApprovalDisplayedContent,
                                           choice: ToolApprovalChoice, evidence: ApprovalPhoneEvidence) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        guard approvalOperation?.presentation?.binding == binding, approvalOperation?.draining == false else { return .rejected(.wrongBinding) }
        let result = approvalCore.confirmOnPhone(binding: binding, displayed: displayed, choice: choice, evidence: evidence)
        progressApprovalHandoff(); publish(); return withoutDecisionPayload(result)
    }

    public func cancelToolApprovalCapture(capture: ApprovalCaptureToken) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        let result = approvalCore.cancelCapture(capture)
        progressApprovalHandoff(); publish(); return withoutDecisionPayload(result)
    }

    public func cancelToolApproval(binding: ApprovalBinding) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        guard approvalOperation?.presentation?.binding == binding else { return .rejected(.wrongBinding) }
        beginApprovalDrain(reason: .hostCancellation, deferred: nil)
        progressApprovalHandoff(); publish(); return .accepted
    }

    /// Single in-memory claim, not delivery or tool execution. Invalidation before claim discards it.
    public func takePendingApprovalDecision() -> ApprovalDecision? {
        progressApprovalHandoff()
        guard let decision = pendingApprovalDecision, !stopped, approvalOperation?.draining == false,
              machine.accepts(decision.binding.context.originRound), approvalCore.isDecisionDispatchable(decision.binding) else {
            pendingApprovalDecision = nil; publish(); return nil
        }
        pendingApprovalDecision = nil; publish(); return decision
    }

    public func finishToolApproval(binding: ApprovalBinding) -> ApprovalSubsessionResult {
        progressApprovalHandoff()
        guard approvalOperation?.presentation?.binding == binding else { return .rejected(.wrongBinding) }
        guard approvalCore.storedSnapshot.decision != nil, pendingApprovalDecision == nil else { return .rejected(.requestBusy) }
        beginApprovalDrain(reason: .hostCancellation, deferred: nil)
        progressApprovalHandoff(); publish(); return .accepted
    }

    func withoutDecisionPayload(_ result: ApprovalSubsessionResult) -> ApprovalSubsessionResult {
        switch result {
        case .resolved, .alreadyResolved: return .accepted
        default: return result
        }
    }

    func approvalSnapshot() -> RuntimeApprovalSnapshot {
        let state = approvalCore.storedSnapshot
        let phase: RuntimeApprovalPhase
        if let operation = approvalOperation {
            if operation.draining { phase = .draining }
            else if operation.presentation == nil { phase = .preparing }
            else {
                switch state.phase {
                case .awaitingPresentation: phase = .awaitingPresentation
                case .awaitingToolApproval: phase = .awaitingToolApproval
                case .awaitingPhoneConfirmation: phase = .awaitingPhoneConfirmation
                case .capturingConfirmation: phase = .capturingConfirmation
                case .resolved: phase = .decisionReady
                default: phase = .failed
                }
            }
        } else { phase = .inactive }
        return .init(phase: phase, suspensionID: approvalOperation?.id,
                     presentation: approvalOperation?.presentation, capture: approvalOperation?.capture,
                     lastDecision: state.decision, hasPendingDecision: pendingApprovalDecision != nil,
                     lastRejection: lastApprovalRejection ?? state.lastRejection)
    }

    var approvalQuiescent: Bool {
        jobs.isEmpty && cleanupTasks.isEmpty && commandQueue.isEmpty && sending == nil && retiringTransportTasks.isEmpty
    }

    func progressApprovalHandoff() {
        guard !updatingApproval, !stopped, let operation = approvalOperation else { return }
        updatingApproval = true
        defer { updatingApproval = false }
        let state = approvalCore.currentSnapshot()
        if state.lastRejection == .invalidClock { approvalRuntimeFault(.approvalClockInvalid); return }
        guard machine.accepts(operation.request.originRound), machine.snapshot.isConnected else {
            abortApproval(reason: .disconnection); return
        }
        if let capture = operation.capture, state.capture?.token != capture.token {
            stopApprovalCaptureWork(capture.token)
        }
        if operation.presentation != nil, !operation.draining, !operation.decisionRecorded, let decision = state.decision {
            approvalOperation?.decisionRecorded = true
            if [.approved, .denied].contains(decision.receipt.resolution) { pendingApprovalDecision = decision }
        }
        if let decision = pendingApprovalDecision, !approvalCore.isDecisionDispatchable(decision.binding) { pendingApprovalDecision = nil }
        guard let current = approvalOperation, approvalQuiescent else { return }
        if current.draining {
            cancelApprovalTimers()
            approvalOperation = nil
            if let event = current.deferredOrdinaryEvent { pendingEvents.append(event) }
            else { pendingEvents.append(.finishToolApprovalSuspension(round: current.request.originRound, suspensionID: current.id)) }
            drainEvents(); return
        }
        guard current.presentation == nil else { return }
        cancelTimer(.init(round: current.request.originRound, stage: .model, approvalID: current.id))
        guard case .established(let context) = approvalCore.beginSuspendedContext(originRound: current.request.originRound,
            connectionGeneration: transportGeneration, evidence: .ordinaryWorkPausedAndDrained),
              case .registered(let presentation) = approvalCore.register(current.request, context: context, policy: current.policy)
        else { lastApprovalRejection = .invalidRequest; approvalRuntimeFault(.approvalASRFailed); return }
        approvalOperation?.presentation = presentation
        scheduleApprovalTimer(.init(round: current.request.originRound, stage: .nextRound, approvalID: current.id),
                              nanoseconds: nanosUntil(current.request.expiresAt))
        enqueue(.showApproval(presentation), policy: .currentRoundWork)
        drainEvents()
    }

    func interceptApprovalLifecycle(_ event: VoiceSessionEvent) -> Bool {
        guard let operation = approvalOperation else { return false }
        switch event {
        case .nextRound(let round), .interrupt(let round):
            guard round == operation.request.originRound else { return false }
            let reason: ApprovalContextInvalidation
            if case .nextRound = event { reason = .normalNextRound } else { reason = .interruption }
            beginApprovalDrain(reason: reason, deferred: event)
            return true
        case .glassesExited(let round):
            if round == operation.request.originRound { abortApproval(reason: .exit) }
        case .exitRequested(let reason):
            if ![SessionExitReason.disconnected, .glassesExit].contains(reason) { abortApproval(reason: .exit) }
        case .disconnected: abortApproval(reason: .disconnection)
        default: break
        }
        return false
    }

    func beginApprovalDrain(reason: ApprovalContextInvalidation, deferred: VoiceSessionEvent?) {
        guard let operation = approvalOperation else { return }
        approvalCore.invalidateOrdinaryRound(operation.request.originRound, reason: reason)
        pendingApprovalDecision = nil
        if let capture = operation.capture { stopApprovalCaptureWork(capture.token) }
        cancelApprovalTimers()
        approvalOperation?.draining = true
        if approvalOperation?.deferredOrdinaryEvent == nil { approvalOperation?.deferredOrdinaryEvent = deferred }
        scheduleApprovalTimer(.init(round: operation.request.originRound, stage: .model, approvalID: operation.id),
                              nanoseconds: configuration.approvalHandoffTimeoutMilliseconds * 1_000_000)
    }

    func abortApproval(reason: ApprovalContextInvalidation) {
        guard let operation = approvalOperation else { return }
        approvalCore.invalidateOrdinaryRound(operation.request.originRound, reason: reason)
        pendingApprovalDecision = nil
        if let capture = operation.capture { stopApprovalCaptureWork(capture.token) }
        cancelApprovalTimers(); approvalOperation = nil
    }

    func isApprovalCaptureActive(_ capture: ApprovalCaptureToken) -> Bool {
        !stopped && transportUsable && machine.snapshot.phase == .awaitingToolApproval
            && machine.accepts(capture.binding.context.originRound) && approvalOperation?.draining == false
            && approvalOperation?.capture?.token == capture && approvalCore.storedSnapshot.capture?.token == capture
            && jobs[approvalKey(capture)] != nil
    }

    func approvalKey(_ capture: ApprovalCaptureToken) -> JobKey {
        .init(round: capture.binding.context.originRound, stage: .listening, approvalID: capture.id)
    }

    func startApprovalASR(_ prompt: ApprovalCapturePrompt, source: ASRSource, provider: any ApprovalASRProvider) {
        let capture = prompt.token, key = approvalKey(prompt.token), id = UUID()
        let pair = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(configuration.audioBufferChunks))
        approvalAudioInputs[capture.id] = pair.continuation
        let request = ApprovalASRRequest(capture: capture, source: source, language: configuration.session.language)
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let output = try await provider.recognize(request, audio: pair.stream)
                for try await result in output {
                    try Task.checkCancellation()
                    await self?.approvalASRResult(result, capture: capture, key: key, id: id)
                }
                if !Task.isCancelled { await self?.approvalASREnded(capture, key: key, id: id) }
            } catch {
                if !Task.isCancelled { await self?.approvalASREnded(capture, key: key, id: id) }
            }
        }
        jobs[key] = .init(id: id, task: task, cancel: { await provider.cancel(capture: capture) })
    }

    func approvalASRResult(_ result: ASRTranscript, capture: ApprovalCaptureToken, key: JobKey, id: UUID) {
        progressApprovalHandoff()
        guard jobs[key]?.id == id, isApprovalCaptureActive(capture),
              approvalOperation?.revision.map({ result.revision > $0 }) ?? true else { return }
        guard result.text.utf8.count <= 256, result.text.count <= 64 else { failApprovalCapture(capture, issue: .approvalASRFailed); return }
        approvalOperation?.revision = result.revision
        if result.isFinal {
            _ = approvalCore.submitVoiceFinal(token: capture, text: result.text)
            progressApprovalHandoff()
        }
        publish()
    }

    func approvalASREnded(_ capture: ApprovalCaptureToken, key: JobKey, id: UUID) {
        guard jobs[key]?.id == id else { return }
        failApprovalCapture(capture, issue: .approvalASRFailed)
    }

    func stopApprovalCaptureWork(_ capture: ApprovalCaptureToken) {
        approvalAudioInputs.removeValue(forKey: capture.id)?.finish(throwing: CancellationError())
        cancelJob(approvalKey(capture)); cancelTimer(approvalKey(capture))
        if approvalOperation?.capture?.token == capture { approvalOperation?.capture = nil }
        enqueue(.stopApprovalCapture(capture), policy: .cleanup)
    }

    func failApprovalCapture(_ capture: ApprovalCaptureToken, issue: SessionRuntimeIssue) {
        guard approvalOperation?.capture?.token == capture else { return }
        lastIssue = issue
        _ = approvalCore.cancelCapture(capture)
        stopApprovalCaptureWork(capture)
        drainEvents(); progressApprovalHandoff(); publish()
    }

    func scheduleApprovalTimer(_ key: JobKey, nanoseconds: UInt64) {
        cancelTimer(key)
        guard reserveClockCapacity() else { return }
        let id = UUID(), clock = dependencies.clock
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation(); try await clock.sleep(nanoseconds: max(1, nanoseconds)); try Task.checkCancellation()
                await self?.timeoutFired(key, id: id)
            } catch { if !Task.isCancelled { await self?.clockFailed(key, id: id) } }
        }
        timers[key] = .init(id: id, task: task)
    }

    func cancelApprovalTimers() {
        for key in Array(timers.keys) where key.approvalID != nil { cancelTimer(key) }
    }

    func nanosUntil(_ date: Date) -> UInt64 {
        let seconds = date.timeIntervalSince(dependencies.wallTime())
        return seconds.isFinite ? UInt64(max(0.000_000_001, min(300, seconds)) * 1_000_000_000) : 1
    }

    func approvalTimerFired(_ key: JobKey) {
        guard let operation = approvalOperation else { return }
        if key.stage == .model, key.approvalID == operation.id {
            approvalRuntimeFault(.approvalHandoffTimedOut); return
        }
        if let capture = operation.capture, key == approvalKey(capture.token) {
            // The runtime's elapsed deadline is authoritative even if an injected wall clock is stalled.
            _ = approvalCore.cancelCapture(capture.token); lastApprovalRejection = .captureExpired
            stopApprovalCaptureWork(capture.token)
        } else if key.stage == .nextRound, key.approvalID == operation.id {
            _ = approvalCore.expireDue()
            approvalCore.invalidateOrdinaryRound(operation.request.originRound, reason: .hostCancellation)
            pendingApprovalDecision = nil; lastApprovalRejection = .requestExpired
            if let capture = operation.capture { stopApprovalCaptureWork(capture.token) }
        }
        drainEvents(); progressApprovalHandoff(); publish()
    }

    func approvalRuntimeFault(_ issue: SessionRuntimeIssue) {
        lastIssue = issue
        transportFault(issue); drainEvents(); publish()
    }
}
