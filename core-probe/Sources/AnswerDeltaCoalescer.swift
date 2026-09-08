import Foundation

/// Appends model deltas, never cumulative snapshots. Bounded, clock-driven;
/// 100ms/40-character batching follows the recovered official coalescer.
struct AnswerDeltaCoalescer {
    struct Chunk: Equatable { let text: String; let final: Bool }
    enum Failure: Error { case limit, alreadyFinished }
    private var pending = ""
    private var totalBytes = 0
    private var lastFlush: TimeInterval?
    private(set) var finished = false

    mutating func append(_ delta: String, final: Bool = false, now: TimeInterval) throws -> [Chunk] {
        guard !finished else { throw Failure.alreadyFinished }
        guard totalBytes + delta.utf8.count <= 8192 else { throw Failure.limit }
        totalBytes += delta.utf8.count
        pending += delta // No trim: whitespace belongs to the output stream.
        let punctuation = pending.last.map { "。！？!?；;\n".contains($0) } ?? false
        guard final || (!pending.isEmpty && (lastFlush == nil || pending.count >= 40 || punctuation || now - lastFlush! >= 0.1)) else { return [] }
        var pieces: [String] = [], part = "", bytes = 0
        for character in pending {
            let value = String(character), size = value.utf8.count
            guard size <= 480 else { throw Failure.limit }
            if bytes + size > 480 || part.count >= 40 { pieces.append(part); part = ""; bytes = 0 }
            part += value; bytes += size
        }
        if !part.isEmpty { pieces.append(part) }
        if pieces.isEmpty && final { pieces = [""] } // Empty terminal marker; never replay the prior text.
        pending = ""; lastFlush = now; finished = final
        return pieces.enumerated().map { Chunk(text:$0.element,final:final && $0.offset == pieces.count - 1) }
    }
}
