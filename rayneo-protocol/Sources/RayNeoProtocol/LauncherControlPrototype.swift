import Foundation

/// Version-pinned commands observed during official iOS 1.0.2 fresh pairing.
/// This is not a general-purpose command builder. No account data is needed.
public enum LauncherControlPrototype {
    public enum Command: CaseIterable {
        case enableVoiceWakeup, officialWakeWord, requestGeneralStatus
        var fields: (type: UInt8, name: String, mode: Int) {
            switch self {
            case .enableVoiceWakeup: return (16, "set_ai_voice_wakeup", 1)
            case .officialWakeWord: return (16, "set_ai_wakeup_word", 1)
            case .requestGeneralStatus: return (1, "request_general_status", 0)
            }
        }
    }

    public static func encode(_ command: Command) throws -> Data {
        struct Payload: Encodable { let data = ""; let mode: Int; let value = 0 }
        struct Body: Encodable { let cmd: String; let payload: Payload }
        let fields = command.fields
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body = try encoder.encode(Body(cmd: fields.name, payload: Payload(mode: fields.mode)))
        // All three observed bodies are <128 bytes; keep this finite surface.
        precondition(body.count < 128)
        return Data([8, 1, 16, fields.type, 26, UInt8(body.count)]) + body + Data([34, 0])
    }
}
