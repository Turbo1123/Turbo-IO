import Foundation

/// 10ms classifier decisions, not volume thresholds or ASR. No PCM retained.
struct SpeechEndpointDetector {
    enum Event { case none, began, ended }
    private var window: [Bool] = []
    private var silence = 0
    private(set) var hasSpeech = false
    private(set) var ended = false
    mutating func discontinuity() { window.removeAll(); silence = 0 }
    mutating func accept(speech: Bool) -> Event {
        guard !ended else { return .none }
        if !hasSpeech {
            window.append(speech)
            if window.count > 20 { window.removeFirst() }
            if window.filter({ $0 }).count >= 12 {
                hasSpeech = true; silence = 0; window.removeAll()
                return .began
            }
        } else {
            silence = speech ? 0 : silence + 1
            if silence >= 90 { ended = true; return .ended }
        }
        return .none
    }
}
