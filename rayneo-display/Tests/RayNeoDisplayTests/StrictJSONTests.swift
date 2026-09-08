import XCTest
@testable import RayNeoDisplay

final class StrictJSONTests: XCTestCase {
    private func parse(_ text: String, limits: DisplayPayloadLimits = .conservative) throws -> StrictJSONValue {
        var parser = try StrictJSONParser(data: Data(text.utf8), limits: limits)
        return try parser.parse()
    }

    func testIntegerTokensDoNotBecomeBooleansOrDoubles() throws {
        for raw in ["0", "1", "-1", "-0", String(Int64.max), String(Int64.min), "9007199254740993"] {
            let object = try JSONObject(parse("{\"n\":\(raw)}"))
            XCTAssertEqual(try object.int("n"), Int64(raw))
        }
        for raw in ["1.0", "1e0", "1E+0", "0.5", "-4.9"] {
            let object = try JSONObject(parse("{\"n\":\(raw)}"))
            XCTAssertThrowsError(try object.int("n")) {
                XCTAssertEqual($0 as? DisplayPayloadError, .integerRequired("n"))
            }
        }
        for raw in ["true", "false", "null", "\"1\""] {
            let object = try JSONObject(parse("{\"n\":\(raw)}"))
            XCTAssertThrowsError(try object.int("n")) {
                XCTAssertEqual($0 as? DisplayPayloadError, .wrongType("n"))
            }
        }
    }

    func testInt64OverflowRejectedWithoutFloatingPointRoundoff() throws {
        for raw in ["9223372036854775808", "-9223372036854775809", String(repeating: "9", count: 256)] {
            let object = try JSONObject(parse("{\"n\":\(raw)}"))
            XCTAssertThrowsError(try object.int("n")) {
                XCTAssertEqual($0 as? DisplayPayloadError, .integerOutOfRange("n"))
            }
        }
    }

    func testDuplicateKeysIncludingEscapedSpellingRejected() {
        for text in [#"{"cmd":1,"cmd":2}"#, #"{"cmd":1,"\u0063md":2}"#] {
            XCTAssertThrowsError(try parse(text)) {
                XCTAssertEqual($0 as? DisplayPayloadError, .duplicateKey)
            }
        }
    }

    func testInvalidJSONGrammarRejected() {
        for text in ["", " ", "{}{}", "[1,]", #"{"a":1,}"#, #"{"a" 1}"#,
                     #"{"a":01}"#, #"{"a":+1}"#, #"{"a":1.}"#, #"{"a":1e}"#,
                     #"{"a":-}"#, #"{"a":.5}"#, #"{"a":NaN}"#, #"{"a":Infinity}"#,
                     #"{"a":tru}"#, #"{"a":nulll}"#, #"{"a":"\q"}"#,
                     #"{"a":"\uD800"}"#, #"{"a":"\uDC00"}"#,
                     "{\"a\":\"line\nfeed\"}", "{\"a\":\"unterminated}"] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    func testValidEscapesWhitespaceAndUnicode() throws {
        let value = try parse(" \n\t\r{\"a\":\"中\\\"\\\\\\/\\b\\f\\n\\r\\t\\uD83D\\uDE42\"} \n")
        let object = try JSONObject(value)
        guard case .string(let text) = object.fields["a"] else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("中\"\\/"))
        XCTAssertTrue(text.hasSuffix("🙂"))
    }

    func testInvalidUTF8Rejected() {
        XCTAssertThrowsError(try StrictJSONParser(data: Data([0x22, 0xFF, 0x22]), limits: .conservative))
    }

    func testOptionalPresenceDistinguishesMissingNullAndFalse() throws {
        let object = try JSONObject(parse(#"{"a":null,"b":false,"c":0}"#))
        XCTAssertEqual(try object.optionalBool("missing"), .missing)
        XCTAssertEqual(try object.optionalBool("a"), .null)
        XCTAssertEqual(try object.optionalBool("b"), .value(false))
        XCTAssertThrowsError(try object.optionalBool("c"))
        XCTAssertEqual(try object.optionalInt("c"), .value(0))
    }

    func testResourceLimits() throws {
        let byteLimits = try DisplayPayloadLimits(maxPayloadBytes: 2)
        XCTAssertNoThrow(try parse("{}", limits: byteLimits))
        XCTAssertThrowsError(try parse(" {}", limits: byteLimits)) {
            XCTAssertEqual($0 as? DisplayPayloadError, .payloadTooLarge)
        }
        let depthLimits = try DisplayPayloadLimits(maxPayloadBytes: 100, maxNestingDepth: 2)
        XCTAssertNoThrow(try parse("[0]", limits: depthLimits))
        XCTAssertThrowsError(try parse("[[0]]", limits: depthLimits)) {
            XCTAssertEqual($0 as? DisplayPayloadError, .excessiveNesting)
        }
        let countLimits = try DisplayPayloadLimits(maxPayloadBytes: 100, maxCollectionElements: 1)
        XCTAssertNoThrow(try parse("[0]", limits: countLimits))
        XCTAssertThrowsError(try parse("[0,1]", limits: countLimits))
        XCTAssertThrowsError(try parse(#"{"a":0,"b":1}"#, limits: countLimits))
        let stringLimits = try DisplayPayloadLimits(maxPayloadBytes: 100, maxStringBytes: 3)
        XCTAssertNoThrow(try parse(#""中""#, limits: stringLimits))
        XCTAssertThrowsError(try parse(#""🙂""#, limits: stringLimits))
    }

    func testInvalidLimitConfigurations() {
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: 0))
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: -1))
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: 10, maxNestingDepth: 0))
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: 10, maxNestingDepth: 129))
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: 10, maxCollectionElements: 0))
        XCTAssertThrowsError(try DisplayPayloadLimits(maxPayloadBytes: 10, maxStringBytes: 0))
    }

    func testOutboundEncodingKeepsLargeIntegersExactAndChecksLimits() throws {
        let data = try encodeJSON(["n": Int64.max], limits: .conservative)
        XCTAssertEqual(try JSONObject(data: data, limits: .conservative).int("n"), Int64.max)
        XCTAssertThrowsError(try encodeJSON(["n": 1], limits: DisplayPayloadLimits(maxPayloadBytes: 2)))
    }
}
