import Foundation

public enum OggCRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value) << 24
        for _ in 0..<8 {
            crc = (crc &<< 1) ^ ((crc & 0x8000_0000) != 0 ? 0x04c1_1db7 : 0)
        }
        return crc
    }

    /// Ogg's non-reflected polynomial, initial zero, no final xor. This is not CRC-32/ISO-HDLC.
    /// When checking a page, offsets 22..<26 are treated as zero without modifying input.
    public static func compute(_ bytes: Data, zeroPageChecksumField: Bool = false) -> UInt32 {
        calculate(bytes, zeroPageChecksumField: zeroPageChecksumField)
    }

    static func calculate<C: Collection>(_ bytes: C, zeroPageChecksumField: Bool) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0
        for (offset, original) in bytes.enumerated() {
            let byte = zeroPageChecksumField && (22..<26).contains(offset) ? 0 : original
            crc = (crc &<< 8) ^ table[Int((crc >> 24) ^ UInt32(byte))]
        }
        return crc
    }
}

func little16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

func little32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[offset + $1]) << ($1 * 8)) }
}

func signedLittle64(_ bytes: [UInt8], _ offset: Int) -> Int64 {
    Int64(bitPattern: (0..<8).reduce(UInt64(0)) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) })
}
