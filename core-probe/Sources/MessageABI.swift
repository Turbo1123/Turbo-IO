import Foundation

// Version-pinned research facade, not a public/stable SDK declaration.
// 0x10c994 allocates the real RNMessage metadata itself (no incoming metatype
// used). Payload/deviceID/msgID/appUniteCode are consumed; __owned is essential.
@_silgen_name("$s9RayneoNet9RNMessageC7payload8deviceId08businessF003msgF012appUniteCodeAC10Foundation4DataVSg_SSAA10BusinessIDOS2StcfC")
private func createMessageABI(_ payload: __owned Data?, _ deviceID: __owned String,
                              _ businessIndex: UInt8, _ msgID: __owned String,
                              _ appUniteCode: __owned String) -> MessageHandle

/// Holds an object allocated only by RayneoNet. Never allocate this Swift type.
final class MessageHandle {
    private init() { fatalError("Opaque SDK handle") }

    @_silgen_name("$s9RayneoNet9RNMessageC7payload10Foundation4DataVSgvg")
    func payload() -> Data?

    @_silgen_name("$s9RayneoNet9RNMessageC8deviceIdSSvg")
    func deviceID() -> String

    @_silgen_name("$s9RayneoNet9RNMessageC10businessIDAA08BusinessE0Ovg")
    func businessIndex() -> UInt8

    @_silgen_name("$s9RayneoNet9RNMessageC5msgIdSSvg")
    func messageID() -> String

    @_silgen_name("$s9RayneoNet9RNMessageC5msgIdSSvs")
    func setMessageID(_ value: __owned String)
}

/// Enum indices in RayneoNet v1.2.35, NOT transport raw IDs or assistant types.
enum MessageBusinessIndex: UInt8, CaseIterable {
    case voiceAssistant = 13, recordingService = 14, launcher = 15
    case aiSubtitle = 19, teleprompter = 20, notification = 21, scheduleTodo = 22
}

enum MessageFactoryError: Error { case unverifiedImage }

enum MessageFactory {
    /// Creates a message only. Does not load RNCoreConnect or send any data.
    static func make(payload: Data?, deviceID: String, business: MessageBusinessIndex,
                     messageID: String) throws -> MessageHandle {
        guard RNProbeMessageImageMatches() else { throw MessageFactoryError.unverifiedImage }
        // This initializer deliberately discards msgID/appUniteCode (verified
        // disassembly). Set the caller's ID through the exported setter.
        let message = createMessageABI(payload, deviceID, business.rawValue, "", "")
        message.setMessageID(messageID)
        return message
    }
}
