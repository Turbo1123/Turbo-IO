import Foundation

@main struct Tests {
    static func main() throws {
        let parser = RealtimeText()
        func source(_ delta: String, _ event: String) throws -> CaptionUpdate? {
            try parser.consume(["type":"conversation.item.input_audio_transcription.delta", "item_id":"src1", "event_id":event, "delta":delta])
        }
        let first = try source("你", "1"); assert(first?.text == "你")
        let second = try source("好", "2"); assert(second?.text == "你好")
        let duplicate = try source("好", "2"); assert(duplicate == nil)
        _ = try parser.consume(["type":"conversation.item.created", "item":["id":"dst1", "role":"assistant"], "previous_item_id":"src1"])
        let target = try parser.consume(["type":"response.text.delta", "item_id":"dst1", "delta":"Hello"])
        assert(target?.channel == .translation && target?.sourceItemID == "src1")
        assert(parser.source == "你好")
        let final = try parser.consume(["type":"conversation.item.input_audio_transcription.completed", "item_id":"src1", "transcript":"你好。"])
        assert(final?.text == "你好。" && final?.final == true)
        let late = try source("重复", "3"); assert(late == nil)
        let audio = try parser.consume(["type":"response.audio.delta", "delta":"AUDIO"]); assert(audio == nil)
        do { _ = try parser.consume(["type":"response.text.delta", "item_id":"huge", "delta":String(repeating:"x", count:16385)]); assertionFailure() } catch {}
        do { _ = try CaptionConfiguration.url(endpoint:"wss://example.org/realtime", model:"m", reusingTTSKey:true); assertionFailure() } catch {}
        let url = try CaptionConfiguration.url(endpoint:"wss://" + CaptionConfiguration.defaultHost + "/api-ws/v1/realtime", model:CaptionConfiguration.defaultModel, reusingTTSKey:true)
        assert(URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first?.name == "model")
        print("PASS: incremental source/translation isolation, final replacement, deduplication, source association, bounds, shared-key host restriction")
    }
}
