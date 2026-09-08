import XCTest
@testable import RayNeoProtocol

final class TransportFrameTests: XCTestCase {
    // Synthetic only. Independent bitwise JavaScript CRC calculation, not a captured device frame.
    private let minimalVector = Data([0xaa, 0x55, 0, 7, 0x12, 0x34, 0, 0x2a, 1, 2, 0xfe, 0x7e, 0xd3])

    private func minimal() throws -> TransportFrame {
        try TransportFrame(messageNumber: 0x1234, flags: 0, wireBusinessID: 0x2a, payload: Data([1, 2, 0xfe]))
    }

    func testCRCIndependentCheckVectors() {
        XCTAssertEqual(CRC16XMODEM.checksum(Data("123456789".utf8)), 0x31c3)
        XCTAssertEqual(CRC16XMODEM.checksum(Data()), 0)
        XCTAssertEqual(CRC16XMODEM.checksum([UInt8(0x12), 0x34, 0, 0x2a, 1, 2, 0xfe]), 0x7ed3)
    }

    func testGoldenFrameEncodeAndDecode() throws {
        XCTAssertEqual(try minimal().encoded(), minimalVector)
        XCTAssertEqual(try TransportFrame.decode(minimalVector), try minimal())
        XCTAssertEqual(try minimal().encodedByteCount, 13)
    }

    func testAddressAndOpaqueSliceGoldenVector() throws {
        let frame = try TransportFrame(messageNumber: 0xbeef, flags: 2, address: 0x21,
                                       sliceMetadata: .init(opaqueBytes: Data([0xa0, 0xb0, 0xc0])),
                                       wireBusinessID: 0xe1, payload: Data([0, 0xff, 0x55]))
        let expected = Data([0xaa, 0x55, 0, 11, 0xbe, 0xef, 0x62, 0x21, 0xa0, 0xb0, 0xc0, 0xe1, 0, 0xff, 0x55, 0x28, 0x16])
        XCTAssertEqual(try frame.encoded(), expected)
        XCTAssertEqual(try TransportFrame.decode(expected), frame)
        XCTAssertEqual(frame.packetType, 0x62)
    }

    func testEveryFlagAndSliceLengthPreservedWithoutInventingSemantics() throws {
        for flags in UInt8(0)...31 {
            for sliceLength in 0...7 {
                let frame = try TransportFrame(messageNumber: .max, flags: flags,
                                               address: flags & 2 == 0 ? nil : 0xff,
                                               sliceMetadata: .init(opaqueBytes: Data(repeating: 0xff, count: sliceLength)),
                                               wireBusinessID: 0xff, payload: Data([0xaa, 0x55, 0, 0]))
                XCTAssertEqual(try TransportFrame.decode(frame.encoded()), frame)
            }
        }
    }

    func testMinimalEmptyPayloadAndNonZeroDataSlice() throws {
        let frame = try TransportFrame(messageNumber: 0, flags: 0, wireBusinessID: 0, payload: Data())
        XCTAssertEqual(try frame.encoded().count, 10)
        let prefixed = Data([9, 8]) + (try frame.encoded())
        XCTAssertEqual(try TransportFrame.decode(prefixed.dropFirst(2)), frame)
    }

    func testEveryTruncationRejected() {
        for length in 0..<minimalVector.count {
            XCTAssertThrowsError(try TransportFrame.decode(minimalVector.prefix(length)))
        }
    }

    func testCRCRejectsEverySingleBitChangeInCoveredBytesAndTrailer() {
        for position in 4..<minimalVector.count {
            for bit in 0..<8 {
                var altered = minimalVector
                altered[position] ^= UInt8(1 << bit)
                XCTAssertThrowsError(try TransportFrame.decode(altered))
            }
        }
    }

    func testBadHeadDeclaredLengthAndTrailingDataRejected() {
        var badHead = minimalVector; badHead[0] = 0
        XCTAssertThrowsError(try TransportFrame.decode(badHead)) { XCTAssertEqual($0 as? TransportFrame.CodecError, .invalidHead) }
        for declared in 0...3 {
            XCTAssertThrowsError(try TransportFrame.decode(Data([0xaa, 0x55, 0, UInt8(declared)]))) {
                XCTAssertEqual($0 as? TransportFrame.CodecError, .invalidLength)
            }
        }
        var tooLong = minimalVector; tooLong[3] += 1
        XCTAssertThrowsError(try TransportFrame.decode(tooLong)) { XCTAssertEqual($0 as? TransportFrame.CodecError, .truncated) }
        XCTAssertThrowsError(try TransportFrame.decode(minimalVector + Data([0]))) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .trailingBytes)
        }
    }

    func testTypeCannotClaimMissingAddressOrSlices() {
        for packetType: UInt8 in [2, 0x20, 0xe0, 0xe2] {
            let malformed = Data([0xaa, 0x55, 0, 4, 0, 0, packetType, 0, 0, 0])
            XCTAssertThrowsError(try TransportFrame.decode(malformed)) {
                XCTAssertEqual($0 as? TransportFrame.CodecError, .invalidLength)
            }
        }
    }

    func testConstructionRejectsFlagTruncationAndAddressInconsistency() {
        for flags: UInt8 in [0x20, 0xe0, 0xff] {
            XCTAssertThrowsError(try TransportFrame(messageNumber: 0, flags: flags, wireBusinessID: 0, payload: Data())) {
                XCTAssertEqual($0 as? TransportFrame.CodecError, .invalidFlags)
            }
        }
        XCTAssertThrowsError(try TransportFrame(messageNumber: 0, flags: 2, wireBusinessID: 0, payload: Data()))
        XCTAssertThrowsError(try TransportFrame(messageNumber: 0, flags: 0, address: 1, wireBusinessID: 0, payload: Data()))
        XCTAssertThrowsError(try TransportFrame.SliceMetadata(opaqueBytes: Data(repeating: 0, count: 8)))
    }

    func testBothPayloadAndTotalWireLimitsApply() throws {
        let largest = try TransportFrame(messageNumber: 0, flags: 0,
                                         sliceMetadata: .init(opaqueBytes: Data(repeating: 0, count: 7)),
                                         wireBusinessID: 0, payload: Data(repeating: 0x5a, count: 65_524))
        let encoded = try largest.encoded()
        XCTAssertEqual(encoded.count, 65_541)
        XCTAssertEqual(Array(encoded[2...3]), [0xff, 0xff])
        XCTAssertEqual(try TransportFrame.decode(encoded), largest)
        XCTAssertThrowsError(try TransportFrame(messageNumber: 0, flags: 0, wireBusinessID: 0,
                                                payload: Data(repeating: 0, count: 65_525)))
        XCTAssertThrowsError(try TransportFrame(messageNumber: 0, flags: 2, address: 1,
                                                sliceMetadata: .init(opaqueBytes: Data(repeating: 0, count: 7)),
                                                wireBusinessID: 0, payload: Data(repeating: 0, count: 65_524))) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .frameTooLarge)
        }
    }

    func testConfigurableLimitsAreEnforcedForEncodeAndDecode() throws {
        let noPayload = try TransportFrame.Limits(maxFrameBytes: 10, maxPayloadBytes: 0)
        XCTAssertThrowsError(try minimal().encoded(limits: noPayload))
        XCTAssertThrowsError(try TransportFrame.decode(minimalVector, limits: noPayload))
        let smallPayload = try TransportFrame.Limits(maxFrameBytes: 64, maxPayloadBytes: 2)
        XCTAssertThrowsError(try TransportFrame.decode(minimalVector, limits: smallPayload)) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .payloadTooLarge)
        }
        XCTAssertThrowsError(try TransportFrame.Limits(maxFrameBytes: 9))
        XCTAssertThrowsError(try TransportFrame.Limits(maxFrameBytes: 65_542))
        XCTAssertThrowsError(try TransportFrame.Limits(maxPayloadBytes: -1))
        XCTAssertThrowsError(try TransportFrame.Limits(maxPayloadBytes: 65_525))
    }

    func testDeterministicArbitraryInputDoesNotCrashOrYieldUncheckedFrame() throws {
        var state: UInt64 = 0x7261796e656f
        for count in 0..<512 {
            var bytes = Data()
            for _ in 0..<(count % 96) {
                state = state &* 6364136223846793005 &+ 1
                bytes.append(UInt8(truncatingIfNeeded: state >> 24))
            }
            if let decoded = try? TransportFrame.decode(bytes) {
                XCTAssertEqual(try decoded.encoded(), bytes)
            }
        }
    }
}
