import Foundation

func captionTail(_ text: String, bytes: Int) -> String {
    var result = "", count = 0
    for character in text.reversed() {
        let value = String(character), length = value.utf8.count
        if count + length > bytes { break }
        result = value + result; count += length
    }
    return result
}

struct CaptionSegmenter {
    private var committed = 0
    mutating func take(_ cumulative: String, final: Bool) -> String? {
        let words = cumulative.split(whereSeparator: { $0.isWhitespace })
        let end = final ? words.count : (words.count - committed >= 20 ? words.count - 4 : committed)
        defer { if final { committed = 0 } }
        guard end > committed, committed <= words.count else { return nil }
        let value = words[committed..<end].joined(separator: " "); committed = end
        return value
    }
    static func display(original: String, translated: String, preview: Bool = false) -> String {
        if original.isEmpty && translated.isEmpty { return "" }
        if translated.isEmpty { return captionTail(original, bytes: 360) }
        return "英: " + captionTail(original, bytes: 130) + (preview ? "\n中·预译: " : "\n中·已译片段: ") + captionTail(translated, bytes: 210)
    }
}

/// One inference at a time. Preview work is derived from the newest ASR snapshot,
/// never queued; only sealed final segments enter the bounded FIFO.
struct CaptionTranslationScheduler {
    struct Request: Equatable {
        let id: Int
        let text: String
        let final: Bool
    }
    var previews = true
    private var id = 0, offset = 0
    private var words: [String] = []
    private var finals: [Request] = []
    private var running: Request?
    private var lastPreview = "", lastPreviewCount = 0
    private var lastStarted = -Double.infinity
    var pendingFinals: Int { finals.count }
    var inFlight: Request? { running }

    mutating func offer(_ cumulative: String, final: Bool) throws {
        let incoming = cumulative.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard incoming.count >= offset else { throw CaptionFailureForScheduler.changedCommittedPrefix }
        words = Array(incoming.dropFirst(offset))
        // Keep requests short enough for predictable local inference. Leave context at the trailing edge.
        while words.count >= 20 {
            try seal(Array(words.prefix(16)))
            offset += 16; words.removeFirst(16)
        }
        if final {
            if !words.isEmpty { try seal(words) }
            words.removeAll(); offset = 0
        }
    }
    private mutating func seal(_ words: [String]) throws {
        guard finals.count < 4 else { throw CaptionFailureForScheduler.backpressure }
        finals.append(Request(id: id, text: words.joined(separator: " "), final: true))
        id += 1; lastPreview = ""; lastPreviewCount = 0
    }
    mutating func next(now: Double) -> Request? {
        guard running == nil else { return nil }
        if !finals.isEmpty {
            let request = finals.removeFirst(); running = request; lastStarted = now; return request
        }
        guard previews, words.count >= 6, now - lastStarted >= 1.2 else { return nil }
        // Do not translate the newest two words until more context or EOU arrives.
        let stable = Array(words.dropLast(2)), text = stable.joined(separator: " ")
        guard text != lastPreview, lastPreview.isEmpty || stable.count - lastPreviewCount >= 4 else { return nil }
        lastPreview = text; lastPreviewCount = stable.count; lastStarted = now
        let request = Request(id: id, text: text, final: false); running = request; return request
    }
    mutating func complete(_ request: Request) { if running == request { running = nil } }
    enum CaptionFailureForScheduler: Error { case backpressure, changedCommittedPrefix }
}
