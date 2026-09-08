import XCTest
@testable import RayNeoDisplay

final class TextOffsetMapTests: XCTestCase {
    func testASCIIAndEmptyText() throws {
        let empty = try TextOffsetMap("")
        XCTAssertEqual(empty.utf8Count, 0)
        XCTAssertEqual(try empty.utf16Offset(forUTF8Offset: 0), 0)
        XCTAssertThrowsError(try empty.utf8Offset(forUTF16Offset: 1))
        let map = try TextOffsetMap("abc")
        XCTAssertEqual(map.utf16Count, 3)
        XCTAssertEqual(map.scalarUTF8Boundaries, [0, 1, 2, 3])
        XCTAssertEqual(try map.utf8Range(forUTF16Range: 1..<3), 1..<3)
    }

    func testChineseAndSurrogatePair() throws {
        let map = try TextOffsetMap("A中🙂B")
        XCTAssertEqual(map.utf16Count, 5)
        XCTAssertEqual(map.utf8Count, 9)
        XCTAssertEqual(map.scalarUTF16Boundaries, [0, 1, 2, 4, 5])
        XCTAssertEqual(map.scalarUTF8Boundaries, [0, 1, 4, 8, 9])
        XCTAssertEqual(try map.utf8Offset(forUTF16Offset: 2), 4)
        XCTAssertEqual(try map.utf8Offset(forUTF16Offset: 4), 8)
        XCTAssertThrowsError(try map.utf8Offset(forUTF16Offset: 3)) {
            XCTAssertEqual($0 as? TextOffsetMap.OffsetError, .insideUTF16SurrogatePair)
        }
        for byte in [2, 3, 5, 6, 7] {
            XCTAssertThrowsError(try map.utf16Offset(forUTF8Offset: byte)) {
                XCTAssertEqual($0 as? TextOffsetMap.OffsetError, .insideUTF8Scalar)
            }
        }
        XCTAssertEqual(try map.utf16Range(forUTF8Range: 4..<8), 2..<4)
    }

    func testCombiningCharacterIsNotCollapsedIntoAScalar() throws {
        let map = try TextOffsetMap("e\u{301}")
        XCTAssertEqual(map.scalarUTF16Boundaries, [0, 1, 2])
        XCTAssertEqual(map.characterUTF16Boundaries, [0, 2])
        XCTAssertEqual(map.characterUTF8Boundaries, [0, 3])
        XCTAssertEqual(try map.utf8Offset(forUTF16Offset: 1), 1)
        XCTAssertThrowsError(try map.utf8Offset(forUTF16Offset: 1, boundary: .character)) {
            XCTAssertEqual($0 as? TextOffsetMap.OffsetError, .insideCharacter)
        }
        XCTAssertThrowsError(try map.utf16Offset(forUTF8Offset: 1, boundary: .character))
    }

    func testFamilyEmojiAndFlagCharacterBoundaries() throws {
        let family = try TextOffsetMap("👨‍👩‍👧‍👦")
        XCTAssertEqual(family.utf16Count, 11)
        XCTAssertEqual(family.utf8Count, 25)
        XCTAssertEqual(family.characterUTF16Boundaries, [0, 11])
        XCTAssertEqual(try family.utf8Offset(forUTF16Offset: 2), 4)
        XCTAssertThrowsError(try family.utf8Offset(forUTF16Offset: 2, boundary: .character))
        let flag = try TextOffsetMap("🇨🇳")
        XCTAssertEqual(flag.characterUTF16Boundaries, [0, 4])
        XCTAssertEqual(flag.scalarUTF8Boundaries, [0, 4, 8])
    }

    func testNewlineNormalizationMustBeExplicit() throws {
        let input = "A\r\n中\r🙂\n"
        let preserved = try TextOffsetMap(input)
        XCTAssertEqual(preserved.text, input)
        XCTAssertEqual(preserved.utf8Count, 12)
        let normalized = try TextOffsetMap(input, newlinePolicy: .normalizeToLF)
        XCTAssertEqual(normalized.text, "A\n中\n🙂\n")
        XCTAssertEqual(normalized.utf8Count, 11)
        XCTAssertEqual(normalized.utf16Count, 7)
        XCTAssertNotEqual(preserved.utf8Count, normalized.utf8Count)
    }

    func testNegativeAndBeyondEndAreNeverRounded() throws {
        let map = try TextOffsetMap("🙂")
        for offset in [-1, 3, Int.max] {
            XCTAssertThrowsError(try map.utf8Offset(forUTF16Offset: offset)) {
                XCTAssertEqual($0 as? TextOffsetMap.OffsetError, .outOfBounds)
            }
        }
        for offset in [-1, 5, Int.max] {
            XCTAssertThrowsError(try map.utf16Offset(forUTF8Offset: offset)) {
                XCTAssertEqual($0 as? TextOffsetMap.OffsetError, .outOfBounds)
            }
        }
    }

    func testVariationSelectorSkinToneAndRanges() throws {
        let map = try TextOffsetMap("X👍🏽Y✈️Z")
        XCTAssertEqual(map.characterUTF16Boundaries, [0, 1, 5, 6, 8, 9])
        XCTAssertEqual(try map.utf8Range(forUTF16Range: 1..<5, boundary: .character), 1..<9)
        XCTAssertThrowsError(try map.utf8Range(forUTF16Range: 1..<3, boundary: .character))
    }

    func testDeterministicUnicodeBoundaryRoundTrips() throws {
        let scalars: [UInt32] = [0, 0x0A, 0x0D, 0x41, 0x7F, 0x80, 0x301, 0x7FF,
                                 0x800, 0x200D, 0x4E2D, 0xD7FF, 0xE000, 0xFE0F,
                                 0xFFFF, 0x10000, 0x1F1E8, 0x1F1F3, 0x1F3FD,
                                 0x1F642, 0x10FFFF]
        var seed: UInt64 = 0x5241594E454F
        for _ in 0..<256 {
            var input = String.UnicodeScalarView()
            for _ in 0..<16 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                input.append(UnicodeScalar(scalars[Int(seed % UInt64(scalars.count))])!)
            }
            let text = String(input)
            let map = try TextOffsetMap(text)
            XCTAssertEqual(map.utf8Count, text.utf8.count)
            XCTAssertEqual(map.utf16Count, text.utf16.count)
            for (units, bytes) in zip(map.scalarUTF16Boundaries, map.scalarUTF8Boundaries) {
                XCTAssertEqual(try map.utf8Offset(forUTF16Offset: units), bytes)
                XCTAssertEqual(try map.utf16Offset(forUTF8Offset: bytes), units)
            }
            let validBytes = Set(map.scalarUTF8Boundaries)
            for bytes in 0...map.utf8Count where !validBytes.contains(bytes) {
                XCTAssertThrowsError(try map.utf16Offset(forUTF8Offset: bytes))
            }
            let validUnits = Set(map.scalarUTF16Boundaries)
            for units in 0...map.utf16Count where !validUnits.contains(units) {
                XCTAssertThrowsError(try map.utf8Offset(forUTF16Offset: units))
            }
            for (units, bytes) in zip(map.characterUTF16Boundaries, map.characterUTF8Boundaries) {
                XCTAssertEqual(try map.utf8Offset(forUTF16Offset: units, boundary: .character), bytes)
                XCTAssertEqual(try map.utf16Offset(forUTF8Offset: bytes, boundary: .character), units)
            }
        }
    }

    func testTextResourceLimitsBeforeNormalizationAndTableAllocation() throws {
        let bytes = try TextOffsetLimits(maxInputUTF8Bytes: 3, maxScalarBoundaries: 10)
        XCTAssertNoThrow(try TextOffsetMap("中", limits: bytes))
        XCTAssertThrowsError(try TextOffsetMap("🙂", limits: bytes)) {
            XCTAssertEqual($0 as? TextOffsetLimitError, .inputTooLarge)
        }
        // The 4-byte input exceeds the cap even though normalization would shrink it.
        XCTAssertThrowsError(try TextOffsetMap("\r\n\r\n", newlinePolicy: .normalizeToLF, limits: bytes))
        let boundaries = try TextOffsetLimits(maxInputUTF8Bytes: 100, maxScalarBoundaries: 3)
        XCTAssertNoThrow(try TextOffsetMap("🙂中", limits: boundaries))
        XCTAssertThrowsError(try TextOffsetMap("abc", limits: boundaries)) {
            XCTAssertEqual($0 as? TextOffsetLimitError, .tooManyBoundaries)
        }
        let emptyOnly = try TextOffsetLimits(maxInputUTF8Bytes: 1, maxScalarBoundaries: 1)
        XCTAssertNoThrow(try TextOffsetMap("", limits: emptyOnly))
        XCTAssertThrowsError(try TextOffsetMap("a", limits: emptyOnly))
        XCTAssertThrowsError(try TextOffsetLimits(maxInputUTF8Bytes: 0, maxScalarBoundaries: 1))
        XCTAssertThrowsError(try TextOffsetLimits(maxInputUTF8Bytes: 1, maxScalarBoundaries: 0))
    }
}
