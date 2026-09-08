import Foundation

public struct ToolApprovalRequest: Equatable, Sendable {
    public let requestID: String
    public let round: RoundToken
    /// Show this exact action summary before soliciting confirmation. No command is executed here.
    public let actionDescription: String
    public let createdAt: Date
    public let expiresAt: Date
    public init(requestID: String, round: RoundToken, actionDescription: String, createdAt: Date, expiresAt: Date) {
        self.requestID = requestID; self.round = round; self.actionDescription = actionDescription
        self.createdAt = createdAt; self.expiresAt = expiresAt
    }
}

public enum ToolApprovalChoice: String, Codable, Sendable { case approve, deny }
public enum ToolApprovalResolution: String, Codable, Sendable { case approved, denied, expired, invalidated }
public enum ToolApprovalRejection: String, Codable, Sendable {
    case invalidRequest, duplicateRequestID, capacityReached, invalidatedRound, unknownRequest, wrongRound, confirmationRequired, invalidClock
}

/// A typed assertion made by the trusted UI/voice interaction layer, not a model's tool call.
/// A recognizer phrase alone is insufficient: the host must have presented the matching action.
public enum ToolConfirmationEvidence: Sendable { case explicitUserConfirmation, unconfirmed }

public struct ToolApprovalReceipt: Equatable, Sendable {
    public let requestID: String
    public let round: RoundToken
    public let resolution: ToolApprovalResolution
    public let resolvedAt: Date
    public let expiresAt: Date
    public init(requestID: String, round: RoundToken, resolution: ToolApprovalResolution, resolvedAt: Date, expiresAt: Date) {
        self.requestID = requestID; self.round = round; self.resolution = resolution; self.resolvedAt = resolvedAt
        self.expiresAt = expiresAt
    }
}

public enum ToolApprovalRegistration: Equatable, Sendable {
    case registered
    case rejected(ToolApprovalRejection)
}
public enum ToolApprovalResult: Equatable, Sendable {
    /// Only this new resolution may cause the host to send a decision; never execute blindly.
    case resolved(ToolApprovalReceipt)
    /// Idempotent replay. The host must NOT send/execute the decision again.
    case alreadyResolved(ToolApprovalReceipt)
    case rejected(ToolApprovalRejection)
}

/// In-memory at-most-once decision ledger. Persistent/restart-safe delivery belongs to the host.
/// Entries are not evicted: at capacity, registration fails closed instead of permitting ID reuse.
public struct ToolApprovalGate: Sendable {
    public static let maximumRequestIDUTF8Bytes = 1_024
    public static let maximumActionDescriptionUTF8Bytes = 16_384
    private struct Entry: Sendable { let request: ToolApprovalRequest; var receipt: ToolApprovalReceipt? }
    private var entries: [String: Entry] = [:]
    private var invalidatedRounds: Set<RoundToken> = []
    private var refusesNewRegistrations = false
    public let capacity: Int
    public var entryCount: Int { entries.count }
    public var invalidatedRoundCount: Int { invalidatedRounds.count }

    public init(capacity: Int = 1_024) { self.capacity = min(10_000, max(1, capacity)) }

    public mutating func register(_ request: ToolApprovalRequest, now: Date) -> ToolApprovalRegistration {
        guard valid(now), valid(request.createdAt), valid(request.expiresAt),
              validRequestID(request.requestID),
              TextBounds.contains(request.actionDescription, maximumCharacters: 4_096, maximumUTF8Bytes: Self.maximumActionDescriptionUTF8Bytes),
              !request.actionDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.createdAt <= now, request.expiresAt > now, request.createdAt < request.expiresAt else {
            return .rejected(.invalidRequest)
        }
        guard entries[request.requestID] == nil else { return .rejected(.duplicateRequestID) }
        guard !invalidatedRounds.contains(request.round) else { return .rejected(.invalidatedRound) }
        guard !refusesNewRegistrations, entries.count < capacity else { return .rejected(.capacityReached) }
        entries[request.requestID] = Entry(request: request)
        return .registered
    }

    public mutating func resolve(requestID: String, round: RoundToken, choice: ToolApprovalChoice,
                                 evidence: ToolConfirmationEvidence, now: Date) -> ToolApprovalResult {
        guard validRequestID(requestID) else { return .rejected(.invalidRequest) }
        guard var entry = entries[requestID] else { return .rejected(.unknownRequest) }
        // Swift String equality is Unicode-canonical, but server request IDs are opaque UTF-8.
        guard entry.request.requestID.utf8.elementsEqual(requestID.utf8) else { return .rejected(.unknownRequest) }
        guard entry.request.round == round else { return .rejected(.wrongRound) }
        guard valid(now), now >= entry.request.createdAt else { return .rejected(.invalidClock) }
        if let receipt = entry.receipt { return .alreadyResolved(receipt) }
        let resolution: ToolApprovalResolution
        if now >= entry.request.expiresAt { resolution = .expired }
        else {
            guard case .explicitUserConfirmation = evidence else { return .rejected(.confirmationRequired) }
            resolution = choice == .approve ? .approved : .denied
        }
        let receipt = ToolApprovalReceipt(requestID: entry.request.requestID, round: round, resolution: resolution,
                                          resolvedAt: now, expiresAt: entry.request.expiresAt)
        entry.receipt = receipt; entries[requestID] = entry
        return .resolved(receipt)
    }

    /// Call when the machine emits invalidateToolApprovals (interrupt, exit, disconnect, next round).
    @discardableResult
    public mutating func invalidate(round: RoundToken, now: Date) -> [ToolApprovalReceipt] {
        // Record cancellation even before a delayed model tool request has been registered.
        // Never evict tombstones: once full, fail closed for ALL new registrations.
        if !invalidatedRounds.contains(round) {
            if invalidatedRounds.count < capacity { invalidatedRounds.insert(round) }
            else { refusesNewRegistrations = true }
        }
        var receipts: [ToolApprovalReceipt] = []
        for requestID in entries.keys.sorted() {
            guard var entry = entries[requestID], entry.request.round == round, entry.receipt == nil else { continue }
            let resolution: ToolApprovalResolution = valid(now) && now >= entry.request.expiresAt ? .expired : .invalidated
            // Invalidation is fail-closed even if a wall-clock adjustment predates creation.
            let receipt = ToolApprovalReceipt(requestID: entry.request.requestID, round: round, resolution: resolution,
                                              resolvedAt: valid(now) ? now : entry.request.createdAt, expiresAt: entry.request.expiresAt)
            entry.receipt = receipt; entries[requestID] = entry; receipts.append(receipt)
        }
        return receipts
    }

    public func pendingRequest(requestID: String, round: RoundToken, now: Date) -> ToolApprovalRequest? {
        guard valid(now), validRequestID(requestID), let entry = entries[requestID], entry.receipt == nil, entry.request.round == round,
              entry.request.requestID.utf8.elementsEqual(requestID.utf8),
              now >= entry.request.createdAt, now < entry.request.expiresAt else { return nil }
        return entry.request
    }

    private func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
    private func validRequestID(_ id: String) -> Bool {
        TextBounds.contains(id, maximumCharacters: 256, maximumUTF8Bytes: Self.maximumRequestIDUTF8Bytes)
            && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Optional phrase classification only. This function never looks up a request or approves a tool.
public enum VoiceApprovalPhrase {
    public static func classify(_ text: String) -> ToolApprovalChoice? {
        guard TextBounds.contains(text, maximumCharacters: 64, maximumUTF8Bytes: 256) else { return nil }
        let exact = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch exact {
        case "批准", "批准了", "确认批准", "approve", "i approve": return .approve
        case "拒绝", "不批准", "取消批准", "deny", "i deny": return .deny
        default: return nil
        }
    }
}

/// Serializes resolution races from UI, ASR and deadline callbacks.
public actor ToolApprovalCoordinator {
    private var gate: ToolApprovalGate
    public init(capacity: Int = 1_024) { gate = .init(capacity: capacity) }
    public func register(_ request: ToolApprovalRequest, now: Date) -> ToolApprovalRegistration {
        gate.register(request, now: now)
    }
    public func resolve(requestID: String, round: RoundToken, choice: ToolApprovalChoice,
                        evidence: ToolConfirmationEvidence, now: Date) -> ToolApprovalResult {
        gate.resolve(requestID: requestID, round: round, choice: choice, evidence: evidence, now: now)
    }
    public func invalidate(round: RoundToken, now: Date) -> [ToolApprovalReceipt] { gate.invalidate(round: round, now: now) }
    public func pendingRequest(requestID: String, round: RoundToken, now: Date) -> ToolApprovalRequest? {
        gate.pendingRequest(requestID: requestID, round: round, now: now)
    }
}
