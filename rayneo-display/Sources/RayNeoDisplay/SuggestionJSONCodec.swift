import Foundation

/// These commands concern notification-business suggestion cards, NOT ordinary
/// notification replies, raw head gestures, or permission to execute a tool.
public enum SuggestionCommand: Equatable, Sendable {
    case accept
    case reject
    case unknown(Int64)

    public init(rawValue: Int64) {
        switch rawValue {
        case 1: self = .accept
        case 2: self = .reject
        default: self = .unknown(rawValue)
        }
    }
}

public struct SuggestionOperationObserved: Equatable, Sendable {
    public let suggestUID: String
    public let suggestType: Int64
    public let command: SuggestionCommand
    /// Merely parsing an accept command does not authorize execution. There is
    /// deliberately no `approved`, `execute`, or automatic-ACK property/API.

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.suggestUID, rhs.suggestUID) &&
        lhs.suggestType == rhs.suggestType && lhs.command == rhs.command
    }
}

public enum SuggestionGlassesMessage: Equatable, Sendable {
    case operation(SuggestionOperationObserved)
    case unknown(type: UInt16, payload: Data)
}

public enum SuggestionUnknownCommandPolicy: Sendable {
    case retainUnknown
    case reject
}

public enum SuggestionAcknowledgementCode: Int64, Sendable {
    case success = 0
    case permissionDenied = 1
    /// Inspected code 2 also includes missing/nonunique details, not only network.
    case lookupOrNetworkFailure = 2
    case otherFailure = 3
}

/// Strict iOS static operation/ACK subset. It cannot create a suggestion card,
/// look up official cloud details, map an ID to a tool, or approve anything.
public struct SuggestionJSONCodec: Sendable {
    public let limits: DisplayPayloadLimits
    public let unknownCommandPolicy: SuggestionUnknownCommandPolicy

    public init(limits: DisplayPayloadLimits = .conservative,
                unknownCommandPolicy: SuggestionUnknownCommandPolicy = .reject) {
        self.limits = limits
        self.unknownCommandPolicy = unknownCommandPolicy
    }

    public func decodeGlassesOperation(type: UInt16, payload: Data) throws -> SuggestionGlassesMessage {
        try limits.checkSize(payload)
        guard type == 34 else { return .unknown(type: type, payload: payload) }
        let json = try JSONObject(data: payload, limits: limits)
        try json.requireOnly(["suggestUID", "suggestType", "cmd"])
        let raw = try json.int("cmd")
        let command = SuggestionCommand(rawValue: raw)
        if case .unknown = command, unknownCommandPolicy == .reject {
            throw DisplayPayloadError.unknownCommand(raw)
        }
        return .operation(SuggestionOperationObserved(
            suggestUID: try json.identifier("suggestUID"),
            suggestType: try json.int("suggestType"), command: command
        ))
    }

    /// App → glasses type 35. Caller must independently resolve the exact pending
    /// request, current presentation, expiry, generation, and idempotent outcome.
    /// This method only serializes the caller's explicit result; it sends nothing.
    public func encodeAppAcknowledgement(suggestUID: String, suggestType: Int64,
                                          code: SuggestionAcknowledgementCode) throws -> DisplayJSONMessage {
        try validateIdentifier(suggestUID, key: "suggestUID", limits: limits)
        return DisplayJSONMessage(type: 35, payload: try encodeJSON(
            ["suggestUID": suggestUID, "suggestType": suggestType, "code": code.rawValue],
            limits: limits
        ))
    }
}
