import Foundation

/// Version-pinned prototype, not a generic notification or arbitrary UI API.
/// iOS AssistantType=5 / app_asr_text, wire keys are text/final, NOT isFinal.
/// 1.0.2 AsrTextMessage CodingKey getter 0x101780d9c; Android @SerializedName("final").
/// Device display and state requirements must be tested independently.
public enum AssistantTextPrototype {
    public enum EncodingError: Error { case textTooLong }
    public static func asrText(_ text: String, isFinal: Bool) throws -> Data {
        guard text.utf8.count <= 1024 else { throw EncodingError.textTooLong }
        struct Body: Encodable {
            let text: String; let isFinal: Bool
            enum CodingKeys: String, CodingKey { case text; case isFinal = "final" }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = try encoder.encode(Body(text:text, isFinal:isFinal))
        var packet = Data([8,1,16,5,26])
        var length = UInt64(body.count)
        while length >= 128 { packet.append(UInt8(length & 127) | 128); length >>= 7 }
        packet.append(UInt8(length))
        packet.append(body)
        return packet
    }
}
