import XCTest
@testable import RayNeoSession

final class VoiceSessionMachineTests: XCTestCase {
    private func listening(_ configuration: VoiceSessionConfiguration = .init(), online: Bool = true) -> VoiceSessionMachine {
        var machine = VoiceSessionMachine(configuration: configuration)
        _ = machine.handle(.connected); _ = machine.handle(.networkChanged(isAvailable: online)); _ = machine.handle(.wake)
        return machine
    }
    private func recognize(_ machine: inout VoiceSessionMachine, _ text: String = "三加四等于几") -> [VoiceSessionEffect] {
        machine.handle(.asrResult(round: machine.snapshot.currentRound!, source: machine.snapshot.asrSource!,
                                  result: .init(revision: 1, text: text, isFinal: true)))
    }
    private func answer(_ machine: inout VoiceSessionMachine, _ text: String = "等于七") -> [VoiceSessionEffect] {
        let round = machine.snapshot.currentRound!
        _ = machine.handle(.modelText(round: round, update: .init(revision: 0, text: text)))
        return machine.handle(.modelFinished(round: round))
    }
    private func modelRequests(_ effects: [VoiceSessionEffect]) -> [ModelRequest] {
        effects.compactMap { if case let .requestModel(request) = $0 { return request }; return nil }
    }
    private func completionCount(_ effects: [VoiceSessionEffect]) -> Int {
        effects.filter { if case .responseComplete = $0 { return true }; return false }.count
    }

    func testWakeRequiresConnectionAndDuplicateWakeDoesNotRestart() {
        var machine = VoiceSessionMachine()
        XCTAssertTrue(machine.handle(.wake).isEmpty)
        _ = machine.handle(.connected)
        let effects = machine.handle(.wake)
        let first = machine.snapshot.currentRound!
        XCTAssertEqual(machine.snapshot.phase, .listening)
        XCTAssertEqual(effects.first, .startRecognition(.init(round: first, source: .local, language: "zh")))
        XCTAssertTrue(effects.contains(.startCapture(round: first)))
        XCTAssertTrue(machine.handle(.wake).isEmpty)
        XCTAssertEqual(machine.snapshot.currentRound, first)
    }

    func testCloudPolicySelectsOneSourceAtRoundStartAndDoesNotSilentlySwitch() {
        XCTAssertEqual(ASRPolicy.localOnly.source(networkAvailable: true), .local)
        XCTAssertNil(ASRPolicy.cloudOnly.source(networkAvailable: false))
        XCTAssertEqual(ASRPolicy.preferCloudWithLocalFallback.source(networkAvailable: false), .local)
        var machine = listening(.init(asrPolicy: .preferCloudWithLocalFallback))
        XCTAssertEqual(machine.snapshot.asrSource, .cloud)
        _ = machine.handle(.networkChanged(isAvailable: false))
        XCTAssertEqual(machine.snapshot.asrSource, .cloud)
        _ = machine.handle(.interrupt(round: machine.snapshot.currentRound!))
        XCTAssertEqual(machine.snapshot.asrSource, .local)
    }

    func testCloudOnlyOfflineFailsWithoutOpeningCapture() {
        var machine = VoiceSessionMachine(configuration: .init(asrPolicy: .cloudOnly))
        _ = machine.handle(.connected)
        let effects = machine.handle(.wake)
        XCTAssertEqual(machine.snapshot.phase, .closed)
        XCTAssertEqual(machine.snapshot.lastFailure, .networkUnavailable)
        XCTAssertFalse(effects.contains { if case .startCapture = $0 { return true }; return false })
        XCTAssertFalse(effects.contains { if case .startRecognition = $0 { return true }; return false })
    }

    func testValidAudioRoutesOnlyDuringCapture() {
        var machine = listening()
        let round = machine.snapshot.currentRound!
        let chunk = AudioChunk(data: Data([0, 0, 1, 0]), format: .pcm16LE(sampleRate: 16_000, channels: 1))
        XCTAssertEqual(machine.handle(.audioReceived(round: round, chunk: chunk)), [.feedRecognition(round: round, chunk: chunk)])
        _ = machine.handle(.audioEnded(round: round))
        XCTAssertTrue(machine.handle(.audioReceived(round: round, chunk: chunk)).isEmpty)
    }

    func testAudioEndRequestsFinalASRButDoesNotStartModel() {
        var machine = listening()
        let round = machine.snapshot.currentRound!
        let effects = machine.handle(.audioEnded(round: round))
        XCTAssertEqual(machine.snapshot.phase, .awaitingTranscript)
        XCTAssertTrue(effects.contains(.stopCapture(round: round)))
        XCTAssertTrue(effects.contains(.finishRecognition(round: round)))
        XCTAssertTrue(modelRequests(effects).isEmpty)
        XCTAssertTrue(machine.handle(.audioEnded(round: round)).isEmpty)
        XCTAssertEqual(modelRequests(recognize(&machine)).count, 1)
    }

    func testPartialRevisionsAndWrongSourceCannotOverwriteChosenTranscript() {
        var machine = listening()
        let round = machine.snapshot.currentRound!
        _ = machine.handle(.asrResult(round: round, source: .local, result: .init(revision: 5, text: "三加四", isFinal: false)))
        XCTAssertTrue(machine.handle(.asrResult(round: round, source: .local, result: .init(revision: 4, text: "旧", isFinal: false))).isEmpty)
        XCTAssertTrue(machine.handle(.asrResult(round: round, source: .cloud, result: .init(revision: 6, text: "云", isFinal: true))).isEmpty)
        XCTAssertEqual(machine.snapshot.transcript, "三加四")
        XCTAssertEqual(machine.snapshot.phase, .listening)
    }

    func testFinalStopsCaptureAndRequestsExactlyOneModelRun() {
        var machine = listening()
        let round = machine.snapshot.currentRound!
        let effects = recognize(&machine)
        XCTAssertEqual(machine.snapshot.phase, .generating)
        XCTAssertTrue(effects.contains(.stopCapture(round: round)))
        XCTAssertTrue(effects.contains(.cancelRecognition(round: round)))
        XCTAssertEqual(modelRequests(effects).count, 1)
        XCTAssertTrue(recognize(&machine, "重复 final").isEmpty)
        XCTAssertEqual(machine.snapshot.transcript, "三加四等于几")
    }

    func testEmptyFinalDoesNotInvokeModel() {
        var machine = listening()
        let effects = recognize(&machine, " \n ")
        XCTAssertEqual(machine.snapshot.phase, .closed)
        XCTAssertEqual(machine.snapshot.lastFailure, .emptyTranscript)
        XCTAssertTrue(modelRequests(effects).isEmpty)
    }

    func testModelFullSnapshotsHandleGapsAndRejectOldRevisions() {
        var machine = listening(); _ = recognize(&machine)
        let round = machine.snapshot.currentRound!
        _ = machine.handle(.modelText(round: round, update: .init(revision: 0, text: "等")))
        _ = machine.handle(.modelText(round: round, update: .init(revision: 8, text: "等于七")))
        XCTAssertTrue(machine.handle(.modelText(round: round, update: .init(revision: 7, text: "等于"))).isEmpty)
        XCTAssertTrue(machine.handle(.modelText(round: round, update: .init(revision: 8, text: "重复"))).isEmpty)
        XCTAssertEqual(machine.snapshot.response, "等于七")
    }

    func testTextOnlyCompletesWithoutTTSAndDoesNotExitPage() {
        var machine = listening(); _ = recognize(&machine)
        let round = machine.snapshot.currentRound!
        let effects = answer(&machine)
        XCTAssertEqual(machine.snapshot.phase, .awaitingNextRound)
        XCTAssertEqual(completionCount(effects), 1)
        XCTAssertFalse(effects.contains { if case .requestExit = $0 { return true }; return false })
        XCTAssertFalse(effects.contains { if case .synthesizeAndPlay = $0 { return true }; return false })
        XCTAssertTrue(machine.handle(.modelFinished(round: round)).isEmpty)
        XCTAssertTrue(machine.handle(.ttsPlaybackDrained(round: round)).isEmpty)
    }

    func testTTSCompletionSeparatesModelEndInputEndAndFinalDrain() {
        var machine = listening(.init(ttsMode: .enabled)); _ = recognize(&machine)
        let round = machine.snapshot.currentRound!
        let modelEnd = answer(&machine)
        XCTAssertEqual(machine.snapshot.phase, .speaking)
        XCTAssertEqual(completionCount(modelEnd), 0)
        XCTAssertTrue(machine.handle(.ttsPlaybackDrained(round: round)).isEmpty, "Interim empty queue cannot complete speech")
        XCTAssertEqual(machine.handle(.ttsStarted(round: round)), [.reportTTSStatus(round: round, status: .began)])
        XCTAssertTrue(machine.handle(.ttsInputFinished(round: round)).isEmpty)
        XCTAssertEqual(machine.snapshot.phase, .speaking)
        let drain = machine.handle(.ttsPlaybackDrained(round: round))
        XCTAssertTrue(drain.contains(.reportTTSStatus(round: round, status: .completed)))
        XCTAssertEqual(completionCount(drain), 1)
        XCTAssertEqual(machine.snapshot.phase, .awaitingNextRound)
        XCTAssertTrue(machine.handle(.ttsPlaybackDrained(round: round)).isEmpty)
    }

    func testTTSStatusGuardsPauseResumeAndDuplicates() {
        var machine = listening(.init(ttsMode: .enabled)); _ = recognize(&machine); _ = answer(&machine)
        let round = machine.snapshot.currentRound!
        XCTAssertTrue(machine.handle(.ttsPaused(round: round)).isEmpty)
        _ = machine.handle(.ttsStarted(round: round))
        XCTAssertTrue(machine.handle(.ttsStarted(round: round)).isEmpty)
        XCTAssertEqual(machine.handle(.ttsPaused(round: round)), [.reportTTSStatus(round: round, status: .paused)])
        XCTAssertTrue(machine.handle(.ttsProgress(round: round)).isEmpty)
        XCTAssertEqual(machine.handle(.ttsResumed(round: round)), [.reportTTSStatus(round: round, status: .resumed)])
        XCTAssertEqual(machine.handle(.ttsProgress(round: round)), [.reportTTSStatus(round: round, status: .progress)])
    }

    func testEmptyResponseDoesNotWaitForImpossibleTTS() {
        var machine = listening(.init(ttsMode: .enabled)); _ = recognize(&machine)
        let effects = answer(&machine, "")
        XCTAssertEqual(machine.snapshot.phase, .awaitingNextRound)
        XCTAssertEqual(completionCount(effects), 1)
    }

    func testTTSFailureFallsBackToTextCompletion() {
        var machine = listening(.init(ttsMode: .enabled)); _ = recognize(&machine); _ = answer(&machine)
        let round = machine.snapshot.currentRound!
        let effects = machine.handle(.failed(round: round, stage: .speech, failure: .providerFailure))
        XCTAssertEqual(machine.snapshot.phase, .awaitingNextRound)
        XCTAssertEqual(machine.snapshot.response, "等于七")
        XCTAssertEqual(completionCount(effects), 1)
        XCTAssertTrue(effects.contains(.cancelWork(round: round)))
        XCTAssertTrue(machine.handle(.ttsInputFinished(round: round)).isEmpty)
    }

    func testModelTimeoutClosesButSpeechTimeoutCompletesText() {
        var model = listening(); _ = recognize(&model)
        _ = model.handle(.timeout(round: model.snapshot.currentRound!, stage: .model))
        XCTAssertEqual(model.snapshot.phase, .closed)
        XCTAssertEqual(model.snapshot.lastExitReason, .timeout)
        var speech = listening(.init(ttsMode: .enabled)); _ = recognize(&speech); _ = answer(&speech)
        let effects = speech.handle(.timeout(round: speech.snapshot.currentRound!, stage: .speech))
        XCTAssertEqual(speech.snapshot.phase, .awaitingNextRound)
        XCTAssertEqual(completionCount(effects), 1)
    }

    func testInterruptAdvancesGenerationAndRejectsAllLateProviderResults() {
        var machine = listening(.init(ttsMode: .enabled)); _ = recognize(&machine); _ = answer(&machine)
        let old = machine.snapshot.currentRound!
        let effects = machine.handle(.interrupt(round: old))
        let current = machine.snapshot.currentRound!
        XCTAssertEqual(current.sessionID, old.sessionID)
        XCTAssertEqual(current.index, old.index + 1)
        XCTAssertTrue(effects.contains(.cancelWork(round: old)))
        XCTAssertTrue(effects.contains(.invalidateToolApprovals(round: old)))
        for event in lateEvents(old) { XCTAssertTrue(machine.handle(event).isEmpty) }
        XCTAssertEqual(machine.snapshot.phase, .listening)
        XCTAssertEqual(machine.snapshot.response, "")
    }

    func testExitAndDisconnectRejectLateResultsWithoutMoreDeviceCommands() {
        for disconnect in [false, true] {
            var machine = listening(); _ = recognize(&machine)
            let round = machine.snapshot.currentRound!
            let effects = machine.handle(disconnect ? .disconnected : .exitRequested(reason: .normal))
            XCTAssertTrue(effects.contains(.cancelWork(round: round)))
            XCTAssertFalse(machine.accepts(round))
            for event in lateEvents(round) { XCTAssertTrue(machine.handle(event).isEmpty) }
            if disconnect {
                XCTAssertFalse(effects.contains { if case .requestExit = $0 { return true }; return false })
                XCTAssertFalse(effects.contains(.stopCapture(round: round)))
            }
        }
    }

    func testDisconnectDuringCaptureCancelsLocalWorkWithoutSendingToDeadTransport() {
        var machine = listening(); let round = machine.snapshot.currentRound!
        let effects = machine.handle(.disconnected)
        XCTAssertEqual(machine.snapshot.phase, .disconnected)
        XCTAssertTrue(effects.contains(.cancelWork(round: round)))
        XCTAssertFalse(effects.contains(.stopCapture(round: round)))
        XCTAssertTrue(machine.handle(.disconnected).isEmpty)
    }

    func testReconnectWakeUsesNewSessionIdentity() {
        var machine = listening(); let old = machine.snapshot.currentRound!
        _ = machine.handle(.disconnected); _ = machine.handle(.connected); _ = machine.handle(.wake)
        XCTAssertNotEqual(machine.snapshot.currentRound!.sessionID, old.sessionID)
        XCTAssertEqual(machine.snapshot.currentRound!.index, 0)
        XCTAssertTrue(machine.handle(.timeout(round: old, stage: .listening)).isEmpty)
    }

    func testManualNextRoundIsAcceptedOnlyAfterCompletionAndOldDuplicateIsIgnored() {
        var machine = listening(); let old = machine.snapshot.currentRound!
        XCTAssertTrue(machine.handle(.nextRound(round: old)).isEmpty)
        _ = recognize(&machine); _ = answer(&machine)
        _ = machine.handle(.nextRound(round: old))
        XCTAssertEqual(machine.snapshot.phase, .listening)
        XCTAssertEqual(machine.snapshot.currentRound!.index, 1)
        XCTAssertTrue(machine.handle(.nextRound(round: old)).isEmpty)
    }

    func testAutomaticNextRoundOccursAfterTextCompletionOnly() {
        var machine = listening(.init(nextRoundMode: .automatic)); let old = machine.snapshot.currentRound!
        _ = recognize(&machine)
        let effects = answer(&machine)
        XCTAssertEqual(machine.snapshot.phase, .listening)
        XCTAssertEqual(machine.snapshot.currentRound!.index, 1)
        XCTAssertEqual(completionCount(effects), 1)
        XCTAssertTrue(effects.contains(.responseComplete(round: old)))
        XCTAssertEqual(machine.snapshot.completedRoundCount, 1)
    }

    func testNextRoundDeadlineRequestsPageExitNotAnotherRoundCompletion() {
        var machine = listening(); _ = recognize(&machine); _ = answer(&machine)
        let round = machine.snapshot.currentRound!
        let effects = machine.handle(.timeout(round: round, stage: .nextRound))
        XCTAssertEqual(machine.snapshot.phase, .closed)
        XCTAssertTrue(effects.contains(.requestExit(round: round, reason: .timeout)))
        XCTAssertEqual(completionCount(effects), 0)
    }

    func testGlassesExitDoesNotEchoPhoneExit() {
        var machine = listening(); let round = machine.snapshot.currentRound!
        XCTAssertTrue(machine.handle(.exitRequested(reason: .glassesExit)).isEmpty)
        XCTAssertTrue(machine.handle(.exitRequested(reason: .disconnected)).isEmpty)
        let effects = machine.handle(.glassesExited(round: round))
        XCTAssertEqual(machine.snapshot.lastExitReason, .glassesExit)
        XCTAssertFalse(effects.contains { if case .requestExit = $0 { return true }; return false })
    }

    func testContinuousConversationCarriesOnlyCompletedPairsAndBoundedHistory() {
        var machine = listening(.init(maximumHistoryTurns: 1))
        _ = recognize(&machine, "一"); _ = answer(&machine, "二")
        _ = machine.handle(.nextRound(round: machine.snapshot.currentRound!))
        let second = modelRequests(recognize(&machine, "三")).first!
        XCTAssertEqual(second.messages.map(\.text), ["一", "二", "三"])
        _ = answer(&machine, "四")
        _ = machine.handle(.nextRound(round: machine.snapshot.currentRound!))
        let third = modelRequests(recognize(&machine, "五")).first!
        XCTAssertEqual(third.messages.map(\.text), ["三", "四", "五"])
        _ = machine.handle(.interrupt(round: machine.snapshot.currentRound!))
        let interrupted = modelRequests(recognize(&machine, "六")).first!
        XCTAssertEqual(interrupted.messages.map(\.text), ["三", "四", "六"], "Interrupted incomplete pair is not committed")
    }

    func testNewWakeClearsOldConversation() {
        var machine = listening(); _ = recognize(&machine, "旧问"); _ = answer(&machine, "旧答")
        _ = machine.handle(.exitRequested(reason: .normal)); _ = machine.handle(.wake)
        XCTAssertEqual(modelRequests(recognize(&machine, "新问")).first!.messages.map(\.text), ["新问"])
    }

    func testOversizedTextFailsBeforeDisplayOrModel() {
        var machine = listening(.init(maximumTextCharacters: 3))
        let effects = recognize(&machine, "四个汉字")
        XCTAssertEqual(machine.snapshot.lastFailure, .textLimitExceeded)
        XCTAssertTrue(modelRequests(effects).isEmpty)
        var model = listening(.init(maximumTextCharacters: 3)); _ = recognize(&model, "问")
        _ = model.handle(.modelText(round: model.snapshot.currentRound!, update: .init(revision: 0, text: "四个汉字")))
        XCTAssertEqual(model.snapshot.phase, .closed)
        XCTAssertEqual(model.snapshot.response, "")
    }

    func testAudioValidationDoesNotGuessEncodingFromPacketLength() {
        XCTAssertFalse(AudioChunk(data: Data([1]), format: .pcm16LE(sampleRate: 16_000, channels: 1)).isValid)
        XCTAssertFalse(AudioChunk(data: Data([0, 0]), format: .pcm16LE(sampleRate: 16_000, channels: 0)).isValid)
        XCTAssertFalse(AudioChunk(data: Data(repeating: 0, count: 65_537), format: .opus(sampleRate: 16_000, channels: 1)).isValid)
        XCTAssertTrue(AudioChunk(data: Data([1]), format: .opus(sampleRate: 16_000, channels: 1)).isValid,
                      "Framing bounds are not codec validity; decoder must validate Opus")
        var machine = listening()
        _ = machine.handle(.audioReceived(round: machine.snapshot.currentRound!, chunk: .init(data: Data(), format: .opus(sampleRate: 16_000, channels: 1))))
        XCTAssertEqual(machine.snapshot.lastFailure, .invalidAudio)
        XCTAssertEqual(machine.snapshot.phase, .closed)
    }

    func testTimeoutAndFailureForInactiveStagesAreIgnored() {
        var machine = listening(); let round = machine.snapshot.currentRound!
        XCTAssertTrue(machine.handle(.timeout(round: round, stage: .speech)).isEmpty)
        XCTAssertTrue(machine.handle(.failed(round: round, stage: .model, failure: .providerFailure)).isEmpty)
        _ = recognize(&machine)
        XCTAssertTrue(machine.handle(.timeout(round: round, stage: .listening)).isEmpty)
    }

    func testConfigurationIsBounded() {
        let value = VoiceSessionConfiguration(language: String(repeating: "a", count: 100), maximumTextCharacters: .max,
                                             maximumHistoryTurns: .max, timeouts: .init(listeningSeconds: 0, speechSeconds: .max))
        XCTAssertEqual(value.language.count, 64)
        XCTAssertEqual(value.maximumTextCharacters, 65_536)
        XCTAssertEqual(value.maximumHistoryTurns, 32)
        XCTAssertEqual(value.timeouts.listeningSeconds, 1)
        XCTAssertEqual(value.timeouts.speechSeconds, 600)
    }

    func testCombiningScalarsCannotBypassTextByteLimits() {
        let oversizedSingleCharacter = "a" + String(repeating: "\u{0301}", count: 100)
        XCTAssertEqual(oversizedSingleCharacter.count, 1)
        var asr = listening(.init(maximumTextCharacters: 10, maximumTextUTF8Bytes: 64))
        XCTAssertTrue(modelRequests(recognize(&asr, oversizedSingleCharacter)).isEmpty)
        XCTAssertEqual(asr.snapshot.lastFailure, .textLimitExceeded)
        var model = listening(.init(maximumTextCharacters: 10, maximumTextUTF8Bytes: 64)); _ = recognize(&model, "问")
        _ = model.handle(.modelText(round: model.snapshot.currentRound!, update: .init(revision: 0, text: oversizedSingleCharacter)))
        XCTAssertEqual(model.snapshot.lastFailure, .textLimitExceeded)
        let language = VoiceSessionConfiguration(language: "a" + String(repeating: "\u{0301}", count: 300)).language
        XCTAssertLessThanOrEqual(language.utf8.count, 256)
    }

    func testAutomaticContinuationKeepsOldCompletionAndCleanupDespiteNewSnapshotToken() {
        var machine = listening(.init(nextRoundMode: .automatic)); let old = machine.snapshot.currentRound!
        _ = recognize(&machine)
        let effects = answer(&machine)
        let current = machine.snapshot.currentRound!
        XCTAssertNotEqual(old, current)
        let output = effects.filter { $0.executionPolicy != .currentRoundWork || $0.round == current }
        XCTAssertTrue(output.contains(.responseComplete(round: old)))
        XCTAssertTrue(output.contains(.cancelWork(round: old)))
        XCTAssertTrue(output.contains(.invalidateToolApprovals(round: old)))
        XCTAssertTrue(output.contains(.cancelTimeout(round: old, stage: .speech)))
        XCTAssertTrue(output.contains(.startCapture(round: current)))
        let completionIndex = output.firstIndex(of: .responseComplete(round: old))!
        let newCaptureIndex = output.firstIndex(of: .startCapture(round: current))!
        XCTAssertLessThan(completionIndex, newCaptureIndex)
        XCTAssertEqual(VoiceSessionEffect.stopCapture(round: old).executionPolicy, .cleanup)
        XCTAssertEqual(VoiceSessionEffect.requestExit(round: old, reason: .normal).executionPolicy, .orderedOutput)
    }

    func testConcurrentFinalsAreSerializedAndInvokeOnlyOneModel() async {
        let coordinator = VoiceSessionCoordinator()
        _ = await coordinator.send(.connected)
        let transition = await coordinator.send(.wake)
        let round = transition.snapshot.currentRound!
        let effects = await withTaskGroup(of: [VoiceSessionEffect].self) { group in
            for revision in 0..<40 {
                group.addTask {
                    await coordinator.send(.asrResult(round: round, source: .local,
                        result: .init(revision: UInt64(revision), text: "同一 final", isFinal: true))).effects
                }
            }
            var result: [VoiceSessionEffect] = []
            for await item in group { result += item }
            return result
        }
        XCTAssertEqual(modelRequests(effects).count, 1)
        let state = await coordinator.currentSnapshot()
        XCTAssertEqual(state.phase, .generating)
    }

    func testConcurrentExitAndProviderCallbacksEndClosedAndRejectSubsequentWork() async {
        let coordinator = VoiceSessionCoordinator()
        _ = await coordinator.send(.connected)
        let round = await coordinator.send(.wake).snapshot.currentRound!
        await withTaskGroup(of: Void.self) { group in
            for revision in 0..<40 {
                group.addTask {
                    _ = await coordinator.send(.asrResult(round: round, source: .local,
                        result: .init(revision: UInt64(revision), text: "确认", isFinal: true)))
                }
            }
            group.addTask { _ = await coordinator.send(.exitRequested(reason: .normal)) }
        }
        let state = await coordinator.currentSnapshot()
        XCTAssertEqual(state.phase, .closed)
        for event in lateEvents(round) {
            let transition = await coordinator.send(event)
            XCTAssertTrue(transition.effects.isEmpty)
            XCTAssertEqual(transition.snapshot.phase, .closed)
        }
    }

    private func lateEvents(_ round: RoundToken) -> [VoiceSessionEvent] {
        [.audioEnded(round: round), .asrResult(round: round, source: .local, result: .init(revision: 100, text: "迟到", isFinal: true)),
         .modelText(round: round, update: .init(revision: 100, text: "迟到")), .modelFinished(round: round),
         .ttsStarted(round: round), .ttsInputFinished(round: round), .ttsPlaybackDrained(round: round),
         .timeout(round: round, stage: .listening), .timeout(round: round, stage: .model),
         .failed(round: round, stage: .recognition, failure: .providerFailure), .nextRound(round: round), .glassesExited(round: round)]
    }
}
