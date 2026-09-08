import XCTest
@testable import RayNeoDisplay

final class PendingSuggestionCardRegistryTests: XCTestCase {
    private enum FixtureError: Error { case unexpectedResult }

    func card(_ uid: String = "synthetic-pending", category: SuggestionCardCategory = .todo,
              content: String = "No tool execution") -> SuggestionCardAppRequest {
        .add(suggestUID: uid, suggestType: category, title: "Synthetic", source: "Local test",
             content: content, timeRange: nil)
    }

    func operation(_ uid: String = "synthetic-pending", type: Int64 = 2,
                   cmd: Int64 = 1) throws -> SuggestionOperationObserved {
        let json = try JSONSerialization.data(withJSONObject: ["suggestUID": uid, "suggestType": type, "cmd": cmd])
        guard case .operation(let operation) = try SuggestionJSONCodec(unknownCommandPolicy: .retainUnknown)
            .decodeGlassesOperation(type: 34, payload: json) else { throw FixtureError.unexpectedResult }
        return operation
    }

    func record(_ result: SuggestionCardRegistrationResult) throws -> RegisteredSuggestionCard {
        guard case .registered(let record) = result else { throw FixtureError.unexpectedResult }
        return record
    }

    func testCannotRegisterOrObserveBeforeExplicitConnection() async throws {
        let registry = PendingSuggestionCardRegistry()
        let registration = try await registry.register(card(), generation: 1, now: 10, expiresAt: 20)
        let observation = await registry.observe(try operation(), generation: 1, now: 11)
        XCTAssertEqual(registration, .rejected(.noOpenConnection))
        XCTAssertEqual(observation, .rejected(.noOpenConnection))
        let snapshot = await registry.snapshot()
        XCTAssertNil(snapshot.lastConnectionGeneration)
        XCTAssertNil(snapshot.lastObservedTick)
        XCTAssertEqual(snapshot.registeredCards, 0)
    }

    func testConnectionGenerationMustStrictlyIncrease() async throws {
        let registry = PendingSuggestionCardRegistry()
        let first = await registry.openConnection(generation: 10)
        let same = await registry.openConnection(generation: 10)
        let older = await registry.openConnection(generation: 9)
        XCTAssertEqual(first, .opened(generation: 10, invalidatedPending: 0))
        XCTAssertEqual(same, .rejected(.generationMustIncrease))
        XCTAssertEqual(older, .rejected(.generationMustIncrease))
        _ = try await registry.register(card(), generation: 10, now: 1, expiresAt: 9)
        let newer = await registry.openConnection(generation: 11)
        XCTAssertEqual(newer, .opened(generation: 11, invalidatedPending: 1))
        let wrongDisconnect = await registry.disconnect(generation: 10)
        XCTAssertEqual(wrongDisconnect, .rejected(.generationMismatch))
        let snapshot = await registry.snapshot()
        XCTAssertTrue(snapshot.connectionOpen)
        XCTAssertEqual(snapshot.terminalCards[.invalidated], 1)
        XCTAssertEqual(snapshot.registeredCards, 1)
    }

    func testRegistrationRetainsExactImmutableEncodedCard() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        let request = card("synthetic-e\u{301}", content: "A中🙂B\r\n")
        let registered = try record(await registry.register(request, generation: 1, now: 10, expiresAt: 50))
        let expected = try SuggestionCardJSONCodec().encodeAppRequest(request)
        XCTAssertEqual(registered.encodedMessage, expected)
        XCTAssertEqual(registered.uid, WireTextIdentity("synthetic-e\u{301}"))
        XCTAssertEqual(registered.connectionGeneration, 1)
        XCTAssertEqual(registered.registeredAt, 10)
        XCTAssertEqual(registered.expiresAt, 50)
        var callerCopy = registered.encodedMessage.payload
        callerCopy.append(0)
        let result = await registry.observe(try operation("synthetic-e\u{301}"), generation: 1, now: 11)
        guard case .decision(let decision) = result else { return XCTFail() }
        XCTAssertEqual(decision.card.encodedMessage, expected)
        XCTAssertNotEqual(decision.card.encodedMessage.payload, callerCopy)
    }

    func testAcceptProducesOneDecisionThenOnlyProcessedStatus() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 20)
        let first = await registry.observe(try operation(), generation: 1, now: 2)
        guard case .decision(let decision) = first else { return XCTFail() }
        XCTAssertEqual(decision.choice, .accept)
        XCTAssertEqual(decision.observedAt, 2)
        let duplicate = await registry.observe(try operation(), generation: 1, now: 3)
        let contrary = await registry.observe(try operation(cmd: 2), generation: 1, now: 4)
        let unknown = await registry.observe(try operation(cmd: 99), generation: 1, now: 5)
        XCTAssertEqual(duplicate, .alreadyProcessed(.accepted))
        XCTAssertEqual(contrary, .alreadyProcessed(.accepted))
        XCTAssertEqual(unknown, .rejected(.unknownCommand(99)))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.pendingCards, 0)
        XCTAssertEqual(snapshot.terminalCards[.accepted], 1)
    }

    func testRejectConsumesWithoutAnAcceptDecisionLater() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 20)
        let first = await registry.observe(try operation(cmd: 2), generation: 1, now: 2)
        guard case .decision(let decision) = first else { return XCTFail() }
        XCTAssertEqual(decision.choice, .reject)
        let replay = await registry.observe(try operation(), generation: 1, now: 3)
        XCTAssertEqual(replay, .alreadyProcessed(.rejected))
    }

    func testNfcNfdIdentifiersCannotAliasOrConsumeEachOther() async throws {
        let registry = PendingSuggestionCardRegistry()
        let composed = "synthetic-é"
        let decomposed = "synthetic-e\u{301}"
        XCTAssertEqual(composed, decomposed)
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(composed), generation: 1, now: 1, expiresAt: 30)
        let alias = await registry.observe(try operation(decomposed), generation: 1, now: 2)
        XCTAssertEqual(alias, .rejected(.unknownIdentifier))
        _ = try record(await registry.register(card(decomposed), generation: 1, now: 3, expiresAt: 30))
        let own = await registry.observe(try operation(decomposed), generation: 1, now: 4)
        guard case .decision(let decision) = own else { return XCTFail() }
        XCTAssertTrue(WireTextIdentity.matches(decision.card.uid.rawValue, decomposed))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 2)
        XCTAssertEqual(snapshot.pendingCards, 1)
    }

    func testWrongTypeAndUnknownCmdDoNotConsumePendingCard() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 20)
        let typeMismatch = await registry.observe(try operation(type: 1), generation: 1, now: 2)
        let unknown = await registry.observe(try operation(cmd: 99), generation: 1, now: 3)
        XCTAssertEqual(typeMismatch, .rejected(.suggestTypeMismatch))
        XCTAssertEqual(unknown, .rejected(.unknownCommand(99)))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.pendingCards, 1)
        let valid = await registry.observe(try operation(), generation: 1, now: 4)
        guard case .decision = valid else { return XCTFail() }
    }

    func testWrongGenerationCannotChangeClockOrCardState() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 7)
        _ = try await registry.register(card(), generation: 7, now: 10, expiresAt: 30)
        let wrong = await registry.observe(try operation(), generation: 6, now: UInt64.max)
        XCTAssertEqual(wrong, .rejected(.generationMismatch))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.lastObservedTick, 10)
        XCTAssertEqual(snapshot.pendingCards, 1)
        let valid = await registry.observe(try operation(), generation: 7, now: 11)
        guard case .decision = valid else { return XCTFail() }
    }

    func testUnknownIdentifierNeverCreatesARecord() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        let result = await registry.observe(try operation(), generation: 1, now: 1)
        XCTAssertEqual(result, .rejected(.unknownIdentifier))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 0)
        XCTAssertEqual(snapshot.totalEncodedBytes, 0)
    }

    func testExpiryBoundaryAndRepeatedExpiryAreNotDecisions() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card("before"), generation: 1, now: 10, expiresAt: 20)
        _ = try await registry.register(card("at"), generation: 1, now: 10, expiresAt: 20)
        let before = await registry.observe(try operation("before"), generation: 1, now: 19)
        guard case .decision = before else { return XCTFail() }
        let at = await registry.observe(try operation("at"), generation: 1, now: 20)
        let again = await registry.observe(try operation("at"), generation: 1, now: 21)
        XCTAssertEqual(at, .expired)
        XCTAssertEqual(again, .alreadyProcessed(.expired))
    }

    func testInvalidExpiryDoesNotReserveUID() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        for expiry: UInt64 in [0, 9, 10] {
            let invalid = try await registry.register(card(), generation: 1, now: 10, expiresAt: expiry)
            XCTAssertEqual(invalid, .rejected(.expiryMustFollowRegistration))
        }
        let before = await registry.snapshot()
        XCTAssertEqual(before.registeredCards, 0)
        _ = try record(await registry.register(card(), generation: 1, now: 10, expiresAt: 11))
    }

    func testUInt64TickAndGenerationUpperBoundsDoNotOverflow() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: UInt64.max)
        _ = try await registry.register(card(), generation: UInt64.max, now: UInt64.max - 1, expiresAt: UInt64.max)
        let expiry = await registry.observe(try operation(), generation: UInt64.max, now: UInt64.max)
        let noFuture = await registry.openConnection(generation: 0)
        XCTAssertEqual(expiry, .expired)
        XCTAssertEqual(noFuture, .rejected(.generationMustIncrease))
    }

    func testClockBeforeRegistrationFailsClosedAndDoesNotConsume() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 10, expiresAt: 30)
        let rollback = await registry.observe(try operation(), generation: 1, now: 9)
        let invalidSweep = await registry.expirePending(generation: 1, now: 8)
        XCTAssertEqual(rollback, .rejected(.clockMovedBackwards))
        XCTAssertEqual(invalidSweep, .rejected(.clockMovedBackwards))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.lastObservedTick, 10)
        XCTAssertEqual(snapshot.pendingCards, 1)
        let valid = await registry.observe(try operation(), generation: 1, now: 11)
        guard case .decision = valid else { return XCTFail() }
    }

    func testClockWatermarkPersistsAcrossGenerations() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card("first"), generation: 1, now: 100, expiresAt: 200)
        _ = await registry.openConnection(generation: 2)
        let rollback = try await registry.register(card("second"), generation: 2, now: 99, expiresAt: 200)
        XCTAssertEqual(rollback, .rejected(.clockMovedBackwards))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.lastObservedTick, 100)
        XCTAssertEqual(snapshot.registeredCards, 1)
    }

    func testDisconnectPreventsLateRegistrationAndObserveFromReviving() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 50)
        let closed = await registry.disconnect(generation: 1)
        let lateRegistration = try await registry.register(card("late"), generation: 1, now: 2, expiresAt: 50)
        let lateOperation = await registry.observe(try operation(), generation: 1, now: 2)
        let repeatedClose = await registry.disconnect(generation: 1)
        let reopen = await registry.openConnection(generation: 1)
        XCTAssertEqual(closed, .closed(invalidatedPending: 1))
        XCTAssertEqual(lateRegistration, .rejected(.noOpenConnection))
        XCTAssertEqual(lateOperation, .rejected(.noOpenConnection))
        XCTAssertEqual(repeatedClose, .alreadyClosed)
        XCTAssertEqual(reopen, .rejected(.generationMustIncrease))
        let snapshot = await registry.snapshot()
        XCTAssertFalse(snapshot.connectionOpen)
        XCTAssertEqual(snapshot.registeredCards, 1)
        XCTAssertEqual(snapshot.terminalCards[.invalidated], 1)
    }

    func testUsedUidCannotBeReusedAcrossTypeContentExpiryOrGeneration() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 20)
        _ = await registry.observe(try operation(), generation: 1, now: 2)
        for request in [card(), card(category: .calendar), card(content: "changed")] {
            let retry = try await registry.register(request, generation: 1, now: 3, expiresAt: 999)
            XCTAssertEqual(retry, .rejected(.identifierAlreadyUsed))
        }
        _ = await registry.openConnection(generation: 2)
        let crossGeneration = try await registry.register(card(), generation: 2, now: 4, expiresAt: 999)
        let relabeledOldPacket = await registry.observe(try operation(), generation: 2, now: 5)
        XCTAssertEqual(crossGeneration, .rejected(.identifierAlreadyUsed))
        XCTAssertEqual(relabeledOldPacket, .rejected(.recordGenerationMismatch))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 1)
    }

    func testExplicitExpirationRetainsTombstonesAndCounts() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card("a"), generation: 1, now: 1, expiresAt: 10)
        _ = try await registry.register(card("b"), generation: 1, now: 1, expiresAt: 20)
        _ = try await registry.register(card("c"), generation: 1, now: 1, expiresAt: 30)
        let expiration = await registry.expirePending(generation: 1, now: 20)
        let duplicate = await registry.expirePending(generation: 1, now: 20)
        XCTAssertEqual(expiration, .expired(count: 2))
        XCTAssertEqual(duplicate, .expired(count: 0))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 3)
        XCTAssertEqual(snapshot.pendingCards, 1)
        XCTAssertEqual(snapshot.terminalCards[.expired], 2)
        let cannotReuse = try await registry.register(card("a"), generation: 1, now: 21, expiresAt: 50)
        XCTAssertEqual(cannotReuse, .rejected(.identifierAlreadyUsed))
    }

    func testRecordCapacityIncludesConsumedAndCrossGenerationHistory() async throws {
        let registry = PendingSuggestionCardRegistry(limits: try PendingSuggestionCardLimits(
            maxRegisteredCards: 1, maxTotalEncodedBytes: 4096
        ))
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card("first"), generation: 1, now: 1, expiresAt: 20)
        _ = await registry.observe(try operation("first"), generation: 1, now: 2)
        let full = try await registry.register(card("second"), generation: 1, now: 3, expiresAt: 20)
        _ = await registry.openConnection(generation: 2)
        let stillFull = try await registry.register(card("third"), generation: 2, now: 4, expiresAt: 20)
        XCTAssertEqual(full, .rejected(.recordCapacityReached))
        XCTAssertEqual(stillFull, .rejected(.recordCapacityReached))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 1)
        XCTAssertEqual(snapshot.terminalCards[.accepted], 1)
    }

    func testEncodedByteCapacityIsExactAndNeverFreesTerminalRecords() async throws {
        let first = card("first")
        let byteCount = try SuggestionCardJSONCodec().encodeAppRequest(first).payload.count
        let registry = PendingSuggestionCardRegistry(limits: try PendingSuggestionCardLimits(
            maxRegisteredCards: 10, maxTotalEncodedBytes: byteCount
        ))
        _ = await registry.openConnection(generation: 1)
        _ = try record(await registry.register(first, generation: 1, now: 1, expiresAt: 2))
        _ = await registry.expirePending(generation: 1, now: 2)
        let full = try await registry.register(card("other"), generation: 1, now: 2, expiresAt: 20)
        XCTAssertEqual(full, .rejected(.encodedByteCapacityReached))
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.totalEncodedBytes, byteCount)
        XCTAssertEqual(snapshot.registeredCards, 1)
    }

    func testInvalidCardAndDeleteDoNotReserveUid() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        let deletion = try await registry.register(.delete(suggestUID: "d", suggestType: .todo),
                                                   generation: 1, now: 1, expiresAt: 10)
        XCTAssertEqual(deletion, .rejected(.onlyAddCardsCanBeRegistered))
        do {
            _ = try await registry.register(.add(suggestUID: "d", suggestType: .todo,
                title: "", source: "", content: "", timeRange: "not established"),
                generation: 1, now: 1, expiresAt: 10)
            XCTFail("Expected stricter codec rejection")
        } catch {
            XCTAssertEqual(error as? SuggestionCardEncodingError, .unverifiedTimeRangeForTodo)
        }
        let before = await registry.snapshot()
        XCTAssertEqual(before.registeredCards, 0)
        _ = try record(await registry.register(card("d"), generation: 1, now: 1, expiresAt: 10))
    }

    func testConcurrentSameOperationCanProduceOnlyOneDecision() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        _ = try await registry.register(card(), generation: 1, now: 1, expiresAt: 20)
        let event = try operation()
        let results = await withTaskGroup(of: SuggestionCardObservationResult.self, returning: [SuggestionCardObservationResult].self) { group in
            for _ in 0..<128 { group.addTask { await registry.observe(event, generation: 1, now: 2) } }
            var results: [SuggestionCardObservationResult] = []
            for await result in group { results.append(result) }
            return results
        }
        let decisions = results.filter { if case .decision = $0 { return true }; return false }
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(results.filter { $0 == .alreadyProcessed(.accepted) }.count, 127)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.pendingCards, 0)
        XCTAssertEqual(snapshot.terminalCards[.accepted], 1)
    }

    func testConcurrentSameUidRegistrationReservesOnlyOnce() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        let request = card()
        let results = try await withThrowingTaskGroup(of: SuggestionCardRegistrationResult.self, returning: [SuggestionCardRegistrationResult].self) { group in
            for _ in 0..<64 {
                group.addTask { try await registry.register(request, generation: 1, now: 1, expiresAt: 20) }
            }
            var results: [SuggestionCardRegistrationResult] = []
            for try await result in group { results.append(result) }
            return results
        }
        let registered = results.filter { if case .registered = $0 { return true }; return false }
        XCTAssertEqual(registered.count, 1)
        XCTAssertEqual(results.filter { $0 == .rejected(.identifierAlreadyUsed) }.count, 63)
        let snapshot = await registry.snapshot()
        XCTAssertEqual(snapshot.registeredCards, 1)
    }

    func testRegistryValidatesIdentifierEvenForConstructedObservation() async throws {
        let registry = PendingSuggestionCardRegistry()
        _ = await registry.openConnection(generation: 1)
        let bad = SuggestionOperationObserved(suggestUID: "", suggestType: 2, command: .accept)
        let result = await registry.observe(bad, generation: 1, now: 1)
        XCTAssertEqual(result, .rejected(.invalidIdentifier))
    }

    func testInvalidRegistryLimitsAreRejected() {
        XCTAssertThrowsError(try PendingSuggestionCardLimits(maxRegisteredCards: 0, maxTotalEncodedBytes: 1))
        XCTAssertThrowsError(try PendingSuggestionCardLimits(maxRegisteredCards: 1, maxTotalEncodedBytes: 0))
        XCTAssertThrowsError(try PendingSuggestionCardLimits(maxRegisteredCards: -1, maxTotalEncodedBytes: 1))
    }
}
