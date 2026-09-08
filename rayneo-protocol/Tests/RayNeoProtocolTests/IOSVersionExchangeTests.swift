import XCTest
@testable import RayNeoProtocol

final class IOSVersionExchangeTests: XCTestCase {
    typealias Codec = IOSVersionExchange
    private let identifier = Data([0, 1, 2, 3, 4, 5])
    // Hand-assembled synthetic fields, not output captured from a device or another SDK encoder.
    private let sixFieldVector = Data([
        0x11, 0, 40, 0x10, 0, 1, 1, 0x11, 0, 6, 0, 1, 2, 3, 4, 5,
        0x12, 0, 3, 0x4c, 0x61, 0x62, 0x13, 0, 1, 1,
        0x16, 0, 6, 0x69, 0x50, 0x68, 0x6f, 0x6e, 0x65,
        0x17, 0, 5, 0x54, 0x65, 0x73, 0x74, 0x31
    ])

    private func request(_ policy: Codec.ModelPolicy = .omitForV4,
                         limits: Codec.Limits = .standard) throws -> Codec.Request {
        try .init(phoneProtocolIdentifier: identifier, phoneName: "Lab", phoneModelName: "Test1",
                  modelPolicy: policy, limits: limits)
    }

    private func response(_ fields: [TLV], limits: Codec.Limits = .standard) throws -> Codec.Response {
        try Codec.decodeResponse(wireBusinessID: 0x10, payload: packet(fields), limits: limits)
    }

    private func packet(_ fields: [TLV]) throws -> Data {
        var bytes = Data()
        for field in fields { bytes.append(try field.encoded()) }
        return try TLV(tag: 0x11, value: bytes).encoded()
    }

    func testIndependentSixFieldVectorAndFixedOrder() throws {
        let payload = try request().encodedPayload()
        XCTAssertEqual(payload, sixFieldVector)
        let inner = try TLV.decode(XCTUnwrap(TLV.decode(payload).first).value)
        XCTAssertEqual(inner.map(\.tag), [0x10, 0x11, 0x12, 0x13, 0x16, 0x17])
    }

    func testSevenFieldOtherRelationVector() throws {
        var expected = sixFieldVector; expected[2] = 44
        expected.append(contentsOf: [0x1b, 0, 1, 1])
        XCTAssertEqual(try request(.includeBondTag(.otherOrUnavailable)).encodedPayload(), expected)
    }

    func testSevenFieldMutualRelationDoesNotImplyAuthentication() throws {
        var expected = sixFieldVector; expected[2] = 44
        expected.append(contentsOf: [0x1b, 0, 1, 2])
        XCTAssertEqual(try request(.includeBondTag(.mutual)).encodedPayload(), expected)
    }

    func testIndependentFrameCRCVector() throws {
        // Independent bitwise JavaScript CRC-XMODEM: 0x1e77 over message number through payload.
        let frame = try request().transportFrame(messageNumber: 0x1234, flags: 0)
        let expected = Data([0xaa, 0x55, 0, 47, 0x12, 0x34, 0, 0x10]) +
            sixFieldVector + Data([0x1e, 0x77])
        XCTAssertEqual(try frame.encoded(), expected)
        XCTAssertEqual(try TransportFrame.decode(expected), frame)
        XCTAssertEqual(frame.wireBusinessID, 0x10)
        XCTAssertTrue(frame.sliceMetadata.opaqueBytes.isEmpty)
    }

    func testNamesAreExactUTF8WithoutTrimmingNormalizationOrNullConversion() throws {
        let name = "  测试\0e\u{301}  ", model = "null"
        let request = try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: name,
                                        phoneModelName: model, modelPolicy: .omitForV4)
        let inner = try TLV.decode(XCTUnwrap(TLV.decode(request.encodedPayload()).first).value)
        XCTAssertEqual(inner[2].value, Data(name.utf8))
        XCTAssertEqual(inner[5].value, Data(model.utf8))
    }

    func testRequestEqualityPreservesOpaqueUTF8Identity() throws {
        let nfc = try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: "é",
                                    phoneModelName: "é", modelPolicy: .omitForV4)
        let nameNFD = try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: "e\u{301}",
                                        phoneModelName: "é", modelPolicy: .omitForV4)
        let modelNFD = try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: "é",
                                         phoneModelName: "e\u{301}", modelPolicy: .omitForV4)
        XCTAssertNotEqual(nfc, nameNFD)
        XCTAssertNotEqual(nfc, modelNFD)
        XCTAssertNotEqual(try nfc.encodedPayload(), try nameNFD.encodedPayload())
    }

    func testIdentifierUsesStrictLocalSixBytePolicyAndHandlesDataSlices() throws {
        for count in [0, 1, 5, 7, 65_536] {
            XCTAssertThrowsError(try Codec.Request(phoneProtocolIdentifier: Data(repeating: 0, count: count),
                                                   phoneName: "Lab", phoneModelName: "Test1", modelPolicy: .omitForV4)) {
                XCTAssertEqual($0 as? Codec.CodecError, .invalidIdentifierLength)
            }
        }
        let prefixed = Data([0xff, 0xfe]) + identifier
        let sliced = try Codec.Request(phoneProtocolIdentifier: prefixed.dropFirst(2), phoneName: "Lab",
                                       phoneModelName: "Test1", modelPolicy: .omitForV4)
        XCTAssertEqual(try sliced.encodedPayload(), sixFieldVector)
    }

    func testEmptyRequestNamesAreNotSilentlyFilled() {
        for (name, model, tag): (String, String, UInt8) in [("", "M", 0x12), ("N", "", 0x17)] {
            XCTAssertThrowsError(try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: name,
                                                   phoneModelName: model, modelPolicy: .omitForV4)) {
                XCTAssertEqual($0 as? Codec.CodecError, .emptyText(tag: tag))
            }
        }
    }

    func testRequestFieldLimitCountsUTF8BytesNotCharacters() throws {
        let limits = try Codec.Limits(maxFieldBytes: 6)
        let valid = try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: "中文",
                                      phoneModelName: "Model", modelPolicy: .omitForV4, limits: limits)
        XCTAssertNoThrow(try valid.encodedPayload(limits: limits))
        XCTAssertThrowsError(try Codec.Request(phoneProtocolIdentifier: identifier, phoneName: "中文x",
                                               phoneModelName: "Model", modelPolicy: .omitForV4, limits: limits)) {
            XCTAssertEqual($0 as? Codec.CodecError, .fieldTooLarge(tag: 0x12))
        }
        XCTAssertThrowsError(try request(limits: .init(maxFieldBytes: 5))) {
            XCTAssertEqual($0 as? Codec.CodecError, .fieldTooLarge(tag: 0x11))
        }
    }

    func testRequestPayloadAndFieldCountLimitsRecheckedAtEncode() throws {
        let r = try request()
        XCTAssertEqual(try r.encodedPayload(limits: .init(maxPayloadBytes: 43)).count, 43)
        XCTAssertThrowsError(try r.encodedPayload(limits: .init(maxPayloadBytes: 42))) {
            XCTAssertEqual($0 as? Codec.CodecError, .payloadTooLarge)
        }
        XCTAssertNoThrow(try request(limits: .init(maxFields: 6)))
        XCTAssertThrowsError(try request(.includeBondTag(.mutual), limits: .init(maxFields: 6))) {
            XCTAssertEqual($0 as? Codec.CodecError, .tooManyFields)
        }
        XCTAssertThrowsError(try r.encodedPayload(limits: .init(maxFields: 5)))
        XCTAssertThrowsError(try r.transportFrame(messageNumber: 0, flags: 0,
                                                  frameLimits: .init(maxPayloadBytes: 42)))
    }

    func testInvalidLimitsRejectedWithoutOverflow() {
        for value in [Int.min, -1, 0, 2, 65_525, Int.max] {
            XCTAssertThrowsError(try Codec.Limits(maxPayloadBytes: value))
        }
        for value in [Int.min, -1, 65_522, Int.max] {
            XCTAssertThrowsError(try Codec.Limits(maxFieldBytes: value))
        }
        for value in [Int.min, -1, 257, Int.max] {
            XCTAssertThrowsError(try Codec.Limits(maxFields: value))
        }
    }

    func testResponseIsDirectionSpecificAndRetainsUnknownRawOrder() throws {
        let fields = [TLV(tag: 0xfa, value: Data([0xff, 0, 0xaa])),
                      TLV(tag: 0x14, value: Data("synthetic-sn".utf8)),
                      TLV(tag: 0x11, value: Data([0xfe])), TLV(tag: 0x19, value: Data()),
                      TLV(tag: 0x18, value: Data("synthetic-mfi".utf8))]
        let decoded = try response(fields)
        XCTAssertEqual(decoded.fields.map(\.tag), fields.map(\.tag))
        XCTAssertEqual(decoded.fields.map(\.value), fields.map(\.value))
        XCTAssertEqual(decoded.serialNumber, "synthetic-sn")
        XCTAssertEqual(decoded.mfiSerialNumber, "synthetic-mfi")
        XCTAssertEqual(decoded.unknownFields.map(\.tag), [0xfa])
        XCTAssertEqual(decoded.value(for: .opaque11), Data([0xfe]))
        XCTAssertEqual(decoded.value(for: .opaque19), Data())
        // Same outer type cannot establish direction/source. Request-only tags stay unknown on receive.
        let ownRequest = try Codec.decodeResponse(wireBusinessID: 0x10, payload: sixFieldVector)
        XCTAssertNil(ownRequest.serialNumber)
        XCTAssertEqual(ownRequest.unknownFields.map(\.tag), [0x10, 0x12, 0x13, 0x16, 0x17])
    }

    func testResponseEmptyContainerDoesNotInventRequiredFieldsOrSuccess() throws {
        let decoded = try Codec.decodeResponse(wireBusinessID: 0x10, payload: Data([0x11, 0, 0]),
                                                limits: .init(maxPayloadBytes: 3, maxFieldBytes: 0, maxFields: 0))
        XCTAssertTrue(decoded.fields.isEmpty)
        XCTAssertNil(decoded.serialNumber)
        XCTAssertNil(decoded.mfiSerialNumber)
        XCTAssertNil(decoded.value(for: .opaque11))
    }

    func testResponseEmptyTextLiteralNullAndNULAreNotAbsence() throws {
        let empty = try response([TLV(tag: 0x14, value: Data())])
        XCTAssertEqual(empty.serialNumber, "")
        XCTAssertEqual(empty.value(for: .serialNumber), Data())
        XCTAssertNil(empty.mfiSerialNumber)
        let literal = try response([TLV(tag: 0x14, value: Data("null".utf8)),
                                    TLV(tag: 0x18, value: Data([0]))])
        XCTAssertEqual(literal.serialNumber, "null")
        XCTAssertEqual(literal.mfiSerialNumber, "\0")
    }

    func testResponseKnownSingularDuplicatesRejectedEvenWhenIdenticalOrEmpty() {
        for tag: UInt8 in [0x11, 0x14, 0x18, 0x19] {
            XCTAssertThrowsError(try response([TLV(tag: tag, value: Data()), TLV(tag: tag, value: Data())])) {
                XCTAssertEqual($0 as? Codec.CodecError, .duplicateKnownField(tag: tag))
            }
        }
    }

    func testResponseRepeatedUnknownFieldsRemainDistinctAndOrdered() throws {
        // Outbound tag 0x12 has NOT been asserted to be a known receive-side field.
        let fields = [TLV(tag: 0x12, value: Data()), TLV(tag: 0x12, value: Data([0xff])),
                      TLV(tag: 0xff, value: Data([1])), TLV(tag: 0xff, value: Data([2]))]
        let decoded = try response(fields)
        XCTAssertEqual(decoded.unknownFields.map(\.value), fields.map(\.value))
    }

    func testResponseKnownTextRejectsInvalidUTF8WithoutReplacementCharacters() {
        for tag: UInt8 in [0x14, 0x18] {
            for bytes: [UInt8] in [[0xff], [0xc0, 0x80], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe4, 0xb8]] {
                XCTAssertThrowsError(try response([TLV(tag: tag, value: Data(bytes))])) {
                    XCTAssertEqual($0 as? Codec.CodecError, .invalidUTF8(tag: tag))
                }
            }
        }
    }

    func testOpaqueResponseFieldsDoNotAcquireTextOrAuthSemantics() throws {
        let decoded = try response([TLV(tag: 0x11, value: Data([0xff])),
                                    TLV(tag: 0x19, value: Data([0xff])), TLV(tag: 0xfe, value: Data([0xff]))])
        XCTAssertEqual(decoded.fields.map(\.value), [Data([0xff]), Data([0xff]), Data([0xff])])
    }

    func testResponseEqualityIsByteExactEvenForCanonicallyEquivalentText() throws {
        let a = try response([TLV(tag: 0x14, value: Data("é".utf8))])
        let b = try response([TLV(tag: 0x14, value: Data("e\u{301}".utf8))])
        XCTAssertEqual(a.serialNumber, b.serialNumber) // Swift String canonical equivalence.
        XCTAssertNotEqual(a, b) // The wire bytes still distinguish the responses.
    }

    func testWrongBusinessAndOuterMessageTypesAreRejected() {
        for business: UInt8 in [0, 0x11, 0x19, 0xff] {
            XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: business, payload: Data([0x11, 0, 0]))) {
                XCTAssertEqual($0 as? Codec.CodecError, .wrongBusinessID)
            }
        }
        for tag: UInt8 in [0x12, 0x18, 0x19, 0xff] {
            XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: Data([tag, 0, 0]))) {
                XCTAssertEqual($0 as? Codec.CodecError, .invalidOuterTag)
            }
        }
    }

    func testEveryOuterTruncationAndTrailingByteRejected() throws {
        let valid = try packet([TLV(tag: 0x14, value: Data("synthetic".utf8))])
        for count in 0..<valid.count {
            XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: valid.prefix(count)))
        }
        XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: valid + Data([0])))
        XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: valid + Data([0x11, 0, 0])))
        XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: Data([0x11, 0xff, 0xff])))
    }

    func testInnerPartialHeaderAndDeclaredValueRejected() {
        for inner: [UInt8] in [[0x14], [0x14, 0], [0x14, 0, 1], [0xfa, 0, 2, 1]] {
            let payload = Data([0x11, 0, UInt8(inner.count)] + inner)
            XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: payload)) {
                XCTAssertEqual($0 as? Codec.CodecError, .truncatedField)
            }
        }
    }

    func testResponseResourceLimitsApplyBeforeUnboundedDecoding() throws {
        let two = [TLV(tag: 0xff, value: Data()), TLV(tag: 0xff, value: Data())]
        XCTAssertNoThrow(try response(two, limits: .init(maxPayloadBytes: 9, maxFieldBytes: 0, maxFields: 2)))
        XCTAssertThrowsError(try response(two, limits: .init(maxFields: 1))) {
            XCTAssertEqual($0 as? Codec.CodecError, .tooManyFields)
        }
        XCTAssertThrowsError(try response(two, limits: .init(maxPayloadBytes: 8))) {
            XCTAssertEqual($0 as? Codec.CodecError, .payloadTooLarge)
        }
        XCTAssertThrowsError(try response([TLV(tag: 0xfe, value: Data([1, 2]))], limits: .init(maxFieldBytes: 1))) {
            XCTAssertEqual($0 as? Codec.CodecError, .fieldTooLarge(tag: 0xfe))
        }
    }

    func testLargestLocalPayloadAcceptedAndNextByteRejected() throws {
        let limits = try Codec.Limits(maxPayloadBytes: 65_524, maxFieldBytes: 65_521)
        let fields = [TLV(tag: 0xfe, value: Data(repeating: 0x7f, count: 65_518))]
        let bytes = try packet(fields)
        XCTAssertEqual(bytes.count, 65_524)
        XCTAssertEqual(try Codec.decodeResponse(wireBusinessID: 0x10, payload: bytes, limits: limits).fields[0].value.count, 65_518)
        XCTAssertThrowsError(try Codec.decodeResponse(wireBusinessID: 0x10, payload: bytes + Data([0]), limits: limits)) {
            XCTAssertEqual($0 as? Codec.CodecError, .payloadTooLarge)
        }
    }

    func testAll256TagsWithBoundedCountAndNonZeroStartIndex() throws {
        let fields = (0...255).map { TLV(tag: UInt8($0), value: Data()) }
        let bytes = try packet(fields)
        let prefixed = Data([9, 8, 7]) + bytes
        let decoded = try Codec.decodeResponse(wireBusinessID: 0x10, payload: prefixed.dropFirst(3),
                                                limits: .init(maxFields: 256))
        XCTAssertEqual(decoded.fields.map(\.tag), (0...255).map(UInt8.init))
        XCTAssertEqual(decoded.unknownFields.count, 252)
    }

    func testFrameStreamToResponseAtEverySplitAndCRCFailure() throws {
        let payload = try packet([TLV(tag: 0x18, value: Data("synthetic".utf8)), TLV(tag: 0xfa, value: Data([9]))])
        let frame = try TransportFrame(messageNumber: 7, flags: 0, wireBusinessID: 0x10, payload: payload)
        let bytes = try frame.encoded()
        for split in 0...bytes.count {
            var stream = try TransportFrameStreamDecoder()
            let a = try stream.append(bytes.prefix(split))
            let b = try stream.append(bytes.dropFirst(split))
            XCTAssertEqual(a + b, [frame])
            let decoded = try Codec.decodeResponse(from: XCTUnwrap((a + b).first))
            XCTAssertEqual(decoded.mfiSerialNumber, "synthetic")
            try stream.finish()
        }
        var corrupted = bytes; corrupted[corrupted.count - 1] ^= 1
        XCTAssertThrowsError(try TransportFrame.decode(corrupted)) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .crcMismatch)
        }
    }

    func testFramePoliciesDoNotInventFlagsOrReassembly() throws {
        let frame = try request().transportFrame(messageNumber: 9, flags: 2, address: 0x31)
        XCTAssertEqual(frame.flags, 2)
        XCTAssertEqual(frame.address, 0x31)
        XCTAssertThrowsError(try request().transportFrame(messageNumber: 0, flags: 2))
        let sliced = try TransportFrame(messageNumber: 1, flags: 0,
                                        sliceMetadata: .init(opaqueBytes: Data([0])), wireBusinessID: 0x10,
                                        payload: Data([0x11, 0, 0]))
        XCTAssertThrowsError(try Codec.decodeResponse(from: sliced)) {
            XCTAssertEqual($0 as? Codec.CodecError, .opaqueSliceMetadata)
        }
    }

    func testDeterministicMalformedInnerDataDoesNotCrashOrLoseAcceptedBytes() throws {
        var state: UInt64 = 0x11223344
        for length in 0..<512 {
            var inner = Data()
            for _ in 0..<(length % 96) {
                state = state &* 6364136223846793005 &+ 1
                inner.append(UInt8(truncatingIfNeeded: state >> 32))
            }
            let payload = try TLV(tag: 0x11, value: inner).encoded()
            if let decoded = try? Codec.decodeResponse(wireBusinessID: 0x10, payload: payload) {
                let rebuilt = try packet(decoded.fields.map { TLV(tag: $0.tag, value: $0.value) })
                XCTAssertEqual(rebuilt, payload)
            }
        }
    }
}
