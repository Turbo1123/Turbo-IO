import Foundation
import RayNeoSessionRuntime

/// Explicit test clock. Advancing it is synthetic time, not wall-clock or hardware evidence.
public actor ManualRuntimeClock: SessionRuntimeClock {
    private struct Sleeper { let deadline: UInt64; let continuation: CheckedContinuation<Void, Error> }
    private var sleepers: [UUID: Sleeper] = [:]
    public private(set) var nanoseconds: UInt64 = 0
    public var pendingSleepCount: Int { sleepers.count }
    public init() {}

    public func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let sum = self.nanoseconds.addingReportingOverflow(nanoseconds)
        let deadline = sum.overflow ? UInt64.max : sum.partialValue
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if deadline <= self.nanoseconds { continuation.resume() }
                else { sleepers[id] = .init(deadline: deadline, continuation: continuation) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    public func advance(by nanoseconds: UInt64) {
        let sum = self.nanoseconds.addingReportingOverflow(nanoseconds)
        self.nanoseconds = sum.overflow ? UInt64.max : sum.partialValue
        let ready = sleepers.filter { $0.value.deadline <= self.nanoseconds }.map(\.key)
        for id in ready { sleepers.removeValue(forKey: id)?.continuation.resume() }
    }

    private func cancel(_ id: UUID) { sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError()) }
}
