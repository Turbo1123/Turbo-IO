import XCTest
@testable import RayNeoCompanion

@MainActor private final class TestReminderReader: SystemReminderReading {
    var canRead = false
    var grant = true
    var requestCount = 0, listCount = 0, readCount = 0, cancellations = 0
    var values: [SystemReminderSnapshot] = []
    var deferred = false
    var requests: [CheckedContinuation<[SystemReminderSnapshot], Error>] = []
    func requestAccess() async throws {
        requestCount += 1
        guard grant else { throw SystemReminderError.denied }
        canRead = true
    }
    func lists() throws -> [SystemReminderList] {
        listCount += 1
        return [SystemReminderList(id: "list-a", title: "Synthetic list")]
    }
    func reminders(in listID: String) async throws -> [SystemReminderSnapshot] {
        readCount += 1
        if deferred { return try await withCheckedThrowingContinuation { requests.append($0) } }
        return values
    }
    func cancel() { cancellations += 1 }
}

final class SystemReminderTests: XCTestCase {
    private func row(_ id: String = "synthetic-id", title: String = "系统测试待办", completed: Bool = false,
                     due: DateComponents? = nil) -> SystemReminderSnapshot {
        SystemReminderSnapshot(id: id, title: title, completed: completed, dueComponents: due)
    }
    @MainActor private func fixture(_ body: (CompanionStore, UserDefaults) throws -> Void) throws {
        let name = "system-reminder-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(CompanionStore(defaults: defaults), defaults)
    }
    @MainActor func testSelectedImportPersistsWithoutDeviceMapping() throws {
        try fixture { store, defaults in
            let components = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 28800),
                                            year: 2026, month: 9, day: 9, hour: 13, minute: 5)
            let values = [row("one", completed: true, due: components), row("two")]
            XCTAssertEqual(try store.importSystemReminders(values, selectedIDs: ["one"]), ReminderImportReport(imported: 1, skipped: 0))
            let reopened = CompanionStore(defaults: defaults)
            XCTAssertEqual(reopened.todos.count, 1)
            XCTAssertTrue(reopened.todos[0].completed)
            XCTAssertEqual(reopened.todos[0].dueAt, values[0].dueAt)
            XCTAssertEqual(reopened.todos[0].reminderDueComponents, components)
            XCTAssertNil(reopened.todos[0].wireID); XCTAssertNil(reopened.todos[0].delivery)
        }
    }
    @MainActor func testReimportDoesNotOverwriteLocalEditOrResurrectArchivedTodo() throws {
        try fixture { store, _ in
            try store.importSystemReminders([row()], selectedIDs: ["synthetic-id"])
            let id = store.todos[0].id
            store.editTodo(id, title: "保留手机修改", dueAt: nil)
            store.archiveTodo(id, archived: true)
            XCTAssertEqual(try store.importSystemReminders([row(title: "系统新标题")], selectedIDs: ["synthetic-id"]), ReminderImportReport(imported: 0, skipped: 1))
            XCTAssertEqual(store.todos.count, 1); XCTAssertEqual(store.todos[0].title, "保留手机修改")
            XCTAssertNotNil(store.todos[0].archivedAt)
        }
    }
    @MainActor func testSameTitleDifferentIDsRemainSeparate() throws {
        try fixture { store, _ in
            try store.importSystemReminders([row("one"), row("two")], selectedIDs: ["one", "two"])
            XCTAssertEqual(store.todos.count, 2)
        }
    }
    @MainActor func testUnknownDuplicateAndOversizedSelectionAreRejectedAtomically() throws {
        try fixture { store, _ in
            XCTAssertThrowsError(try store.importSystemReminders([row()], selectedIDs: ["missing"]))
            XCTAssertThrowsError(try store.importSystemReminders([row(), row()], selectedIDs: ["synthetic-id"]))
            let many = (0..<101).map { row(String($0)) }
            XCTAssertThrowsError(try store.importSystemReminders(many, selectedIDs: Set(many.map(\.id))))
            XCTAssertTrue(store.todos.isEmpty)
        }
    }
    @MainActor func testInvalidSelectedRowDoesNotPartiallyImportEarlierRows() throws {
        try fixture { store, _ in
            XCTAssertThrowsError(try store.importSystemReminders([row("valid"), row("invalid", title: "  ")], selectedIDs: ["valid", "invalid"]))
            XCTAssertTrue(store.todos.isEmpty)
            XCTAssertThrowsError(try store.importSystemReminders([row("")], selectedIDs: [""]))
        }
    }
    @MainActor func testDateOnlyIsNotInventedAsTimedReminderAndTitleEditKeepsIt() throws {
        try fixture { store, _ in
            let due = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 9)
            let snapshot = row(due: due)
            XCTAssertNotNil(SystemReminderSnapshot.dateOnlyLabel(due))
            try store.importSystemReminders([snapshot], selectedIDs: [snapshot.id])
            let id = store.todos[0].id
            store.editTodo(id, title: "新标题", dueAt: snapshot.dueAt)
            XCTAssertEqual(store.todos[0].reminderDueComponents, due)
            store.editTodo(id, title: "新标题", dueAt: nil)
            XCTAssertNil(store.todos[0].reminderDueComponents)
            XCTAssertNil(SystemReminderSnapshot.date(DateComponents(hour: 10)))
            XCTAssertNil(SystemReminderSnapshot.dateOnlyLabel(DateComponents(year: 2026, month: 9, day: 9, hour: 12)))
        }
    }
    @MainActor func testLongTitleIsBoundedWithoutSplittingCharacters() throws {
        try fixture { store, _ in
            try store.importSystemReminders([row(title: String(repeating: "👨‍👩‍👧‍👦", count: 310))], selectedIDs: ["synthetic-id"])
            XCTAssertEqual(store.todos[0].title.count, 300)
        }
    }
    @MainActor func testControllerNeverRequestsPermissionOrReadsOnInit() {
        let reader = TestReminderReader()
        let controller = ReminderImportController(reader: reader)
        XCTAssertTrue(controller.rows.isEmpty); XCTAssertTrue(controller.lists.isEmpty)
        XCTAssertEqual(reader.requestCount, 0); XCTAssertEqual(reader.readCount, 0)
    }
    @MainActor func testDeniedAccessDoesNotReadListsOrRows() async {
        let reader = TestReminderReader(); reader.grant = false
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists()
        XCTAssertEqual(reader.requestCount, 1); XCTAssertEqual(reader.listCount, 0); XCTAssertEqual(reader.readCount, 0)
        XCTAssertNotNil(controller.error); XCTAssertFalse(controller.busy)
    }
    @MainActor func testExplicitListReadDoesNotSelectOrImportAnything() async {
        let reader = TestReminderReader(); reader.values = [row()]
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists()
        XCTAssertEqual(reader.readCount, 0)
        await controller.loadReminders(listID: "list-a")
        XCTAssertEqual(controller.rows.count, 1); XCTAssertTrue(controller.selected.isEmpty)
        XCTAssertEqual(reader.readCount, 1)
    }
    @MainActor func testLateFetchAfterCancelCannotRepopulatePreview() async {
        let reader = TestReminderReader(); reader.deferred = true
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists()
        let task = Task { await controller.loadReminders(listID: "list-a") }
        for _ in 0..<100 where reader.requests.isEmpty { await Task.yield() }
        guard let reply = reader.requests.first else { XCTFail("no request"); task.cancel(); return }
        controller.discardPreview()
        reply.resume(returning: [row()])
        await task.value
        XCTAssertTrue(controller.rows.isEmpty); XCTAssertTrue(controller.lists.isEmpty); XCTAssertFalse(controller.busy)
    }
    @MainActor func testRevokedPermissionDiscardsFetchedRowsAndImportSelection() async throws {
        let reader = TestReminderReader(); reader.values = [row()]
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists(); await controller.loadReminders(listID: "list-a")
        controller.toggle("synthetic-id"); reader.canRead = false
        try fixture { store, _ in
            controller.importSelected(into: store)
            XCTAssertTrue(store.todos.isEmpty); XCTAssertTrue(controller.rows.isEmpty)
            XCTAssertTrue(controller.selected.isEmpty); XCTAssertTrue(controller.lists.isEmpty)
        }
    }
    @MainActor func testOlderFetchCannotReplaceNewerResult() async {
        let reader = TestReminderReader(); reader.deferred = true
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists()
        let old = Task { await controller.loadReminders(listID: "list-a") }
        for _ in 0..<100 where reader.requests.count < 1 { await Task.yield() }
        let current = Task { await controller.loadReminders(listID: "list-a") }
        for _ in 0..<100 where reader.requests.count < 2 { await Task.yield() }
        guard reader.requests.count == 2 else { XCTFail("requests not started"); old.cancel(); current.cancel(); return }
        reader.requests[1].resume(returning: [row("new", title: "新快照")])
        await current.value
        reader.requests[0].resume(returning: [row("old", title: "旧快照")])
        await old.value
        XCTAssertEqual(controller.rows.map(\.id), ["new"])
    }
    @MainActor func testRefreshClearsSelectionAndFetchLimitIsNotSilentTruncation() async {
        let reader = TestReminderReader(); reader.values = [row()]
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists(); await controller.loadReminders(listID: "list-a")
        controller.toggle("synthetic-id"); XCTAssertEqual(controller.selected.count, 1)
        reader.values = (0..<501).map { row(String($0)) }
        await controller.loadReminders(listID: "list-a")
        XCTAssertTrue(controller.rows.isEmpty); XCTAssertTrue(controller.selected.isEmpty)
        XCTAssertNotNil(controller.error)
    }
    @MainActor func testSelectionLimitAndClearPreview() async {
        let reader = TestReminderReader(); reader.values = (0..<101).map { row(String($0)) }
        let controller = ReminderImportController(reader: reader)
        await controller.loadLists(); await controller.loadReminders(listID: "list-a")
        for row in reader.values { controller.toggle(row.id) }
        XCTAssertEqual(controller.selected.count, 100)
        controller.clearSelection(); XCTAssertTrue(controller.selected.isEmpty)
        controller.discardPreview(); XCTAssertTrue(controller.rows.isEmpty); XCTAssertTrue(controller.lists.isEmpty)
    }
}
