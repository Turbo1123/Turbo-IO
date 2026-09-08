import Foundation
import EventKit

struct SystemReminderList: Identifiable, Equatable {
    let id: String
    let title: String
}

struct SystemReminderSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let completed: Bool
    let dueComponents: DateComponents?
    var dueAt: Date? { Self.date(dueComponents) }
    static func date(_ components: DateComponents?) -> Date? {
        guard let components, components.year != nil, components.month != nil, components.day != nil else { return nil }
        var calendar = components.calendar ?? Calendar.current
        calendar.timeZone = components.timeZone ?? calendar.timeZone
        return calendar.date(from: components)
    }
    static func dateOnlyLabel(_ components: DateComponents?) -> String? {
        guard let components, components.hour == nil, components.minute == nil,
              let date = date(components) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = components.calendar ?? Calendar.current
        formatter.timeZone = components.timeZone ?? formatter.calendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .none
        return formatter.string(from: date) + " · 全天"
    }
}

enum SystemReminderError: LocalizedError {
    case denied, unavailable, failed, limit, selection
    var errorDescription: String? {
        switch self {
        case .denied: return "未获得提醒事项读取权限。你可在 iPhone 设置中允许访问；Turbo IO不会修改系统待办。"
        case .unavailable: return "所选清单已不可用，请重新读取清单。"
        case .failed: return "提醒事项读取失败或超时，请重试；没有导入或修改系统数据。"
        case .limit: return "一次最多显示 500 条、导入 100 条；请在系统中拆分清单或缩小选择。"
        case .selection: return "所选条目已过期或格式异常，请重新读取后选择。"
        }
    }
}

@MainActor protocol SystemReminderReading: AnyObject {
    var canRead: Bool { get }
    func requestAccess() async throws
    func lists() throws -> [SystemReminderList]
    func reminders(in listID: String) async throws -> [SystemReminderSnapshot]
    func cancel()
}

/// EventKit is used only for access requests and reads. No save/remove/commit API is exposed.
@MainActor final class EventKitReminderReader: SystemReminderReading {
    private let store = EKEventStore()
    private var pendingID: UUID?
    private var fetchHandle: Any?
    private var continuation: CheckedContinuation<[SystemReminderSnapshot], Error>?
    private var timeout: Task<Void, Never>?

    var canRead: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    func requestAccess() async throws {
        guard !canRead else { return }
        do {
            let granted: Bool
            if #available(iOS 17.0, *) { granted = try await store.requestFullAccessToReminders() }
            else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    store.requestAccess(to: .reminder) { granted, error in
                        if error != nil { continuation.resume(throwing: SystemReminderError.denied) }
                        else { continuation.resume(returning: granted) }
                    }
                }
            }
            guard granted, canRead else { throw SystemReminderError.denied }
        } catch { throw SystemReminderError.denied }
    }
    func lists() throws -> [SystemReminderList] {
        guard canRead else { throw SystemReminderError.denied }
        let calendars = store.calendars(for: .reminder)
        guard calendars.count <= 200 else { throw SystemReminderError.limit }
        return calendars.map { SystemReminderList(id: $0.calendarIdentifier, title: String($0.title.prefix(200))) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func reminders(in listID: String) async throws -> [SystemReminderSnapshot] {
        cancel()
        guard canRead else { throw SystemReminderError.denied }
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == listID }) else { throw SystemReminderError.unavailable }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pendingID = requestID; self.continuation = continuation
                let predicate = store.predicateForReminders(in: [calendar])
                fetchHandle = store.fetchReminders(matching: predicate) { [weak self] reminders in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.pendingID == requestID else { return }
                        guard self.canRead else { self.finish(requestID, result: .failure(SystemReminderError.denied)); return }
                        guard let reminders else { self.finish(requestID, result: .failure(SystemReminderError.failed)); return }
                        guard reminders.count <= 500 else { self.finish(requestID, result: .failure(SystemReminderError.limit)); return }
                        let rows = reminders.map {
                            SystemReminderSnapshot(id: $0.calendarItemIdentifier, title: String(($0.title ?? "").prefix(300)),
                                completed: $0.isCompleted, dueComponents: $0.dueDateComponents)
                        }
                        self.finish(requestID, result: .success(rows))
                    }
                }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    self?.finish(requestID, result: .failure(SystemReminderError.failed))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(requestID, result: .failure(CancellationError())) }
        }
    }
    func cancel() { if let pendingID { finish(pendingID, result: .failure(CancellationError())) } }
    private func finish(_ id: UUID, result: Result<[SystemReminderSnapshot], Error>) {
        guard pendingID == id else { return }
        let reply = continuation, handle = fetchHandle
        pendingID = nil; continuation = nil; fetchHandle = nil
        timeout?.cancel(); timeout = nil
        if let handle { store.cancelFetchRequest(handle) }
        reply?.resume(with: result)
    }
}

struct ReminderImportReport: Equatable {
    let imported: Int
    let skipped: Int
}
