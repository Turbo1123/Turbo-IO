import XCTest
@testable import RayNeoDisplay

final class CityWeatherJSONCodecTests: XCTestCase {
    let codec = CityWeatherJSONCodec()

    func item(location: String = "合成城市", id: String = "synthetic-city-id",
              temp: Int64 = 28, icon: Int64 = 9001, des: String = "合成描述",
              range: String = "caller raw range", hourly: [CityWeatherHourlyRawEntry] = []) -> CityWeatherRawItem {
        CityWeatherRawItem(location: location, locationID: id, temperatureRaw: temp,
                           iconRaw: icon, descriptionRaw: des, temperatureRangeRaw: range, hourly: hourly)
    }

    func entry(_ label: String = "1pm", temp: Int64 = 29, icon: Int64 = 9002) -> CityWeatherHourlyRawEntry {
        CityWeatherHourlyRawEntry(label: label, temperatureRaw: temp, iconRaw: icon)
    }

    func update(_ items: [CityWeatherRawItem]? = nil, ts: String = "synthetic-ts-not-for-device") -> SelectedCityWeatherRawUpdate {
        SelectedCityWeatherRawUpdate(items: items ?? [item()], timestampRaw: ts)
    }

    func string(_ key: String, _ value: JSONObject) throws -> String {
        guard case .string(let text) = value.fields[key] else { throw DisplayPayloadError.wrongType(key) }
        return text
    }

    func payload(_ message: DisplayJSONMessage) throws -> JSONObject {
        XCTAssertEqual(message.type, 18)
        let outer = try JSONObject(data: message.payload, limits: .conservative)
        XCTAssertEqual(Set(outer.fields.keys), ["cmd", "payload"])
        XCTAssertEqual(try string("cmd", outer), "weather_update")
        return try JSONObject(XCTUnwrap(outer.fields["payload"]))
    }

    func decodedItems(_ message: DisplayJSONMessage) throws -> [JSONObject] {
        let body = try payload(message)
        XCTAssertEqual(Set(body.fields.keys), ["value", "mode", "data", "ts"])
        XCTAssertEqual(try body.int("value"), 0)
        XCTAssertEqual(try body.int("mode"), 0)
        var parser = try StrictJSONParser(data: Data(string("data", body).utf8), limits: .conservative)
        guard case .array(let array) = try parser.parse() else { throw DisplayPayloadError.invalidJSON }
        return try array.map { try JSONObject($0) }
    }

    func testSevenFieldArrayAndHourlyLabelToTemperatureIconPair() throws {
        let message = try codec.encodeUpdate(update([item(hourly: [entry("1pm"), entry("2pm", temp: -3, icon: 9100)])]))
        let cities = try decodedItems(message)
        XCTAssertEqual(cities.count, 1)
        let city = try XCTUnwrap(cities.first)
        XCTAssertEqual(Set(city.fields.keys), ["location", "location_id", "temp", "icon", "des", "temp_range", "hourly"])
        XCTAssertEqual(try string("location", city), "合成城市")
        XCTAssertEqual(try string("location_id", city), "synthetic-city-id")
        XCTAssertEqual(try string("des", city), "合成描述")
        XCTAssertEqual(try string("temp_range", city), "caller raw range")
        XCTAssertEqual(try city.int("temp"), 28)
        XCTAssertEqual(try city.int("icon"), 9001) // Synthetic, not an identified weather icon.
        let hourly = try JSONObject(XCTUnwrap(city.fields["hourly"]))
        XCTAssertEqual(Set(hourly.fields.keys), ["1pm", "2pm"])
        for (label, expected): (String, [Int64]) in [("1pm", [29, 9002]), ("2pm", [-3, 9100])] {
            guard case .array(let pair) = hourly.fields[label] else { return XCTFail("Expected hourly array pair") }
            XCTAssertEqual(pair.count, 2)
            XCTAssertEqual(try pair.map { try JSONObject.integer($0, key: label) }, expected)
        }
    }

    func testEmptyDescriptionRangeAndHourlyObjectAreExplicitNotMissingOrNull() throws {
        let city = try XCTUnwrap(decodedItems(codec.encodeUpdate(update([item(des: "", range: "")]))).first)
        XCTAssertEqual(try string("des", city), "")
        XCTAssertEqual(try string("temp_range", city), "")
        XCTAssertTrue(try JSONObject(XCTUnwrap(city.fields["hourly"])).fields.isEmpty)
    }

    func testListOrderPreservedWithoutSelectingOrMergingCities() throws {
        let cities = try decodedItems(codec.encodeUpdate(update([item(id: "B"), item(id: "A")])) )
        XCTAssertEqual(try cities.map { try string("location_id", $0) }, ["B", "A"])
    }

    func testAllTextFieldsKeepExactUtf8ThroughTwoJsonLayers() throws {
        for text in ["A中🙂B\r\n", "é", "e\u{301}", " quote\" \\ slash/ ", "\u{0000}x", "  caller value  "] {
            let body = try codec.encodeUpdate(update([item(location: text, id: text, des: text, range: text, hourly: [entry(text)])], ts: text))
            let city = try XCTUnwrap(decodedItems(body).first)
            for key in ["location", "location_id", "des", "temp_range"] {
                XCTAssertTrue(WireTextIdentity.matches(try string(key, city), text))
            }
            let hourly = try JSONObject(XCTUnwrap(city.fields["hourly"]))
            XCTAssertTrue(WireTextIdentity.matches(try XCTUnwrap(hourly.fields.keys.first), text))
            XCTAssertTrue(WireTextIdentity.matches(try string("ts", payload(body)), text))
        }
    }

    func testRawInt64ExtremesAreExactNotWeatherValidityClaims() throws {
        for raw in [Int64.min, -100, 0, 28, 9_007_199_254_740_993, Int64.max] {
            let city = try XCTUnwrap(decodedItems(codec.encodeUpdate(update([item(temp: raw, icon: raw, hourly: [entry(temp: raw, icon: raw)])]))).first)
            XCTAssertEqual(try city.int("temp"), raw)
            XCTAssertEqual(try city.int("icon"), raw)
            let hourly = try JSONObject(XCTUnwrap(city.fields["hourly"]))
            guard case .array(let pair) = hourly.fields["1pm"] else { return XCTFail("Expected pair") }
            XCTAssertEqual(try pair.map { try JSONObject.integer($0, key: "hourly") }, [raw, raw])
        }
    }

    func testNoAutomaticDateLabelRangeOrTimestampFormatting() throws {
        let body = try codec.encodeUpdate(update([item(range: "raw A / raw B", hourly: [entry("explicit label, not a Date")])], ts: "0001"))
        let city = try XCTUnwrap(decodedItems(body).first)
        XCTAssertEqual(try string("temp_range", city), "raw A / raw B")
        XCTAssertEqual(try string("ts", payload(body)), "0001")
        XCTAssertEqual(Set(try JSONObject(XCTUnwrap(city.fields["hourly"])).fields.keys), ["explicit label, not a Date"])
        XCTAssertNil(city.fields["timezone"])
        XCTAssertNil(city.fields["unit"])
        XCTAssertNil(city.fields["date"])
    }

    func testNfcNfdModelEqualityIsByteIdentityAcrossEveryString() throws {
        let nfc = "é", nfd = "e\u{301}"
        XCTAssertEqual(nfc, nfd)
        XCTAssertNotEqual(entry(nfc), entry(nfd))
        XCTAssertNotEqual(item(location: nfc), item(location: nfd))
        XCTAssertNotEqual(item(id: nfc), item(id: nfd))
        XCTAssertNotEqual(item(des: nfc), item(des: nfd))
        XCTAssertNotEqual(item(range: nfc), item(range: nfd))
        XCTAssertNotEqual(item(hourly: [entry(nfc)]), item(hourly: [entry(nfd)]))
        XCTAssertNotEqual(update(ts: nfc), update(ts: nfd))
        XCTAssertEqual(update(), update())
    }

    func testCityIdsNfcNfdAreDistinctValuesAndBothSurvive() throws {
        let cities = try decodedItems(codec.encodeUpdate(update([item(id: "é"), item(id: "e\u{301}")])))
        XCTAssertEqual(cities.count, 2)
        XCTAssertFalse(WireTextIdentity.matches(try string("location_id", cities[0]), try string("location_id", cities[1])))
    }

    func testDuplicateByteCityIdRejectsWholeUpdateWithoutMerging() throws {
        XCTAssertThrowsError(try codec.encodeUpdate(update([item(id: "same"), item(location: "different", id: "same")]))) {
            XCTAssertEqual($0 as? CityWeatherEncodingError, .duplicateCityIdentifier)
        }
    }

    func testDuplicateHourlyLabelsAndCanonicalCollisionsRejectInsteadOfOverwrite() throws {
        for labels in [["1pm", "1pm"], ["é", "e\u{301}"], ["e\u{301}", "é"]] {
            XCTAssertThrowsError(try codec.encodeUpdate(update([item(hourly: labels.map { entry($0) })]))) {
                XCTAssertEqual($0 as? CityWeatherEncodingError, .duplicateHourlyLabel)
            }
        }
    }

    func testSameHourlyLabelsInDifferentCitiesAreIndependent() throws {
        let cities = try decodedItems(codec.encodeUpdate(update([item(id: "A", hourly: [entry()]), item(id: "B", hourly: [entry()])])) )
        XCTAssertEqual(cities.count, 2)
    }

    func testEmptyCityListRejectedWithoutAssumingClearSemantics() throws {
        XCTAssertThrowsError(try codec.encodeUpdate(update([]))) {
            XCTAssertEqual($0 as? CityWeatherEncodingError, .emptyCityList)
        }
    }

    func testBlankRequiredTextsAreLocalStrictPolicyAndNeverTrimmedToOtherValues() throws {
        for blank in ["", " ", "\r\n", "\u{2003}"] {
            for input in [update([item(location: blank)]), update([item(id: blank)]),
                          update([item(hourly: [entry(blank)])]), update(ts: blank)] {
                XCTAssertThrowsError(try codec.encodeUpdate(input))
            }
        }
    }

    func testCollectionsAndNestingBoundedBeforeBuildingNestedGraph() throws {
        let narrow = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxCollectionElements: 7))
        XCTAssertThrowsError(try narrow.encodeUpdate(update((0..<8).map { item(id: "id\($0)") })))
        XCTAssertThrowsError(try narrow.encodeUpdate(update([item(hourly: (0..<8).map { entry("hour\($0)") })])))
        let fewerKeys = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxCollectionElements: 6))
        XCTAssertThrowsError(try fewerKeys.encodeUpdate(update()))
        let shallow = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxNestingDepth: 4))
        XCTAssertThrowsError(try shallow.encodeUpdate(update([item(hourly: [entry()])])))
        XCTAssertNoThrow(try shallow.encodeUpdate(update()))
        let exactDepth = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxNestingDepth: 5))
        XCTAssertNoThrow(try exactDepth.encodeUpdate(update([item(hourly: [entry()])])) )
    }

    func testIndividualAndAggregateStringBudgetBeforeSerialization() throws {
        let limited = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxStringBytes: 512))
        let huge = String(repeating: "x", count: 513)
        for input in [update([item(location: huge)]), update([item(id: huge)]), update([item(des: huge)]),
                      update([item(range: huge)]), update([item(hourly: [entry(huge)])]), update(ts: huge)] {
            XCTAssertThrowsError(try limited.encodeUpdate(input))
        }
        // Every string is individually short; their known-schema aggregate is not.
        XCTAssertThrowsError(try limited.encodeUpdate(update((0..<7).map { item(id: "id\($0)") })))
    }

    func testEscapingExpansionCannotBypassFinalStringLimit() throws {
        let limited = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 4096, maxStringBytes: 512))
        // Unescaped aggregate <512; control bytes expand in inner and outer JSON.
        XCTAssertThrowsError(try limited.encodeUpdate(update([item(des: String(repeating: "\u{0001}", count: 100))])))
        XCTAssertNoThrow(try limited.encodeUpdate(update([item(des: String(repeating: "x", count: 100))])))
    }

    func testEntireEnvelopeExactByteLimitAndSmallBoundaries() throws {
        let input = update([item(hourly: [entry()])])
        let expected = try codec.encodeUpdate(input)
        let exact = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: expected.payload.count))
        XCTAssertEqual(try exact.encodeUpdate(input), expected)
        let short = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: expected.payload.count - 1))
        XCTAssertThrowsError(try short.encodeUpdate(input))
        for size in [1, 2, 16, 64] {
            let tiny = CityWeatherJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: size))
            XCTAssertThrowsError(try tiny.encodeUpdate(input))
        }
    }

    func testEncodingAndRepeatedCityResponseDoNotEstablishRequestOrLensSuccess() throws {
        let encoded = try codec.encodeUpdate(update())
        let responses = WeatherJSONCodec()
        XCTAssertEqual(try responses.decodeGlassesResponse(businessRawValue: 15, type: encoded.type, payload: encoded.payload),
                       .unknown(businessRawValue: 15, type: 18, payload: encoded.payload))
        let data = Data(#"{"cmd":"weather_update","payload":{"value":0}}"#.utf8)
        let first = try responses.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: data)
        XCTAssertEqual(first, try responses.decodeGlassesResponse(businessRawValue: 15, type: 19, payload: data))
        guard case .responseObserved(let observation) = first else { return XCTFail("Expected observation only") }
        XCTAssertEqual(observation.command, .selectedCities)
        XCTAssertEqual(observation.originalPayload, data)
        // No request association, displayed flag, transport or state transitions.
    }
}
