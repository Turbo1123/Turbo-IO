import XCTest
@testable import RayNeoProtocol

final class BusinessEnvelopeMetadataTests: XCTestCase {
    func testOptInAssistantAudio() throws {
        let packet = Data([16, 3, 34, 3, 1, 2, 3])
        XCTAssertEqual(try BusinessEnvelopeMetadata.assistantAudio(packet), Data([1,2,3]))
        XCTAssertEqual(try BusinessEnvelopeMetadata.assistantAudio((Data([99]) + packet).dropFirst()), Data([1,2,3]))
        XCTAssertNil(try BusinessEnvelopeMetadata.assistantAudio(Data([16,1,34,1,42])))
        XCTAssertNil(try BusinessEnvelopeMetadata.assistantAudio(Data([16,3,34,0])))
        XCTAssertNil(try BusinessEnvelopeMetadata.assistantAudio(Data([16,3])))
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.assistantAudio(Data([16,3,34,2,1])))
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.assistantAudio(Data([16,3,34,0,34,0])))
        XCTAssertNil(try BusinessEnvelopeMetadata.assistantAudio(Data([16,3,34,129,32]) + Data(repeating:0,count:4097)))
    }
    func testFixedSyntheticWake() throws {
        let result = try BusinessEnvelopeMetadata.inspect(Data([8, 1, 16, 1]))
        XCTAssertEqual(result.version, 1)
        XCTAssertEqual(result.messageType, 1)
        XCTAssertNil(result.messageBytes)
        XCTAssertNil(result.dataBytes)
    }
    func testOpaqueFieldsAreOnlyLengths() throws {
        // Synthetic content; intentionally not valid JSON or audio.
        let result = try BusinessEnvelopeMetadata.inspect(Data([8, 1, 16, 3, 26, 2, 255, 254, 34, 3, 1, 2, 3]))
        XCTAssertEqual(result.messageType, 3)
        XCTAssertEqual(result.messageBytes, 2)
        XCTAssertEqual(result.dataBytes, 3)
    }
    func testMultiByteTypeAndOutOfOrderFields() throws {
        let result = try BusinessEnvelopeMetadata.inspect(Data([34, 0, 16, 163, 1, 8, 1]))
        XCTAssertEqual(result.messageType, 163)
        XCTAssertEqual(result.dataBytes, 0)
    }
    func testDataSliceAndMissingAreNotInvented() throws {
        let packet = Data([99, 8, 1, 16, 32]).dropFirst()
        XCTAssertEqual(try BusinessEnvelopeMetadata.inspect(packet).messageType, 32)
        XCTAssertNil(try BusinessEnvelopeMetadata.inspect(Data()).messageType)
    }
    func testUnknownFieldsSkipAllSupportedWireTypes() throws {
        let packet = Data([40, 200, 1, 49] + Array(repeating: 0, count: 8)
            + [58, 2, 8, 99, 69, 0, 0, 0, 0, 16, 5])
        let result = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(result.messageType, 5)
        XCTAssertEqual(result.unknownFieldCount, 4)
    }
    func testMalformedAndDuplicateFieldsAreRejected() {
        for bytes: [UInt8] in [[16], [26, 3, 1], [8, 1, 8, 2], [18, 0], [0], [43],
                              [16, 255, 255, 255, 255, 16], Array(repeating: 255, count: 10)] {
            XCTAssertThrowsError(try BusinessEnvelopeMetadata.inspect(Data(bytes)))
        }
    }
    func testResourceLimits() {
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.inspect(Data(repeating: 0, count: 1_048_577)))
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.inspect(Data(Array(repeating: [UInt8(40), 0], count: 257).flatMap { $0 })))
    }
    func testEveryTruncationOfOpaquePayloadRejects() {
        let packet = Data([8, 1, 16, 3, 34, 8, 1, 2, 3, 4, 5, 6, 7, 8])
        for count in 5..<packet.count {
            XCTAssertThrowsError(try BusinessEnvelopeMetadata.inspect(packet.prefix(count)))
        }
    }
}
