import Foundation

/// Pure, transport-independent reducer. Calling handle never performs I/O or runs a model.
public struct VoiceSessionMachine: Sendable {
    public let configuration: VoiceSessionConfiguration
    public private(set) var snapshot = SessionSnapshot()
    private var captureOpen = false
    private var asrRevision: UInt64?
    private var modelRevision: UInt64?
    private var speechInputFinished = false
    private var completionSent = false
    private var completedHistory: [ConversationMessage] = []

    public init(configuration: VoiceSessionConfiguration = .init()) { self.configuration = configuration }

    public mutating func handle(_ event: VoiceSessionEvent) -> [VoiceSessionEffect] {
        switch event {
        case .connected:
            guard !snapshot.isConnected else { return [] }
            snapshot.isConnected = true; snapshot.phase = .idle
            return []
        case .disconnected:
            guard snapshot.isConnected else { return [] }
            snapshot.isConnected = false
            let effects = close(reason: .disconnected, requestDeviceExit: false)
            snapshot.phase = .disconnected
            return effects
        case let .networkChanged(available):
            snapshot.networkAvailable = available
            // A mid-round network change never silently replays audio into a different provider.
            return []
        case .wake:
            guard snapshot.isConnected, [.idle, .closed].contains(snapshot.phase) else { return [] }
            completedHistory.removeAll(keepingCapacity: false)
            snapshot.completedRoundCount = 0
            return beginRound(.init(sessionID: UUID(), index: 0))
        case let .audioReceived(round, chunk):
            guard accepts(round), snapshot.phase == .listening, captureOpen else { return [] }
            guard chunk.isValid else { return fail(round, stage: .recognition, failure: .invalidAudio) }
            return [.feedRecognition(round: round, chunk: chunk)]
        case let .audioEnded(round):
            guard accepts(round), snapshot.phase == .listening else { return [] }
            snapshot.phase = .awaitingTranscript
            var effects = stopCapture(round)
            effects += [.cancelTimeout(round: round, stage: .listening), .finishRecognition(round: round)]
            effects.append(deadline(round, stage: .recognition))
            return effects
        case let .asrResult(round, source, result):
            guard accepts(round), [.listening, .awaitingTranscript].contains(snapshot.phase),
                  source == snapshot.asrSource, isNew(result.revision, after: asrRevision) else { return [] }
            guard withinLimit(result.text) else { return fail(round, stage: .recognition, failure: .textLimitExceeded) }
            asrRevision = result.revision
            snapshot.transcript = result.text
            if !result.isFinal {
                return [.displayTranscript(round: round, text: result.text, isFinal: false)]
            }
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fail(round, stage: .recognition, failure: .emptyTranscript)
            }
            snapshot.phase = .generating
            var effects = stopCapture(round)
            effects += [.cancelTimeout(round: round, stage: .listening),
                        .cancelTimeout(round: round, stage: .recognition),
                        .cancelRecognition(round: round),
                        .displayTranscript(round: round, text: result.text, isFinal: true),
                        .requestModel(.init(round: round, messages: completedHistory + [.init(role: .user, text: result.text)])),
                        deadline(round, stage: .model)]
            return effects
        case let .modelText(round, update):
            guard accepts(round), snapshot.phase == .generating,
                  isNew(update.revision, after: modelRevision) else { return [] }
            guard withinLimit(update.text) else { return fail(round, stage: .model, failure: .textLimitExceeded) }
            modelRevision = update.revision; snapshot.response = update.text
            return [.displayResponse(round: round, text: update.text, isFinal: false)]
        case let .modelFinished(round):
            guard accepts(round), snapshot.phase == .generating else { return [] }
            recordCompletedTurn()
            var effects: [VoiceSessionEffect] = [.cancelTimeout(round: round, stage: .model),
                .displayResponse(round: round, text: snapshot.response, isFinal: true)]
            if configuration.ttsMode == .enabled,
               !snapshot.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                snapshot.phase = .speaking
                effects += [.synthesizeAndPlay(.init(round: round, text: snapshot.response, language: configuration.language)),
                            deadline(round, stage: .speech)]
            } else { effects += completeRound(round) }
            return effects
        case let .ttsStarted(round):
            guard accepts(round), snapshot.phase == .speaking, snapshot.ttsStatus == nil else { return [] }
            return setTTS(.began, round: round)
        case let .ttsPaused(round):
            guard accepts(round), snapshot.phase == .speaking,
                  [.began, .resumed, .progress].contains(snapshot.ttsStatus) else { return [] }
            return setTTS(.paused, round: round)
        case let .ttsResumed(round):
            guard accepts(round), snapshot.phase == .speaking, snapshot.ttsStatus == .paused else { return [] }
            return setTTS(.resumed, round: round)
        case let .ttsProgress(round):
            guard accepts(round), snapshot.phase == .speaking,
                  [.began, .resumed, .progress].contains(snapshot.ttsStatus) else { return [] }
            return setTTS(.progress, round: round)
        case let .ttsInputFinished(round):
            guard accepts(round), snapshot.phase == .speaking else { return [] }
            speechInputFinished = true
            return []
        case let .ttsPlaybackDrained(round):
            guard accepts(round), snapshot.phase == .speaking, speechInputFinished else { return [] }
            return setTTS(.completed, round: round) + completeRound(round)
        case let .suspendForToolApproval(round, suspensionID):
            guard accepts(round), [.generating, .speaking, .awaitingNextRound].contains(snapshot.phase) else { return [] }
            snapshot.phase = .awaitingToolApproval; snapshot.approvalSuspensionID = suspensionID
            return stopCapture(round) + [.cancelWork(round: round)]
                + SessionStage.allCases.map { .cancelTimeout(round: round, stage: $0) }
        case let .finishToolApprovalSuspension(round, suspensionID):
            guard accepts(round), snapshot.phase == .awaitingToolApproval,
                  snapshot.approvalSuspensionID == suspensionID else { return [] }
            snapshot.approvalSuspensionID = nil; snapshot.phase = .awaitingNextRound
            var effects: [VoiceSessionEffect] = []
            if !completionSent {
                completionSent = true
                if snapshot.completedRoundCount < UInt64.max { snapshot.completedRoundCount += 1 }
                effects.append(.responseComplete(round: round))
            }
            // Approval completion never executes a tool, restarts the cancelled model, or auto-advances.
            effects.append(deadline(round, stage: .nextRound))
            return effects
        case let .nextRound(round):
            guard accepts(round), [.awaitingNextRound, .awaitingToolApproval].contains(snapshot.phase) else { return [] }
            return advanceRound(after: round)
        case let .interrupt(round):
            guard accepts(round), isActive else { return [] }
            return advanceRound(after: round)
        case let .glassesExited(round):
            guard accepts(round), isActive else { return [] }
            return close(reason: .glassesExit, requestDeviceExit: false)
        case let .exitRequested(reason):
            // Device-originated exit and transport loss have their own events and no phone rc.
            guard isActive, ![.glassesExit, .disconnected].contains(reason) else { return [] }
            return close(reason: reason, requestDeviceExit: true)
        case let .failed(round, stage, failure):
            guard accepts(round), stageMatches(stage) else { return [] }
            return fail(round, stage: stage, failure: failure)
        case let .timeout(round, stage):
            guard accepts(round), stageMatches(stage) else { return [] }
            if stage == .nextRound { return close(reason: .timeout, requestDeviceExit: true) }
            return fail(round, stage: stage, failure: .timedOut)
        }
    }

    public func accepts(_ round: RoundToken) -> Bool { snapshot.currentRound == round && isActive }
    private var isActive: Bool { ![.disconnected, .idle, .closed].contains(snapshot.phase) }

    private mutating func beginRound(_ round: RoundToken) -> [VoiceSessionEffect] {
        snapshot.currentRound = round; snapshot.phase = .listening
        snapshot.approvalSuspensionID = nil
        snapshot.transcript = ""; snapshot.response = ""; snapshot.ttsStatus = nil
        snapshot.lastFailure = nil; snapshot.lastExitReason = nil
        asrRevision = nil; modelRevision = nil; speechInputFinished = false; completionSent = false
        guard let source = configuration.asrPolicy.source(networkAvailable: snapshot.networkAvailable) else {
            snapshot.asrSource = nil
            return fail(round, stage: .recognition, failure: .networkUnavailable)
        }
        snapshot.asrSource = source; captureOpen = true
        return [.startRecognition(.init(round: round, source: source, language: configuration.language)),
                .startCapture(round: round), deadline(round, stage: .listening)]
    }

    private mutating func advanceRound(after round: RoundToken) -> [VoiceSessionEffect] {
        guard round.index < UInt64.max else { return close(reason: .serviceError, requestDeviceExit: true) }
        var effects = cancelRound(round)
        effects += beginRound(.init(sessionID: round.sessionID, index: round.index + 1))
        return effects
    }

    private mutating func completeRound(_ round: RoundToken) -> [VoiceSessionEffect] {
        guard !completionSent else { return [] }
        completionSent = true
        if snapshot.completedRoundCount < UInt64.max { snapshot.completedRoundCount += 1 }
        snapshot.phase = .awaitingNextRound
        var effects: [VoiceSessionEffect] = [.cancelTimeout(round: round, stage: .speech), .responseComplete(round: round)]
        if configuration.nextRoundMode == .automatic { effects += advanceRound(after: round) }
        else { effects.append(deadline(round, stage: .nextRound)) }
        return effects
    }

    private mutating func close(reason: SessionExitReason, requestDeviceExit: Bool) -> [VoiceSessionEffect] {
        let wasActive = isActive
        var effects: [VoiceSessionEffect] = []
        if let round = snapshot.currentRound, wasActive {
            effects = cancelRound(round)
            if requestDeviceExit && snapshot.isConnected { effects.append(.requestExit(round: round, reason: reason)) }
        }
        snapshot.phase = snapshot.isConnected ? .closed : .disconnected
        snapshot.lastExitReason = reason
        return effects
    }

    private mutating func cancelRound(_ round: RoundToken) -> [VoiceSessionEffect] {
        snapshot.approvalSuspensionID = nil
        var effects = stopCapture(round)
        effects += [.cancelWork(round: round), .invalidateToolApprovals(round: round)]
        effects += SessionStage.allCases.map { .cancelTimeout(round: round, stage: $0) }
        return effects
    }

    private mutating func stopCapture(_ round: RoundToken) -> [VoiceSessionEffect] {
        guard captureOpen else { return [] }
        captureOpen = false
        return snapshot.isConnected ? [.stopCapture(round: round)] : []
    }

    private mutating func fail(_ round: RoundToken, stage: SessionStage, failure: SessionFailure) -> [VoiceSessionEffect] {
        snapshot.lastFailure = failure
        var effects: [VoiceSessionEffect] = [.reportFailure(round: round, stage: stage, failure: failure)]
        if stage == .speech {
            // A failed player never deadlocks a valid text reply waiting for a TTS callback.
            effects += [.cancelWork(round: round)] + completeRound(round)
        } else {
            let reason: SessionExitReason = failure == .networkUnavailable ? .networkUnavailable
                : failure == .timedOut ? .timeout : .serviceError
            effects += close(reason: reason, requestDeviceExit: true)
        }
        return effects
    }

    private mutating func setTTS(_ status: TTSStatus, round: RoundToken) -> [VoiceSessionEffect] {
        snapshot.ttsStatus = status
        return [.reportTTSStatus(round: round, status: status)]
    }

    private mutating func recordCompletedTurn() {
        guard configuration.maximumHistoryTurns > 0 else { return }
        completedHistory += [.init(role: .user, text: snapshot.transcript), .init(role: .assistant, text: snapshot.response)]
        let excess = completedHistory.count - configuration.maximumHistoryTurns * 2
        if excess > 0 { completedHistory.removeFirst(excess) }
    }

    private func stageMatches(_ stage: SessionStage) -> Bool {
        switch stage {
        case .listening: return snapshot.phase == .listening
        case .recognition: return [.listening, .awaitingTranscript].contains(snapshot.phase)
        case .model: return snapshot.phase == .generating
        case .speech: return snapshot.phase == .speaking
        case .nextRound: return snapshot.phase == .awaitingNextRound
        }
    }
    private func withinLimit(_ text: String) -> Bool {
        TextBounds.contains(text, maximumCharacters: configuration.maximumTextCharacters,
                            maximumUTF8Bytes: configuration.maximumTextUTF8Bytes)
    }
    private func isNew(_ revision: UInt64, after prior: UInt64?) -> Bool { prior.map { revision > $0 } ?? true }
    private func deadline(_ round: RoundToken, stage: SessionStage) -> VoiceSessionEffect {
        .scheduleTimeout(round: round, stage: stage, seconds: configuration.timeouts.seconds(for: stage))
    }
}

/// Serializes concurrent callbacks; snapshot and effects describe the same atomic transition.
/// Execute all effects in order before processing the next event. Re-check currentRoundWork tokens
/// before deferred starts; cleanup/orderedOutput must NOT be dropped just because their round ended.
public actor VoiceSessionCoordinator {
    private var machine: VoiceSessionMachine
    public init(configuration: VoiceSessionConfiguration = .init()) { machine = .init(configuration: configuration) }
    public func send(_ event: VoiceSessionEvent) -> VoiceSessionTransition {
        let effects = machine.handle(event)
        return .init(snapshot: machine.snapshot, effects: effects)
    }
    public func currentSnapshot() -> SessionSnapshot { machine.snapshot }
    public func accepts(_ round: RoundToken) -> Bool { machine.accepts(round) }
}
