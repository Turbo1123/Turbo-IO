import Foundation

/// Version-pinned framing recovered from iOS RayneoNet 1.2.35.
/// This is a pure codec, not a connected transport, ACK policy or authenticated message.
public struct TransportFrame: Equatable, Sendable {
    public enum CodecError: Error, Equatable {
        case invalidLimits, invalidFlags, addressFlagMismatch, sliceInfoTooLong
        case frameTooLarge, payloadTooLarge, truncated, invalidHead, invalidLength
        case trailingBytes, crcMismatch
    }

    /// Local safety limits, not a claim about device/MTU support.
    public struct Limits: Equatable, Sendable {
        public let maxFrameBytes: Int
        public let maxPayloadBytes: Int

        /// 65541 is UInt16.max + 6. The observed encoder separately checks 65524 payload bytes.
        public init(maxFrameBytes: Int = 65_541, maxPayloadBytes: Int = 65_524) throws {
            guard (10...65_541).contains(maxFrameBytes), (0...65_524).contains(maxPayloadBytes) else {
                throw CodecError.invalidLimits
            }
            self.maxFrameBytes = maxFrameBytes
            self.maxPayloadBytes = maxPayloadBytes
        }

        private init() { maxFrameBytes = 65_541; maxPayloadBytes = 65_524 }
        public static let standard = Limits()
    }

    /// Raw 0...7 bytes only. Their sequence/total/retransmission semantics are not yet verified.
    public struct SliceMetadata: Equatable, Sendable {
        public let opaqueBytes: Data
        public init(opaqueBytes: Data) throws {
            guard opaqueBytes.count <= 7 else { throw CodecError.sliceInfoTooLong }
            self.opaqueBytes = opaqueBytes
        }
        private init() { opaqueBytes = Data() }
        public static let none = SliceMetadata()
    }

    public let messageNumber: UInt16
    /// Low five wire bits. Only bit 1's address-presence role is interpreted here.
    public let flags: UInt8
    public let address: UInt8?
    public let sliceMetadata: SliceMetadata
    /// Actual byte on the wire, NOT a Swift/Android business enum ordinal.
    public let wireBusinessID: UInt8
    public let payload: Data
    public var packetType: UInt8 { flags | UInt8(sliceMetadata.opaqueBytes.count << 5) }
    public var encodedByteCount: Int { 10 + (address == nil ? 0 : 1) + sliceMetadata.opaqueBytes.count + payload.count }

    public init(messageNumber: UInt16, flags: UInt8, address: UInt8? = nil,
                sliceMetadata: SliceMetadata = .none, wireBusinessID: UInt8,
                payload: Data, limits: Limits = .standard) throws {
        guard flags & 0xe0 == 0 else { throw CodecError.invalidFlags }
        guard (flags & 0x02 != 0) == (address != nil) else { throw CodecError.addressFlagMismatch }
        guard payload.count <= limits.maxPayloadBytes else { throw CodecError.payloadTooLarge }
        let count = 10 + (address == nil ? 0 : 1) + sliceMetadata.opaqueBytes.count + payload.count
        guard count <= limits.maxFrameBytes else { throw CodecError.frameTooLarge }
        self.messageNumber = messageNumber
        self.flags = flags
        self.address = address
        self.sliceMetadata = sliceMetadata
        self.wireBusinessID = wireBusinessID
        self.payload = payload
    }

    public func encoded(limits: Limits = .standard) throws -> Data {
        guard payload.count <= limits.maxPayloadBytes else { throw CodecError.payloadTooLarge }
        guard encodedByteCount <= limits.maxFrameBytes else { throw CodecError.frameTooLarge }
        let length = encodedByteCount - 6
        var result = Data([0xaa, 0x55, UInt8(length >> 8), UInt8(length & 0xff),
                           UInt8(messageNumber >> 8), UInt8(messageNumber & 0xff), packetType])
        if let address { result.append(address) }
        result.append(sliceMetadata.opaqueBytes)
        result.append(wireBusinessID)
        result.append(payload)
        let crc = CRC16XMODEM.checksum(result.dropFirst(4))
        result.append(UInt8(crc >> 8))
        result.append(UInt8(crc & 0xff))
        return result
    }

    /// Exactly one frame. Rejects trailing bytes, malformed lengths and CRC errors.
    /// Unlike the vendor's error-packet path, this API never returns a CRC-invalid payload.
    public static func decode(_ data: Data, limits: Limits = .standard) throws -> Self {
        guard data.count <= limits.maxFrameBytes else { throw CodecError.frameTooLarge }
        let count = try declaredByteCount(data, limits: limits)
        guard data.count >= count else { throw CodecError.truncated }
        guard data.count == count else { throw CodecError.trailingBytes }
        return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let flags = bytes[6] & 0x1f
            let sliceCount = Int(bytes[6] >> 5)
            let addressCount = flags & 0x02 == 0 ? 0 : 1
            let minimum = 10 + addressCount + sliceCount
            guard count >= minimum else { throw CodecError.invalidLength }
            let payloadCount = count - minimum
            guard payloadCount <= limits.maxPayloadBytes else { throw CodecError.payloadTooLarge }
            let expectedCRC = UInt16(bytes[count - 2]) << 8 | UInt16(bytes[count - 1])
            guard CRC16XMODEM.checksum(bytes[4..<(count - 2)]) == expectedCRC else {
                throw CodecError.crcMismatch
            }
            let sliceStart = 7 + addressCount
            let businessOffset = sliceStart + sliceCount
            return try Self(messageNumber: UInt16(bytes[4]) << 8 | UInt16(bytes[5]), flags: flags,
                            address: addressCount == 0 ? nil : bytes[7],
                            sliceMetadata: SliceMetadata(opaqueBytes: Data(bytes[sliceStart..<businessOffset])),
                            wireBusinessID: bytes[businessOffset],
                            payload: Data(bytes[(businessOffset + 1)..<(count - 2)]), limits: limits)
        }
    }

    // Shared by exact and stream decoding. Never assumes a Data slice starts at zero.
    static func declaredByteCount(_ data: Data, limits: Limits) throws -> Int {
        guard data.count >= 4 else { throw CodecError.truncated }
        return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard bytes[0] == 0xaa, bytes[1] == 0x55 else { throw CodecError.invalidHead }
            let count = (Int(bytes[2]) << 8 | Int(bytes[3])) + 6
            guard count >= 10 else { throw CodecError.invalidLength }
            guard count <= limits.maxFrameBytes else { throw CodecError.frameTooLarge }
            return count
        }
    }
}
