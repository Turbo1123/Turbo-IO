import Foundation
@main struct Tests {
    static func main() throws {
        var q = CaptionTranslationScheduler()
        try q.offer("well i do not wish", final: false)
        assert(q.next(now: 0) == nil)
        try q.offer("well i do not wish to", final: false)
        let preview = q.next(now: 0)!
        assert(preview.text == "well i do not" && !preview.final)
        try q.offer("well i do not wish to see it any more", final: false)
        assert(q.next(now: 2) == nil) // Never parallel inference.
        q.complete(preview)
        assert(q.next(now: 0.5) == nil) // No update storm.
        let newer = q.next(now: 1.2)!
        assert(newer.text == "well i do not wish to see it")
        try q.offer("well i do not wish to see it any more", final: true)
        q.complete(newer)
        let final = q.next(now: 1.3)!
        assert(final.final && final.id == preview.id && final.text.hasSuffix("any more"))
        q.complete(final)
        assert(q.next(now: 3) == nil)
        // Long speech seals bounded chunks; queued final beats the latest preview.
        let words = (0..<35).map { "word\($0)" }
        try q.offer(words.joined(separator: " "), final: false)
        let first = q.next(now: 4)!
        assert(first.final && first.text == words.prefix(16).joined(separator: " "))
        q.complete(first)
        try q.offer(words.joined(separator: " "), final: true)
        let tail = q.next(now: 4.1)!
        assert(tail.final && tail.text == words.dropFirst(16).joined(separator: " "))
        q.complete(tail)
        // Stable-only mode remains selectable.
        var slow = CaptionTranslationScheduler(); slow.previews = false
        try slow.offer("one two three four five six seven eight", final: false)
        assert(slow.next(now: 10) == nil)
        try slow.offer("one two three four five six seven eight", final: true)
        assert(slow.next(now: 11)?.final == true)
        // Final history is bounded, and overload is explicit rather than silent loss.
        var blocked = CaptionTranslationScheduler()
        for _ in 0..<4 { try blocked.offer("a short sentence", final: true) }
        assert(blocked.pendingFinals == 4)
        do { try blocked.offer("fifth sentence", final: true); assertionFailure("unbounded queue") }
        catch CaptionTranslationScheduler.CaptionFailureForScheduler.backpressure {}
        assert(CaptionSegmenter.display(original: String(repeating: "a", count: 500), translated: String(repeating: "字", count: 500), preview: true).utf8.count < 384)
        print("PASS preview before EOU, coalescing, one inference, throttle, final priority, stable mode and bounds")
    }
}
