import XCTest
@testable import RayNeoCompanion

final class TodoDeliveryTests: XCTestCase {
    @MainActor private func fixture(_ body: (CompanionStore, UserDefaults) throws -> Void) throws {
        let name = "todo-delivery-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(CompanionStore(defaults: defaults), defaults)
    }
    @MainActor func testLegacyJSONLoadsWithoutInventingSubmission() throws {
        let original = LocalTodo(title: "旧格式")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "delivery")
        let decoded = try JSONDecoder().decode(LocalTodo.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.delivery)
        XCTAssertEqual(decoded.deliveryDescription, "仅保存在手机")
    }
    @MainActor func testOfflineEditsPersistAndCoalesceToLatestRevision() throws {
        try fixture { store, defaults in
            store.addTodo("第一版"); let id = store.todos[0].id
            _ = store.assignWireID(id, device: "A")
            store.editTodo(id, title: "第二版", dueAt: nil)
            let first = store.todos[0].delivery?.revision
            store.editTodo(id, title: "第三版", dueAt: nil)
            let reopened = CompanionStore(defaults: defaults)
            XCTAssertEqual(reopened.todos[0].title, "第三版")
            XCTAssertTrue(reopened.todos[0].delivery?.pending == true)
            XCTAssertNotEqual(first, reopened.todos[0].delivery?.revision)
            XCTAssertEqual(try reopened.todoCandidates(device: "A", pendingOnly: true).count, 1)
        }
    }
    @MainActor func testFailedOrInterruptedSubmissionStaysPendingOnReopen() throws {
        try fixture { store, defaults in
            store.addTodo("发送前保存")
            let row = try store.prepareTodoSubmission(store.todos[0].id, device: "A")
            let reopened = CompanionStore(defaults: defaults)
            XCTAssertEqual(reopened.todos[0].wireID, row.wireID)
            XCTAssertTrue(reopened.todos[0].delivery?.pending == true)
            XCTAssertNil(reopened.todos[0].delivery?.submittedAt)
        }
    }
    @MainActor func testSubmissionIsNotAcknowledgementAndStaleCompletionCannotClearNewEdit() throws {
        try fixture { store, _ in
            store.addTodo("版本一")
            let row = try store.prepareTodoSubmission(store.todos[0].id, device: "A")
            let revision = try XCTUnwrap(row.delivery?.revision)
            store.markTodoSubmitted(row.id, device: "A", revision: revision)
            XCTAssertEqual(store.todos[0].deliveryDescription, "已提交 · 未逐项确认")
            store.editTodo(row.id, title: "版本二", dueAt: nil)
            store.markTodoSubmitted(row.id, device: "A", revision: revision)
            XCTAssertTrue(store.todos[0].delivery?.pending == true)
        }
    }
    @MainActor func testOfflineConflictPersistsWithoutEchoOrOverwrite() throws {
        try fixture { store, defaults in
            store.addTodo("本机标题"); let id = store.todos[0].id
            let wire = store.assignWireID(id, device: "A")
            store.toggleTodo(id)
            XCTAssertFalse(store.applyGlassesTodo(device: "A", id: wire, status: 0, important: true))
            let reopened = CompanionStore(defaults: defaults)
            XCTAssertTrue(reopened.todos[0].completed)
            XCTAssertNotNil(reopened.todos[0].delivery?.conflict)
            XCTAssertNil(reopened.todos[0].delivery?.submittedAt)
            XCTAssertThrowsError(try reopened.todoCandidates(device: "A", pendingOnly: true))
            XCTAssertThrowsError(try reopened.prepareTodoSubmission(id, device: "A"))
        }
    }
    @MainActor func testMatchingStatusDoesNotAcknowledgePendingTitle() throws {
        try fixture { store, _ in
            store.addTodo("旧标题"); let id = store.todos[0].id
            let wire = store.assignWireID(id, device: "A")
            store.editTodo(id, title: "新标题", dueAt: nil)
            XCTAssertFalse(store.applyGlassesTodo(device: "A", id: wire, status: 0, important: false))
            XCTAssertTrue(store.todos[0].delivery?.pending == true)
            XCTAssertNil(store.todos[0].delivery?.conflict)
        }
    }
    @MainActor func testConflictResolutionPreservesTitleAndRequiresExplicitSend() throws {
        try fixture { store, _ in
            store.addTodo("保留标题"); let id = store.todos[0].id
            let wire = store.assignWireID(id, device: "A")
            store.toggleTodo(id)
            _ = store.applyGlassesTodo(device: "A", id: wire, status: 0, important: true)
            store.resolveTodoConflict(id, useGlassesStatus: false)
            XCTAssertTrue(store.todos[0].completed)
            XCTAssertNil(store.todos[0].delivery?.conflict)
            _ = store.applyGlassesTodo(device: "A", id: wire, status: 0, important: true)
            store.resolveTodoConflict(id, useGlassesStatus: true)
            XCTAssertFalse(store.todos[0].completed)
            XCTAssertEqual(store.todos[0].important, true)
            XCTAssertEqual(store.todos[0].title, "保留标题")
            XCTAssertTrue(store.todos[0].delivery?.pending == true)
            XCTAssertNil(store.todos[0].delivery?.submittedAt)
        }
    }
    @MainActor func testDifferentDeviceCannotReassignOrClearQueue() throws {
        try fixture { store, _ in
            store.addTodo("眼镜A"); let id = store.todos[0].id
            let wire = store.assignWireID(id, device: "A")
            store.toggleTodo(id)
            XCTAssertEqual(store.assignWireID(id, device: "B"), 0)
            XCTAssertEqual(store.todos[0].wireID, wire)
            XCTAssertThrowsError(try store.todoCandidates(device: "B", pendingOnly: false))
            XCTAssertThrowsError(try store.prepareTodoSubmission(id, device: "B"))
            store.markTodoSubmitted(id, device: "B", revision: try XCTUnwrap(store.todos[0].delivery?.revision))
            XCTAssertTrue(store.todos[0].delivery?.pending == true)
        }
    }
    @MainActor func testRetryExcludesNewAndArchivedTodos() throws {
        try fixture { store, _ in
            store.addTodo("新条目"); store.toggleTodo(store.todos[0].id)
            XCTAssertTrue(try store.todoCandidates(device: "A", pendingOnly: true).isEmpty)
            let id = store.todos[0].id
            _ = store.assignWireID(id, device: "A")
            store.archiveTodo(id, archived: true)
            XCTAssertTrue(try store.todoCandidates(device: "A", pendingOnly: true).isEmpty)
            XCTAssertThrowsError(try store.prepareTodoSubmission(id, device: "A"))
            store.archiveTodo(id, archived: false)
            XCTAssertEqual(try store.todoCandidates(device: "A", pendingOnly: true).count, 1)
        }
    }
    @MainActor func testLocalDueDateOnlyDoesNotCreateWireEdit() throws {
        try fixture { store, _ in
            store.addTodo("本机计划"); let id = store.todos[0].id
            _ = store.assignWireID(id, device: "A")
            store.editTodo(id, title: "本机计划", dueAt: Date())
            XCTAssertNil(store.todos[0].delivery)
        }
    }
    @MainActor func testUncontestedGlassesCompletionStillAppliesAfterSubmission() throws {
        try fixture { store, _ in
            store.addTodo("双向状态")
            let row = try store.prepareTodoSubmission(store.todos[0].id, device: "A")
            store.markTodoSubmitted(row.id, device: "A", revision: try XCTUnwrap(row.delivery?.revision))
            XCTAssertTrue(store.applyGlassesTodo(device: "A", id: try XCTUnwrap(row.wireID), status: 1, important: nil))
            XCTAssertTrue(store.todos[0].completed)
            XCTAssertEqual(store.todos[0].deliveryDescription, "已提交 · 未逐项确认")
        }
    }
}
