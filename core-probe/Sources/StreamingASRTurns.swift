import Foundation

/// One ASR task, monotonic sentence IDs, independent model-turn identities.
/// No local VAD and no PCM. Late/duplicate results cannot revive an old turn.
struct StreamingASRTurns {
    enum Event: Equatable {
        case began(UUID)
        case transcript(UUID, String, Bool)
        case ended(UUID, String)
    }
    enum Failure: Error { case invalid, limit }
    private var sentence = -1
    private var turn: UUID?
    private var finished = false
    private var count = 0
    private var lastText = ""
    private var lastEmit = -Double.infinity
    mutating func accept(sentenceID: Int, text: String, begin: Bool, end: Bool,
                         heartbeat: Bool, now: TimeInterval) throws -> [Event] {
        if heartbeat { return [] }
        guard (0...1_000_000).contains(sentenceID), text.utf8.count <= 8192, now.isFinite else { throw Failure.invalid }
        if sentenceID < sentence || (sentenceID == sentence && finished) { return [] }
        let nonempty = !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        var events: [Event] = []
        if sentenceID > sentence {
            guard begin || nonempty else { return [] }
            guard count < 64 else { throw Failure.limit }
            count += 1; sentence = sentenceID; turn = nil; finished = false
            lastText = ""; lastEmit = -Double.infinity
        }
        // A cloud BOS can be noise with an empty final. Do not invalidate the
        // active model or put the lens into listening/loading until real text.
        if turn == nil, nonempty {
            turn = UUID(); events.append(.began(turn!))
        }
        if end { finished = true }
        guard let turn else { return [] }
        if nonempty && (end || (text != lastText && now-lastEmit >= 0.25)) {
            events.append(.transcript(turn,text,end)); lastText = text; lastEmit = now
        }
        if end { events.append(.ended(turn,nonempty ? text : "")) }
        return events
    }
}
