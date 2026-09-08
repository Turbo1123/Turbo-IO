import Foundation

/// Experimental observer for the four-field business protobuf envelope.
/// Field numbers are recovered from Android 1.0.1 AssistantMsg/CaptionMsg;
/// Selected iOS 1.0.2 voice/launcher packets were validated on 2026-09-06;
/// other business channels (including recording files) are not inferred.
/// This does not parse the outer transport frame or authenticate any sender.
/// It returns lengths only: no JSON text, audio bytes, IDs, or credentials.
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
        let (metadata, range) = try parse(packet)
        guard metadata.messageType == 3, let range, !range.isEmpty,
              range.count <= 4096 else { return nil }
        return Data(packet).subdata(in:range)
    }

    private static func parse(_ packet: Data) throws -> (Self, Range<Int>?) {
        guard packet.count <= 1_048_576 else { throw DecodeError.packetTooLarge }
        return try packet.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0, fields = 0, unknown = 0
            var seen = Set<UInt64>()
            var version: UInt32?, type: UInt32?, messageLength: Int?, dataLength: Int?
            var audioRange: Range<Int>?
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
                        if field == 3 { messageLength = count } else { dataLength = count }
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
                        dataBytes: dataLength, unknownFieldCount: unknown), audioRange)
        }
    }
}
