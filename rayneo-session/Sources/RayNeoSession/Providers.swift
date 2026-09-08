import Foundation

public struct ASRRequest: Equatable, Sendable {
    public let round: RoundToken
    public let source: ASRSource
    public let language: String
    public init(round: RoundToken, source: ASRSource, language: String) {
        self.round = round; self.source = source; self.language = language
    }
}

public struct ModelRequest: Equatable, Sendable {
    public let round: RoundToken
    /// Completed prior user/assistant pairs plus the current user's finalized transcript.
    public let messages: [ConversationMessage]
    public init(round: RoundToken, messages: [ConversationMessage]) {
        self.round = round; self.messages = messages
    }
}

public struct SpeechRequest: Equatable, Sendable {
    public let round: RoundToken
    public let text: String
    public let language: String
    public init(round: RoundToken, text: String, language: String) {
        self.round = round; self.text = text; self.language = language
    }
}

/// No implementation, endpoint, credentials, audio storage or cloud requests are supplied here.
/// The host closes `audio` on finishRecognition and must cancel the task on cancelWork.
public protocol ASRProvider: Sendable {
    var source: ASRSource { get }
    func recognize(_ request: ASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>)
        async throws -> AsyncThrowingStream<ASRTranscript, Error>
    func cancel(round: RoundToken) async
}

/// Yield increasing revision/full-text snapshots; finish the stream only after the final snapshot.
public protocol ConversationModelProvider: Sendable {
    func respond(to request: ModelRequest) async throws -> AsyncThrowingStream<ModelText, Error>
    func cancel(round: RoundToken) async
}

/// Audio bytes returned here must go to a playback adapter, never into the type 6 status packet.
public protocol SpeechSynthesisProvider: Sendable {
    func synthesize(_ request: SpeechRequest) async throws -> AsyncThrowingStream<AudioChunk, Error>
    func cancel(round: RoundToken) async
}

public protocol SpeechPlaybackAdapter: Sendable {
    func start(round: RoundToken, format: AudioFormat) async throws
    func enqueue(_ chunk: AudioChunk, round: RoundToken) async throws
    /// Must return only after all queued buffers have completed, not just after network EOF.
    func finishAndDrain(round: RoundToken) async throws
    func stop(round: RoundToken) async
}
