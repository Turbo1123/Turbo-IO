import Foundation

/// 1-byte tag + 2-byte big-endian length + value.
/// iOS RNTlvBox.pack disassembly corroborates this framing.
public struct TLV: Equatable {
    public let tag: UInt8
    public let value: Data
    public init(tag: UInt8, value: Data) { self.tag = tag; self.value = value }

    public func encoded() throws -> Data {
        guard value.count <= Int(UInt16.max) else { throw ProtocolError.invalidLength }
        return Data([tag, UInt8(value.count >> 8), UInt8(value.count & 0xff)]) + value
    }

    public static func decode(_ data: Data) throws -> [TLV] {
        let bytes = Array(data)
        var result: [TLV] = [], offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 3 else { throw ProtocolError.truncatedTLV }
            let tag = bytes[offset]
            let length = Int(bytes[offset+1]) << 8 | Int(bytes[offset+2])
            offset += 3
            guard length <= bytes.count-offset else { throw ProtocolError.truncatedTLV }
            result.append(TLV(tag: tag, value: Data(bytes[offset..<offset+length])))
            offset += length
        }
        return result
    }

    /// Inner authentication message; transport packet header is NOT included.
    public static func authRequest(random: Data, proof: Data) throws -> Data {
        guard random.count == 4, proof.count == 32 else { throw ProtocolError.invalidLength }
        let children = try TLV(tag: 0x10, value: random).encoded() + TLV(tag: 0x11, value: proof).encoded()
        return try TLV(tag: 0x18, value: children).encoded()
    }

    public static func authFields(_ inner: Data) throws -> (random: Data, proof: Data) {
        let fields = try decode(inner)
        let randoms = fields.filter { $0.tag == 0x10 }
        let proofs = fields.filter { $0.tag == 0x11 }
        guard randoms.count <= 1, proofs.count <= 1 else { throw ProtocolError.duplicateTag }
        guard let r = randoms.first?.value, let p = proofs.first?.value,
              r.count == 4, p.count == 32 else { throw ProtocolError.invalidLength }
        return (r,p)
    }
}
