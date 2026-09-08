import Foundation
@_spi(ApprovalRuntime) import RayNeoSession

/// An actor-isolated effect dispatcher. Public send never waits for a provider stream or transport.
/// It starts bounded, separately cancellable tasks; callbacks re-enter the same actor with job/round IDs.
public actor SessionRuntime {
    struct JobKey: Hashable {
        let round: RoundToken
        let stage: SessionStage
        let approvalID: UUID?
        init(round: RoundToken, stage: SessionStage, approvalID: UUID? = nil) {
            self.round = round; self.stage = stage; self.approvalID = approvalID
        }
    }
    struct Job { let id: UUID; let task: Task<Void, Never>; let cancel: @Sendable () async -> Void }
    struct Timer { let id: UUID; let task: Task<Void, Never> }
    struct QueuedCommand { let command: GlassesSessionCommand; let policy: EffectExecutionPolicy }
    struct SendingCommand {
        let id: UUID; let generation: UUID; let task: Task<Void, Never>; let timeout: Task<Void, Never>
    }
    enum SpeechFailure: Error { case invalidAudio, emptyAudio }

    public let configuration: SessionRuntimeConfiguration
    let dependencies: SessionRuntimeDependencies
    var machine: VoiceSessionMachine
    var approvalCore: ApprovalSubsessionState
    var approvalOperation: ApprovalOperation?
    var approvalAudioInputs: [UUID: AsyncThrowingStream<AudioChunk, Error>.Continuation] = [:]
    var pendingApprovalDecision: ApprovalDecision?
    var lastApprovalRejection: ApprovalSubsessionRejection?
    var updatingApproval = false
    var jobs: [JobKey: Job] = [:]
    var audioInputs: [RoundToken: AsyncThrowingStream<AudioChunk, Error>.Continuation] = [:]
    var timers: [JobKey: Timer] = [:]
    var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    var retiringTransportTasks: [UUID: Task<Void, Never>] = [:]
    var retiringClockTasks: [UUID: Task<Void, Never>] = [:]
    var commandQueue: [QueuedCommand] = []
    var sending: SendingCommand?
    var transportGeneration = UUID()
    var transportUsable = false
    var pendingEvents: [VoiceSessionEvent] = []
    var processing = false
    var revision: UInt64 = 0
    var lastIssue: SessionRuntimeIssue?
    var observers: [UUID: AsyncStream<SessionRuntimeSnapshot>.Continuation] = [:]
    var droppedObservationUpdates: UInt64 = 0
    var stopped = false

    public init(configuration: SessionRuntimeConfiguration = .init(), dependencies: SessionRuntimeDependencies) {
        self.configuration = configuration; self.dependencies = dependencies
        machine = VoiceSessionMachine(configuration: configuration.session)
        approvalCore = .init(configuration: configuration.approval, ledgerCapacity: configuration.approvalCapacity, clock: dependencies.wallTime)
    }

    /// The host supplies real connection/wake/audio facts. Synthetic events are allowed for explicit lab UI.
    @discardableResult
    public func send(_ event: VoiceSessionEvent) -> SessionRuntimeSnapshot {
        guard !stopped else { return currentSnapshot() }
        // These are runtime-owned transitions, not facts an external microphone/model may inject.
        switch event {
        case .suspendForToolApproval, .finishToolApprovalSuspension: return currentSnapshot()
        default: break
        }
        pendingEvents.append(event)
        drainEvents()
        progressApprovalHandoff()
        return currentSnapshot()
    }

    public func currentSnapshot() -> SessionRuntimeSnapshot {
        progressApprovalHandoff()
        return makeSnapshot()
    }

    func makeSnapshot() -> SessionRuntimeSnapshot {
        .init(session: machine.snapshot, revision: revision, activeProviderTasks: jobs.count,
              activeCleanupTasks: cleanupTasks.count, retiringTransportTasks: retiringTransportTasks.count,
              retiringClockTasks: retiringClockTasks.count, outstandingClockTasks: clockTaskCount,
              scheduledTimeouts: timers.count,
              pendingTransportCommands: commandQueue.count + (sending == nil ? 0 : 1),
              droppedObservationUpdates: droppedObservationUpdates, lastIssue: lastIssue, isShutdown: stopped,
              approval: approvalSnapshot())
    }

    /// Maximum 8 observers; each keeps only the latest bounded number of snapshots. No logging occurs.
    public func observe() -> SessionRuntimeObservation? {
        guard !stopped, observers.count < 8 else { return nil }
        let id = UUID()
        let pair = AsyncStream<SessionRuntimeSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(configuration.observationBufferUpdates))
        observers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.stopObserving(id) } }
        pair.continuation.yield(currentSnapshot())
        return .init(id: id, updates: pair.stream)
    }

    public func stopObserving(_ id: UUID) { observers.removeValue(forKey: id)?.finish() }

    public func registerToolApproval(_ request: ToolApprovalRequest) -> ToolApprovalRegistration {
        guard !stopped, machine.accepts(request.round) else { return .rejected(.wrongRound) }
        guard approvalOperation == nil else { return .rejected(.confirmationRequired) }
        return approvalCore.registerLegacy(request)
    }

    /// Returns a decision only. No tool, process, Codex command or server acknowledgement is executed.
    public func resolveToolApproval(requestID: String, round: RoundToken, choice: ToolApprovalChoice,
                                    evidence: ToolConfirmationEvidence) -> ToolApprovalResult {
        guard !stopped, machine.accepts(round) else { return .rejected(.wrongRound) }
        guard approvalOperation == nil else { return .rejected(.confirmationRequired) }
        return approvalCore.resolveLegacy(requestID: requestID, round: round, choice: choice, evidence: evidence)
    }

    /// Requests cancellation and stops accepting events. Cleanup callbacks can still finish afterward.
    /// This does not claim that a noncooperative provider/transport has physically stopped.
    @discardableResult
    public func shutdown() -> SessionRuntimeSnapshot {
        guard !stopped else { return currentSnapshot() }
        _ = send(.disconnected)
        stopped = true
        cancelTransport()
        for key in Array(timers.keys) { cancelTimer(key) }
        for key in Array(jobs.keys) { cancelJob(key) }
        pendingEvents.removeAll()
        publish()
        for observer in observers.values { observer.finish() }
        observers.removeAll()
        return currentSnapshot()
    }

    func drainEvents() {
        guard !processing else { return }
        processing = true
        while !pendingEvents.isEmpty, !stopped {
            let event = pendingEvents.removeFirst()
            if interceptApprovalLifecycle(event) {
                if revision < UInt64.max { revision += 1 }
                publish(); continue
            }
            switch event {
            case .connected where !machine.snapshot.isConnected:
                if !retiringTransportTasks.isEmpty {
                    lastIssue = .transportCancellationBackpressure
                    transportUsable = false
                    pendingEvents.append(.disconnected)
                } else { transportGeneration = UUID(); transportUsable = true }
            case .disconnected:
                cancelTransport()
            default: break
            }
            let effects = machine.handle(event)
            if revision < UInt64.max { revision += 1 }
            // No await here: one event's dispatch completes before another actor message can enter.
            for effect in effects { dispatch(effect) }
            publish()
        }
        processing = false
    }

    func dispatch(_ effect: VoiceSessionEffect) {
        if effect.executionPolicy == .currentRoundWork,
           let round = effect.round, !machine.accepts(round) { return }
        switch effect {
        case let .startRecognition(request): startASR(request)
        case let .feedRecognition(round, chunk):
            guard let input = audioInputs[round] else { return }
            switch input.yield(chunk) {
            case .enqueued: break
            case .dropped:
                lastIssue = .audioBackpressure
                pendingEvents.append(.failed(round: round, stage: .recognition, failure: .providerFailure))
            case .terminated:
                lastIssue = .providerFailed(.recognition)
                pendingEvents.append(.failed(round: round, stage: .recognition, failure: .providerFailure))
            @unknown default:
                lastIssue = .providerFailed(.recognition)
                pendingEvents.append(.failed(round: round, stage: .recognition, failure: .providerFailure))
            }
        case let .finishRecognition(round): audioInputs.removeValue(forKey: round)?.finish()
        case let .cancelRecognition(round): cancelJob(.init(round: round, stage: .recognition))
        case let .requestModel(request): startModel(request)
        case let .synthesizeAndPlay(request): startSpeech(request)
        case let .cancelWork(round):
            for stage in [SessionStage.recognition, .model, .speech] { cancelJob(.init(round: round, stage: stage)) }
            audioInputs.removeValue(forKey: round)?.finish(throwing: CancellationError())
        case let .invalidateToolApprovals(round): approvalCore.invalidateOrdinaryRound(round, reason: .hostCancellation)
        case let .scheduleTimeout(round, stage, seconds): scheduleTimeout(round: round, stage: stage, seconds: seconds)
        case let .cancelTimeout(round, stage): cancelTimer(.init(round: round, stage: stage))
        case let .startCapture(round): enqueue(.startCapture(round: round), policy: effect.executionPolicy)
        case let .stopCapture(round): enqueue(.stopCapture(round: round), policy: effect.executionPolicy)
        case let .displayTranscript(round, text, final): enqueue(.transcript(round: round, text: text, isFinal: final), policy: effect.executionPolicy)
        case let .displayResponse(round, text, final): enqueue(.response(round: round, text: text, isFinal: final), policy: effect.executionPolicy)
        case let .reportTTSStatus(round, status): enqueue(.ttsStatus(round: round, status: status), policy: effect.executionPolicy)
        case let .responseComplete(round): enqueue(.responseComplete(round: round), policy: effect.executionPolicy)
        case let .requestExit(round, reason): enqueue(.exit(round: round, reason: reason), policy: effect.executionPolicy)
        case .reportFailure: break // Already represented by SessionSnapshot; never log provider error bodies.
        }
    }

    func startASR(_ request: ASRRequest) {
        guard reserveCleanupCapacity() else { return }
        let provider = request.source == .local ? dependencies.localASR : dependencies.cloudASR
        guard let provider else {
            lastIssue = .missingASR(request.source)
            pendingEvents.append(.failed(round: request.round, stage: .recognition, failure: .unavailable)); return
        }
        guard provider.source == request.source else {
            lastIssue = .wrongASRProviderSource
            pendingEvents.append(.failed(round: request.round, stage: .recognition, failure: .unavailable)); return
        }
        let key = JobKey(round: request.round, stage: .recognition), id = UUID()
        let pair = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(configuration.audioBufferChunks))
        audioInputs[request.round] = pair.continuation
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let output = try await provider.recognize(request, audio: pair.stream)
                for try await result in output {
                    try Task.checkCancellation()
                    await self?.deliver(.asrResult(round: request.round, source: request.source, result: result), key: key, id: id)
                }
                if !Task.isCancelled { await self?.jobFailed(key, id: id, issue: .providerFailed(.recognition)) }
                else { await self?.jobCancelled(key, id: id) }
            } catch {
                if Task.isCancelled { await self?.jobCancelled(key, id: id) }
                else { await self?.jobFailed(key, id: id, issue: .providerFailed(.recognition)) }
            }
        }
        jobs[key] = .init(id: id, task: task, cancel: { await provider.cancel(round: request.round) })
    }

    func startModel(_ request: ModelRequest) {
        guard reserveCleanupCapacity() else { return }
        let provider = dependencies.model
        let key = JobKey(round: request.round, stage: .model), id = UUID()
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let output = try await provider.respond(to: request)
                for try await text in output {
                    try Task.checkCancellation()
                    await self?.deliver(.modelText(round: request.round, update: text), key: key, id: id)
                }
                try Task.checkCancellation()
                await self?.jobCompleted(key, id: id, event: .modelFinished(round: request.round))
            } catch {
                if Task.isCancelled { await self?.jobCancelled(key, id: id) }
                else { await self?.jobFailed(key, id: id, issue: .providerFailed(.model)) }
            }
        }
        jobs[key] = .init(id: id, task: task, cancel: { await provider.cancel(round: request.round) })
    }

    func startSpeech(_ request: SpeechRequest) {
        guard reserveCleanupCapacity() else { return }
        guard let synthesis = dependencies.synthesis, let playback = dependencies.playback else {
            lastIssue = .missingSpeechProvider
            pendingEvents.append(.failed(round: request.round, stage: .speech, failure: .unavailable)); return
        }
        let key = JobKey(round: request.round, stage: .speech), id = UUID()
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let output = try await synthesis.synthesize(request)
                var format: AudioFormat?
                for try await chunk in output {
                    try Task.checkCancellation()
                    guard chunk.isValid else { throw SpeechFailure.invalidAudio }
                    if let format { guard format == chunk.format else { throw SpeechFailure.invalidAudio } }
                    else {
                        format = chunk.format
                        try await playback.start(round: request.round, format: chunk.format)
                        try Task.checkCancellation()
                        await self?.deliver(.ttsStarted(round: request.round), key: key, id: id)
                    }
                    // Delivering status may itself fail transport admission and cancel this task.
                    // Do not start another playback operation after that actor reentrancy point.
                    try Task.checkCancellation()
                    try await playback.enqueue(chunk, round: request.round)
                }
                try Task.checkCancellation()
                guard format != nil else { throw SpeechFailure.emptyAudio }
                await self?.deliver(.ttsInputFinished(round: request.round), key: key, id: id)
                try Task.checkCancellation()
                try await playback.finishAndDrain(round: request.round)
                try Task.checkCancellation()
                await self?.jobCompleted(key, id: id, event: .ttsPlaybackDrained(round: request.round))
            } catch {
                if Task.isCancelled { await self?.jobCancelled(key, id: id) }
                else {
                    let issue: SessionRuntimeIssue
                    switch error {
                    case SpeechFailure.invalidAudio: issue = .invalidSpeechAudio
                    case SpeechFailure.emptyAudio: issue = .emptySpeechAudio
                    default: issue = .providerFailed(.speech)
                    }
                    await self?.jobFailed(key, id: id, issue: issue)
                }
            }
        }
        jobs[key] = .init(id: id, task: task, cancel: {
            // Separate operations so a synthesizer cancellation cannot prevent an audio stop.
            async let cancelSynthesis: Void = synthesis.cancel(round: request.round)
            async let stopPlayback: Void = playback.stop(round: request.round)
            _ = await (cancelSynthesis, stopPlayback)
        })
    }

    func deliver(_ event: VoiceSessionEvent, key: JobKey, id: UUID) {
        guard !stopped, jobs[key]?.id == id, machine.accepts(key.round) else { return }
        _ = send(event)
    }

    func jobCompleted(_ key: JobKey, id: UUID, event: VoiceSessionEvent) {
        guard jobs[key]?.id == id else { return }
        retireCompletedJob(key)
        guard !stopped else { return }
        _ = send(event)
    }

    func jobCancelled(_ key: JobKey, id: UUID) {
        guard jobs[key]?.id == id else { return }
        retireCompletedJob(key)
        publish()
    }

    func retireCompletedJob(_ key: JobKey) {
        guard let job = jobs.removeValue(forKey: key) else { return }
        let id = UUID()
        cleanupTasks[id] = Task { [weak self] in
            await job.task.value
            await self?.cleanupFinished(id)
        }
    }

    func jobFailed(_ key: JobKey, id: UUID, issue: SessionRuntimeIssue) {
        guard !stopped, jobs[key]?.id == id else { return }
        lastIssue = issue
        _ = send(.failed(round: key.round, stage: key.stage, failure: .providerFailure))
        if jobs[key]?.id == id { cancelJob(key) }
    }

    func cancelJob(_ key: JobKey) {
        if let approvalID = key.approvalID { approvalAudioInputs.removeValue(forKey: approvalID)?.finish(throwing: CancellationError()) }
        else if key.stage == .recognition { audioInputs.removeValue(forKey: key.round)?.finish(throwing: CancellationError()) }
        guard let job = jobs.removeValue(forKey: key) else { return }
        job.task.cancel()
        guard cleanupTasks.count < configuration.maximumCleanupTasks else {
            lastIssue = .cleanupBackpressure
            if machine.snapshot.isConnected { pendingEvents.append(.disconnected) }
            return
        }
        let id = UUID()
        cleanupTasks[id] = Task { [weak self] in
            // Do not free this reserved slot merely because cancel(round:) returned quickly.
            // A provider that ignores task cancellation must remain accounted for until it exits.
            async let signal: Void = job.cancel()
            async let workExited: Void = job.task.value
            _ = await (signal, workExited)
            await self?.cleanupFinished(id)
        }
    }

    func cleanupFinished(_ id: UUID) {
        cleanupTasks.removeValue(forKey: id)
        progressApprovalHandoff()
        publish()
    }

    func reserveCleanupCapacity() -> Bool {
        // Every active provider reserves space for its eventual asynchronous cancellation call.
        guard cleanupTasks.count + jobs.count < configuration.maximumCleanupTasks else {
            lastIssue = .cleanupBackpressure
            if machine.snapshot.isConnected { pendingEvents.append(.disconnected) }
            return false
        }
        return true
    }

    func scheduleTimeout(round: RoundToken, stage: SessionStage, seconds: UInt32) {
        let key = JobKey(round: round, stage: stage), id = UUID(), clock = dependencies.clock
        cancelTimer(key)
        guard reserveClockCapacity() else { return }
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                try await clock.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                try Task.checkCancellation()
                await self?.timeoutFired(key, id: id)
            } catch {
                if !Task.isCancelled { await self?.clockFailed(key, id: id) }
            }
        }
        timers[key] = .init(id: id, task: task)
    }

    var clockTaskCount: Int { timers.count + retiringClockTasks.count + (sending == nil ? 0 : 1) }

    func reserveClockCapacity() -> Bool {
        guard clockTaskCount < configuration.maximumPendingClockTasks else {
            transportFault(.clockBackpressure)
            return false
        }
        return true
    }

    func cancelTimer(_ key: JobKey) {
        guard let timer = timers.removeValue(forKey: key) else { return }
        retireClockTask(id: timer.id, task: timer.task)
    }

    func retireClockTask(id: UUID, task: Task<Void, Never>) {
        task.cancel()
        guard retiringClockTasks[id] == nil else { return }
        // Its slot was reserved before sleep began. Cancellation is a signal, not proof of exit.
        retiringClockTasks[id] = Task { [weak self] in
            await task.value
            await self?.retiredClockFinished(id)
        }
    }

    func retiredClockFinished(_ id: UUID) {
        retiringClockTasks.removeValue(forKey: id)
        progressApprovalHandoff()
        publish()
    }

    func timeoutFired(_ key: JobKey, id: UUID) {
        guard !stopped, timers[key]?.id == id else { return }
        timers.removeValue(forKey: key)
        if key.approvalID != nil { approvalTimerFired(key); return }
        _ = send(.timeout(round: key.round, stage: key.stage))
    }

    func clockFailed(_ key: JobKey, id: UUID) {
        guard !stopped, timers[key]?.id == id else { return }
        timers.removeValue(forKey: key)
        if key.approvalID != nil { approvalRuntimeFault(.clockFailed); return }
        lastIssue = .clockFailed
        _ = send(.failed(round: key.round, stage: key.stage, failure: .providerFailure))
    }

    func enqueue(_ command: GlassesSessionCommand, policy: EffectExecutionPolicy) {
        guard transportUsable, !stopped else { return }
        guard commandQueue.count + (sending == nil ? 0 : 1) < configuration.transportQueueCommands else {
            transportFault(.transportBackpressure); return
        }
        commandQueue.append(.init(command: command, policy: policy))
        startTransportIfNeeded()
    }

    func startTransportIfNeeded() {
        guard transportUsable, sending == nil, !stopped else { return }
        guard retiringTransportTasks.isEmpty else {
            transportFault(.transportCancellationBackpressure); return
        }
        while !commandQueue.isEmpty {
            let queued = commandQueue.removeFirst()
            if queued.policy == .currentRoundWork, !machine.accepts(queued.command.round) { continue }
            guard reserveClockCapacity() else { return }
            let id = UUID(), generation = transportGeneration
            let transport = dependencies.transport, clock = dependencies.clock
            let duration = configuration.transportTimeoutMilliseconds * 1_000_000
            let task = Task { [weak self] in
                do {
                    try Task.checkCancellation()
                    guard await self?.maySend(queued, id: id, generation: generation) == true else {
                        await self?.transportFinished(id, generation: generation, succeeded: true)
                        return
                    }
                    try await transport.send(queued.command)
                    try Task.checkCancellation()
                    await self?.transportFinished(id, generation: generation, succeeded: true)
                } catch {
                    if !Task.isCancelled { await self?.transportFinished(id, generation: generation, succeeded: false) }
                }
            }
            let timeout = Task { [weak self] in
                do {
                    try Task.checkCancellation()
                    try await clock.sleep(nanoseconds: duration)
                    try Task.checkCancellation()
                    await self?.transportTimeout(id, generation: generation)
                } catch {
                    if !Task.isCancelled { await self?.transportClockFailed(id, generation: generation) }
                }
            }
            sending = .init(id: id, generation: generation, task: task, timeout: timeout)
            return
        }
    }

    func maySend(_ queued: QueuedCommand, id: UUID, generation: UUID) -> Bool {
        guard !stopped, transportUsable, sending?.id == id, sending?.generation == generation else { return false }
        switch queued.command {
        case .startApprovalCapture(let capture): return isApprovalCaptureActive(capture)
        case .showApproval(let presentation):
            return approvalOperation?.presentation?.binding == presentation.binding && approvalCore.storedSnapshot.decision == nil
        case .stopApprovalCapture: return true
        default: break
        }
        guard queued.policy == .currentRoundWork else { return true }
        guard machine.accepts(queued.command.round) else { return false }
        if case .startCapture = queued.command { return machine.snapshot.phase == .listening }
        return true
    }

    func transportFinished(_ id: UUID, generation: UUID, succeeded: Bool) {
        guard let old = sending, old.id == id, old.generation == generation else { return }
        sending = nil
        retireClockTask(id: old.id, task: old.timeout)
        if succeeded { startTransportIfNeeded() }
        else { transportFault(.transportFailed) }
        // Starting the next command can itself exhaust a budget and enqueue disconnection.
        // Drain that event now; do not wait for an unrelated future microphone/UI callback.
        drainEvents()
        progressApprovalHandoff()
        publish()
    }

    func transportTimeout(_ id: UUID, generation: UUID) {
        guard sending?.id == id, sending?.generation == generation else { return }
        transportFault(.transportTimedOut); drainEvents(); publish()
    }

    func transportClockFailed(_ id: UUID, generation: UUID) {
        guard sending?.id == id, sending?.generation == generation else { return }
        transportFault(.clockFailed); drainEvents(); publish()
    }

    func transportFault(_ issue: SessionRuntimeIssue) {
        lastIssue = issue
        cancelTransport()
        if machine.snapshot.isConnected { pendingEvents.append(.disconnected) }
    }

    func cancelTransport() {
        transportUsable = false; transportGeneration = UUID()
        if let old = sending {
            old.task.cancel(); sending = nil
            retireClockTask(id: old.id, task: old.timeout)
            // A shared transport may still be writing physically. No replacement writer is admitted
            // until this exact original task exits, even when its old generation is logically dead.
            retiringTransportTasks[old.id] = Task { [weak self] in
                await old.task.value
                await self?.retiredTransportFinished(old.id)
            }
        }
        commandQueue.removeAll(keepingCapacity: false)
    }

    func retiredTransportFinished(_ id: UUID) {
        retiringTransportTasks.removeValue(forKey: id)
        progressApprovalHandoff()
        publish()
    }

    func publish() {
        let snapshot = makeSnapshot()
        for continuation in observers.values {
            if case .dropped = continuation.yield(snapshot), droppedObservationUpdates < UInt64.max { droppedObservationUpdates += 1 }
        }
    }
}
