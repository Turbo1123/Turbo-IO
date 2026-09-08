import XCTest
@testable import RayNeoDisplay

final class WeatherJSONCodecTests: XCTestCase {
    let codec = WeatherJSONCodec()

    func update(location: String = "合成地点", temp: Int64 = 28,
                icon: Int64 = 9001, ts: String = "synthetic-ts-not-for-device") -> CurrentWeatherRawUpdate {
        CurrentWeatherRawUpdate(location: location, temperatureRaw: temp,
                                iconRaw: icon, timestampRaw: ts)
    }

    func decode(_ json: String, business: UInt16 = 15, type: UInt16 = 19) throws -> WeatherGlassesMessage {
        try codec.decodeGlassesResponse(businessRawValue: business, type: type, payload: Data(json.utf8))
    }

    func string(_ key: String, in json: JSONObject) throws -> String {
        guard case .string(let value) = json.fields[key] else {
            throw DisplayPayloadError.wrongType(key)
        }
        return value
    }

    func payload(_ message: DisplayJSONMessage) throws -> JSONObject {
        let envelope = try JSONObject(data: message.payload, limits: .conservative)
        XCTAssertEqual(Set(envelope.fields.keys), ["cmd", "payload"])
        XCTAssertEqual(try string("cmd", in: envelope), "current_weather_update")
        return try JSONObject(XCTUnwrap(envelope.fields["payload"]))
    }

    func testFixedEnvelopeAndDoubleEncodedThreeFieldData() throws {
        let message = try codec.encodeCurrentWeatherUpdate(update())
        XCTAssertEqual(WeatherJSONCodec.launcherBusinessRawValue, 15)
        XCTAssertEqual(message.type, 18)
        let outer = try payload(message)
        XCTAssertEqual(Set(outer.fields.keys), ["value", "mode", "data", "ts"])
        XCTAssertEqual(try outer.int("value"), 0)
        XCTAssertEqual(try outer.int("mode"), 0)
        XCTAssertEqual(try string("ts", in: outer), "synthetic-ts-not-for-device")
        let inner = try JSONObject(data: Data(string("data", in: outer).utf8), limits: .conservative)
        XCTAssertEqual(Set(inner.fields.keys), ["location", "icon", "temp"])
        XCTAssertEqual(try string("location", in: inner), "合成地点")
        XCTAssertEqual(try inner.int("temp"), 28)
        XCTAssertEqual(try inner.int("icon"), 9001) // Synthetic raw value, not a weather icon enum.
    }

    func testExactUtf8TextsAndEscapesSurviveBothJsonLayers() throws {
        for text in ["A中🙂B\r\n", " quote\" \\ slash/ ", "e\u{301}", "é", "  地点  "] {
            let outer = try payload(codec.encodeCurrentWeatherUpdate(update(location: text, ts: text)))
            let inner = try JSONObject(data: Data(string("data", in: outer).utf8), limits: .conservative)
            XCTAssertTrue(WireTextIdentity.matches(try string("location", in: inner), text))
            XCTAssertTrue(WireTextIdentity.matches(try string("ts", in: outer), text))
        }
    }

    func testIntegerExtremesArePreservedWithoutUnitsOrRounding() throws {
        for raw in [Int64.min, -273, -1, 0, 28, 9_007_199_254_740_993, Int64.max] {
            let outer = try payload(codec.encodeCurrentWeatherUpdate(update(temp: raw, icon: raw)))
            let inner = try JSONObject(data: Data(string("data", in: outer).utf8), limits: .conservative)
            XCTAssertEqual(try inner.int("temp"), raw)
            XCTAssertEqual(try inner.int("icon"), raw)
        }
    }

    func testRawTimestampHasNoAutomaticDateConversion() throws {
        for raw in ["1", "001", "-1", "9007199254740993", "synthetic time", " 42 ", "4\n2"] {
            let outer = try payload(codec.encodeCurrentWeatherUpdate(update(ts: raw)))
            XCTAssertTrue(WireTextIdentity.matches(try string("ts", in: outer), raw))
        }
    }

    func testNfcNfdEqualityUsesWireBytesForBothTextFields() throws {
        XCTAssertEqual("é", "e\u{301}")
        XCTAssertNotEqual(update(location: "é"), update(location: "e\u{301}"))
        XCTAssertNotEqual(update(ts: "é"), update(ts: "e\u{301}"))
        XCTAssertEqual(update(), update())
        XCTAssertNotEqual(try codec.encodeCurrentWeatherUpdate(update(ts: "é")),
                          try codec.encodeCurrentWeatherUpdate(update(ts: "e\u{301}")))
    }

    func testBlankTextRejectionIsExplicitLocalPolicy() throws {
        for blank in ["", " ", "\r\n", "\u{2003}"] {
            XCTAssertThrowsError(try codec.encodeCurrentWeatherUpdate(update(location: blank)))
            XCTAssertThrowsError(try codec.encodeCurrentWeatherUpdate(update(ts: blank)))
        }
    }

    func testOutboundStringLimitsAndEntireEnvelopeLimit() throws {
        let limits = try DisplayPayloadLimits(maxPayloadBytes: 1_024, maxStringBytes: 128)
        let limited = WeatherJSONCodec(limits: limits)
        for input in [update(location: String(repeating: "x", count: 129)),
                      update(ts: String(repeating: "x", count: 129))] {
            XCTAssertThrowsError(try limited.encodeCurrentWeatherUpdate(input))
        }
        // Individual location fits, but encoded inner JSON exceeds string budget.
        XCTAssertThrowsError(try limited.encodeCurrentWeatherUpdate(update(location: String(repeating: "x", count: 115))))
        let valid = try codec.encodeCurrentWeatherUpdate(update())
        let exact = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: valid.payload.count))
        XCTAssertEqual(try exact.encodeCurrentWeatherUpdate(update()), valid)
        let short = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: valid.payload.count - 1))
        XCTAssertThrowsError(try short.encodeCurrentWeatherUpdate(update()))
    }

    func testOutboundNestingAndCollectionLimitsApplyToEnvelope() throws {
        let shallow = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 1_024, maxNestingDepth: 2))
        XCTAssertThrowsError(try shallow.encodeCurrentWeatherUpdate(update()))
        let narrow = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 1_024, maxCollectionElements: 3))
        XCTAssertThrowsError(try narrow.encodeCurrentWeatherUpdate(update()))
    }

    func testResponseIsObservationAndUnknownResultsRemainRaw() throws {
        for value in [Int64.min, -1, 0, 1, 2, 3, 4, 99, Int64.max] {
            let json = "{\"cmd\":\"current_weather_update\",\"payload\":{\"value\":\(value)}}"
            guard case .responseObserved(let event) = try decode(json) else { return XCTFail("Expected observation") }
            XCTAssertEqual(event.command, .currentLocation)
            XCTAssertEqual(event.valueRaw, value)
            XCTAssertEqual(event.originalPayload, Data(json.utf8))
            // No request, displayed flag, success bool or mutable state exists.
        }
    }

    func testResponsePreservesUnknownFieldsWithoutReserializing() throws {
        let json = #"{ "cmd":"current_weather_update", "extra": {"future":true}, "payload":{"value":0,"ts":null,"data":{"future":[1,"x"]}} }"#
        guard case .responseObserved(let event) = try decode(json) else { return XCTFail("Expected observation") }
        XCTAssertEqual(event.originalPayload, Data(json.utf8))
        XCTAssertEqual(event.valueRaw, 0)
        // This is unknown response data, NOT permission to use an object as the
        // outgoing weather data String or to infer its timestamp semantics.
    }

    func testWrongBusinessOrDirectionCannotProduceWeatherObservation() throws {
        let json = #"{"cmd":"current_weather_update","payload":{"value":0}}"#
        for (business, type): (UInt16, UInt16) in [(14, 19), (21, 19), (15, 18), (15, 0), (0, 0)] {
            XCTAssertEqual(try decode(json, business: business, type: type),
                           .unknown(businessRawValue: business, type: type, payload: Data(json.utf8)))
        }
        let outbound = try codec.encodeCurrentWeatherUpdate(update())
        XCTAssertEqual(try codec.decodeGlassesResponse(businessRawValue: 15, type: outbound.type, payload: outbound.payload),
                       .unknown(businessRawValue: 15, type: 18, payload: outbound.payload))
    }

    func testConfigRequestsAndSimilarNamesRemainUnknown() throws {
        for command in ["dashboard_update", "dashboard_config", "current_weather_request",
                        "weather_request", "CURRENT_WEATHER_UPDATE", "current_weather_update ", "", "é", "e\u{301}"] {
            let data = try JSONSerialization.data(withJSONObject: ["cmd": command, "payload": ["value": 0]])
            XCTAssertEqual(try codec.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: data),
                           .unknown(businessRawValue: 15, type: 19, payload: data))
        }
    }

    func testSelectedCitiesIsDistinctObservationNotCurrentWeatherOrConfig() throws {
        for value in [Int64.min, -1, 0, 1, 4, 99, Int64.max] {
            let city = "{\"cmd\":\"weather_update\",\"payload\":{\"value\":\(value)}}"
            let current = "{\"cmd\":\"current_weather_update\",\"payload\":{\"value\":\(value)}}"
            let first = try decode(city)
            guard case .responseObserved(let event) = first else { return XCTFail("Expected city observation") }
            XCTAssertEqual(event.command, .selectedCities)
            XCTAssertEqual(event.command.rawValue, "weather_update")
            XCTAssertEqual(event.valueRaw, value)
            XCTAssertEqual(event.originalPayload, Data(city.utf8))
            XCTAssertNotEqual(first, try decode(current))
            XCTAssertEqual(try decode(city), first) // No transaction completion/dedup state.
        }
    }

    func testBothCommandsRejectMissingOrCoercedValueInsteadOfOfficialZeroFallback() throws {
        for command in WeatherUpdateCommand.allCases {
            for body in ["{}", "{\"value\":null}", "{\"value\":true}", "{\"value\":\"0\"}",
                         "{\"value\":0.0}", "{\"value\":0e0}", "{\"value\":9223372036854775808}"] {
                XCTAssertThrowsError(try decode("{\"cmd\":\"\(command.rawValue)\",\"payload\":\(body)}"))
            }
        }
    }

    func testResponseMissingNullAndWrongFieldsDoNotDefaultToZero() throws {
        for json in [#"{}"#, #"{"cmd":null}"#, #"{"cmd":18}"#,
                     #"{"cmd":"current_weather_update"}"#,
                     #"{"cmd":"current_weather_update","payload":null}"#,
                     #"{"cmd":"current_weather_update","payload":[]}"#,
                     #"{"cmd":"current_weather_update","payload":{}}"#,
                     #"{"cmd":"current_weather_update","payload":{"value":null}}"#] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testResponseIntegersRejectCoercionAndOverflow() throws {
        for value in ["true", "false", "\"0\"", "0.0", "0e0", "9223372036854775808", "-9223372036854775809", "[]", "{}"] {
            XCTAssertThrowsError(try decode("{\"cmd\":\"current_weather_update\",\"payload\":{\"value\":\(value)}}"))
        }
    }

    func testDuplicateKeysAndMalformedJsonAreRejected() throws {
        for json in [#"{"cmd":"current_weather_update","\u0063md":"weather_update","payload":{"value":0}}"#,
                     #"{"cmd":"current_weather_update","payload":{"value":0,"value":1}}"#,
                     #"{"cmd":"current_weather_update","payload":{"value":0},"future":{"a":1,"a":2}}"#,
                     #"{"cmd":"current_weather_update","payload":{"value":0}} trailing"#,
                     #"{"cmd":"\uD800","payload":{"value":0}}"#] {
            XCTAssertThrowsError(try decode(json))
        }
        XCTAssertThrowsError(try codec.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: Data([0xFF])))
    }

    func testInboundLimitsAlsoProtectUnknownRouteAndUnknownFields() throws {
        let small = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 64))
        for route: UInt16 in [0, 15] {
            XCTAssertThrowsError(try small.decodeGlassesResponse(businessRawValue: route, type: 19,
                                                               payload: Data(repeating: 0, count: 65)))
        }
        let shallow = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 1_024, maxNestingDepth: 3))
        XCTAssertThrowsError(try shallow.decodeGlassesResponse(businessRawValue: 15, type: 19,
            payload: Data(#"{"cmd":"current_weather_update","payload":{"value":0,"future":[[[]]]}}"#.utf8)))
        let narrow = WeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 1_024, maxCollectionElements: 2))
        XCTAssertThrowsError(try narrow.decodeGlassesResponse(businessRawValue: 15, type: 19,
            payload: Data(#"{"cmd":"other","future":[1,2,3]}"#.utf8)))
    }

    func testNonzeroDataStartIndexAndRepeatedObservationsHaveNoSideEffects() throws {
        let json = #"{"cmd":"current_weather_update","payload":{"value":0}}"#
        var sliced = Data([0xFF, 0xFF])
        sliced.append(Data(json.utf8))
        sliced.removeFirst(2)
        XCTAssertNotEqual(sliced.startIndex, 0)
        let first = try codec.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: sliced)
        let second = try codec.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: sliced)
        XCTAssertEqual(first, second) // An observation may repeat, never a completion/decision.
        guard case .responseObserved(let event) = first else { return XCTFail("Expected observation") }
        XCTAssertEqual(event.originalPayload, Data(json.utf8))
    }
}
