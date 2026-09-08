import XCTest
@testable import RayNeoDisplay

final class WireTextIdentityTests: XCTestCase {
    let composed = "request-é"
    let decomposed = "request-e\u{301}"

    func testSwiftCanonicalEqualityIsNotWireIdentity() {
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(WireTextIdentity.matches(composed, decomposed))
        XCTAssertNotEqual(WireTextIdentity(composed), WireTextIdentity(decomposed))
        XCTAssertEqual(Set([WireTextIdentity(composed), WireTextIdentity(decomposed)]).count, 2)
        XCTAssertTrue(WireTextIdentity.matches(composed, composed))
    }

    func testPositionTrackerCannotBindCanonicallyEquivalentDid() throws {
        let codec = TeleprompterJSONCodec()
        let payload = try codec.encodeAppRequest(.progress(
            did: decomposed, pageOffset: 0, highLightOffset: 0, autoSync: false
        ))
        guard case .progress(let observed) = try codec.decodeGlassesRequest(type: 8, payload: payload.payload)
        else { return XCTFail() }
        var tracker = try TeleprompterProgressTracker(did: composed, connectionGeneration: 1)
        XCTAssertEqual(tracker.observe(observed, connectionGeneration: 1), .differentDocument)
        XCTAssertNil(tracker.position)
    }

    func testAllTeleprompterDirectionModelsUseByteIdentity() throws {
        let codec = TeleprompterJSONCodec()
        let pairs: [(TeleprompterAppRequest, TeleprompterAppRequest)] = [
            (.pause(did: composed, offset: 0, code: 1, isCompleted: false),
             .pause(did: decomposed, offset: 0, code: 1, isCompleted: false)),
            (.resume(did: composed), .resume(did: decomposed)),
            (.stop(did: composed), .stop(did: decomposed)),
            (.progress(did: composed, pageOffset: 0, highLightOffset: 0, autoSync: nil),
             .progress(did: decomposed, pageOffset: 0, highLightOffset: 0, autoSync: nil))
        ]
        for (left, right) in pairs {
            XCTAssertNotEqual(left, right)
            let first = try codec.encodeAppRequest(left)
            let second = try codec.encodeAppRequest(right)
            XCTAssertNotEqual(try codec.decodeGlassesRequest(type: first.type, payload: first.payload),
                              try codec.decodeGlassesRequest(type: second.type, payload: second.payload))
        }
        let firstResponse = try codec.encodeAppResponse(type: .progress, did: composed, code: .accepted)
        let secondResponse = try codec.encodeAppResponse(type: .progress, did: decomposed, code: .accepted)
        XCTAssertNotEqual(try codec.decodeGlassesResponse(type: .progress, payload: firstResponse.payload),
                          try codec.decodeGlassesResponse(type: .progress, payload: secondResponse.payload))
    }

    func testSuggestionOperationEqualityCannotAliasCanonicalUIDs() throws {
        let codec = SuggestionJSONCodec()
        let first = try JSONSerialization.data(withJSONObject: ["suggestUID": composed, "suggestType": 1, "cmd": 1])
        let second = try JSONSerialization.data(withJSONObject: ["suggestUID": decomposed, "suggestType": 1, "cmd": 1])
        XCTAssertNotEqual(try codec.decodeGlassesOperation(type: 34, payload: first),
                          try codec.decodeGlassesOperation(type: 34, payload: second))
    }
}
