import Foundation
import CryptoKit

public enum ApprovalRisk: String, Sendable { case low, high }
public enum ApprovalConfirmationPolicy: String, Sendable { case phoneRequired, voiceExact, voiceChallenge }
public enum ApprovalSubsessionPhase: String, Sendable {
    case inactive, idle, awaitingPresentation, awaitingToolApproval, awaitingPhoneConfirmation, capturingConfirmation, resolved
}
public enum ApprovalContextInvalidation: String, Sendable {
    case normalNextRound, interruption, exit, disconnection, hostCancellation, clockFailure
}
public enum ApprovalSubsessionRejection: String, Error, Sendable {
    case invalidRequest, capacityReached, contextBusy, contextRequired, contextAlreadyUsed, wrongContext
    case hostSuspensionRequired, requestBusy, duplicateRequestID, unknownRequest, wrongBinding
    case presentationRequired, presentationMismatch, explicitPresentationRequired, trustedInteractionRequired
    case phoneRequired, confirmationRequired, captureRequired, wrongCapture, captureExpired, ambiguousVoice
    case attemptsExhausted, challengeUnavailable, requestExpired, invalidClock, invalidated, gateRejected
}

/// These are trusted host assertions, not proof of physical state and never model/ASR output.
public enum ApprovalHostSuspensionEvidence: Sendable { case ordinaryWorkPausedAndDrained, unconfirmed }
public enum ApprovalPresentationEvidence: Sendable { case trustedHostDisplayedExactContent, unconfirmed }
public enum ApprovalCaptureInteraction: Sendable {
    case explicitUserButtonOrGesture
    /// Host asserts an active user conversation just presented this exact request and opened dedicated confirmation capture.
    /// This is not speaker authentication and cannot distinguish matching TV/replayed speech.
    case activeUserConversationAndPresentedRequest
    case unconfirmed
}
public enum ApprovalPhoneEvidence: Sendable { case foregroundExplicitConfirmation, unconfirmed }

public struct ApprovalActionDigest: Equatable, Hashable, Sendable {
    public let bytes: Data
    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }
    internal init(hashing data: Data) { bytes = Data(SHA256.hash(data: data)) }
}

/// Immutable action bytes. The host must canonicalize/review the action and choose its risk class.
/// SHA-256 binds bytes; it does not prove that a natural-language summary describes them correctly.
public struct BoundToolApprovalRequest: Equatable, Sendable {
    public static let maximumActionBytes = 65_536
    public let requestID: String
    public let originRound: RoundToken
    public let actionDescription: String
    public let canonicalActionBytes: Data
    public let actionDigest: ApprovalActionDigest
    public let risk: ApprovalRisk
    public let createdAt: Date
    public let expiresAt: Date

    public init(requestID: String, originRound: RoundToken, actionDescription: String, canonicalActionBytes: Data,
                risk: ApprovalRisk, createdAt: Date, expiresAt: Date) throws {
        guard TextBounds.contains(requestID, maximumCharacters: 256, maximumUTF8Bytes: ToolApprovalGate.maximumRequestIDUTF8Bytes),
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextBounds.contains(actionDescription, maximumCharacters: 4_096, maximumUTF8Bytes: ToolApprovalGate.maximumActionDescriptionUTF8Bytes),
              !actionDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !canonicalActionBytes.isEmpty, canonicalActionBytes.count <= Self.maximumActionBytes,
              createdAt.timeIntervalSinceReferenceDate.isFinite, expiresAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt < expiresAt else { throw ApprovalSubsessionRejection.invalidRequest }
        self.requestID = requestID; self.originRound = originRound; self.actionDescription = actionDescription
        self.canonicalActionBytes = canonicalActionBytes; actionDigest = .init(hashing: canonicalActionBytes)
        self.risk = risk; self.createdAt = createdAt; self.expiresAt = expiresAt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.requestID.utf8.elementsEqual(rhs.requestID.utf8) && lhs.originRound == rhs.originRound
            && lhs.actionDescription.utf8.elementsEqual(rhs.actionDescription.utf8)
            && lhs.canonicalActionBytes == rhs.canonicalActionBytes && lhs.risk == rhs.risk
            && lhs.createdAt == rhs.createdAt && lhs.expiresAt == rhs.expiresAt
    }

    internal var legacyRequest: ToolApprovalRequest {
        .init(requestID: requestID, round: originRound, actionDescription: actionDescription, createdAt: createdAt, expiresAt: expiresAt)
    }
}

/// Controller-minted scope. It is NOT a real connection ACK or a new ordinary conversation round.
public struct ApprovalContextToken: Equatable, Hashable, Sendable {
    public let id: UUID
    public let originRound: RoundToken
    public let connectionGeneration: UUID
    internal init(originRound: RoundToken, connectionGeneration: UUID) {
        id = UUID(); self.originRound = originRound; self.connectionGeneration = connectionGeneration
    }
}

public struct ApprovalBinding: Equatable, Sendable {
    public let id: UUID
    public let context: ApprovalContextToken
    /// Exact UTF-8 bytes avoid Swift String's canonical-equivalence equality for opaque IDs.
    public let requestIDBytes: Data
    public var requestID: String { String(decoding: requestIDBytes, as: UTF8.self) }
    public let actionDigest: ApprovalActionDigest
    public let requestDigest: ApprovalActionDigest

    internal init(request: BoundToolApprovalRequest, context: ApprovalContextToken, policy: ApprovalConfirmationPolicy) {
        id = UUID(); self.context = context; requestIDBytes = Data(request.requestID.utf8)
        actionDigest = request.actionDigest
        var bytes = Data("RayNeoSession.ApprovalBinding.v1".utf8)
        // Length-prefixed exact byte fields; no locale-sensitive JSON/number formatting.
        for field in [Data(id.uuidString.utf8), Data(context.id.uuidString.utf8),
                      Data(context.connectionGeneration.uuidString.utf8), Data(request.originRound.sessionID.uuidString.utf8),
                      Self.integerBytes(request.originRound.index), requestIDBytes, Data(request.actionDescription.utf8),
                      request.actionDigest.bytes, Data(request.risk.rawValue.utf8), Data(policy.rawValue.utf8),
                      Self.integerBytes(request.createdAt.timeIntervalSinceReferenceDate.bitPattern),
                      Self.integerBytes(request.expiresAt.timeIntervalSinceReferenceDate.bitPattern)] {
            bytes.append(Self.integerBytes(UInt64(field.count))); bytes.append(field)
        }
        requestDigest = .init(hashing: bytes)
    }
    private static func integerBytes(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
}

/// The host must show and acknowledge these same bytes, not a model's paraphrased action.
public struct ApprovalDisplayedContent: Equatable, Sendable {
    public let requestID: String
    public let actionDescription: String
    public let actionDigest: ApprovalActionDigest
    public let risk: ApprovalRisk
    public let expiresAt: Date
    public init(requestID: String, actionDescription: String, actionDigest: ApprovalActionDigest, risk: ApprovalRisk, expiresAt: Date) {
        self.requestID = requestID; self.actionDescription = actionDescription; self.actionDigest = actionDigest
        self.risk = risk; self.expiresAt = expiresAt
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.requestID.utf8.elementsEqual(rhs.requestID.utf8)
            && lhs.actionDescription.utf8.elementsEqual(rhs.actionDescription.utf8)
            && lhs.actionDigest == rhs.actionDigest && lhs.risk == rhs.risk && lhs.expiresAt == rhs.expiresAt
    }
}

public struct ApprovalPresentation: Equatable, Sendable {
    public let binding: ApprovalBinding
    public let content: ApprovalDisplayedContent
    public let effectivePolicy: ApprovalConfirmationPolicy
    internal init(request: BoundToolApprovalRequest, binding: ApprovalBinding, policy: ApprovalConfirmationPolicy) {
        self.binding = binding; effectivePolicy = policy
        content = .init(requestID: request.requestID, actionDescription: request.actionDescription,
                        actionDigest: request.actionDigest, risk: request.risk, expiresAt: request.expiresAt)
    }
}

/// Separate identity namespace: never convert this into a reused origin RoundToken for ordinary ASR.
public struct ApprovalCaptureToken: Equatable, Sendable {
    public let id: UUID
    public let binding: ApprovalBinding
    public let generation: UInt64
    public let expiresAt: Date
    internal init(binding: ApprovalBinding, generation: UInt64, expiresAt: Date) {
        id = UUID(); self.binding = binding; self.generation = generation; self.expiresAt = expiresAt
    }
}
public struct ApprovalCapturePrompt: Equatable, Sendable {
    public let token: ApprovalCaptureToken
    public let policy: ApprovalConfirmationPolicy
    public let acceptedApprovalPhrases: [String]
    public let acceptedDenialPhrases: [String]
    public var approvePhrase: String { acceptedApprovalPhrases[0] }
    public var denyPhrase: String { acceptedDenialPhrases[0] }
    internal init(token: ApprovalCaptureToken, policy: ApprovalConfirmationPolicy, digits: String?) {
        self.token = token; self.policy = policy
        if let digits {
            acceptedApprovalPhrases = ["批准 " + digits]; acceptedDenialPhrases = ["拒绝 " + digits]
        } else {
            acceptedApprovalPhrases = ["批准了", "确认批准"]; acceptedDenialPhrases = ["拒绝", "不批准"]
        }
    }
}

public enum ApprovalDecisionSource: Equatable, Sendable {
    case phone
    case voiceExact(ApprovalCaptureToken)
    case voiceChallenge(ApprovalCaptureToken)
    case expiration
    case invalidation(ApprovalContextInvalidation)
}
public struct ApprovalDecision: Equatable, Sendable {
    public let binding: ApprovalBinding
    public let receipt: ToolApprovalReceipt
    public let source: ApprovalDecisionSource
    /// No action execution is encoded here. Only .resolved may be newly delivered by the host.
    internal init(binding: ApprovalBinding, receipt: ToolApprovalReceipt, source: ApprovalDecisionSource) {
        self.binding = binding; self.receipt = receipt; self.source = source
    }
}
public enum ApprovalContextResult: Equatable, Sendable {
    case established(ApprovalContextToken)
    case rejected(ApprovalSubsessionRejection)
}
public enum ApprovalSubsessionRegistration: Equatable, Sendable {
    case registered(ApprovalPresentation)
    case rejected(ApprovalSubsessionRejection)
}
public enum ApprovalSubsessionResult: Equatable, Sendable {
    case accepted
    case captureStarted(ApprovalCapturePrompt)
    case resolved(ApprovalDecision)
    case alreadyResolved(ApprovalDecision)
    case rejected(ApprovalSubsessionRejection)
}

public struct ApprovalSubsessionConfiguration: Equatable, Sendable {
    public let requestCapacity: Int
    public let contextCapacity: Int
    public let maximumCaptureAttempts: UInt64
    public let captureWindowSeconds: TimeInterval
    public let maximumRequestLifetimeSeconds: TimeInterval
    public init(requestCapacity: Int = 256, contextCapacity: Int = 256, maximumCaptureAttempts: UInt64 = 3,
                captureWindowSeconds: TimeInterval = 15, maximumRequestLifetimeSeconds: TimeInterval = 300) {
        self.requestCapacity = min(1_024, max(1, requestCapacity)); self.contextCapacity = min(1_024, max(1, contextCapacity))
        self.maximumCaptureAttempts = min(3, max(1, maximumCaptureAttempts))
        self.captureWindowSeconds = captureWindowSeconds.isFinite ? min(15, max(0.01, captureWindowSeconds)) : 15
        self.maximumRequestLifetimeSeconds = maximumRequestLifetimeSeconds.isFinite ? min(300, max(0.01, maximumRequestLifetimeSeconds)) : 300
    }
}

public struct ApprovalSubsessionSnapshot: Equatable, Sendable {
    public let phase: ApprovalSubsessionPhase
    public let context: ApprovalContextToken?
    public let presentation: ApprovalPresentation?
    public let capture: ApprovalCapturePrompt?
    public let decision: ApprovalDecision?
    public let captureAttempts: UInt64
    public let registeredRequestCount: Int
    public let usedContextCount: Int
    public let lastRejection: ApprovalSubsessionRejection?
    public let lastInvalidation: ApprovalContextInvalidation?
}
