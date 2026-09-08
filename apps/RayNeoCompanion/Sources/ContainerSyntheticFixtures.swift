#if DEBUG
import Foundation

/// Debug-only container bytes, not recorded speech or a codec/playback acceptance fixture.
enum ContainerSyntheticFixture: String, CaseIterable, Identifiable {
    case supported, badCRC, unsupportedVersion
    var id: String { rawValue }
    var title: String {
        switch self {
        case .supported: return "合成 Ogg · 结构子集"
        case .badCRC: return "合成 Ogg · CRC 损坏"
        case .unsupportedVersion: return "合成 Ogg · 未支持版本"
        }
    }
    func bytes() -> Data {
        var head = Data(repeating: 0, count: 19)
        head.replaceSubrange(0..<8, with: "OpusHead".utf8)
        head[8] = self == .unsupportedVersion ? 2 : 1; head[9] = 2
        Self.put(UInt16(312), into: &head, at: 10)
        Self.put(UInt32(16_000), into: &head, at: 12)
        let tags = Data("OpusTags".utf8) + Data(repeating: 0, count: 8)
        var result = Self.page(0, flags: 2, granule: 0, payload: head)
        result.append(Self.page(1, flags: 0, granule: 0, payload: tags))
        result.append(Self.page(2, flags: 4, granule: 960, payload: Data([0xf8, 0xff, 0xfe])))
        if self == .badCRC { result[result.count - 1] ^= 1 }
        return result
    }
    private static func page(_ sequence: UInt32, flags: UInt8, granule: Int64, payload: Data) -> Data {
        precondition(payload.count < 255)
        var page = Data(repeating: 0, count: 28)
        page.replaceSubrange(0..<4, with: "OggS".utf8)
        page[5] = flags; page[26] = 1; page[27] = UInt8(payload.count)
        put(granule, into: &page, at: 6); put(UInt32(117), into: &page, at: 14)
        put(sequence, into: &page, at: 18); page.append(payload)
        // Independent bit-by-bit fixture CRC; do not use the implementation under test.
        var crc: UInt32 = 0
        for byte in page {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 { let top = crc & 0x8000_0000 != 0; crc = crc &<< 1; if top { crc ^= 0x04c1_1db7 } }
        }
        put(crc, into: &page, at: 22)
        return page
    }
    private static func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
        let bits = UInt64(truncatingIfNeeded: value)
        for index in 0..<MemoryLayout<T>.size { data[offset + index] = UInt8(truncatingIfNeeded: bits >> (index * 8)) }
    }
}
#endif
