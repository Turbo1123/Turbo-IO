import XCTest
@testable import RayNeoDisplay

final class SuggestionJSONCodecTests: XCTestCase {
    let codec = SuggestionJSONCodec()
    func decode(_ text: String) throws -> SuggestionGlassesMessage {
        try codec.decodeGlassesOperation(type: 34, payload: Data(text.utf8))
    }

    func testOnlyKnownRawOneAndTwoAreRecognized() throws {
        for (raw, command) in [(1, SuggestionCommand.accept), (2, .reject)] {
            guard case .operation(let event) = try decode(
                "{\"suggestUID\":\"synthetic-request\",\"suggestType\":7,\"cmd\":\(raw)}"
            ) else { return XCTFail() }
            XCTAssertEqual(event.suggestUID, "synthetic-request")
            XCTAssertEqual(event.suggestType, 7)
            XCTAssertEqual(event.command, command)
        }
    }

    func testUnknownCommandsNeverFallBackToAccept() throws {
        for raw in [-1, 0, 3, 999] {
            let payload = Data("{\"suggestUID\":\"test\",\"suggestType\":7,\"cmd\":\(raw)}".utf8)
            XCTAssertThrowsError(try codec.decodeGlassesOperation(type: 34, payload: payload)) {
                XCTAssertEqual($0 as? DisplayPayloadError, .unknownCommand(Int64(raw)))
            }
            let retaining = SuggestionJSONCodec(unknownCommandPolicy: .retainUnknown)
            guard case .operation(let event) = try retaining.decodeGlassesOperation(type: 34, payload: payload)
            else { return XCTFail() }
            XCTAssertEqual(event.command, .unknown(Int64(raw)))
            XCTAssertNotEqual(event.command, .accept)
        }
    }

    func testAmbiguousCmdIdentifierAndFieldTypesRejected() {
        for text in [#"{"suggestUID":"test","suggestType":7,"cmd":true}"#,
                     #"{"suggestUID":"test","suggestType":7,"cmd":1.0}"#,
                     #"{"suggestUID":"test","suggestType":7,"cmd":"1"}"#,
                     #"{"suggestUID":"test","suggestType":7,"cmd":1,"cmd":2}"#,
                     #"{"suggestUID":"","suggestType":7,"cmd":1}"#,
                     #"{"suggestUID":" ","suggestType":7,"cmd":1}"#,
                     #"{"suggestUID":1,"suggestType":7,"cmd":1}"#,
                     #"{"suggestUID":"test","suggestType":"7","cmd":1}"#,
                     #"{"suggestUID":"test","suggestType":7,"cmd":1,"approved":true}"#] {
            XCTAssertThrowsError(try decode(text))
        }
    }

    func testNormalNotificationAndEnumIndexAreNotSuggestionOperations() throws {
        let payload = Data(#"{"notificationUID":"test","cmd":1}"#.utf8)
        for type: UInt16 in [4, 12, 13, 33, 35] {
            XCTAssertEqual(try codec.decodeGlassesOperation(type: type, payload: payload),
                           .unknown(type: type, payload: payload))
        }
    }

    func testAcknowledgementIsExplicitResultWithNoCmd() throws {
        for code in [SuggestionAcknowledgementCode.success, .permissionDenied, .lookupOrNetworkFailure, .otherFailure] {
            let message = try codec.encodeAppAcknowledgement(suggestUID: "test", suggestType: 7, code: code)
            XCTAssertEqual(message.type, 35)
            let json = try JSONObject(data: message.payload, limits: .conservative)
            XCTAssertEqual(try json.int("code"), code.rawValue)
            XCTAssertNil(json.fields["cmd"])
            XCTAssertEqual(Set(json.fields.keys), ["suggestUID", "suggestType", "code"])
        }
        XCTAssertThrowsError(try codec.encodeAppAcknowledgement(suggestUID: "", suggestType: 1, code: .success))
    }

    func testUnknownRawPayloadStillHasASizeLimit() throws {
        let small = SuggestionJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 2))
        XCTAssertThrowsError(try small.decodeGlassesOperation(type: 4, payload: Data([0, 1, 2])))
    }
}
