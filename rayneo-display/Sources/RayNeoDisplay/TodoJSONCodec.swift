import Foundation

/// Intentionally has NO Date, seconds, milliseconds, or automatic unit inference.
/// Inspected iOS compare/writeback paths use inconsistent scales; retain raw data
/// until a caller explicitly chooses a field-specific, hardware-verified policy.
public struct UnverifiedWireTime: Equatable, Hashable, Sendable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }
}

public enum TodoCompletionStatus: Equatable, Sendable {
    case incomplete
    case complete
    case unknown(Int64)

    public init(rawValue: Int64) {
        switch rawValue {
        case 0: self = .incomplete
        case 1: self = .complete
        default: self = .unknown(rawValue)
        }
    }
}

public struct TodoStatusObserved: Equatable, Sendable {
    public let eventID: Int64
    public let statusRaw: Int64
    public let isImportant: FieldPresence<Bool>
    public let lastModifiedTime: UnverifiedWireTime
    public var completionStatus: TodoCompletionStatus { TodoCompletionStatus(rawValue: statusRaw) }
}

public struct TodoBatchStatusObserved: Equatable, Sendable {
    public let eventID: Int64
    public let statusRaw: Int64
    public let isImportant: FieldPresence<Bool>
    public let lastModifiedTime: FieldPresence<UnverifiedWireTime>

    /// Only the inspected batch handler supplies 0 for absent/null time. The raw
    /// presence remains available and this default must not migrate to type 4.
    public var effectiveLastModifiedTime: UnverifiedWireTime {
        lastModifiedTime.value ?? UnverifiedWireTime(rawValue: 0)
    }
    public var completionStatus: TodoCompletionStatus { TodoCompletionStatus(rawValue: statusRaw) }
}

public enum TodoBatchEntry: Equatable, Sendable {
    public enum IgnoreReason: Equatable, Sendable {
        case notTodo(eventType: Int64?)
        case missingEventID
        case missingStatus
    }
    case todo(TodoBatchStatusObserved)
    case ignored(IgnoreReason)
}

public struct TodoBatchObserved: Equatable, Sendable {
    public let scheduleTotal: FieldPresence<Int64>
    public let todoTotal: FieldPresence<Int64>
    /// Order and ignored entries are retained. Received count != applied count.
    public let eventList: FieldPresence<[TodoBatchEntry]>
}

public enum TodoGlassesMessage: Equatable, Sendable {
    case status(TodoStatusObserved)
    case batch(TodoBatchObserved)
    case unknown(type: UInt16, payload: Data)
}

/// Read-only glasses → App status subset. No symmetric encoder is offered:
/// static inbound evidence is not authorization to send a spoofed reverse event.
public struct TodoJSONCodec: Sendable {
    public let limits: DisplayPayloadLimits
    public init(limits: DisplayPayloadLimits = .conservative) { self.limits = limits }

    public func decodeGlassesMessage(type: UInt16, payload: Data) throws -> TodoGlassesMessage {
        try limits.checkSize(payload)
        guard type == 4 || type == 10 else { return .unknown(type: type, payload: payload) }
        let json = try JSONObject(data: payload, limits: limits)
        if type == 4 {
            try json.requireOnly(["eventID", "status", "isImportant", "lastModifiedTime"])
            return .status(TodoStatusObserved(
                eventID: try json.int("eventID"), statusRaw: try json.int("status"),
                isImportant: try json.optionalBool("isImportant"),
                lastModifiedTime: UnverifiedWireTime(rawValue: try json.int("lastModifiedTime"))
            ))
        }
        try json.requireOnly(["scheduleTotal", "todoTotal", "eventList"])
        let eventList: FieldPresence<[TodoBatchEntry]>
        if let value = json.fields["eventList"] {
            switch value {
            case .null: eventList = .null
            case .array(let entries): eventList = .value(try entries.map(decodeBatchEntry))
            default: throw DisplayPayloadError.wrongType("eventList")
            }
        } else {
            eventList = .missing
        }
        return .batch(TodoBatchObserved(
            scheduleTotal: try json.optionalInt("scheduleTotal"),
            todoTotal: try json.optionalInt("todoTotal"), eventList: eventList
        ))
    }

    private func decodeBatchEntry(_ value: StrictJSONValue) throws -> TodoBatchEntry {
        let json = try JSONObject(value)
        let eventType = try json.optionalInt("eventType").value
        guard eventType == 1 else { return .ignored(.notTodo(eventType: eventType)) }
        guard let eventID = try json.optionalInt("eventID").value else {
            return .ignored(.missingEventID)
        }
        guard let status = try json.optionalInt("status").value else {
            return .ignored(.missingStatus)
        }
        let rawTime = try json.optionalInt("lastModifiedTime")
        let time: FieldPresence<UnverifiedWireTime>
        switch rawTime {
        case .missing: time = .missing
        case .null: time = .null
        case .value(let raw): time = .value(UnverifiedWireTime(rawValue: raw))
        }
        // Metadata maps can include title/createTime/offline markers or schedule
        // fields. They are not applied by this immediate-status decoder. Never
        // mistake this projection for a lossless reconnect-metadata codec.
        return .todo(TodoBatchStatusObserved(
            eventID: eventID, statusRaw: status, isImportant: try json.optionalBool("isImportant"),
            lastModifiedTime: time
        ))
    }
}

/// Pure local planning, not a write/merge operation. Only the host can establish
/// that an incoming ID belongs to a task in the current account and generation.
public enum TodoImmediateUpdatePlanner {
    public struct ExistingTask: Equatable, Sendable {
        public let eventID: Int64
        public let completed: Bool
        public let important: Bool
        public init(eventID: Int64, completed: Bool, important: Bool) {
            self.eventID = eventID; self.completed = completed; self.important = important
        }
    }

    public struct Changes: Equatable, Sendable {
        /// nil means preserve, not false. No local task is created here.
        public let completed: Bool?
        public let important: Bool?
        /// Host persistence must suppress echo; this flag sends nothing itself.
        public let shouldSuppressImmediateEcho = true
    }

    public enum Plan: Equatable, Sendable {
        case unknownTask
        case noChange
        case update(Changes)
    }

    public static func plan(_ observation: TodoStatusObserved, existing: ExistingTask?) -> Plan {
        plan(eventID: observation.eventID, statusRaw: observation.statusRaw,
             importance: observation.isImportant, existing: existing)
    }

    public static func plan(_ observation: TodoBatchStatusObserved, existing: ExistingTask?) -> Plan {
        plan(eventID: observation.eventID, statusRaw: observation.statusRaw,
             importance: observation.isImportant, existing: existing)
    }

    private static func plan(eventID: Int64, statusRaw: Int64, importance: FieldPresence<Bool>,
                             existing: ExistingTask?) -> Plan {
        guard let existing, existing.eventID == eventID else { return .unknownTask }
        let completed: Bool?
        switch TodoCompletionStatus(rawValue: statusRaw) {
        case .complete: completed = existing.completed ? nil : true
        case .incomplete: completed = existing.completed ? false : nil
        case .unknown: completed = nil
        }
        let important = importance.value.flatMap { $0 == existing.important ? nil : $0 }
        guard completed != nil || important != nil else { return .noChange }
        return .update(Changes(completed: completed, important: important))
    }
}
