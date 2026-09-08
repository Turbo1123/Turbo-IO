import Foundation

public enum PendingSuggestionCardError: Error, Equatable, Sendable {
    case invalidLimits
}

/// Includes pending records AND every terminal record/UID tombstone for the
/// actor's entire lifetime. No generation change evicts this history.
public struct PendingSuggestionCardLimits: Equatable, Sendable {
    public let maxRegisteredCards: Int
    public let maxTotalEncodedBytes: Int
    public static let conservative = PendingSuggestionCardLimits(uncheckedCards: 128, bytes: 1_048_576)

    public init(maxRegisteredCards: Int, maxTotalEncodedBytes: Int) throws {
        guard maxRegisteredCards > 0, maxTotalEncodedBytes > 0 else {
            throw PendingSuggestionCardError.invalidLimits
        }
        self.init(uncheckedCards: maxRegisteredCards, bytes: maxTotalEncodedBytes)
    }

    private init(uncheckedCards: Int, bytes: Int) {
        maxRegisteredCards = uncheckedCards
        maxTotalEncodedBytes = bytes
    }
}

/// All times are explicit UInt64 ticks from one host monotonic source. The host
/// selects the unit and expiry; there is no default TTL or epoch conversion.
public struct RegisteredSuggestionCard: Equatable, Sendable {
    public let uid: WireTextIdentity
    public let suggestType: SuggestionCardCategory
    /// Host connection epoch, NOT a wire field; bind at actual transport receipt.
    public let connectionGeneration: UInt64
    public let registeredAt: UInt64
    public let expiresAt: UInt64
    /// Exact immutable type-33 JSON generated at registration, not a later edit.
    public let encodedMessage: DisplayJSONMessage
}

public enum SuggestionCardChoice: String, Equatable, Sendable {
    case accept
    case reject
}

/// A single card-domain decision. It confers no tool authorization, actual
/// presentation proof, account permission, or right to execute external work.
public struct SuggestionCardDecision: Equatable, Sendable {
    public let choice: SuggestionCardChoice
    public let card: RegisteredSuggestionCard
    public let observedAt: UInt64
}

public enum SuggestionCardTerminalState: String, Equatable, Hashable, Sendable {
    case accepted
    case rejected
    case expired
    case invalidated
}

public enum SuggestionCardRegistryRejection: Equatable, Sendable {
    case noOpenConnection
    case generationMismatch
    case generationMustIncrease
    case clockMovedBackwards
    case expiryMustFollowRegistration
    case onlyAddCardsCanBeRegistered
    case invalidIdentifier
    case identifierAlreadyUsed
    case recordCapacityReached
    case encodedByteCapacityReached
    case unknownIdentifier
    case recordGenerationMismatch
    case suggestTypeMismatch
    case unknownCommand(Int64)
}

public enum SuggestionCardConnectionResult: Equatable, Sendable {
    case opened(generation: UInt64, invalidatedPending: Int)
    case rejected(SuggestionCardRegistryRejection)
}

public enum SuggestionCardDisconnectResult: Equatable, Sendable {
    case closed(invalidatedPending: Int)
    case alreadyClosed
    case rejected(SuggestionCardRegistryRejection)
}

public enum SuggestionCardRegistrationResult: Equatable, Sendable {
    case registered(RegisteredSuggestionCard)
    case rejected(SuggestionCardRegistryRejection)
}

public enum SuggestionCardObservationResult: Equatable, Sendable {
    case decision(SuggestionCardDecision)
    /// Status only, deliberately NOT another decision or the previous decision.
    case alreadyProcessed(SuggestionCardTerminalState)
    case expired
    case rejected(SuggestionCardRegistryRejection)
}

public enum SuggestionCardExpirationResult: Equatable, Sendable {
    case expired(count: Int)
    case rejected(SuggestionCardRegistryRejection)
}

public struct SuggestionCardRegistrySnapshot: Equatable, Sendable {
    public let lastConnectionGeneration: UInt64?
    public let connectionOpen: Bool
    public let lastObservedTick: UInt64?
    public let registeredCards: Int
    public let pendingCards: Int
    public let terminalCards: [SuggestionCardTerminalState: Int]
    public let totalEncodedBytes: Int
}

/// Atomic, bounded, in-memory association of cards and operations. Each method
/// performs its complete check-and-transition with NO internal await. There are
/// no transports, clocks, timers, automatic ACKs, or execution adapters.
///
/// Used UID records never evict, including on reconnect; capacity exhaustion is
/// fail-closed. Across process/actor lifetimes the host MUST use globally fresh
/// random UIDs or a persisted used-UID ledger. Do not relabel an old receive event
/// with the current generation; capture its epoch at the real transport boundary.
public actor PendingSuggestionCardRegistry {
    private enum State {
        case pending
        case terminal(SuggestionCardTerminalState)
    }
    private struct Entry {
        let card: RegisteredSuggestionCard
        var state: State
    }

    public let limits: PendingSuggestionCardLimits
    private let codec: SuggestionCardJSONCodec
    private var generation: UInt64?
    private var connectionOpen = false
    private var lastTick: UInt64?
    private var records: [WireTextIdentity: Entry] = [:]
    private var totalEncodedBytes = 0

    public init(limits: PendingSuggestionCardLimits = .conservative,
                payloadLimits: DisplayPayloadLimits = .conservative) {
        self.limits = limits
        codec = SuggestionCardJSONCodec(limits: payloadLimits)
    }

    /// Trusted host lifecycle input only. Does not clear UID history or clock.
    public func openConnection(generation next: UInt64) -> SuggestionCardConnectionResult {
        if let generation, next <= generation { return .rejected(.generationMustIncrease) }
        let invalidated = invalidatePending()
        generation = next
        connectionOpen = true
        return .opened(generation: next, invalidatedPending: invalidated)
    }

    public func disconnect(generation incoming: UInt64) -> SuggestionCardDisconnectResult {
        guard generation == incoming else { return .rejected(.generationMismatch) }
        guard connectionOpen else { return .alreadyClosed }
        connectionOpen = false
        return .closed(invalidatedPending: invalidatePending())
    }

    /// Only a successful first registration reserves a UID and returns its
    /// immutable record. Invalid expiry/card input does not create a pending item.
    public func register(_ request: SuggestionCardAppRequest, generation incoming: UInt64,
                         now: UInt64, expiresAt: UInt64) throws -> SuggestionCardRegistrationResult {
        if let error = connectionError(incoming) { return .rejected(error) }
        guard advanceClock(now) else { return .rejected(.clockMovedBackwards) }
        guard expiresAt > now else { return .rejected(.expiryMustFollowRegistration) }
        guard case .add(let rawUID, let category, _, _, _, _) = request else {
            return .rejected(.onlyAddCardsCanBeRegistered)
        }
        try validateIdentifier(rawUID, key: "suggestUID", limits: codec.limits)
        let uid = WireTextIdentity(rawUID)
        guard records[uid] == nil else { return .rejected(.identifierAlreadyUsed) }
        guard records.count < limits.maxRegisteredCards else { return .rejected(.recordCapacityReached) }
        let message = try codec.encodeAppRequest(request)
        guard message.payload.count <= limits.maxTotalEncodedBytes,
              totalEncodedBytes <= limits.maxTotalEncodedBytes - message.payload.count else {
            return .rejected(.encodedByteCapacityReached)
        }
        let card = RegisteredSuggestionCard(
            uid: uid, suggestType: category, connectionGeneration: incoming,
            registeredAt: now, expiresAt: expiresAt, encodedMessage: message
        )
        records[uid] = Entry(card: card, state: .pending)
        totalEncodedBytes += message.payload.count
        return .registered(card)
    }

    /// Consumes a matching known operation at most once. Unknown/mismatched
    /// events do not consume the card or turn into a user rejection/acceptance.
    public func observe(_ operation: SuggestionOperationObserved, generation incoming: UInt64,
                        now: UInt64) -> SuggestionCardObservationResult {
        if let error = connectionError(incoming) { return .rejected(error) }
        guard advanceClock(now) else { return .rejected(.clockMovedBackwards) }
        do {
            try validateIdentifier(operation.suggestUID, key: "suggestUID", limits: codec.limits)
        } catch {
            return .rejected(.invalidIdentifier)
        }
        let uid = WireTextIdentity(operation.suggestUID)
        guard var entry = records[uid] else { return .rejected(.unknownIdentifier) }
        guard entry.card.connectionGeneration == incoming else { return .rejected(.recordGenerationMismatch) }
        guard entry.card.suggestType.rawValue == operation.suggestType else { return .rejected(.suggestTypeMismatch) }
        guard now >= entry.card.registeredAt else { return .rejected(.clockMovedBackwards) }
        let choice: SuggestionCardChoice
        let terminal: SuggestionCardTerminalState
        switch operation.command {
        case .accept: choice = .accept; terminal = .accepted
        case .reject: choice = .reject; terminal = .rejected
        case .unknown(let raw): return .rejected(.unknownCommand(raw))
        }
        if case .terminal(let state) = entry.state { return .alreadyProcessed(state) }
        if now >= entry.card.expiresAt {
            entry.state = .terminal(.expired)
            records[uid] = entry
            return .expired
        }
        // No await or externally callable effect between this check and consume.
        entry.state = .terminal(terminal)
        records[uid] = entry
        return .decision(SuggestionCardDecision(choice: choice, card: entry.card, observedAt: now))
    }

    /// Explicit host maintenance; observe independently enforces expiry too.
    public func expirePending(generation incoming: UInt64, now: UInt64) -> SuggestionCardExpirationResult {
        if let error = connectionError(incoming) { return .rejected(error) }
        guard advanceClock(now) else { return .rejected(.clockMovedBackwards) }
        var count = 0
        for uid in Array(records.keys) {
            guard var entry = records[uid], case .pending = entry.state,
                  entry.card.connectionGeneration == incoming, now >= entry.card.expiresAt else { continue }
            entry.state = .terminal(.expired)
            records[uid] = entry
            count += 1
        }
        return .expired(count: count)
    }

    /// Counts only; no implicit expiry, mutation, unredacted log or I/O.
    public func snapshot() -> SuggestionCardRegistrySnapshot {
        var pending = 0
        var terminal: [SuggestionCardTerminalState: Int] = [:]
        for entry in records.values {
            switch entry.state {
            case .pending: pending += 1
            case .terminal(let state): terminal[state, default: 0] += 1
            }
        }
        return SuggestionCardRegistrySnapshot(
            lastConnectionGeneration: generation, connectionOpen: connectionOpen,
            lastObservedTick: lastTick, registeredCards: records.count, pendingCards: pending,
            terminalCards: terminal, totalEncodedBytes: totalEncodedBytes
        )
    }

    private func connectionError(_ incoming: UInt64) -> SuggestionCardRegistryRejection? {
        guard connectionOpen else { return .noOpenConnection }
        guard generation == incoming else { return .generationMismatch }
        return nil
    }

    private func advanceClock(_ now: UInt64) -> Bool {
        if let lastTick, now < lastTick { return false }
        lastTick = now
        return true
    }

    private func invalidatePending() -> Int {
        var count = 0
        for uid in Array(records.keys) {
            guard var entry = records[uid], case .pending = entry.state else { continue }
            entry.state = .terminal(.invalidated)
            records[uid] = entry
            count += 1
        }
        return count
    }
}
