import Foundation

/// iOS 1.0.2: AssistantType.rawValue 32, SkillPayloadMessage reflection fields.
/// Text-only candidate, NOT yet lens-validated. No executable intent/payload.
/// workflow/chat/-1 observed in official 09-06 19:08 logs. Vendor remains our
/// label. The encoder exposes wire isFinal; cloud EOF must not blindly set it.
public enum AssistantAnswerPrototype {
    public enum EncodingError: Error { case invalidInput }
    public static func chat(_ text: String, isFinal: Bool, roundID: UUID,
                            query: String, timestampMilliseconds: Int64) throws -> Data {
        guard (!text.isEmpty || isFinal), text.utf8.count <= 512, query.utf8.count <= 512,
              timestampMilliseconds >= 0 else { throw EncodingError.invalidInput }
        struct Answer: Encodable { let text: String; let isFinal: Bool }
        struct Body: Encodable {
            let sub = "workflow", vendor = "deepseek"
            let uuid: String, sid: String
            let round = -1
            let timestamp: Int64
            let query: String
            let domain = "chat", intent = "chat"
            let payload: [String:String] = [:]
            let offline = false
            let answer: Answer
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys,.withoutEscapingSlashes]
        let id = roundID.uuidString.lowercased()
        let body = try encoder.encode(Body(uuid:id,sid:id,timestamp:timestampMilliseconds,
                                          query:query,answer:Answer(text:text,isFinal:isFinal)))
        guard body.count <= 8192 else { throw EncodingError.invalidInput }
        var packet = Data([8,1,16,32,26])
        var length = UInt64(body.count)
        while length >= 128 { packet.append(UInt8(length & 127) | 128); length >>= 7 }
        packet.append(UInt8(length)); packet.append(body)
        return packet
    }
}
