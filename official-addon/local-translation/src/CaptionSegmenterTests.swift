import Foundation
@main struct Tests {
    static func main() {
        var s = CaptionSegmenter()
        assert(s.take("one two three", final: false) == nil)
        assert(s.take("one two three", final: true) == "one two three")
        let words = (0..<25).map { "word\($0)" }
        assert(s.take(words.joined(separator: " "), final: false) == words.prefix(21).joined(separator: " "))
        assert(s.take(words.joined(separator: " "), final: false) == nil)
        assert(s.take(words.joined(separator: " "), final: true) == words.suffix(4).joined(separator: " "))
        assert(s.take("next", final: true) == "next")
        assert(captionTail("中文🙂", bytes: 4) == "🙂")
        assert(captionTail("e\u{301}", bytes: 1).isEmpty)
        let frame = CaptionSegmenter.display(original: String(repeating: "hello ", count: 100), translated: String(repeating: "你好🙂", count: 100))
        assert(frame.utf8.count <= 384)
        assert(CaptionSegmenter.display(original: "", translated: "").isEmpty)
        print("PASS: stable segments, no duplicate final, UTF8 and glasses frame bounds")
    }
}
