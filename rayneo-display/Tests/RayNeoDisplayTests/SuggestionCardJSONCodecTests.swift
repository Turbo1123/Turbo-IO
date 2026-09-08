import XCTest
@testable import RayNeoDisplay

final class SuggestionCardJSONCodecTests: XCTestCase {
    let codec = SuggestionCardJSONCodec()

    func card(_ category: SuggestionCardCategory = .todo, uid: String = "synthetic-card",
              title: String = "合成确认测试", source: String = "独立 App",
              content: String = "仅做本地编码，不执行操作", timeRange: String? = nil) -> SuggestionCardAppRequest {
        .add(suggestUID: uid, suggestType: category, title: title, source: source,
             content: content, timeRange: timeRange)
    }

    func json(_ request: SuggestionCardAppRequest) throws -> JSONObject {
        let result = try codec.encodeAppRequest(request)
        XCTAssertEqual(result.type, 33)
        return try JSONObject(data: result.payload, limits: .conservative)
    }

    func string(_ key: String, in json: JSONObject) throws -> String {
        guard case .string(let value) = json.fields[key] else {
            throw DisplayPayloadError.wrongType(key)
        }
        return value
    }

    func testRawCategoriesAreWireValuesNotDartIndices() throws {
        XCTAssertEqual(SuggestionCardCategory.allCases.map(\.rawValue), [1, 2])
        XCTAssertEqual(try SuggestionCardCategory(validatingRawValue: 1), .calendar)
        XCTAssertEqual(try SuggestionCardCategory(validatingRawValue: 2), .todo)
        for raw: Int64 in [-1, 0, 3, 99, Int64.min, Int64.max] {
            XCTAssertNil(SuggestionCardCategory(rawValue: raw))
            XCTAssertThrowsError(try SuggestionCardCategory(validatingRawValue: raw)) {
                XCTAssertEqual($0 as? SuggestionCardEncodingError, .unsupportedSuggestType(raw))
            }
        }
    }

    func testAddHasExactlySixFixedNonNullKeys() throws {
        for category in SuggestionCardCategory.allCases {
            let object = try json(card(category))
            XCTAssertEqual(Set(object.fields.keys), ["suggestUID", "suggestType", "type", "title", "source", "content"])
            XCTAssertEqual(try object.int("suggestType"), category.rawValue)
            XCTAssertEqual(try object.int("type"), 1)
            XCTAssertEqual(try object.identifier("suggestUID"), "synthetic-card")
            XCTAssertEqual(try string("title", in: object), "合成确认测试")
            XCTAssertEqual(try string("source", in: object), "独立 App")
            XCTAssertEqual(try string("content", in: object), "仅做本地编码，不执行操作")
        }
    }

    func testCalendarTimeRangeOmissionAndNoTrimming() throws {
        let nilMessage = try codec.encodeAppRequest(card(.calendar, timeRange: nil))
        let emptyMessage = try codec.encodeAppRequest(card(.calendar, timeRange: ""))
        XCTAssertEqual(nilMessage.payload, emptyMessage.payload)
        XCTAssertNil(try json(card(.calendar, timeRange: nil)).fields["timeRange"])
        XCTAssertNil(try json(card(.calendar, timeRange: "")).fields["timeRange"])
        for value in [" ", "\t", " 09:00–10:00 ", "明天\n上午"] {
            let object = try json(card(.calendar, timeRange: value))
            XCTAssertEqual(object.fields.count, 7)
            XCTAssertTrue(WireTextIdentity.matches(try string("timeRange", in: object), value))
        }
    }

    func testTodoNonemptyTimeRangeIsExplicitLocalRestriction() throws {
        XCTAssertNoThrow(try codec.encodeAppRequest(card(.todo, timeRange: nil)))
        XCTAssertNoThrow(try codec.encodeAppRequest(card(.todo, timeRange: "")))
        for value in [" ", "09:00", "tomorrow"] {
            XCTAssertThrowsError(try codec.encodeAppRequest(card(.todo, timeRange: value))) {
                XCTAssertEqual($0 as? SuggestionCardEncodingError, .unverifiedTimeRangeForTodo)
            }
        }
    }

    func testDeleteRetainsExactIdentityAndEmitsThreeEmptyStrings() throws {
        let uid = "synthetic-e\u{301}-🙂"
        for category in SuggestionCardCategory.allCases {
            let object = try json(.delete(suggestUID: uid, suggestType: category))
            XCTAssertEqual(Set(object.fields.keys), ["suggestUID", "suggestType", "type", "title", "source", "content"])
            XCTAssertTrue(WireTextIdentity.matches(try object.identifier("suggestUID"), uid))
            XCTAssertEqual(try object.int("suggestType"), category.rawValue)
            XCTAssertEqual(try object.int("type"), 2)
            for key in ["title", "source", "content"] { XCTAssertEqual(try string(key, in: object), "") }
            XCTAssertNil(object.fields["timeRange"])
        }
    }

    func testExplicitEmptyTextsStayStringsAndDoNotInventDefaults() throws {
        let object = try json(card(title: "", source: "", content: ""))
        XCTAssertEqual(object.fields.count, 6)
        for key in ["title", "source", "content"] { XCTAssertEqual(try string(key, in: object), "") }
        for key in ["buttons", "cmd", "action", "layout", "TTL", "url", "accountId", "signature"] {
            XCTAssertNil(object.fields[key])
        }
    }

    func testUidValidationIsNotSilentTrimming() throws {
        for uid in ["", " ", "\r\n", "\u{2003}"] {
            XCTAssertThrowsError(try codec.encodeAppRequest(card(uid: uid)))
            XCTAssertThrowsError(try codec.encodeAppRequest(.delete(suggestUID: uid, suggestType: .todo)))
        }
        let spaced = " synthetic-card "
        let object = try json(card(uid: spaced))
        XCTAssertTrue(WireTextIdentity.matches(try object.identifier("suggestUID"), spaced))
    }

    func testNfcNfdIdentityAndTextsNeverAliasInRequestEquality() throws {
        let composed = "é"
        let decomposed = "e\u{301}"
        XCTAssertEqual(composed, decomposed)
        let pairs: [(SuggestionCardAppRequest, SuggestionCardAppRequest)] = [
            (card(uid: composed), card(uid: decomposed)),
            (card(title: composed), card(title: decomposed)),
            (card(source: composed), card(source: decomposed)),
            (card(content: composed), card(content: decomposed)),
            (card(.calendar, timeRange: composed), card(.calendar, timeRange: decomposed)),
            (.delete(suggestUID: composed, suggestType: .todo), .delete(suggestUID: decomposed, suggestType: .todo))
        ]
        for (left, right) in pairs {
            XCTAssertNotEqual(left, right)
            XCTAssertNotEqual(try codec.encodeAppRequest(left).payload, try codec.encodeAppRequest(right).payload)
            XCTAssertEqual(left, left)
        }
        XCTAssertNotEqual(card(), .delete(suggestUID: "synthetic-card", suggestType: .todo))
        XCTAssertNotEqual(card(.todo), card(.calendar))
    }

    func testNilAndEmptyTimeRangeHaveDistinctInputButSameWireOmission() throws {
        let absent = card(.calendar, timeRange: nil)
        let empty = card(.calendar, timeRange: "")
        XCTAssertNotEqual(absent, empty)
        XCTAssertEqual(try codec.encodeAppRequest(absent), try codec.encodeAppRequest(empty))
    }

    func testStringAndPayloadResourceLimitsApplyToEveryTextField() throws {
        let limited = SuggestionCardJSONCodec(limits: try DisplayPayloadLimits(
            maxPayloadBytes: 512, maxStringBytes: 16
        ))
        let large = String(repeating: "x", count: 17)
        let requests: [SuggestionCardAppRequest] = [
            card(uid: large, title: "", source: "", content: ""),
            card(title: large, source: "", content: ""),
            card(title: "", source: large, content: ""),
            card(title: "", source: "", content: large),
            card(.calendar, title: "", source: "", content: "", timeRange: large),
            .delete(suggestUID: large, suggestType: .calendar)
        ]
        for request in requests { XCTAssertThrowsError(try limited.encodeAppRequest(request)) }
        let tiny = SuggestionCardJSONCodec(limits: try DisplayPayloadLimits(maxPayloadBytes: 16))
        XCTAssertThrowsError(try tiny.encodeAppRequest(card()))
    }

    func testKnownCardTypesDoNotEnableUnknownOperationCommands() throws {
        let cardMessage = try codec.encodeAppRequest(card())
        let operationCodec = SuggestionJSONCodec()
        XCTAssertEqual(try operationCodec.decodeGlassesOperation(type: 33, payload: cardMessage.payload),
                       .unknown(type: 33, payload: cardMessage.payload))
        XCTAssertThrowsError(try operationCodec.decodeGlassesOperation(type: 34,
            payload: Data(#"{"suggestUID":"synthetic-card","suggestType":2,"cmd":99}"#.utf8))) {
                XCTAssertEqual($0 as? DisplayPayloadError, .unknownCommand(99))
        }
    }
}
