import Foundation

/// CRC-16/XMODEM: polynomial 0x1021, initial value 0, no reflection/xor-out.
/// This detects corruption; it is neither encryption nor source authentication.
public enum CRC16XMODEM {
    public static func checksum<Bytes: Sequence>(_ bytes: Bytes) -> UInt16 where Bytes.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 == 0 ? crc << 1 : (crc << 1) ^ 0x1021
            }
        }
        return crc
    }
}
