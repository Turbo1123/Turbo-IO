import Foundation
import CoreFoundation

/// Experimental observer for the four-field business protobuf envelope.
/// Field numbers are recovered from Android 1.0.1 AssistantMsg/CaptionMsg;
/// Selected iOS 1.0.2 voice/launcher packets were validated on 2026-09-06;
/// other business channels (including recording files) are not inferred.
/// This does not parse the outer transport frame or authenticate any sender.
/// `inspect` returns lengths only. Opt-in helpers separately extract audio or
/// produce a redacted wake-event diagnostic; neither authenticates the sender.
public struct BusinessEnvelopeMetadata: Equatable {
    public let version: UInt32?
    public let messageType: UInt32?
    public let messageBytes: Int?
    public let dataBytes: Int?
    public let unknownFieldCount: Int

    public enum DecodeError: Error, Equatable {
        case packetTooLarge, tooManyFields, truncated, varintOverflow
        case invalidTag, unsupportedWireType, wrongWireType, duplicateField, scalarOverflow
    }

    /// Known singular duplicates are rejected (unlike protobuf last-one-wins)
    /// so an ambiguous observation is never silently reported as a known type.
    /// Unknown scalar, fixed-width, and length-delimited fields are skipped.
    public static func inspect(_ packet: Data) throws -> Self {
        try parse(packet).0
    }

    /// Opt-in in-memory voice payload extraction. No text or audio logging.
    /// The caller must independently gate business ID, authenticated target and
    /// active round; this parser does not authenticate a device.
    public static func assistantAudio(_ packet: Data) throws -> Data? {
        let (metadata, range, _) = try parse(packet)
        guard metadata.messageType == 3, let range, !range.isEmpty,
              range.count <= 4096 else { return nil }
        return Data(packet).subdata(in:range)
    }

    /// Diagnostic only: never use unverified source values to authorize or route.
    /// Unknown names, string values and audio contents are never included.
    public static func wakeDiagnostic(_ packet: Data) throws -> String? {
        let (metadata, _, messageRange) = try parse(packet)
        guard metadata.messageType == 1 else { return nil }
        let prefix = "type=1 messageBytes=\(metadata.messageBytes.map(String.init) ?? "missing") audioBytes=\(metadata.dataBytes.map(String.init) ?? "missing") unknownEnvelope=\(metadata.unknownFieldCount)"
        guard let messageRange else { return prefix + " message=missing" }
        guard !messageRange.isEmpty else { return prefix + " message=empty" }
        guard messageRange.count <= 8192 else { return prefix + " message=oversize" }
        let body = Data(packet).subdata(in: messageRange)
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return prefix + " message=opaque"
        }
        let sources: Set<String> = ["source", "wakeSource", "wake_source", "wakeupSource", "wakeup_source", "wakeType", "wake_type", "wakeupType", "wakeup_type"]
        let containers: Set<String> = ["payload", "data"]
        var fields: [String] = [], unknown = 0
        func walk(_ object: [String: Any], path: String, depth: Int) {
            for key in object.keys.sorted() {
                guard fields.count < 16 else { return }
                guard sources.contains(key) || containers.contains(key) else { unknown += 1; continue }
                let name = path.isEmpty ? key : path + "." + key
                let value = object[key]!
                if let number = value as? NSNumber {
                    // JSON booleans bridge to NSNumber too; they are not enums.
                    let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                    let numeric = number.doubleValue
                    if sources.contains(key), !isBoolean, numeric >= 0, numeric <= 255, numeric.rounded() == numeric {
                        fields.append(name + "=" + number.stringValue)
                    } else { fields.append(name + (isBoolean ? ":bool" : ":number-redacted")) }
                } else if let nested = value as? [String: Any] {
                    fields.append(name + ":object")
                    if depth < 2 { walk(nested, path: name, depth: depth + 1) }
                } else if value is String { fields.append(name + ":string-redacted") }
                else if value is [Any] { fields.append(name + ":array-redacted") }
                else { fields.append(name + ":null") }
            }
        }
        walk(root, path: "", depth: 0)
        return String((prefix + " message=json unknownFields=\(unknown) " + fields.joined(separator: ",")).prefix(600))
    }

    /// Read-only Launcher observer. Call only for business 15 from the current
    /// authenticated target during an explicit query. No capability is inferred
    /// from absent fields, numeric values, or a successful transport submission.
    public static func wakeSettingsDiagnostic(_ packet: Data) throws -> String? {
        let (metadata, _, range) = try parse(packet)
        guard metadata.version == 1, let type = metadata.messageType,
              [1, 3, 4, 6, 17].contains(type) else { return nil }
        let prefix = "type=\(type)"
        guard let range else { return prefix + " message=missing" }
        guard range.count <= 8192 else { return prefix + " message=oversize" }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(packet).subdata(in: range))) as? [String: Any] else {
            return prefix + " message=opaque"
        }
        let commands: Set<String> = ["request_general_status", "general_status", "request_general_settings", "general_settings", "set_ai_voice_wakeup", "set_ai_wakeup_word"]
        let command = (root["cmd"] as? String).flatMap { commands.contains($0) ? $0 : nil }
        let controls: Set<String> = ["voiceWakeup", "voice_wakeup", "aiVoiceWakeup", "ai_voice_wakeup", "aiWakeupWord", "ai_wakeup_word", "wakeWord", "wakeWords", "wakeupWord", "wakeupWords", "wakeup_word", "wakeup_words", "customWakeWord", "customWakeWordSupported", "supportsCustomWakeWord"]
        let containers: Set<String> = ["generalStatus", "generalSettings", "general_status", "general_settings", "payload", "data", "aiConfig", "voiceConfig", "wakeupConfig"]
        let phrases: Set<String> = ["小雷小雷", "Hey RayNeo", "OK RayNeo", "Hey Norman"]
        var fields: [String] = [], unknown = 0, wakeFields = 0, visited = 0
        func walk(_ object: [String: Any], path: String, depth: Int) {
            guard depth <= 3 else { return }
            for key in object.keys.sorted() {
                guard fields.count < 16, visited < 128 else { return }
                visited += 1
                let value = object[key]!
                if path.isEmpty, key == "cmd" { continue }
                let control = controls.contains(key)
                let envelopeScalar = command != nil && ((path.isEmpty && key == "rc") || (path == "payload" && ["mode", "value"].contains(key)))
                guard control || envelopeScalar || containers.contains(key) else { unknown += 1; continue }
                let name = path.isEmpty ? key : path + "." + key
                if control { wakeFields += 1 }
                if control || envelopeScalar {
                    if let number = value as? NSNumber {
                        if CFGetTypeID(number) == CFBooleanGetTypeID() {
                            fields.append(name + "=" + String(number.boolValue))
                        } else if number.doubleValue >= 0, number.doubleValue <= 255, number.doubleValue.rounded() == number.doubleValue {
                            fields.append(name + "=" + number.stringValue)
                        } else { fields.append(name + ":number-redacted") }
                    } else if let text = value as? String {
                        fields.append(name + (control && phrases.contains(text) ? "=" + text : ":string-redacted"))
                    } else { fields.append(name + ":complex-redacted") }
                } else if let nested = value as? [String: Any] {
                    walk(nested, path: name, depth: depth + 1)
                } else if key == "data", let text = value as? String, text.utf8.count <= 8192,
                          let nested = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
                    walk(nested, path: name, depth: depth + 1)
                }
            }
        }
        walk(root, path: "", depth: 0)
        return String((prefix + " cmd=\(command ?? "unrecognized-or-missing") wakeFields=\(wakeFields) unknownFields=\(unknown) " + fields.joined(separator: ",")).prefix(900))
    }

    private static func parse(_ packet: Data) throws -> (Self, Range<Int>?, Range<Int>?) {
        guard packet.count <= 1_048_576 else { throw DecodeError.packetTooLarge }
        return try packet.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0, fields = 0, unknown = 0
            var seen = Set<UInt64>()
            var version: UInt32?, type: UInt32?, messageLength: Int?, dataLength: Int?
            var audioRange: Range<Int>?, messageRange: Range<Int>?
            func varint() throws -> UInt64 {
                var result: UInt64 = 0
                for index in 0..<10 {
                    guard offset < bytes.count else { throw DecodeError.truncated }
                    let byte = bytes[offset]; offset += 1
                    if index == 9 && byte > 1 { throw DecodeError.varintOverflow }
                    result |= UInt64(byte & 0x7f) << (index * 7)
                    if byte & 0x80 == 0 { return result }
                }
                throw DecodeError.varintOverflow
            }
            func skip(_ length: UInt64) throws -> Int {
                guard length <= UInt64(bytes.count - offset) else { throw DecodeError.truncated }
                let count = Int(length)
                offset += count
                return count
            }
            while offset < bytes.count {
                fields += 1
                guard fields <= 256 else { throw DecodeError.tooManyFields }
                let key = try varint(), field = key >> 3, wire = key & 7
                guard field > 0 && field <= 0x1fffffff else { throw DecodeError.invalidTag }
                if field <= 4 {
                    guard seen.insert(field).inserted else { throw DecodeError.duplicateField }
                    guard wire == (field <= 2 ? 0 : 2) else { throw DecodeError.wrongWireType }
                    if field <= 2 {
                        let value = try varint()
                        guard value <= UInt64(UInt32.max) else { throw DecodeError.scalarOverflow }
                        if field == 1 { version = UInt32(value) } else { type = UInt32(value) }
                    } else {
                        let length = try varint(), start = offset
                        let count = try skip(length)
                        if field == 3 { messageLength = count; messageRange = start..<offset } else { dataLength = count }
                        if field == 4 { audioRange = start..<offset }
                    }
                } else {
                    unknown += 1
                    switch wire {
                    case 0: _ = try varint()
                    case 1: _ = try skip(8)
                    case 2: _ = try skip(varint())
                    case 5: _ = try skip(4)
                    default: throw DecodeError.unsupportedWireType
                    }
                }
            }
            return (Self(version: version, messageType: type, messageBytes: messageLength,
                        dataBytes: dataLength, unknownFieldCount: unknown), audioRange, messageRange)
        }
    }
}
