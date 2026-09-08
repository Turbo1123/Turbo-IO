import XCTest
import RayNeoSession
import RayNeoSessionRuntime
import RayNeoSessionRuntimeTestSupport

final class SessionRuntimeTests: XCTestCase {
    private let pcm = AudioChunk(data: Data([0, 0, 1, 0]), format: .pcm16LE(sampleRate: 16_000, channels: 1))

    private func wake(_ runtime: SessionRuntime) async -> RoundToken {
        _ = await runtime.send(.connected)
        return await runtime.send(.wake).session.currentRound!
    }

    private func finishInput(_ runtime: SessionRuntime, round: RoundToken) async {
        _ = await runtime.send(.audioReceived(round: round, chunk: pcm))
        _ = await runtime.send(.audioEnded(round: round))
    }

    @discardableResult
    private func eventually(_ predicate: @escaping @Sendable () async -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        for _ in 0..<2_000 {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for a specific synthetic runtime condition", file: file, line: line)
        return false
    }

    func testInitialStateHasNoIOWork() async {
        let runtime = SessionRuntime(dependencies: .init(model: SyntheticConversationModel(), transport: RecordingGlassesTransport()))
        let snapshot = await runtime.currentSnapshot()
        XCTAssertEqual(snapshot.session.phase, .disconnected)
        XCTAssertEqual(snapshot.activeProviderTasks, 0)
        XCTAssertEqual(snapshot.pendingTransportCommands, 0)
        _ = await runtime.shutdown()
    }

    func testTextRoundExecutesASRModelAndOrderedTransportWithoutTTS() async {
        let asr = SyntheticASRProvider(), model = SyntheticConversationModel(), transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(dependencies: .init(localASR: asr, model: model, transport: transport))
        let round = await wake(runtime)
        await finishInput(runtime, round: round)
        guard await eventually({
            let state = await runtime.currentSnapshot()
            return state.session.phase == .awaitingNextRound && state.pendingTransportCommands == 0
        }) else { _ = await runtime.shutdown(); return }
        let state = await runtime.currentSnapshot(), requests = await model.requests, audioBytes = await asr.receivedAudioBytes
        XCTAssertEqual(state.session.transcript, "合成测试问题")
        XCTAssertEqual(state.session.response, "合成测试回答")
        XCTAssertEqual(state.session.completedRoundCount, 1)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(audioBytes, 4)
        let commands = await transport.admittedCommands
        let finalText = commands.firstIndex(of: .response(round: round, text: "合成测试回答", isFinal: true))!
        let completion = commands.firstIndex(of: .responseComplete(round: round))!
        XCTAssertLessThan(finalText, completion)
        XCTAssertFalse(commands.contains { if case .ttsStatus = $0 { return true }; return false })
        XCTAssertFalse(commands.contains { if case .exit = $0 { return true }; return false })
        _ = await runtime.shutdown()
    }

    func testMissingASRDoesNotStartPhysicalCaptureWork() async {
        let transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(dependencies: .init(model: SyntheticConversationModel(), transport: transport))
        _ = await wake(runtime)
        await eventually { await runtime.currentSnapshot().pendingTransportCommands == 0 }
        let state = await runtime.currentSnapshot(), commands = await transport.admittedCommands
        XCTAssertEqual(state.session.phase, .closed)
        XCTAssertEqual(state.lastIssue, .missingASR(.local))
        XCTAssertFalse(commands.contains { if case .startCapture = $0 { return true }; return false })
        _ = await runtime.shutdown()
    }

    func testCloudSelectionIsInjectedAndOfflineFallbackUsesLocalOnlyOnNextRound() async {
        let local = SyntheticASRProvider(), cloud = SyntheticASRProvider(source: .cloud)
        let runtime = SessionRuntime(configuration: .init(session: .init(asrPolicy: .preferCloudWithLocalFallback)),
            dependencies: .init(localASR: local, cloudASR: cloud, model: SyntheticConversationModel(), transport: RecordingGlassesTransport()))
        _ = await runtime.send(.connected); _ = await runtime.send(.networkChanged(isAvailable: true))
        let old = await runtime.send(.wake).session.currentRound!
        await eventually { await cloud.requests.count == 1 }
        _ = await runtime.send(.networkChanged(isAvailable: false))
        let stillCloud = await runtime.currentSnapshot().session.asrSource
        XCTAssertEqual(stillCloud, .cloud)
        let next = await runtime.send(.interrupt(round: old))
        XCTAssertEqual(next.session.asrSource, .local)
        await eventually { await local.requests.count == 1 }
        _ = await runtime.shutdown()
    }

    func testWrongASRProviderSourceFailsClosed() async {
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(source: .cloud),
            model: SyntheticConversationModel(), transport: RecordingGlassesTransport()))
        _ = await wake(runtime)
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.session.phase, .closed)
        XCTAssertEqual(state.lastIssue, .wrongASRProviderSource)
        _ = await runtime.shutdown()
    }

    func testAudioQueueOverflowFailsInsteadOfSilentlyDroppingSpeech() async {
        let clock = ManualRuntimeClock()
        let asr = SyntheticASRProvider(consumeInput: false, delayNanoseconds: 10_000_000_000, clock: clock)
        let runtime = SessionRuntime(configuration: .init(audioBufferChunks: 1), dependencies: .init(localASR: asr,
            model: SyntheticConversationModel(), transport: RecordingGlassesTransport(), clock: clock))
        let round = await wake(runtime)
        await eventually { await asr.requests.count == 1 }
        _ = await runtime.send(.audioReceived(round: round, chunk: pcm))
        let overflow = await runtime.send(.audioReceived(round: round, chunk: pcm))
        XCTAssertEqual(overflow.session.phase, .closed)
        XCTAssertEqual(overflow.lastIssue, .audioBackpressure)
        XCTAssertEqual(overflow.activeProviderTasks, 0)
        await eventually { await asr.cancelledRounds.contains(round) }
        _ = await runtime.shutdown()
        await eventually { await clock.pendingSleepCount == 0 }
    }

    func testSlowModelDoesNotBlockInterruptAndLateInjectedCallbackCannotReturn() async {
        let model = UncooperativeModel()
        let transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: model, transport: transport))
        let old = await wake(runtime); await finishInput(runtime, round: old)
        guard await eventually({ await model.pendingCount == 1 }) else { _ = await runtime.shutdown(); return }
        let after = await runtime.send(.interrupt(round: old))
        XCTAssertEqual(after.session.phase, .listening)
        XCTAssertEqual(after.session.currentRound!.index, old.index + 1)
        await model.release(old)
        await eventually { await model.cancelledRounds.contains(old) }
        for _ in 0..<20 { await Task.yield() }
        let state = await runtime.currentSnapshot(), commands = await transport.admittedCommands
        XCTAssertEqual(state.session.response, "")
        XCTAssertFalse(commands.contains(.response(round: old, text: "迟到的合成回答", isFinal: false)))
        _ = await runtime.shutdown()
    }

    func testTTSWaitsForFinalPlaybackDrainRatherThanModelOrAudioEOF() async {
        let clock = ManualRuntimeClock(), transport = RecordingGlassesTransport()
        let playback = SyntheticPlayback(drainNanoseconds: 1_000_000_000, clock: clock)
        let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled)),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
                synthesis: SyntheticSpeechSynthesis(), playback: playback, transport: transport, clock: clock))
        let round = await wake(runtime); await finishInput(runtime, round: round)
        guard await eventually({
            let draining = await playback.isDraining, sleepers = await clock.pendingSleepCount
            return draining && sleepers >= 2
        }) else { _ = await runtime.shutdown(); return }
        let before = await runtime.currentSnapshot(), beforeCommands = await transport.admittedCommands
        XCTAssertEqual(before.session.phase, .speaking)
        XCTAssertFalse(beforeCommands.contains(.responseComplete(round: round)))
        await clock.advance(by: 999_999_999)
        for _ in 0..<10 { await Task.yield() }
        let almost = await runtime.currentSnapshot().session.phase
        XCTAssertEqual(almost, .speaking)
        await clock.advance(by: 1)
        guard await eventually({
            let state = await runtime.currentSnapshot()
            return state.session.phase == .awaitingNextRound && state.pendingTransportCommands == 0
        }) else { _ = await runtime.shutdown(); return }
        let commands = await transport.admittedCommands, drained = await playback.drainedRounds
        XCTAssertEqual(drained, [round])
        XCTAssertLessThan(commands.firstIndex(of: .ttsStatus(round: round, status: .completed))!,
                          commands.firstIndex(of: .responseComplete(round: round))!)
        _ = await runtime.shutdown()
    }

    func testTTSInterruptStopsPlaybackAndDoesNotEmitOldCompletion() async {
        let clock = ManualRuntimeClock(), transport = RecordingGlassesTransport()
        let playback = SyntheticPlayback(drainNanoseconds: 10_000_000_000, clock: clock)
        let speech = SyntheticSpeechSynthesis()
        let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled)),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
                synthesis: speech, playback: playback, transport: transport, clock: clock))
        let old = await wake(runtime); await finishInput(runtime, round: old)
        guard await eventually({ await playback.isDraining }) else { _ = await runtime.shutdown(); return }
        _ = await runtime.send(.interrupt(round: old))
        await eventually { await playback.stoppedRounds.contains(old) }
        await clock.advance(by: 10_000_000_000)
        for _ in 0..<20 { await Task.yield() }
        let commands = await transport.admittedCommands, drained = await playback.drainedRounds
        XCTAssertFalse(commands.contains(.responseComplete(round: old)))
        XCTAssertFalse(drained.contains(old))
        _ = await runtime.shutdown()
    }

    func testSpeechDoesNotEnqueueAfterStartedEventDisconnectsAndCancelsItsTask() async {
        let asr = GatedSpeechASR(), model = GatedSpeechModel(), transport = FinalResponseGateTransport()
        let playback = CancellationInspectingPlayback(transport: transport)
        let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled), transportQueueCommands: 1),
            dependencies: .init(localASR: asr, model: model,
                synthesis: SyntheticSpeechSynthesis(), playback: playback, transport: transport))
        let round = await wake(runtime)
        guard await eventually({
            let pending = await runtime.currentSnapshot().pendingTransportCommands, ready = await asr.isReady
            return pending == 0 && ready
        }) else {
            _ = await runtime.shutdown(); await transport.release(); return
        }
        _ = await runtime.send(.audioEnded(round: round))
        guard await eventually({ await runtime.currentSnapshot().pendingTransportCommands == 0 }) else {
            _ = await runtime.shutdown(); await transport.release(); return
        }
        // Gate ASR too: an immediate final must not overflow the queue before the target TTS event.
        await asr.emitFinal()
        guard await eventually({
            let state = await runtime.currentSnapshot(), modelReady = await model.isReady
            return state.session.phase == .generating && state.pendingTransportCommands == 0 && modelReady
        }) else { _ = await runtime.shutdown(); await transport.release(); return }
        await model.emitText()
        guard await eventually({
            let state = await runtime.currentSnapshot()
            return state.session.response == "合成取消边界" && state.pendingTransportCommands == 0
        }) else { _ = await runtime.shutdown(); await transport.release(); return }
        // Hold only the final response: ttsStarted's status now overflows the one-command queue.
        await model.finish()
        await eventually { await runtime.currentSnapshot().session.phase == .disconnected }
        await eventually { await runtime.currentSnapshot().activeCleanupTasks == 0 }
        let state = await runtime.currentSnapshot(), calls = await playback.enqueuesAfterCancellation
        let stops = await playback.stopCount
        XCTAssertEqual(state.lastIssue, .transportBackpressure)
        XCTAssertEqual(calls, 0, "Do not start enqueue after ttsStarted delivery cancelled this exact speech task")
        XCTAssertEqual(stops, 1)
        _ = await runtime.shutdown()
        await transport.release()
        await eventually { await runtime.currentSnapshot().retiringTransportTasks == 0 }
    }

    func testTTSDeadlineDegradesToTextAndCancelsPlayer() async {
        let clock = ManualRuntimeClock(), playback = SyntheticPlayback(drainNanoseconds: 10_000_000_000, clock: ManualRuntimeClock())
        // Use the runtime's clock for the deadline; the player's separate clock deliberately never advances.
        let transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled, timeouts: .init(speechSeconds: 1))),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
                synthesis: SyntheticSpeechSynthesis(), playback: playback, transport: transport, clock: clock))
        let round = await wake(runtime); await finishInput(runtime, round: round)
        guard await eventually({
            let draining = await playback.isDraining, sleepers = await clock.pendingSleepCount
            return draining && sleepers >= 1
        }) else { _ = await runtime.shutdown(); return }
        await clock.advance(by: 1_000_000_000)
        await eventually { await runtime.currentSnapshot().session.phase == .awaitingNextRound }
        await eventually { await playback.stoppedRounds.contains(round) }
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.session.lastFailure, .timedOut)
        XCTAssertEqual(state.session.response, "合成测试回答")
        XCTAssertEqual(state.session.completedRoundCount, 1)
        _ = await runtime.shutdown()
    }

    func testMissingOrEmptyTTSCompletesTextWithoutClaimingPlayback() async {
        for empty in [false, true] {
            let transport = RecordingGlassesTransport(), playback = SyntheticPlayback()
            let synthesis: (any SpeechSynthesisProvider)? = empty ? SyntheticSpeechSynthesis(chunks: []) : nil
            let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled)),
                dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
                    synthesis: synthesis, playback: empty ? playback : nil, transport: transport))
            let round = await wake(runtime); await finishInput(runtime, round: round)
            await eventually { await runtime.currentSnapshot().session.phase == .awaitingNextRound }
            let state = await runtime.currentSnapshot(), starts = await playback.startedRounds
            XCTAssertEqual(state.lastIssue, empty ? .emptySpeechAudio : .missingSpeechProvider)
            XCTAssertTrue(starts.isEmpty)
            XCTAssertEqual(state.session.completedRoundCount, 1)
            _ = await runtime.shutdown()
        }
    }

    func testInvalidSpeechFormatFailsBeforePlaybackAndDegradesToText() async {
        let speech = SyntheticSpeechSynthesis(chunks: [.init(data: Data([1]), format: .pcm16LE(sampleRate: 16_000, channels: 1))])
        let playback = SyntheticPlayback()
        let runtime = SessionRuntime(configuration: .init(session: .init(ttsMode: .enabled)),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
                synthesis: speech, playback: playback, transport: RecordingGlassesTransport()))
        let round = await wake(runtime); await finishInput(runtime, round: round)
        await eventually { await runtime.currentSnapshot().session.phase == .awaitingNextRound }
        let state = await runtime.currentSnapshot(), starts = await playback.startedRounds
        XCTAssertEqual(state.lastIssue, .invalidSpeechAudio)
        XCTAssertTrue(starts.isEmpty)
        _ = await runtime.shutdown()
    }

    func testAutomaticNextRoundPreservesOldCompletionBeforeNewCapture() async {
        let transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(configuration: .init(session: .init(nextRoundMode: .automatic)),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport))
        let old = await wake(runtime); await finishInput(runtime, round: old)
        guard await eventually({
            let state = await runtime.currentSnapshot()
            return state.session.currentRound?.index == 1 && state.pendingTransportCommands == 0
        }) else { _ = await runtime.shutdown(); return }
        let new = await runtime.currentSnapshot().session.currentRound!
        let commands = await transport.admittedCommands
        XCTAssertLessThan(commands.firstIndex(of: .responseComplete(round: old))!, commands.firstIndex(of: .startCapture(round: new))!)
        XCTAssertEqual(commands.filter { $0 == .responseComplete(round: old) }.count, 1)
        _ = await runtime.shutdown()
    }

    func testManualSecondRoundCarriesInjectedProviderHistory() async {
        let model = SyntheticConversationModel()
        let active = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: model, transport: RecordingGlassesTransport()))
        let first = await wake(active); await finishInput(active, round: first)
        await eventually { await active.currentSnapshot().session.phase == .awaitingNextRound }
        let second = await active.send(.nextRound(round: first)).session.currentRound!
        await finishInput(active, round: second)
        await eventually { await active.currentSnapshot().session.completedRoundCount == 2 }
        let requests = await model.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.map(\.role), [.user, .assistant, .user])
        _ = await active.shutdown()
    }

    func testTransportQueueOverflowDisconnectsAndCancelsActiveRecognition() async {
        let clock = ManualRuntimeClock(), asr = SyntheticASRProvider()
        let transport = RecordingGlassesTransport(delayNanoseconds: 10_000_000_000, clock: clock)
        let runtime = SessionRuntime(configuration: .init(transportQueueCommands: 2),
            dependencies: .init(localASR: asr, model: SyntheticConversationModel(), transport: transport, clock: clock))
        let round = await wake(runtime)
        guard await eventually({ await transport.attemptedCommands.count == 1 }) else { _ = await runtime.shutdown(); return }
        _ = await runtime.send(.asrResult(round: round, source: .local, result: .init(revision: 0, text: "合成甲", isFinal: false)))
        let result = await runtime.send(.asrResult(round: round, source: .local, result: .init(revision: 1, text: "合成乙", isFinal: false)))
        XCTAssertEqual(result.lastIssue, .transportBackpressure)
        XCTAssertEqual(result.session.phase, .disconnected)
        XCTAssertEqual(result.pendingTransportCommands, 0)
        await eventually { await asr.cancelledRounds.contains(round) }
        _ = await runtime.shutdown()
    }

    func testTransportTimeoutCancelsSendWithoutWaitingForProviderDuration() async {
        let clock = ManualRuntimeClock()
        let transport = RecordingGlassesTransport(delayNanoseconds: 10_000_000_000, clock: clock)
        let runtime = SessionRuntime(configuration: .init(transportTimeoutMilliseconds: 50),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport, clock: clock))
        _ = await wake(runtime)
        guard await eventually({ await clock.pendingSleepCount >= 3 }) else { _ = await runtime.shutdown(); return }
        await clock.advance(by: 50_000_000)
        await eventually { await runtime.currentSnapshot().session.phase == .disconnected }
        let state = await runtime.currentSnapshot(), admitted = await transport.admittedCommands
        XCTAssertEqual(state.lastIssue, .transportTimedOut)
        XCTAssertTrue(admitted.isEmpty)
        _ = await runtime.shutdown()
        await eventually { await clock.pendingSleepCount == 0 }
    }

    func testTransportErrorFailsClosedAndOldCallbacksDoNotRestartIt() async {
        let transport = RecordingGlassesTransport(shouldFail: true)
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport))
        let round = await wake(runtime)
        await eventually { await runtime.currentSnapshot().session.phase == .disconnected }
        let old = await runtime.send(.modelFinished(round: round))
        XCTAssertEqual(old.lastIssue, .transportFailed)
        XCTAssertEqual(old.activeProviderTasks, 0)
        XCTAssertEqual(old.pendingTransportCommands, 0)
        _ = await runtime.shutdown()
    }

    func testCancellableDeadlineClosesListeningSession() async {
        let clock = ManualRuntimeClock(), transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(configuration: .init(session: .init(timeouts: .init(listeningSeconds: 1))),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport, clock: clock))
        let round = await wake(runtime)
        guard await eventually({
            let state = await runtime.currentSnapshot()
            let sleepers = await clock.pendingSleepCount
            return state.pendingTransportCommands == 0 && state.scheduledTimeouts == 1 && sleepers == 1
        }) else { _ = await runtime.shutdown(); return }
        await clock.advance(by: 1_000_000_000)
        await eventually { await runtime.currentSnapshot().session.phase == .closed }
        await eventually { await runtime.currentSnapshot().pendingTransportCommands == 0 }
        let commands = await transport.admittedCommands
        XCTAssertTrue(commands.contains(.exit(round: round, reason: .timeout)))
        _ = await runtime.shutdown()
    }

    func testDisconnectCancelsTimersAndLateTimeoutCannotAffectNewSession() async {
        let clock = ManualRuntimeClock(), runtime = SessionRuntime(configuration: .init(session: .init(timeouts: .init(listeningSeconds: 1))),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: RecordingGlassesTransport(), clock: clock))
        let old = await wake(runtime)
        _ = await runtime.send(.disconnected)
        await eventually {
            let state = await runtime.currentSnapshot(), sleepers = await clock.pendingSleepCount
            return sleepers == 0 && state.retiringTransportTasks == 0
        }
        await clock.advance(by: 2_000_000_000)
        let fresh = await wake(runtime)
        XCTAssertNotEqual(old.sessionID, fresh.sessionID)
        let state = await runtime.send(.timeout(round: old, stage: .listening))
        XCTAssertEqual(state.session.phase, .listening)
        XCTAssertEqual(state.session.currentRound, fresh)
        _ = await runtime.shutdown()
    }

    func testShutdownRejectsNewWorkAndCancelsAllTimers() async {
        let clock = ManualRuntimeClock(), asr = SyntheticASRProvider()
        let runtime = SessionRuntime(dependencies: .init(localASR: asr, model: SyntheticConversationModel(), transport: RecordingGlassesTransport(), clock: clock))
        let round = await wake(runtime)
        let stopped = await runtime.shutdown()
        XCTAssertTrue(stopped.isShutdown)
        XCTAssertEqual(stopped.activeProviderTasks, 0)
        XCTAssertEqual(stopped.scheduledTimeouts, 0)
        _ = await runtime.send(.connected); _ = await runtime.send(.wake)
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.session.phase, .disconnected)
        await eventually { await asr.cancelledRounds.contains(round) }
        await eventually { await clock.pendingSleepCount == 0 }
    }

    func testApprovalGateIsBoundToCurrentRoundAndInvalidatedOnInterrupt() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
            transport: RecordingGlassesTransport(), wallTime: { now }))
        let round = await wake(runtime)
        let request = ToolApprovalRequest(requestID: "runtime-pending", round: round, actionDescription: "合成操作，仅回执不执行",
                                         createdAt: now, expiresAt: now.addingTimeInterval(30))
        let registered = await runtime.registerToolApproval(request)
        XCTAssertEqual(registered, .registered)
        let unconfirmed = await runtime.resolveToolApproval(requestID: request.requestID, round: round, choice: .approve, evidence: .unconfirmed)
        XCTAssertEqual(unconfirmed, .rejected(.confirmationRequired))
        _ = await runtime.send(.interrupt(round: round))
        let late = await runtime.resolveToolApproval(requestID: request.requestID, round: round, choice: .approve, evidence: .explicitUserConfirmation)
        XCTAssertEqual(late, .rejected(.wrongRound))
        let lateRegistration = await runtime.registerToolApproval(request)
        XCTAssertEqual(lateRegistration, .rejected(.wrongRound))
        _ = await runtime.shutdown()
    }

    func testConcurrentUIConfirmationsReturnOneNewDecision() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
            transport: RecordingGlassesTransport(), wallTime: { now }))
        let round = await wake(runtime)
        _ = await runtime.registerToolApproval(.init(requestID: "same-request", round: round, actionDescription: "合成批准",
                                                      createdAt: now, expiresAt: now.addingTimeInterval(30)))
        let results = await withTaskGroup(of: ToolApprovalResult.self) { group in
            for _ in 0..<50 { group.addTask {
                await runtime.resolveToolApproval(requestID: "same-request", round: round, choice: .approve, evidence: .explicitUserConfirmation)
            } }
            var result: [ToolApprovalResult] = []
            for await value in group { result.append(value) }
            return result
        }
        XCTAssertEqual(results.filter { if case .resolved = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(results.filter { if case .alreadyResolved = $0 { return true }; return false }.count, 49)
        _ = await runtime.shutdown()
    }

    func testObservationBuffersAndSubscriberCountAreBounded() async {
        let runtime = SessionRuntime(configuration: .init(observationBufferUpdates: 1),
            dependencies: .init(model: SyntheticConversationModel(), transport: RecordingGlassesTransport()))
        var subscriptions: [SessionRuntimeObservation] = []
        for _ in 0..<8 { if let subscription = await runtime.observe() { subscriptions.append(subscription) } }
        let refused = await runtime.observe()
        XCTAssertNil(refused)
        for value in [true, false, true] { _ = await runtime.send(.networkChanged(isAvailable: value)) }
        let state = await runtime.currentSnapshot()
        XCTAssertGreaterThan(state.droppedObservationUpdates, 0)
        await runtime.stopObserving(subscriptions[0].id)
        let replacement = await runtime.observe()
        XCTAssertNotNil(replacement)
        _ = await runtime.shutdown()
    }

    func testFastCancelHookCannotHideUncooperativeProviderWorkFromCapacity() async {
        let asr = UncooperativeASR()
        let runtime = SessionRuntime(configuration: .init(maximumCleanupTasks: 2),
            dependencies: .init(localASR: asr, model: SyntheticConversationModel(), transport: RecordingGlassesTransport()))
        let first = await wake(runtime)
        guard await eventually({ await asr.pendingCount == 1 }) else { _ = await runtime.shutdown(); await asr.releaseAll(); return }
        let second = await runtime.send(.interrupt(round: first)).session.currentRound!
        guard await eventually({ await asr.pendingCount == 2 }) else { _ = await runtime.shutdown(); await asr.releaseAll(); return }
        _ = await runtime.send(.interrupt(round: second))
        await eventually { await asr.cancelledRounds.count == 2 }
        let held = await runtime.currentSnapshot()
        XCTAssertEqual(held.session.phase, .disconnected)
        XCTAssertEqual(held.lastIssue, .cleanupBackpressure)
        XCTAssertEqual(held.activeCleanupTasks, 2, "Fast cancel hooks must not free slots while original tasks are blocked")
        XCTAssertEqual(held.outstandingProviderLifecycles, 2)
        _ = await wake(runtime)
        let noThird = await asr.pendingCount
        XCTAssertEqual(noThird, 2)
        await asr.releaseAll()
        await eventually { await runtime.currentSnapshot().activeCleanupTasks == 0 }
        _ = await runtime.shutdown()
    }

    func testNoncooperativeTransportCannotAccumulateAcrossReconnects() async {
        let transport = UncooperativeTransport()
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport))
        _ = await wake(runtime)
        guard await eventually({ await transport.pendingCount == 1 }) else { _ = await runtime.shutdown(); await transport.releaseAll(); return }
        _ = await runtime.send(.disconnected)
        for _ in 0..<10 { _ = await runtime.send(.connected); _ = await runtime.send(.wake) }
        let state = await runtime.currentSnapshot(), pending = await transport.pendingCount
        XCTAssertEqual(state.session.phase, .disconnected)
        XCTAssertEqual(state.lastIssue, .transportCancellationBackpressure)
        XCTAssertEqual(state.retiringTransportTasks, 1)
        XCTAssertEqual(pending, 1, "Generation isolation does not allow a replacement writer while the original is still inside send")
        await transport.releaseAll()
        await eventually { await runtime.currentSnapshot().retiringTransportTasks == 0 }
        let stillDisconnected = await runtime.currentSnapshot().session.phase
        XCTAssertEqual(stillDisconnected, .disconnected, "Do not fabricate a connection when the old writer exits")
        _ = await wake(runtime)
        await eventually { await transport.pendingCount == 1 }
        _ = await runtime.shutdown()
        await transport.releaseAll()
        await eventually { await runtime.currentSnapshot().retiringTransportTasks == 0 }
    }

    func testClockFailureIsReportedInsteadOfLeavingAnUnprotectedSession() async {
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
            transport: RecordingGlassesTransport(), clock: FailingClock()))
        _ = await wake(runtime)
        await eventually {
            let state = await runtime.currentSnapshot()
            return [.closed, .disconnected].contains(state.session.phase) && state.scheduledTimeouts == 0
        }
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.lastIssue, .clockFailed)
        XCTAssertEqual(state.activeProviderTasks, 0)
        _ = await runtime.shutdown()
    }

    func testNoncooperativeClockRemainsAccountedAfterCancellationAndBlocksGrowth() async {
        let clock = UncooperativeClock()
        // Real tiny scheduling delay only; no network or device. Gives the timeout clock a chance to start.
        let transport = RecordingGlassesTransport(delayNanoseconds: 1_000_000)
        let runtime = SessionRuntime(configuration: .init(maximumPendingClockTasks: 3),
            dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(), transport: transport, clock: clock))
        let first = await wake(runtime)
        guard await eventually({
            let state = await runtime.currentSnapshot(), pending = await clock.pendingCount
            return state.pendingTransportCommands == 0 && state.retiringClockTasks >= 1 && pending >= 2
        }) else { _ = await runtime.shutdown(); await clock.releaseAll(); return }
        _ = await runtime.send(.interrupt(round: first))
        await eventually { await runtime.currentSnapshot().session.phase == .disconnected }
        for _ in 0..<5 { _ = await runtime.send(.connected); _ = await runtime.send(.wake) }
        let state = await runtime.currentSnapshot(), pending = await clock.pendingCount
        XCTAssertEqual(state.lastIssue, .clockBackpressure)
        XCTAssertLessThanOrEqual(state.outstandingClockTasks, 3)
        XCTAssertLessThanOrEqual(pending, 3)
        XCTAssertGreaterThan(state.retiringClockTasks, 0)
        _ = await runtime.shutdown()
        await clock.releaseAll()
        await eventually { await runtime.currentSnapshot().outstandingClockTasks == 0 }
    }

    func testNormalTransportCompletionDrainsQueuedFailureImmediately() async {
        let clock = UncooperativeClock(), transport = UncooperativeTransport(), asr = SyntheticASRProvider()
        let runtime = SessionRuntime(configuration: .init(maximumPendingClockTasks: 2),
            dependencies: .init(localASR: asr, model: SyntheticConversationModel(), transport: transport, clock: clock))
        let round = await wake(runtime)
        guard await eventually({
            let writers = await transport.pendingCount, sleepers = await clock.pendingCount
            return writers == 1 && sleepers == 2
        }) else { _ = await runtime.shutdown(); await transport.releaseAll(); await clock.releaseAll(); return }
        _ = await runtime.send(.asrResult(round: round, source: .local,
            result: .init(revision: 0, text: "合成排队文本", isFinal: false)))
        // First send returns normally; next queued command hits a full clock budget.
        // No further external send(event) is permitted to accidentally drain the internal error.
        await transport.releaseAll()
        await eventually { await runtime.currentSnapshot().session.phase == .disconnected }
        await eventually { await asr.cancelledRounds.contains(round) }
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.lastIssue, .clockBackpressure)
        XCTAssertEqual(state.activeProviderTasks, 0)
        _ = await runtime.shutdown()
        await transport.releaseAll(); await clock.releaseAll()
        await eventually { await runtime.currentSnapshot().outstandingClockTasks == 0 }
    }

    func testASRStreamWithoutFinalAndModelFailureAreNotMarkedSuccessful() async {
        for emptyASR in [true, false] {
            let asr = SyntheticASRProvider(transcripts: emptyASR ? [] : [.init(revision: 0, text: "合成问题", isFinal: true)])
            let runtime = SessionRuntime(dependencies: .init(localASR: asr,
                model: SyntheticConversationModel(shouldFail: !emptyASR), transport: RecordingGlassesTransport()))
            let round = await wake(runtime); await finishInput(runtime, round: round)
            await eventually { await runtime.currentSnapshot().session.phase == .closed }
            let state = await runtime.currentSnapshot()
            XCTAssertEqual(state.session.completedRoundCount, 0)
            XCTAssertEqual(state.lastIssue, .providerFailed(emptyASR ? .recognition : .model))
            _ = await runtime.shutdown()
        }
    }

    func testConcurrentExitInterruptAndFinalsCannotResurrectClosedSession() async {
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(), model: SyntheticConversationModel(),
            transport: RecordingGlassesTransport()))
        let round = await wake(runtime)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let event: VoiceSessionEvent = index == 20 ? .exitRequested(reason: .normal)
                        : index.isMultiple(of: 3) ? .interrupt(round: round)
                        : .asrResult(round: round, source: .local, result: .init(revision: UInt64(index), text: "合成确认", isFinal: true))
                    _ = await runtime.send(event)
                }
            }
        }
        let state = await runtime.currentSnapshot()
        XCTAssertEqual(state.session.phase, .closed)
        XCTAssertEqual(state.activeProviderTasks, 0)
        XCTAssertEqual(state.scheduledTimeouts, 0)
        let late = await runtime.send(.modelText(round: round, update: .init(revision: 100, text: "不应出现")))
        XCTAssertNotEqual(late.session.response, "不应出现")
        _ = await runtime.shutdown()
    }
}

/// Deliberately ignores task cancellation while waiting so the real runner must reject its late result.
private actor UncooperativeModel: ConversationModelProvider {
    private var pending: [RoundToken: CheckedContinuation<AsyncThrowingStream<ModelText, Error>, Never>] = [:]
    var pendingCount: Int { pending.count }
    private(set) var cancelledRounds: Set<RoundToken> = []
    func respond(to request: ModelRequest) async throws -> AsyncThrowingStream<ModelText, Error> {
        await withCheckedContinuation { pending[request.round] = $0 }
    }
    func cancel(round: RoundToken) async { cancelledRounds.insert(round) }
    func release(_ round: RoundToken) {
        let pair = AsyncThrowingStream<ModelText, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        pair.continuation.yield(.init(revision: 0, text: "迟到的合成回答")); pair.continuation.finish()
        pending.removeValue(forKey: round)?.resume(returning: pair.stream)
    }
}

private actor UncooperativeASR: ASRProvider {
    nonisolated let source: ASRSource = .local
    private var pending: [RoundToken: CheckedContinuation<AsyncThrowingStream<ASRTranscript, Error>, Never>] = [:]
    var pendingCount: Int { pending.count }
    private(set) var cancelledRounds: Set<RoundToken> = []
    func recognize(_ request: ASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>) async throws -> AsyncThrowingStream<ASRTranscript, Error> {
        await withCheckedContinuation { pending[request.round] = $0 }
    }
    func cancel(round: RoundToken) async { cancelledRounds.insert(round) }
    func releaseAll() {
        let values = pending.values; pending.removeAll()
        for continuation in values {
            let pair = AsyncThrowingStream<ASRTranscript, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
            pair.continuation.finish(); continuation.resume(returning: pair.stream)
        }
    }
}

private actor UncooperativeTransport: GlassesSessionTransport {
    private var pending: [UUID: CheckedContinuation<Void, Never>] = [:]
    var pendingCount: Int { pending.count }
    func send(_ command: GlassesSessionCommand) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in pending[UUID()] = continuation }
    }
    func releaseAll() {
        let values = pending.values; pending.removeAll()
        for continuation in values { continuation.resume() }
    }
}

private struct FailingClock: SessionRuntimeClock {
    func sleep(nanoseconds: UInt64) async throws { throw SyntheticProviderError.configuredFailure }
}

private actor UncooperativeClock: SessionRuntimeClock {
    private var pending: [UUID: CheckedContinuation<Void, Never>] = [:]
    var pendingCount: Int { pending.count }
    func sleep(nanoseconds: UInt64) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in pending[UUID()] = continuation }
    }
    func releaseAll() {
        let values = pending.values; pending.removeAll()
        for continuation in values { continuation.resume() }
    }
}

private actor GatedSpeechASR: ASRProvider {
    nonisolated let source: ASRSource = .local
    private var continuation: AsyncThrowingStream<ASRTranscript, Error>.Continuation?
    var isReady: Bool { continuation != nil }
    func recognize(_ request: ASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>) async throws -> AsyncThrowingStream<ASRTranscript, Error> {
        let pair = AsyncThrowingStream<ASRTranscript, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        continuation = pair.continuation
        return pair.stream
    }
    func emitFinal() { continuation?.yield(.init(revision: 1, text: "合成测试", isFinal: true)); continuation?.finish() }
    func cancel(round: RoundToken) async { continuation?.finish() }
}

private actor GatedSpeechModel: ConversationModelProvider {
    private var continuation: AsyncThrowingStream<ModelText, Error>.Continuation?
    var isReady: Bool { continuation != nil }
    func respond(to request: ModelRequest) async throws -> AsyncThrowingStream<ModelText, Error> {
        let pair = AsyncThrowingStream<ModelText, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        continuation = pair.continuation
        return pair.stream
    }
    func emitText() { continuation?.yield(.init(revision: 1, text: "合成取消边界")) }
    func finish() { continuation?.finish() }
    func cancel(round: RoundToken) async { continuation?.finish() }
}

private actor FinalResponseGateTransport: GlassesSessionTransport {
    private var blocked: CheckedContinuation<Void, Never>?
    var isBlocked: Bool { blocked != nil }
    func send(_ command: GlassesSessionCommand) async throws {
        if case .response(_, _, true) = command { await withCheckedContinuation { blocked = $0 } }
        try Task.checkCancellation()
    }
    func release() { blocked?.resume(); blocked = nil }
}

private actor CancellationInspectingPlayback: SpeechPlaybackAdapter {
    let transport: FinalResponseGateTransport
    private(set) var enqueuesAfterCancellation = 0
    private(set) var stopCount = 0
    init(transport: FinalResponseGateTransport) { self.transport = transport }
    func start(round: RoundToken, format: AudioFormat) async throws {
        while !(await transport.isBlocked) { try await Task.sleep(nanoseconds: 1_000_000) }
    }
    func enqueue(_ chunk: AudioChunk, round: RoundToken) async throws {
        if Task.isCancelled { enqueuesAfterCancellation += 1 }
        try Task.checkCancellation()
    }
    func finishAndDrain(round: RoundToken) async throws {}
    func stop(round: RoundToken) async { stopCount += 1 }
}
