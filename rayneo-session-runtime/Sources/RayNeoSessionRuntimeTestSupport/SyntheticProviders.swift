import Foundation
import RayNeoSession
import RayNeoSessionRuntime

public enum SyntheticProviderError: Error { case configuredFailure, wrongPlaybackRound }

/// Consumes bytes without decoding them and emits configured fixture text. NOT speech recognition.
public actor SyntheticASRProvider: ASRProvider {
    public nonisolated let source: ASRSource
    private let transcripts: [ASRTranscript]
    private let consumeInput: Bool
    private let delayNanoseconds: UInt64
    private let clock: any SessionRuntimeClock
    public private(set) var requests: [ASRRequest] = []
    public private(set) var cancelledRounds: Set<RoundToken> = []
    public private(set) var receivedAudioBytes = 0

    public init(source: ASRSource = .local, transcripts: [ASRTranscript] = [.init(revision: 0, text: "合成测试问题", isFinal: true)],
                consumeInput: Bool = true, delayNanoseconds: UInt64 = 0,
                clock: any SessionRuntimeClock = SystemSessionRuntimeClock()) {
        self.source = source; self.transcripts = Array(transcripts.prefix(64)); self.consumeInput = consumeInput
        self.delayNanoseconds = delayNanoseconds; self.clock = clock
    }

    public func recognize(_ request: ASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>)
        async throws -> AsyncThrowingStream<ASRTranscript, Error> {
        requests.append(request)
        if consumeInput {
            for try await chunk in audio { try Task.checkCancellation(); receivedAudioBytes += chunk.data.count }
        }
        if delayNanoseconds > 0 { try await clock.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        let pair = AsyncThrowingStream<ASRTranscript, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        for value in transcripts { pair.continuation.yield(value) }
        pair.continuation.finish()
        return pair.stream
    }

    public func cancel(round: RoundToken) async { cancelledRounds.insert(round) }
}

/// Returns fixture snapshots, never contacts a model or infers from the supplied prompt.
public actor SyntheticConversationModel: ConversationModelProvider {
    private let texts: [String]
    private let delayNanoseconds: UInt64
    private let clock: any SessionRuntimeClock
    private let shouldFail: Bool
    public private(set) var requests: [ModelRequest] = []
    public private(set) var cancelledRounds: Set<RoundToken> = []

    public init(texts: [String] = ["合成", "合成测试回答"], delayNanoseconds: UInt64 = 0,
                clock: any SessionRuntimeClock = SystemSessionRuntimeClock(), shouldFail: Bool = false) {
        self.texts = Array(texts.prefix(64)); self.delayNanoseconds = delayNanoseconds
        self.clock = clock; self.shouldFail = shouldFail
    }
    public func respond(to request: ModelRequest) async throws -> AsyncThrowingStream<ModelText, Error> {
        requests.append(request)
        if delayNanoseconds > 0 { try await clock.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        if shouldFail { throw SyntheticProviderError.configuredFailure }
        let pair = AsyncThrowingStream<ModelText, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        for (revision, text) in texts.enumerated() { pair.continuation.yield(.init(revision: UInt64(revision), text: text)) }
        pair.continuation.finish(); return pair.stream
    }
    public func cancel(round: RoundToken) async { cancelledRounds.insert(round) }
}

/// Returns zero-valued PCM fixture packets by default; never synthesizes or plays real speech.
public actor SyntheticSpeechSynthesis: SpeechSynthesisProvider {
    private let chunks: [AudioChunk]
    public private(set) var requests: [SpeechRequest] = []
    public private(set) var cancelledRounds: Set<RoundToken> = []
    public init(chunks: [AudioChunk] = [
        .init(data: Data(repeating: 0, count: 640), format: .pcm16LE(sampleRate: 16_000, channels: 1)),
        .init(data: Data(repeating: 0, count: 640), format: .pcm16LE(sampleRate: 16_000, channels: 1))
    ]) { self.chunks = Array(chunks.prefix(64)) }
    public func synthesize(_ request: SpeechRequest) async throws -> AsyncThrowingStream<AudioChunk, Error> {
        requests.append(request); try Task.checkCancellation()
        let pair = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        for chunk in chunks { pair.continuation.yield(chunk) }
        pair.continuation.finish(); return pair.stream
    }
    public func cancel(round: RoundToken) async { cancelledRounds.insert(round) }
}

/// Records software operations only. No AVAudioSession, speaker, Bluetooth or audio device is opened.
public actor SyntheticPlayback: SpeechPlaybackAdapter {
    private let drainNanoseconds: UInt64
    private let clock: any SessionRuntimeClock
    public private(set) var currentRound: RoundToken?
    public private(set) var startedRounds: [RoundToken] = []
    public private(set) var stoppedRounds: [RoundToken] = []
    public private(set) var drainedRounds: [RoundToken] = []
    public private(set) var queuedBytes = 0
    public private(set) var isDraining = false
    public init(drainNanoseconds: UInt64 = 0, clock: any SessionRuntimeClock = SystemSessionRuntimeClock()) {
        self.drainNanoseconds = drainNanoseconds; self.clock = clock
    }
    public func start(round: RoundToken, format: AudioFormat) async throws {
        try Task.checkCancellation(); currentRound = round; startedRounds.append(round)
    }
    public func enqueue(_ chunk: AudioChunk, round: RoundToken) async throws {
        try Task.checkCancellation()
        guard currentRound == round else { throw SyntheticProviderError.wrongPlaybackRound }
        queuedBytes += chunk.data.count
    }
    public func finishAndDrain(round: RoundToken) async throws {
        guard currentRound == round else { throw SyntheticProviderError.wrongPlaybackRound }
        isDraining = true
        defer { if currentRound == round { isDraining = false } }
        if drainNanoseconds > 0 { try await clock.sleep(nanoseconds: drainNanoseconds) }
        try Task.checkCancellation(); drainedRounds.append(round)
    }
    public func stop(round: RoundToken) async {
        stoppedRounds.append(round)
        if currentRound == round { currentRound = nil; isDraining = false }
    }
}

/// Records admitted semantic commands. Nothing is serialized or transmitted to a device.
public actor RecordingGlassesTransport: GlassesSessionTransport {
    private let delayNanoseconds: UInt64
    private let clock: any SessionRuntimeClock
    private let shouldFail: Bool
    public private(set) var attemptedCommands: [GlassesSessionCommand] = []
    public private(set) var admittedCommands: [GlassesSessionCommand] = []
    public init(delayNanoseconds: UInt64 = 0, clock: any SessionRuntimeClock = SystemSessionRuntimeClock(), shouldFail: Bool = false) {
        self.delayNanoseconds = delayNanoseconds; self.clock = clock; self.shouldFail = shouldFail
    }
    public func send(_ command: GlassesSessionCommand) async throws {
        attemptedCommands.append(command)
        if delayNanoseconds > 0 { try await clock.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        if shouldFail { throw SyntheticProviderError.configuredFailure }
        admittedCommands.append(command)
    }
}
