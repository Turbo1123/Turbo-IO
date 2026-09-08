import Foundation

/// Closed set from the two inspected iOS builders, not a claim that firmware
/// rejects all other integers. Unknown values are not an enabled SDK feature.
public enum SuggestionCardCategory: Int64, CaseIterable, Sendable {
    case calendar = 1
    case todo = 2

    public init(validatingRawValue value: Int64) throws {
        guard let category = Self(rawValue: value) else {
            throw SuggestionCardEncodingError.unsupportedSuggestType(value)
        }
        self = category
    }
}

public enum SuggestionCardEncodingError: Error, Equatable, Sendable {
    case unsupportedSuggestType(Int64)
    /// Local strict subset: inspected normal todo construction has no timeRange.
    /// The serializer itself does not prove this is a firmware restriction.
    case unverifiedTimeRangeForTodo
}

/// App → glasses type 33 only. Text is explicitly supplied, not invented from
/// official localized defaults. Deletion cannot carry accidental new content.
public enum SuggestionCardAppRequest: Equatable, Sendable {
    case add(suggestUID: String, suggestType: SuggestionCardCategory,
             title: String, source: String, content: String, timeRange: String?)
    case delete(suggestUID: String, suggestType: SuggestionCardCategory)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.add(let lu, let lt, let lh, let ls, let lc, let lr),
              .add(let ru, let rt, let rh, let rs, let rc, let rr)):
            return WireTextIdentity.matches(lu, ru) && lt == rt &&
                WireTextIdentity.matches(lh, rh) && WireTextIdentity.matches(ls, rs) &&
                WireTextIdentity.matches(lc, rc) && optionalWireTextEqual(lr, rr)
        case (.delete(let lu, let lt), .delete(let ru, let rt)):
            return WireTextIdentity.matches(lu, ru) && lt == rt
        default: return false
        }
    }

    private static func optionalWireTextEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.some(let left), .some(let right)): return WireTextIdentity.matches(left, right)
        default: return false
        }
    }
}

/// iOS 1.0.2(67) static type-33 encoding subset. This has no switches, account
/// provider, transport, return-success bool, card registry, or tool executor.
/// An encoded card is not sent, displayed, accepted, or approved.
public struct SuggestionCardJSONCodec: Sendable {
    public let limits: DisplayPayloadLimits
    public init(limits: DisplayPayloadLimits = .conservative) { self.limits = limits }

    public func encodeAppRequest(_ request: SuggestionCardAppRequest) throws -> DisplayJSONMessage {
        let uid: String
        let category: SuggestionCardCategory
        var fields: [String: Any]
        switch request {
        case .add(let suggestUID, let suggestType, let title, let source, let content, let timeRange):
            uid = suggestUID
            category = suggestType
            fields = ["type": 1, "title": title, "source": source, "content": content]
            if let timeRange, !timeRange.isEmpty {
                guard category == .calendar else {
                    throw SuggestionCardEncodingError.unverifiedTimeRangeForTodo
                }
                // No trim: whitespace is a nonempty display string. No epoch or
                // {start,end} conversion is performed by this wire serializer.
                fields["timeRange"] = timeRange
            }
        case .delete(let suggestUID, let suggestType):
            uid = suggestUID
            category = suggestType
            fields = ["type": 2, "title": "", "source": "", "content": ""]
        }
        try validateIdentifier(uid, key: "suggestUID", limits: limits)
        fields["suggestUID"] = uid
        fields["suggestType"] = category.rawValue
        return DisplayJSONMessage(type: 33, payload: try encodeJSON(fields, limits: limits))
    }
}
