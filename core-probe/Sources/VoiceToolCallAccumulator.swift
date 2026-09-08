import Foundation

/// One explicitly allowlisted function per utterance. Tool fragments are data,
/// never executable code; approval is deliberately absent from this vocabulary.
struct VoiceToolCallAccumulator {
    enum Failure: Error { case invalid }
    private(set) var name = ""
    private(set) var arguments = ""
    private(set) var present = false
    mutating func append(_ value: Any?) throws {
        guard let value else { return }
        guard let calls = value as? [[String: Any]], calls.count <= 1 else { throw Failure.invalid }
        for call in calls {
            guard let index = call["index"] as? Int, index == 0,
                  call["type"] == nil || call["type"] as? String == "function" else { throw Failure.invalid }
            present = true
            if let f = call["function"] as? [String: Any] {
                if let n = f["name"] as? String { name += n }
                if let a = f["arguments"] as? String { arguments += a }
            }
            guard name.utf8.count <= 64, arguments.utf8.count <= 9000 else { throw Failure.invalid }
        }
    }
    func validated(allowed: Set<String>, finishReason: String) throws -> (String, String) {
        guard present, finishReason == "tool_calls", allowed.contains(name),
              let object = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else { throw Failure.invalid }
        if name == "codex_message" {
            guard object.count == 1, let text = object["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192 else { throw Failure.invalid }
        } else { guard object.isEmpty else { throw Failure.invalid } }
        return (name, arguments)
    }
}
