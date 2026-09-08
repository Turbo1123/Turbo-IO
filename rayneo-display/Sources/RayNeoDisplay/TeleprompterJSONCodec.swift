import Foundation

public enum TeleprompterControlType: UInt16, CaseIterable, Sendable {
    case pause = 4
    case resume = 5
    case stop = 6
    case progress = 8
}

public struct TeleprompterPauseObserved: Equatable, Sendable {
    public let did: String
    public let offset: FieldPresence<Int64>
    public let code: FieldPresence<Int64>
    public let isCompleted: FieldPresence<Bool>
    /// The field is named seconds in iOS. Its start/reset behavior is unverified.
    public let elapsedSeconds: FieldPresence<Int64>

    public var effectiveOffset: Int64 { offset.value ?? 0 }
    public var effectiveCode: Int64 { code.value ?? 1 }
    public var effectiveIsCompleted: Bool { isCompleted.value ?? false }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.did, rhs.did) && lhs.offset == rhs.offset &&
        lhs.code == rhs.code && lhs.isCompleted == rhs.isCompleted && lhs.elapsedSeconds == rhs.elapsedSeconds
    }
}

public struct TeleprompterResumeObserved: Equatable, Sendable {
    public let did: String
    public let code: FieldPresence<Int64>
    public let elapsedSeconds: FieldPresence<Int64>
    public var effectiveCode: Int64 { code.value ?? 1 }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.did, rhs.did) && lhs.code == rhs.code && lhs.elapsedSeconds == rhs.elapsedSeconds
    }
}

public struct TeleprompterPositionObserved: Equatable, Sendable {
    public let did: String
    /// Raw offset. iOS headless line-start mapping uses normalized UTF-8 bytes;
    /// this type does not assume that every firmware offset is a valid boundary.
    public let pageOffset: Int64
    /// Wire spelling is intentional. Non-ASCII highlight endpoints need hardware QA.
    public let highLightOffset: Int64
    public let autoSync: FieldPresence<Bool>

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.did, rhs.did) && lhs.pageOffset == rhs.pageOffset &&
        lhs.highLightOffset == rhs.highLightOffset && lhs.autoSync == rhs.autoSync
    }
}

/// These are decoded requests from the glasses, NOT acknowledgements or applied UI.
public enum TeleprompterGlassesRequest: Equatable, Sendable {
    case pause(TeleprompterPauseObserved)
    case resume(TeleprompterResumeObserved)
    case stop(did: String)
    case progress(TeleprompterPositionObserved)
    /// Unsupported types are retained byte-for-byte under the payload limit.
    /// In particular type 9 audio must not be run through the JSON parser.
    case unknown(type: UInt16, payload: Data)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pause(let left), .pause(let right)): return left == right
        case (.resume(let left), .resume(let right)): return left == right
        case (.stop(let left), .stop(let right)): return WireTextIdentity.matches(left, right)
        case (.progress(let left), .progress(let right)): return left == right
        case (.unknown(let lt, let lp), .unknown(let rt, let rp)): return lt == rt && lp == rp
        default: return false
        }
    }
}

/// Explicitly App → glasses. Resume/stop do not serialize inbound-only timing.
public enum TeleprompterAppRequest: Equatable, Sendable {
    case pause(did: String, offset: Int64, code: Int64, isCompleted: Bool)
    case resume(did: String)
    case stop(did: String)
    case progress(did: String, pageOffset: Int64, highLightOffset: Int64, autoSync: Bool?)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.pause(let ld, let lo, let lc, let lf), .pause(let rd, let ro, let rc, let rf)):
            return WireTextIdentity.matches(ld, rd) && lo == ro && lc == rc && lf == rf
        case (.resume(let left), .resume(let right)), (.stop(let left), .stop(let right)):
            return WireTextIdentity.matches(left, right)
        case (.progress(let ld, let lp, let lh, let la), .progress(let rd, let rp, let rh, let ra)):
            return WireTextIdentity.matches(ld, rd) && lp == rp && lh == rh && la == ra
        default: return false
        }
    }
}

public struct TeleprompterResponseObserved: Equatable, Sendable {
    public let type: TeleprompterControlType
    public let did: String
    /// Kept raw: a code 1 response is not proof of applied state or lens display.
    public let code: Int64

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && WireTextIdentity.matches(lhs.did, rhs.did) && lhs.code == rhs.code
    }
}

public enum TeleprompterResponseCode: Int64, Sendable {
    /// The official progress path emits this BEFORE checking DID and duplicates.
    case accepted = 1
    case notCurrentSession = 2
}

/// iOS 1.0.2(67) static subset. No transport, business-ID routing, automatic ACK,
/// file transfer, timers, microphone, or layout rendering lives in this codec.
public struct TeleprompterJSONCodec: Sendable {
    public let limits: DisplayPayloadLimits
    public init(limits: DisplayPayloadLimits = .conservative) { self.limits = limits }

    public func decodeGlassesRequest(type: UInt16, payload: Data) throws -> TeleprompterGlassesRequest {
        try limits.checkSize(payload)
        guard let kind = TeleprompterControlType(rawValue: type) else {
            return .unknown(type: type, payload: payload)
        }
        let json = try JSONObject(data: payload, limits: limits)
        guard try json.int("action") == 1 else { throw DisplayPayloadError.wrongAction }
        let did = try json.identifier("did")
        switch kind {
        case .pause:
            try json.requireOnly(["action", "did", "offset", "code", "isCompleted", "elapsedSeconds"])
            return .pause(TeleprompterPauseObserved(
                did: did, offset: try json.optionalInt("offset"), code: try json.optionalInt("code"),
                isCompleted: try json.optionalBool("isCompleted"),
                elapsedSeconds: try json.optionalInt("elapsedSeconds")
            ))
        case .resume:
            try json.requireOnly(["action", "did", "code", "elapsedSeconds"])
            return .resume(TeleprompterResumeObserved(
                did: did, code: try json.optionalInt("code"),
                elapsedSeconds: try json.optionalInt("elapsedSeconds")
            ))
        case .stop:
            try json.requireOnly(["action", "did"])
            return .stop(did: did)
        case .progress:
            try json.requireOnly(["action", "did", "pageOffset", "highLightOffset", "autoSync"])
            return .progress(TeleprompterPositionObserved(
                did: did, pageOffset: try json.int("pageOffset"),
                highLightOffset: try json.int("highLightOffset"),
                autoSync: try json.optionalBool("autoSync")
            ))
        }
    }

    /// Response decoding is a separate direction/action contract. Unsupported
    /// response types are not guessed to have the same did/code schema.
    public func decodeGlassesResponse(type: TeleprompterControlType,
                                      payload: Data) throws -> TeleprompterResponseObserved {
        let json = try JSONObject(data: payload, limits: limits)
        try json.requireOnly(["action", "did", "code"])
        guard try json.int("action") == 2 else { throw DisplayPayloadError.wrongAction }
        return TeleprompterResponseObserved(type: type, did: try json.identifier("did"),
                                            code: try json.int("code"))
    }

    public func encodeAppRequest(_ request: TeleprompterAppRequest) throws -> DisplayJSONMessage {
        let kind: TeleprompterControlType
        let did: String
        var json: [String: Any] = ["action": 1]
        switch request {
        case .pause(let identifier, let offset, let code, let isCompleted):
            kind = .pause; did = identifier
            json["offset"] = offset; json["code"] = code; json["isCompleted"] = isCompleted
        case .resume(let identifier):
            kind = .resume; did = identifier
        case .stop(let identifier):
            kind = .stop; did = identifier
        case .progress(let identifier, let pageOffset, let highLightOffset, let autoSync):
            kind = .progress; did = identifier
            json["pageOffset"] = pageOffset; json["highLightOffset"] = highLightOffset
            json["autoSync"] = autoSync.map { $0 as Any } ?? NSNull()
        }
        try validateIdentifier(did, key: "did", limits: limits)
        json["did"] = did
        return DisplayJSONMessage(type: kind.rawValue, payload: try encodeJSON(json, limits: limits))
    }

    /// Explicitly chosen response only. This API never sends or automatically
    /// accepts a request and cannot establish that an operation was applied.
    public func encodeAppResponse(type: TeleprompterControlType, did: String,
                                   code: TeleprompterResponseCode) throws -> DisplayJSONMessage {
        try validateIdentifier(did, key: "did", limits: limits)
        return DisplayJSONMessage(type: type.rawValue, payload: try encodeJSON(
            ["action": 2, "did": did, "code": code.rawValue], limits: limits
        ))
    }
}

/// Optional local receipt filter. Its sequence is NOT a wire field. The host
/// owns connection-generation assignment and must open a new tracker on reconnect.
public struct TeleprompterProgressTracker: Sendable {
    public enum Result: Equatable, Sendable {
        case staleConnection
        case differentDocument
        case duplicate
        case sequenceExhausted
        case updated(localSequence: UInt64)
    }

    public let did: String
    public let connectionGeneration: UInt64
    public private(set) var position: TeleprompterPositionObserved?
    public private(set) var localSequence: UInt64 = 0

    public init(did: String, connectionGeneration: UInt64) throws {
        try validateIdentifier(did, key: "did")
        self.did = did
        self.connectionGeneration = connectionGeneration
    }

    public mutating func observe(_ next: TeleprompterPositionObserved,
                                 connectionGeneration: UInt64) -> Result {
        guard self.connectionGeneration == connectionGeneration else { return .staleConnection }
        guard WireTextIdentity.matches(did, next.did) else { return .differentDocument }
        if let position, position.pageOffset == next.pageOffset,
           position.highLightOffset == next.highLightOffset {
            return .duplicate
        }
        guard localSequence < UInt64.max else { return .sequenceExhausted }
        position = next
        localSequence += 1
        return .updated(localSequence: localSequence)
    }
}
