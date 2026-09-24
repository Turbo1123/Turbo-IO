import Foundation

// No audio, credentials or diagnostic logging. Mutated on one caller-owned queue.
enum CaptionFailure: Error { case malformed, capacity, configuration, unavailable, routeChanged }
struct CaptionUpdate {
    enum Channel: String { case source, translation }
    let channel: Channel
    let itemID: String
    let sourceItemID: String?
    let text: String
    let final: Bool
}

final class RealtimeText {
    private struct Line { var text = ""; var final = false }
    private var lines: [String: Line] = [:]
    private var lineOrder: [String] = []
    private var seen: Set<String> = []
    private var eventOrder: [String] = []
    private var parents: [String: String] = [:]
    private var parentOrder: [String] = []
    private(set) var source = ""
    private(set) var translation = ""

    func consume(_ event: [String: Any]) throws -> CaptionUpdate? {
        guard let kind = event["type"] as? String, kind.count < 128 else { throw CaptionFailure.malformed }
        if let id = event["event_id"] as? String {
            guard id.count <= 256 else { throw CaptionFailure.malformed }
            if seen.contains(id) { return nil }
            seen.insert(id); eventOrder.append(id)
            if eventOrder.count > 256 { seen.remove(eventOrder.removeFirst()) }
        }
        if kind == "conversation.item.created" {
            if let item = event["item"] as? [String: Any], item["role"] as? String == "assistant",
               let id = item["id"] as? String, let parent = event["previous_item_id"] as? String {
                guard !id.isEmpty, id.count <= 256, !parent.isEmpty, parent.count <= 256 else { throw CaptionFailure.malformed }
                if parents[id] == nil { parentOrder.append(id) }
                parents[id] = parent
                if parentOrder.count > 64 { parents.removeValue(forKey: parentOrder.removeFirst()) }
            }
            return nil
        }
        let channel: CaptionUpdate.Channel
        let final: Bool
        let field: String
        switch kind {
        case "conversation.item.input_audio_transcription.delta": channel = .source; final = false; field = "delta"
        case "conversation.item.input_audio_transcription.completed": channel = .source; final = true; field = "transcript"
        case "response.text.delta": channel = .translation; final = false; field = "delta"
        case "response.text.done": channel = .translation; final = true; field = "text"
        default: return nil // Never render TTS or a translation event as source ASR.
        }
        guard let id = event["item_id"] as? String, !id.isEmpty, id.count <= 256,
              let text = event[field] as? String, text.utf8.count <= 16384 else { throw CaptionFailure.malformed }
        if let index = event["content_index"] as? Int, index != 0 { throw CaptionFailure.configuration }
        let key = channel.rawValue + ":" + id
        if lines[key] == nil {
            if lineOrder.count >= 64 {
                guard let old = lineOrder.first, lines[old]?.final == true else { throw CaptionFailure.capacity }
                lines.removeValue(forKey: lineOrder.removeFirst())
            }
            lineOrder.append(key); lines[key] = Line()
        }
        var line = lines[key]!
        if line.final { return nil }
        line.text = final ? text : line.text + text
        guard line.text.utf8.count <= 16384 else { throw CaptionFailure.capacity }
        line.final = final; lines[key] = line
        if channel == .source { source = line.text } else { translation = line.text }
        return CaptionUpdate(channel: channel, itemID: id, sourceItemID: channel == .source ? id : parents[id], text: line.text, final: final)
    }
}

enum CaptionConfiguration {
    static let defaultHost = "example.invalid" // No maintainer endpoint. Offline build never uses this configuration.
    static let defaultModel = "qwen3.8-livetranslate-flash-realtime"
    // Explicit host consent belongs to UI. A shared TTS key may only be reused for this host.
    static func url(endpoint: String, model: String, reusingTTSKey: Bool) throws -> URL {
        guard var c = URLComponents(string: endpoint), c.scheme == "wss", c.user == nil, c.password == nil,
              c.fragment == nil, let host = c.host, !host.isEmpty, !model.isEmpty, model.count <= 128,
              !reusingTTSKey || host == defaultHost else { throw CaptionFailure.configuration }
        c.queryItems = (c.queryItems ?? []).filter { $0.name != "model" } + [URLQueryItem(name: "model", value: model)]
        guard let u = c.url else { throw CaptionFailure.configuration }; return u
    }
    static func update(target: String) throws -> [String: Any] {
        guard target.range(of: "^[a-z]{2,3}(-[A-Za-z]{2,4})?$", options: .regularExpression) != nil else { throw CaptionFailure.configuration }
        return ["type": "session.update", "session": ["output_modalities": ["text"], "translation": ["language": target]]]
    }
}
