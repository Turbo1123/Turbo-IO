import Foundation

/// Dedicated capture namespace: this is never an ordinary RoundToken replay.
public struct ApprovalASRRequest: Equatable, Sendable {
    public let capture: ApprovalCaptureToken
    public let source: ASRSource
    public let language: String
    public init(capture: ApprovalCaptureToken, source: ASRSource, language: String) {
        self.capture = capture; self.source = source
        self.language = TextBounds.boundedPrefix(language, maximumCharacters: 64, maximumUTF8Bytes: 256)
    }
}

/// No recognizer/endpoint is bundled. A host backend may implement both ASR protocols explicitly.
public protocol ApprovalASRProvider: Sendable {
    var source: ASRSource { get }
    func recognize(_ request: ApprovalASRRequest, audio: AsyncThrowingStream<AudioChunk, Error>) async throws
        -> AsyncThrowingStream<ASRTranscript, Error>
    func cancel(capture: ApprovalCaptureToken) async
}
