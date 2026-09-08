import Foundation
import Combine

@MainActor final class ReminderImportController: ObservableObject {
    @Published private(set) var lists: [SystemReminderList] = []
    @Published private(set) var rows: [SystemReminderSnapshot] = []
    @Published private(set) var busy = false
    @Published private(set) var activeList: String?
    @Published private(set) var status = "尚未读取系统提醒事项"
    @Published private(set) var error: String?
    @Published private(set) var selected: Set<String> = []
    let isFixture: Bool
    private let reader: SystemReminderReading
    private var generation = UUID()

    init(reader: SystemReminderReading, isFixture: Bool = false) { self.reader = reader; self.isFixture = isFixture }
    static func forCurrentLaunch() -> ReminderImportController {
        #if DEBUG && !COMPANION_DEVICE
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-reminders-fixture"), let index = args.firstIndex(of: "--ui-test-scope"),
           args.indices.contains(index + 1), UUID(uuidString: args[index + 1]) != nil {
            return ReminderImportController(reader: FixtureReminderReader(), isFixture: true)
        }
        #endif
        return ReminderImportController(reader: EventKitReminderReader())
    }
    private func begin() -> UUID {
        cancel(); generation = UUID(); busy = true; error = nil
        return generation
    }
    func loadLists() async {
        let token = begin(); lists = []; activeList = nil
        status = "等待授权并读取清单名称…"
        defer { if generation == token { busy = false } }
        do {
            try await reader.requestAccess()
            guard generation == token, !Task.isCancelled else { return }
            lists = try reader.lists()
            status = lists.isEmpty ? "没有可读取的系统清单" : "请选择一个清单，再读取条目"
        } catch { if generation == token { fail(error) } }
    }
    func loadReminders(listID: String) async {
        let token = begin(); activeList = listID
        status = "正在读取所选清单…"
        defer { if generation == token { busy = false } }
        do {
            guard lists.contains(where: { $0.id == listID }) else { throw SystemReminderError.unavailable }
            guard reader.canRead else { throw SystemReminderError.denied }
            let result = try await reader.reminders(in: listID)
            guard generation == token, !Task.isCancelled else { return }
            guard reader.canRead else { throw SystemReminderError.denied }
            guard result.count <= 500 else { throw SystemReminderError.limit }
            guard Set(result.map(\.id)).count == result.count else { throw SystemReminderError.selection }
            rows = result.sorted { lhs, rhs in
                if lhs.completed != rhs.completed { return !lhs.completed }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            status = "已读取 \(rows.count) 条快照；勾选后才导入，不持续同步"
        } catch { if generation == token { fail(error) } }
    }
    func toggle(_ id: String) {
        guard !busy, rows.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < 100 { selected.insert(id) }
        else { error = SystemReminderError.limit.localizedDescription }
    }
    func clearSelection() { selected = [] }
    func importSelected(into store: CompanionStore) {
        guard !busy else { return }
        do {
            guard reader.canRead else { throw SystemReminderError.denied }
            let report = try store.importSystemReminders(rows, selectedIDs: selected)
            selected = []; error = nil
            status = "已导入 \(report.imported) 条，跳过已导入 \(report.skipped) 条；仅保存在Turbo IO"
        } catch { fail(error) }
    }
    func cancel() {
        generation = UUID(); reader.cancel(); busy = false
        rows = []; selected = []
    }
    func discardPreview() {
        cancel(); lists = []; activeList = nil; error = nil
        status = "已清除读取预览；已导入Turbo IO的本机待办不受影响"
    }
    private func fail(_ failure: Error) {
        rows = []; selected = []
        if case SystemReminderError.denied = failure { lists = []; activeList = nil }
        error = (failure as? SystemReminderError)?.localizedDescription ?? SystemReminderError.failed.localizedDescription
        status = "未导入或修改系统提醒事项"
    }
}

#if DEBUG && !COMPANION_DEVICE
@MainActor private final class FixtureReminderReader: SystemReminderReading {
    var canRead = true
    func requestAccess() async throws {}
    func lists() throws -> [SystemReminderList] { [SystemReminderList(id: "synthetic-list", title: "合成清单 · 不读取系统数据")] }
    func reminders(in listID: String) async throws -> [SystemReminderSnapshot] {
        [SystemReminderSnapshot(id: "synthetic-reminder", title: "合成系统待办 · 导入测试", completed: false,
            dueComponents: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 9))]
    }
    func cancel() {}
}
#endif
