import Foundation

/// Feed stable ASR segments here; display ASR partials directly, not through translation.
/// A cloud translation stream is handled separately by CaptionRealtimeClient.
@available(iOS 26.0, *)
@MainActor final class CaptionTranslationRouter {
    enum Provider: String { case originalOnly, apple, hymt }
    private(set) var provider = Provider.apple
    private let apple = CaptionLocalTranslation()
    private let hymt = CaptionHyMTTranslation()
    private var generation = 0
    private var busy = false
    var localModelReady: Bool { hymt.loaded }
    var hymtThreads: Int { get { hymt.preferredThreads } set { hymt.preferredThreads = newValue } }
    var lastTiming: HyMTTiming? { hymt.lastTiming }
    func select(_ value: Provider) {
        guard value != provider else { return }
        generation += 1; apple.cancel(); hymt.cancel()
        if value != .hymt { hymt.unload() }
        provider = value
    }
    func loadHyMT(_ url: URL) async throws { try await hymt.load(url: url, threads: Int32(hymtThreads)) }
    func stop() { generation += 1; apple.cancel(); hymt.unload() }
    func translateStable(_ text: String, source: String, target: String, onPartial: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> String {
        guard !busy else { throw HyMTFailure.busy }
        busy = true; defer { busy = false }
        let epoch = generation
        let result: String
        switch provider {
        case .originalOnly: result = text
        case .apple: result = try await apple.translate(text, source: source, target: target)
        case .hymt: result = try await hymt.translate(text, source: source, target: target, onPartial: onPartial)
        }
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
        return result
    }
}
