import XCTest
@testable import RayNeoDisplay

final class TodoJSONCodecTests: XCTestCase {
    let codec = TodoJSONCodec()
    func status(_ text: String) throws -> TodoStatusObserved {
        guard case .status(let status) = try codec.decodeGlassesMessage(type: 4, payload: Data(text.utf8)) else {
            throw DisplayPayloadError.invalidJSON
        }
        return status
    }
    func batch(_ text: String) throws -> TodoBatchObserved {
        guard case .batch(let batch) = try codec.decodeGlassesMessage(type: 10, payload: Data(text.utf8)) else {
            throw DisplayPayloadError.invalidJSON
        }
        return batch
    }

    func testStatusIDAndTimeStayExactInt64() throws {
        let event = try status(#"{"eventID":9007199254740993,"status":1,"lastModifiedTime":9223372036854775807}"#)
        XCTAssertEqual(event.eventID, 9_007_199_254_740_993)
        XCTAssertEqual(event.lastModifiedTime.rawValue, Int64.max)
        XCTAssertEqual(event.completionStatus, .complete)
        XCTAssertEqual(event.isImportant, .missing)
    }

    func testTodoStrictIntegerSchemaRejectsStringFloatBooleanAndMissingTime() {
        for text in [#"{"eventID":"4","status":1,"lastModifiedTime":0}"#,
                     #"{"eventID":4.0,"status":1,"lastModifiedTime":0}"#,
                     #"{"eventID":4,"status":true,"lastModifiedTime":0}"#,
                     #"{"eventID":4,"status":1,"lastModifiedTime":1e3}"#,
                     #"{"eventID":4,"status":1,"lastModifiedTime":null}"#,
                     #"{"eventID":4,"status":1}"#,
                     #"{"eventID":4,"status":1,"lastModifiedTime":0,"isImportant":0}"#] {
            XCTAssertThrowsError(try status(text))
        }
    }

    func testUnknownStatusAndNullableImportanceArePreserved() throws {
        let event = try status(#"{"eventID":4,"status":99,"isImportant":null,"lastModifiedTime":-1}"#)
        XCTAssertEqual(event.completionStatus, .unknown(99))
        XCTAssertEqual(event.isImportant, .null)
        XCTAssertEqual(event.lastModifiedTime.rawValue, -1)
    }

    func testBatchPresenceAndFilteredEntryOrder() throws {
        XCTAssertEqual(try batch("{}").eventList, .missing)
        XCTAssertEqual(try batch(#"{"eventList":null}"#).eventList, .null)
        XCTAssertEqual(try batch(#"{"eventList":[]}"#).eventList, .value([]))
        let result = try batch(#"{"scheduleTotal":null,"todoTotal":5,"eventList":[{"eventType":0,"eventID":1,"status":1},{"eventID":2,"status":1},{"eventType":1,"status":1},{"eventType":1,"eventID":3},{"eventType":1,"eventID":4,"status":1,"title":"synthetic","isImportant":true}]}"#)
        XCTAssertEqual(result.scheduleTotal, .null)
        XCTAssertEqual(result.todoTotal, .value(5))
        guard let events = result.eventList.value, events.count == 5 else { return XCTFail() }
        XCTAssertEqual(events[0], .ignored(.notTodo(eventType: 0)))
        XCTAssertEqual(events[1], .ignored(.notTodo(eventType: nil)))
        XCTAssertEqual(events[2], .ignored(.missingEventID))
        XCTAssertEqual(events[3], .ignored(.missingStatus))
        guard case .todo(let todo) = events[4] else { return XCTFail() }
        XCTAssertEqual(todo.eventID, 4)
        XCTAssertEqual(todo.lastModifiedTime, .missing)
        XCTAssertEqual(todo.effectiveLastModifiedTime.rawValue, 0)
        XCTAssertEqual(todo.isImportant, .value(true))
    }

    func testBatchOnlyDefaultsMissingTimeNotWrongTypedTime() throws {
        let absent = try batch(#"{"eventList":[{"eventType":1,"eventID":1,"status":1,"lastModifiedTime":null}]}"#)
        guard case .todo(let todo) = absent.eventList.value?.first else { return XCTFail() }
        XCTAssertEqual(todo.lastModifiedTime, .null)
        XCTAssertEqual(todo.effectiveLastModifiedTime.rawValue, 0)
        for text in [#"{"eventList":[{"eventType":1,"eventID":1,"status":1,"lastModifiedTime":"0"}]}"#,
                     #"{"eventList":[{"eventType":1,"eventID":true,"status":1}]}"#,
                     #"{"eventList":[{"eventType":"1","eventID":1,"status":1}]}"#,
                     #"{"eventList":[1]}"#,
                     #"{"eventList":{}}"#] {
            XCTAssertThrowsError(try batch(text))
        }
    }

    func testTodoTypeIndexMismatchIsNotDecodedAsAStatus() throws {
        let data = Data([0, 255])
        for type: UInt16 in [3, 12, 13, 14, 15, 16] {
            XCTAssertEqual(try codec.decodeGlassesMessage(type: type, payload: data),
                           .unknown(type: type, payload: data))
        }
    }

    func testUnknownTaskDoesNotCreateAndSameStateIsIdempotent() throws {
        let event = try status(#"{"eventID":4,"status":1,"lastModifiedTime":0}"#)
        XCTAssertEqual(TodoImmediateUpdatePlanner.plan(event, existing: nil), .unknownTask)
        XCTAssertEqual(TodoImmediateUpdatePlanner.plan(event,
            existing: .init(eventID: 5, completed: false, important: false)), .unknownTask)
        XCTAssertEqual(TodoImmediateUpdatePlanner.plan(event,
            existing: .init(eventID: 4, completed: true, important: true)), .noChange)
        guard case .update(let changes) = TodoImmediateUpdatePlanner.plan(event,
            existing: .init(eventID: 4, completed: false, important: true)) else { return XCTFail() }
        XCTAssertEqual(changes.completed, true)
        XCTAssertNil(changes.important)
        XCTAssertTrue(changes.shouldSuppressImmediateEcho)
    }

    func testUnknownStatusCannotCompleteButExplicitImportanceMayUpdate() throws {
        let event = try status(#"{"eventID":4,"status":99,"isImportant":false,"lastModifiedTime":1}"#)
        guard case .update(let changes) = TodoImmediateUpdatePlanner.plan(event,
            existing: .init(eventID: 4, completed: true, important: true)) else { return XCTFail() }
        XCTAssertNil(changes.completed)
        XCTAssertEqual(changes.important, false)
    }

    func testNullImportanceDoesNotClearAndZeroStatusCanReopen() throws {
        let event = try status(#"{"eventID":4,"status":0,"isImportant":null,"lastModifiedTime":1}"#)
        guard case .update(let changes) = TodoImmediateUpdatePlanner.plan(event,
            existing: .init(eventID: 4, completed: true, important: true)) else { return XCTFail() }
        XCTAssertEqual(changes.completed, false)
        XCTAssertNil(changes.important)
    }
}
