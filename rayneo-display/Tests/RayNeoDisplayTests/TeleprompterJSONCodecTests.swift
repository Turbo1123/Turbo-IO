import XCTest
@testable import RayNeoDisplay

final class TeleprompterJSONCodecTests: XCTestCase {
    let codec = TeleprompterJSONCodec()
    func decode(_ type: UInt16, _ text: String) throws -> TeleprompterGlassesRequest {
        try codec.decodeGlassesRequest(type: type, payload: Data(text.utf8))
    }

    func testProgressIsFlatAndHasExactKeyCase() throws {
        guard case .progress(let event) = try decode(8,
            #"{"action":1,"did":"test-did","pageOffset":4,"highLightOffset":8,"autoSync":false}"#
        ) else { return XCTFail() }
        XCTAssertEqual(event.did, "test-did")
        XCTAssertEqual(event.pageOffset, 4)
        XCTAssertEqual(event.highLightOffset, 8)
        XCTAssertEqual(event.autoSync, .value(false))
        XCTAssertThrowsError(try decode(8,
            #"{"action":1,"did":"d","position":{"pageOffset":4,"highLightOffset":8}}"#))
        XCTAssertThrowsError(try decode(8,
            #"{"action":1,"did":"d","pageOffset":4,"highlightOffset":8}"#))
    }

    func testProgressRequiredOffsetsAndOptionalBoolean() throws {
        for text in [#"{"action":1,"did":"d","pageOffset":0}"#,
                     #"{"action":1,"did":"d","pageOffset":null,"highLightOffset":0}"#,
                     #"{"action":1,"did":"d","pageOffset":true,"highLightOffset":0}"#,
                     #"{"action":1,"did":"d","pageOffset":0.5,"highLightOffset":0}"#,
                     #"{"action":1,"did":"d","pageOffset":0,"highLightOffset":0,"autoSync":0}"#] {
            XCTAssertThrowsError(try decode(8, text))
        }
        guard case .progress(let absent) = try decode(8,
            #"{"action":1,"did":"d","pageOffset":0,"highLightOffset":0}"#),
              case .progress(let null) = try decode(8,
            #"{"action":1,"did":"d","pageOffset":0,"highLightOffset":0,"autoSync":null}"#)
        else { return XCTFail() }
        XCTAssertEqual(absent.autoSync, .missing)
        XCTAssertEqual(null.autoSync, .null)
    }

    func testPauseDefaultsDoNotErasePresenceOrTiming() throws {
        guard case .pause(let absent) = try decode(4, #"{"action":1,"did":"d"}"#),
              case .pause(let nulls) = try decode(4,
            #"{"action":1,"did":"d","offset":null,"code":null,"isCompleted":null,"elapsedSeconds":null}"#),
              case .pause(let finished) = try decode(4,
            #"{"action":1,"did":"d","offset":7,"code":1,"isCompleted":true,"elapsedSeconds":31}"#)
        else { return XCTFail() }
        XCTAssertEqual(absent.offset, .missing)
        XCTAssertEqual(absent.effectiveOffset, 0)
        XCTAssertEqual(absent.effectiveCode, 1)
        XCTAssertFalse(absent.effectiveIsCompleted)
        XCTAssertEqual(absent.elapsedSeconds, .missing)
        XCTAssertEqual(nulls.offset, .null)
        XCTAssertEqual(nulls.elapsedSeconds, .null)
        XCTAssertEqual(nulls.effectiveCode, 1)
        XCTAssertEqual(finished.elapsedSeconds, .value(31))
        XCTAssertTrue(finished.effectiveIsCompleted)
    }

    func testResumeInboundTimingAndOutboundAsymmetry() throws {
        guard case .resume(let incoming) = try decode(5,
            #"{"action":1,"did":"d","code":1,"elapsedSeconds":32}"#) else { return XCTFail() }
        XCTAssertEqual(incoming.elapsedSeconds, .value(32))
        let outgoing = try codec.encodeAppRequest(.resume(did: "d"))
        XCTAssertEqual(outgoing.type, 5)
        let json = try JSONObject(data: outgoing.payload, limits: .conservative)
        XCTAssertEqual(Set(json.fields.keys), ["action", "did"])
        XCTAssertEqual(try json.int("action"), 1)
    }

    func testStopOnlyUsesActionAndDid() throws {
        XCTAssertEqual(try decode(6, #"{"action":1,"did":"d"}"#), .stop(did: "d"))
        let outgoing = try codec.encodeAppRequest(.stop(did: "d"))
        XCTAssertEqual(outgoing.type, 6)
        XCTAssertEqual(Set(try JSONObject(data: outgoing.payload, limits: .conservative).fields.keys),
                       ["action", "did"])
        XCTAssertThrowsError(try decode(6, #"{"action":1,"did":"d","offset":0}"#))
    }

    func testRequestAndResponseActionsCannotBeConfused() throws {
        XCTAssertThrowsError(try decode(4, #"{"action":2,"did":"d","code":1}"#)) {
            XCTAssertEqual($0 as? DisplayPayloadError, .wrongAction)
        }
        XCTAssertThrowsError(try codec.decodeGlassesResponse(type: .pause,
            payload: Data(#"{"action":1,"did":"d","code":1}"#.utf8)))
        let response = try codec.decodeGlassesResponse(type: .progress,
            payload: Data(#"{"action":2,"did":"old-did","code":99}"#.utf8))
        XCTAssertEqual(response.code, 99)
        XCTAssertEqual(response.did, "old-did")
    }

    func testUnknownTypesRemainRawAndDoNotParseAudioAsJSON() throws {
        let data = Data([0, 255, 0, 128])
        for type: UInt16 in [0, 1, 2, 3, 7, 9, 10, 11, 255] {
            XCTAssertEqual(try codec.decodeGlassesRequest(type: type, payload: data),
                           .unknown(type: type, payload: data))
        }
        let small = TeleprompterJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 3))
        XCTAssertThrowsError(try small.decodeGlassesRequest(type: 9, payload: data))
    }

    func testAppPauseAndProgressEncodingAreKnownSubset() throws {
        let pause = try codec.encodeAppRequest(.pause(did: "d", offset: 0, code: 1, isCompleted: false))
        XCTAssertEqual(pause.type, 4)
        XCTAssertEqual(Set(try JSONObject(data: pause.payload, limits: .conservative).fields.keys),
                       ["action", "did", "offset", "code", "isCompleted"])
        let progress = try codec.encodeAppRequest(.progress(
            did: "d", pageOffset: 4, highLightOffset: 8, autoSync: nil
        ))
        XCTAssertEqual(progress.type, 8)
        let json = try JSONObject(data: progress.payload, limits: .conservative)
        XCTAssertEqual(try json.int("highLightOffset"), 8)
        XCTAssertEqual(try json.optionalBool("autoSync"), .null)
        XCTAssertNil(json.fields["position"])
        XCTAssertNil(json.fields["highlightOffset"])
    }

    func testResponseEncodingDoesNotApplyOrInventASuccess() throws {
        let response = try codec.encodeAppResponse(type: .progress, did: "d", code: .accepted)
        XCTAssertEqual(response.type, 8)
        let json = try JSONObject(data: response.payload, limits: .conservative)
        XCTAssertEqual(try json.int("action"), 2)
        XCTAssertEqual(try json.int("code"), 1)
        XCTAssertEqual(Set(json.fields.keys), ["action", "did", "code"])
    }

    func testIdentifierAndKnownSchemaAreStrict() {
        for text in [#"{"action":1,"did":""}"#, #"{"action":1,"did":"  "}"#,
                     #"{"action":1,"did":12}"#, #"{"action":1,"did":null}"#,
                     #"{"action":1,"did":"d","newFlag":true}"#] {
            XCTAssertThrowsError(try decode(6, text))
        }
        XCTAssertThrowsError(try codec.encodeAppRequest(.resume(did: "\n")))
        XCTAssertThrowsError(try codec.encodeAppResponse(type: .pause, did: "", code: .accepted))
    }

    func testProgressTrackerRejectsStaleConnectionsWrongDidAndDuplicates() throws {
        func position(_ did: String, _ page: Int, _ highlight: Int, _ auto: String = "false") throws -> TeleprompterPositionObserved {
            guard case .progress(let position) = try decode(8,
                "{\"action\":1,\"did\":\"\(did)\",\"pageOffset\":\(page),\"highLightOffset\":\(highlight),\"autoSync\":\(auto)}"
            ) else { throw DisplayPayloadError.invalidJSON }
            return position
        }
        var tracker = try TeleprompterProgressTracker(did: "active", connectionGeneration: 9)
        XCTAssertEqual(tracker.observe(try position("active", 0, 0), connectionGeneration: 8), .staleConnection)
        XCTAssertEqual(tracker.observe(try position("old", 0, 0), connectionGeneration: 9), .differentDocument)
        XCTAssertNil(tracker.position)
        XCTAssertEqual(tracker.observe(try position("active", 4, 8), connectionGeneration: 9), .updated(localSequence: 1))
        XCTAssertEqual(tracker.observe(try position("active", 4, 8, "true"), connectionGeneration: 9), .duplicate)
        XCTAssertEqual(tracker.localSequence, 1)
        XCTAssertEqual(tracker.observe(try position("active", 4, 9), connectionGeneration: 9), .updated(localSequence: 2))
        XCTAssertEqual(tracker.position?.highLightOffset, 9)
    }
}
