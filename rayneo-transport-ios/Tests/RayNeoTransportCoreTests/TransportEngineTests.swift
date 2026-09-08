import Foundation
import Testing
@testable import RayNeoTransportCore

@MainActor private final class FakePort: TransportPort {
    var receive: (@MainActor (UUID, NativeEvent) -> Void)?
    var token = UUID()
    var effects: [NativeEffect] = []
    var bleWrites: [(Data, UUID, BLEWriteMode)] = []
    var maximum = 512
    var canWriteWithoutResponse = true
    var chunks: [Data] = []
    var readResult: Int?
    var outputAvailable = true
    var output = Data()
    var writeResults: [Int] = []
    var writeAlwaysZero = false
    var writeCalls = 0
    var onBLEWrite: (@MainActor (UUID) -> Void)?
    var onStreamWrite: (@MainActor () -> Void)?
    func perform(_ effect: NativeEffect) {
        effects.append(effect)
        if case let .prepare(g, _) = effect { token = g }
    }
    func send(_ event: NativeEvent, token: UUID? = nil) { receive?(token ?? self.token, event) }
    func maximumWriteLength(_ mode: BLEWriteMode) -> Int { maximum }
    func writeBLE(_ bytes: Data, characteristic: UUID, mode: BLEWriteMode) {
        bleWrites.append((bytes, characteristic, mode)); onBLEWrite?(characteristic)
    }
    var inputAvailable: Bool { !chunks.isEmpty || readResult != nil }
    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        if let value = readResult { readResult = nil; return value }
        guard !chunks.isEmpty else { return 0 }
        let n = min(buffer.count, chunks[0].count)
        for (index, byte) in chunks[0].prefix(n).enumerated() { buffer[index] = byte }
        chunks[0].removeFirst(n)
        if chunks[0].isEmpty { chunks.removeFirst() }
        return n
    }
    func write(_ bytes: UnsafeBufferPointer<UInt8>) -> Int {
        writeCalls += 1
        let n = writeAlwaysZero ? 0 : (writeResults.isEmpty ? bytes.count : writeResults.removeFirst())
        if n > 0 && n <= bytes.count { output.append(contentsOf: bytes.prefix(n)) }
        onStreamWrite?()
        return n
    }
}
@MainActor private final class Rig {
    let port = FakePort()
    var now: UInt64 = 1_000_000_000
    var engine: TransportEngine!
    init(_ kind: TransportKind = .bluetooth, limits: TransportLimits = try! .init()) {
        engine = TransportEngine(kind: kind, limits: limits, port: port, clock: { [weak self] in self?.now ?? 0 })
    }
    func drain() throws -> [TransportEvent] { try engine.drainEvents(maxCount: engine.limits.events) }
    func ble(_ properties: CharacteristicProperties = [.write, .writeWithoutResponse]) throws -> (CharacteristicHandle, CharacteristicHandle) {
        try engine.prepare(); port.send(.central(.poweredOn)); _ = try drain()
        try engine.startScan(); port.send(.candidate(UUID())); engine.stopScan(); _ = try drain()
        try engine.connect(engine.snapshotCandidates()[0].handle); port.send(.connected); _ = try drain()
        try engine.discover()
        port.send(.characteristics([
            .init(id: UUID(), uuid: RayNeoIOProfile.outbound, properties: properties),
            .init(id: UUID(), uuid: RayNeoIOProfile.inbound, properties: [.notify])
        ])); _ = try drain()
        let result = engine.snapshotCharacteristics()
        return (result[0].handle, result[1].handle)
    }
    func ea() throws {
        try engine.refreshCandidates(); port.send(.candidate(UUID())); _ = try drain()
        try engine.open(engine.snapshotCandidates()[0].handle)
        port.send(.streamsOpen(input: true)); port.send(.streamsOpen(input: false)); _ = try drain()
    }
}

@Suite @MainActor struct TransportEngineTests {
    @Test func initHasNoNativeEffects() throws {
        let r = Rig(); #expect(r.port.effects.isEmpty); #expect(r.engine.snapshot.phase == .idle)
        #expect(throws: TransportError.invalidState) { try r.engine.startScan() }
    }
    @Test func prepareAndPowerChangesNeverScan() throws {
        let r = Rig(); try r.engine.prepare(); r.port.send(.central(.poweredOff)); r.port.send(.central(.poweredOn))
        #expect(r.port.effects.count == 1); #expect(r.engine.snapshot.phase == .prepared)
    }
    @Test func permissionsAndWrongKindFailClosed() throws {
        let r = Rig(); try r.engine.prepare(); r.port.send(.central(.unauthorized))
        #expect(throws: TransportError.poweredOff) { try r.engine.startScan() }
        #expect(throws: TransportError.wrongKind) { try r.engine.refreshCandidates() }
        let ea = Rig(.externalAccessory); #expect(throws: TransportError.wrongKind) { try ea.engine.prepare() }
    }
    @Test func scanLimitAndLateDiscover() throws {
        let r = Rig(limits: try .init(candidates: 1)); try r.engine.prepare(); r.port.send(.central(.poweredOn)); try r.engine.startScan()
        let id = UUID(); r.port.send(.candidate(id)); r.port.send(.candidate(id)); r.port.send(.candidate(UUID()))
        #expect(r.engine.snapshot.phase == .prepared); #expect(r.engine.snapshotCandidates().count == 1)
        r.port.send(.candidate(UUID())); #expect(r.engine.snapshotCandidates().count == 1)
    }
    @Test func scanTimeoutDoesNotConnect() throws {
        let r = Rig(); try r.engine.prepare(); r.port.send(.central(.poweredOn)); try r.engine.startScan(timeout: 1)
        r.now += 1_000_000_000; r.port.send(.deadline)
        #expect(r.engine.snapshot.phase == .prepared)
        #expect(!r.port.effects.contains { if case .connect = $0 { true } else { false } })
    }
    @Test func handleFromOtherInstanceRejected() throws {
        let a = Rig(), b = Rig(); let handles = try a.ble(); _ = try b.ble()
        #expect(throws: TransportError.staleHandle) { try b.engine.write(Data([1]), to: handles.0, mode: .withResponse) }
    }
    @Test func oldGenerationCallbacksAndHandlesIgnored() throws {
        let r = Rig(); let handles = try r.ble(); let old = r.port.token
        r.engine.close(); _ = try r.drain(); try r.engine.prepare()
        r.port.send(.connected, token: old); r.port.send(.failure(.nativeFailure), token: old)
        #expect(r.engine.snapshot.phase == .prepared)
        r.port.send(.central(.poweredOn)); try r.engine.startScan(); r.port.send(.candidate(UUID())); r.engine.stopScan(); _ = try r.drain()
        try r.engine.connect(r.engine.snapshotCandidates()[0].handle); r.port.send(.connected); try r.engine.discover()
        #expect(throws: TransportError.invalidState) { try r.engine.write(Data([1]), to: handles.0, mode: .withResponse) }
    }
    @Test func connectDoesNotDiscoverAndDiscoverDoesNotSubscribe() throws {
        let r = Rig(); _ = try r.ble()
        #expect(!r.port.effects.contains { if case .subscribe = $0 { true } else { false } })
        #expect(r.port.bleWrites.isEmpty)
    }
    @Test func duplicateAndMissingCharacteristicsReject() throws {
        for duplicate in [false, true] {
            let r = Rig(); _ = try r.ble(); r.engine.close(); _ = try r.drain()
            try r.engine.prepare(); r.port.send(.central(.poweredOn)); try r.engine.startScan(); r.port.send(.candidate(UUID())); r.engine.stopScan(); _ = try r.drain()
            try r.engine.connect(r.engine.snapshotCandidates()[0].handle); r.port.send(.connected); try r.engine.discover()
            let item = NativeCharacteristic(id: UUID(), uuid: RayNeoIOProfile.outbound, properties: [.write])
            r.port.send(.characteristics(duplicate ? [item, item] : [item]))
            #expect(r.engine.snapshot.terminalReason == (duplicate ? .ambiguousCharacteristic : .missingCharacteristic))
        }
    }
    @Test func unsupportedWritePropertyRejects() throws {
        let r = Rig(); let handles = try r.ble([.read])
        #expect(throws: TransportError.unsupportedProperty) { try r.engine.write(Data([1]), to: handles.0, mode: .withResponse) }
        #expect(throws: TransportError.unsupportedProperty) { try r.engine.subscribe(handles.0) }
    }
    @Test func subscriptionNeedsConfirmationAndPreservesEmptyValue() throws {
        let r = Rig(); let handles = try r.ble(); try r.engine.subscribe(handles.1)
        #expect(r.engine.snapshot.phase == .subscribing)
        r.port.send(.notification(handles.1.native, enabled: true, failed: false))
        #expect(r.engine.snapshot.phase == .discovered)
        r.port.send(.value(handles.1.native, Data()))
        let events = try r.drain(); #expect(events.contains { if case .received(_, let bytes) = $0 { bytes.isEmpty } else { false } })
    }
    @Test func nilValueAndSubscriptionLossClose() throws {
        for nilValue in [false, true] {
            let r = Rig(); let handles = try r.ble(); try r.engine.subscribe(handles.1)
            r.port.send(.notification(handles.1.native, enabled: true, failed: false))
            r.port.send(nilValue ? .value(handles.1.native, nil) : .notification(handles.1.native, enabled: false, failed: false))
            #expect(r.engine.snapshot.phase == .closed)
        }
    }
    @Test func bleLengthsAndNonzeroDataStartIndex() throws {
        let r = Rig(); let handles = try r.ble(); r.port.maximum = 3
        #expect(throws: TransportError.emptyWrite) { try r.engine.write(Data(), to: handles.0, mode: .withResponse) }
        #expect(throws: TransportError.writeTooLarge) { try r.engine.write(Data([1, 2, 3, 4]), to: handles.0, mode: .withResponse) }
        let input = Data([99, 1, 2, 3])[1...]; #expect(input.startIndex != 0)
        try r.engine.write(input, to: handles.0, mode: .withResponse)
        #expect(r.port.bleWrites[0].0 == Data([1, 2, 3])); #expect(r.port.bleWrites.count == 1)
    }
    @Test func bleZeroMaximumRejects() throws {
        let r = Rig(); let h = try r.ble().0; r.port.maximum = 0
        #expect(throws: TransportError.writeTooLarge) { try r.engine.write(Data([1]), to: h, mode: .withResponse) }
    }
    @Test func withResponseSerializesAndDoesNotMeanBusinessSuccess() throws {
        let r = Rig(); let h = try r.ble().0
        try r.engine.write(Data([1]), to: h, mode: .withResponse); try r.engine.write(Data([2]), to: h, mode: .withResponse)
        #expect(r.port.bleWrites.count == 1)
        r.port.send(.writeResponse(h.native, failed: false)); #expect(r.port.bleWrites.count == 2)
        r.port.send(.writeResponse(h.native, failed: false)); #expect(r.engine.snapshot.queuedWriteCount == 0)
        #expect(try r.drain().filter { if case .writeCompleted(_, .coreBluetoothResponseReceived) = $0 { true } else { false } }.count == 2)
    }
    @Test func withoutResponseWaitsForReadyAndNeverWaitsForAck() throws {
        let r = Rig(); let h = try r.ble().0; r.port.canWriteWithoutResponse = false
        try r.engine.write(Data([1]), to: h, mode: .withoutResponse); #expect(r.port.bleWrites.isEmpty)
        r.port.send(.writable); #expect(r.port.bleWrites.isEmpty)
        r.port.canWriteWithoutResponse = true; r.port.send(.writable); r.port.send(.writable)
        #expect(r.port.bleWrites.count == 1); #expect(r.engine.snapshot.queuedWriteCount == 0)
        #expect(r.engine.snapshot.deliveryUncertain)
    }
    @Test func timeoutLateAckCannotCompleteNextWrite() throws {
        let r = Rig(); let h = try r.ble().0
        try r.engine.write(Data([1]), to: h, mode: .withResponse, timeout: 1); try r.engine.write(Data([2]), to: h, mode: .withResponse)
        r.now += 1_000_000_000; r.port.send(.deadline); r.port.send(.writeResponse(h.native, failed: false))
        #expect(r.engine.snapshot.phase == .closed); #expect(r.port.bleWrites.count == 1)
        #expect(r.engine.snapshot.terminalWriteFailures.map(\.submittedByteCount) == [1, 0])
        #expect(r.engine.snapshot.deliveryUncertain)
        _ = try r.drain(); try r.engine.prepare(); #expect(r.engine.snapshot.deliveryUncertain)
        #expect(r.port.bleWrites.count == 1)
    }
    @Test func cancelPendingDoesNotRevokeActive() throws {
        let r = Rig(); let h = try r.ble().0
        try r.engine.write(Data([1]), to: h, mode: .withResponse)
        let pending = try r.engine.write(Data([2]), to: h, mode: .withResponse)
        try r.engine.cancel(pending); #expect(r.engine.snapshot.queuedWriteCount == 1)
        #expect(throws: TransportError.staleHandle) { try r.engine.cancel(pending) }
    }
    @Test func cancelActiveClosesAndIsUncertain() throws {
        let r = Rig(); let h = try r.ble().0; let active = try r.engine.write(Data([1]), to: h, mode: .withResponse)
        try r.engine.cancel(active); #expect(r.engine.snapshot.phase == .closed); #expect(r.engine.snapshot.deliveryUncertain)
    }
    @Test func synchronousDriverCallbacksAreSerialized() throws {
        let r = Rig(); let h = try r.ble().0
        r.port.onBLEWrite = { id in r.port.send(.writeResponse(id, failed: false)) }
        try r.engine.write(Data([1]), to: h, mode: .withResponse)
        #expect(r.engine.snapshot.queuedWriteCount == 0); #expect(r.port.bleWrites.count == 1)
    }
    @Test func eaBothStreamsMustOpen() throws {
        let r = Rig(.externalAccessory); try r.engine.refreshCandidates(); r.port.send(.candidate(UUID())); _ = try r.drain()
        try r.engine.open(r.engine.snapshotCandidates()[0].handle); r.port.send(.streamsOpen(input: false)); r.port.send(.streamsOpen(input: false))
        #expect(r.engine.snapshot.phase == .openingStreams)
        #expect(throws: TransportError.invalidState) { try r.engine.write(Data([1])) }
        r.port.send(.streamsOpen(input: true)); #expect(r.engine.snapshot.phase == .streamsOpened)
    }
    @Test func eaEveryTwoPartShortWriteAndSlice() throws {
        for cut in 1..<32 {
            let r = Rig(.externalAccessory); try r.ea()
            let input = Data([250] + Array(0..<32))[1...]
            r.port.writeResults = [cut, 0]
            try r.engine.write(input)
            #expect(r.engine.snapshot.queuedWriteCount == 1); #expect(r.port.output.count == cut)
            r.port.send(.outputReady)
            #expect(r.port.output == Data(input)); #expect(r.engine.snapshot.retainedWriteBytes == 0)
        }
    }
    @Test func eaAllByteShortReadsPreserveOrderAndBoundaries() throws {
        let r = Rig(.externalAccessory); try r.ea()
        r.port.chunks = (0..<32).map { Data([UInt8($0)]) }; r.port.send(.inputReady)
        #expect(r.port.chunks.count == 16)
        r.port.send(.continueDrain)
        let bytes = try r.drain().reduce(into: Data()) { if case let .received(_, data) = $1 { $0.append(data) } }
        #expect(bytes == Data(0..<32))
    }
    @Test func eaZeroWritesDoNotSpinOrReportSuccess() throws {
        let r = Rig(.externalAccessory); try r.ea(); r.port.writeAlwaysZero = true
        try r.engine.write(Data([1]), timeout: 1)
        #expect(r.port.writeCalls == 1); #expect(r.engine.snapshot.queuedWriteCount == 1)
        #expect(!r.port.effects.contains { if case .scheduleDrain = $0 { true } else { false } })
        r.now += 1_000_000_000; r.port.send(.deadline); #expect(r.engine.snapshot.terminalReason == .timedOut)
    }
    @Test func eaPartialCancellationMarksOnlySubmittedBytes() throws {
        let r = Rig(.externalAccessory); try r.ea(); r.port.writeResults = [2, 0]
        let h = try r.engine.write(Data([1, 2, 3])); try r.engine.cancel(h)
        #expect(r.engine.snapshot.terminalWriteFailures[0].submittedByteCount == 2)
        #expect(r.engine.snapshot.terminalWriteFailures[0].deliveryUncertain)
    }
    @Test func eaReentrantFailureDoesNotClaimNoBytesSent() throws {
        let r = Rig(.externalAccessory); try r.ea()
        r.port.onStreamWrite = { r.port.send(.failure(.nativeFailure)) }
        try r.engine.write(Data([1, 2, 3]))
        #expect(r.engine.snapshot.deliveryUncertain); #expect(r.engine.snapshot.terminalWriteFailures[0].deliveryUncertain)
    }
    @Test func invalidReadAndWriteCountsFailClosed() throws {
        for n in [-2, -1, 5_000] {
            let input = Rig(.externalAccessory); try input.ea(); input.port.readResult = n; input.port.send(.inputReady)
            #expect(input.engine.snapshot.phase == .closed)
            let output = Rig(.externalAccessory); try output.ea(); output.port.writeResults = [n]; try output.engine.write(Data([1]))
            #expect(output.engine.snapshot.phase == .closed)
        }
    }
    @Test func zeroReadIsEOFNotTemporaryUnavailability() throws {
        let r = Rig(.externalAccessory); try r.ea(); r.port.readResult = 0; r.port.send(.inputReady)
        #expect(r.engine.snapshot.terminalReason == .streamEnded)
    }
    @Test func queueBytesAndCountHaveIndependentLimits() throws {
        let r = Rig(limits: try .init(writeBytes: 2, queuedBytes: 3, queuedWrites: 2)); let h = try r.ble().0
        try r.engine.write(Data([1, 2]), to: h, mode: .withResponse)
        #expect(throws: TransportError.queueFull) { try r.engine.write(Data([3, 4]), to: h, mode: .withResponse) }
        try r.engine.write(Data([3]), to: h, mode: .withResponse)
        #expect(throws: TransportError.queueFull) { try r.engine.write(Data([4]), to: h, mode: .withResponse) }
    }
    @Test func inputByteOverflowClosesWithoutSilentContinuation() throws {
        let r = Rig(.externalAccessory, limits: try .init(eventBytes: 2)); try r.ea()
        r.port.chunks = [Data([1, 2, 3])]; r.port.send(.inputReady)
        #expect(r.engine.snapshot.terminalReason == .eventBufferOverflow)
        #expect(r.engine.snapshot.pendingEventBytes <= 2)
    }
    @Test func eventCountOverflowHasOutOfBandTerminalSnapshot() throws {
        let r = Rig(limits: try .init(events: 2)); try r.engine.prepare()
        for _ in 0..<1_000 { r.port.send(.central(.poweredOn)) }
        #expect(r.engine.snapshot.phase == .closed); #expect(r.engine.snapshot.pendingEventCount == 2)
        #expect(r.engine.snapshot.terminalReason == .eventBufferOverflow)
    }
    @Test func repeatedCloseAndLateEventsAreNoOps() throws {
        let r = Rig(.externalAccessory); try r.ea(); r.engine.close(); let count = r.port.effects.count
        for _ in 0..<1_000 { r.engine.close(); r.port.send(.streamsOpen(input: true)); r.port.send(.outputReady) }
        #expect(r.port.effects.count == count)
        #expect(throws: TransportError.invalidState) { try r.engine.write(Data([1])) }
    }
    @Test func timeAndLimitsRejectNonfiniteNegativeAndOverflow() throws {
        #expect(throws: TransportError.invalidLimits) { try TransportLimits(events: 0) }
        #expect(throws: TransportError.invalidLimits) { try TransportLimits(writeBytes: Int.max) }
        let r = Rig(); let h = try r.ble().0
        for duration in [Double.nan, .infinity, -1, 0, 301, 0.000_000_000_1] {
            #expect(throws: (any Error).self) { try r.engine.write(Data([1]), to: h, mode: .withResponse, timeout: duration) }
        }
        let overflow = Rig(); _ = try overflow.ble(); overflow.now = UInt64.max
        #expect(throws: TransportError.invalidClock) { try overflow.engine.write(Data([1]), to: overflow.engine.snapshotCharacteristics()[0].handle, mode: .withResponse) }
    }
    @Test func clockGoingBackwardFailsClosed() throws {
        let r = Rig(); let h = try r.ble().0; r.now = 0
        #expect(throws: TransportError.invalidClock) { try r.engine.write(Data([1]), to: h, mode: .withResponse) }
        #expect(r.engine.snapshot.phase == .closed)
    }
    @Test func refreshInvalidatesOldAccessoryHandle() throws {
        let r = Rig(.externalAccessory); try r.engine.refreshCandidates(); r.port.send(.candidate(UUID())); let old = r.engine.snapshotCandidates()[0].handle
        _ = try r.drain(); try r.engine.refreshCandidates(); r.port.send(.candidate(UUID()))
        #expect(throws: TransportError.staleHandle) { try r.engine.open(old) }
    }
    @Test func lateConnectionCannotBeatUnfiredTimer() throws {
        let r = Rig(); try r.engine.prepare(); r.port.send(.central(.poweredOn)); try r.engine.startScan()
        r.port.send(.candidate(UUID())); r.engine.stopScan(); _ = try r.drain()
        try r.engine.connect(r.engine.snapshotCandidates()[0].handle, timeout: 1)
        r.now += 1_000_000_000; r.port.send(.connected)
        #expect(r.engine.snapshot.terminalReason == .timedOut)
        #expect(!r.port.effects.contains { if case .discover = $0 { true } else { false } })
    }
    @Test func lateWriteResponseCannotBeatUnfiredTimer() throws {
        let r = Rig(); let h = try r.ble().0
        try r.engine.write(Data([1]), to: h, mode: .withResponse, timeout: 1)
        r.now += 1_000_000_000; r.port.send(.writeResponse(h.native, failed: false))
        #expect(r.engine.snapshot.terminalReason == .timedOut)
        #expect(r.engine.snapshot.terminalWriteFailures[0].deliveryUncertain)
    }
    @Test func lateWithoutResponseReadyDoesNotSubmitExpiredWrite() throws {
        let r = Rig(); let h = try r.ble().0; r.port.canWriteWithoutResponse = false
        try r.engine.write(Data([1]), to: h, mode: .withoutResponse, timeout: 1)
        r.now += 1_000_000_000; r.port.canWriteWithoutResponse = true; r.port.send(.writable)
        #expect(r.port.bleWrites.isEmpty); #expect(r.engine.snapshot.terminalReason == .timedOut)
    }
    @Test func lateEAOpenCannotBeatUnfiredTimer() throws {
        let r = Rig(.externalAccessory); try r.engine.refreshCandidates(); r.port.send(.candidate(UUID())); _ = try r.drain()
        try r.engine.open(r.engine.snapshotCandidates()[0].handle, timeout: 1)
        r.port.send(.streamsOpen(input: true)); r.now += 1_000_000_000; r.port.send(.streamsOpen(input: false))
        #expect(r.engine.snapshot.terminalReason == .timedOut)
    }
    @Test func eventOverflowKeepsActiveHandleInTerminalFailures() throws {
        let r = Rig(limits: try .init(events: 3)); let h = try r.ble().0
        let id = try r.engine.write(Data([1]), to: h, mode: .withResponse)
        for _ in 0..<3 { r.port.send(.central(.poweredOn)) }
        r.port.send(.writeResponse(h.native, failed: false))
        #expect(r.engine.snapshot.terminalReason == .eventBufferOverflow)
        #expect(r.engine.snapshot.terminalWriteFailures.map(\.handle) == [id])
        #expect(r.engine.snapshot.terminalWriteFailures[0].deliveryUncertain)
    }
    @Test func eventOverflowDuringPendingCancelRetainsBothHandles() throws {
        let r = Rig(limits: try .init(events: 3)); let h = try r.ble().0
        let first = try r.engine.write(Data([1]), to: h, mode: .withResponse)
        let pending = try r.engine.write(Data([2]), to: h, mode: .withResponse)
        for _ in 0..<3 { r.port.send(.central(.poweredOn)) }
        try r.engine.cancel(pending)
        #expect(r.engine.snapshot.terminalWriteFailures.map(\.handle) == [first, pending])
    }
    @Test func subscribeWhileWriteActiveIsRejected() throws {
        let r = Rig(); let h = try r.ble()
        try r.engine.write(Data([1]), to: h.0, mode: .withResponse)
        #expect(throws: TransportError.invalidState) { try r.engine.subscribe(h.1) }
    }
    @Test func perTurnBLEBudgetSchedulesOnlyOneContinuation() throws {
        let r = Rig(limits: try .init(drainOperations: 1)); let h = try r.ble().0
        r.port.canWriteWithoutResponse = false
        for i in 0..<4 { try r.engine.write(Data([UInt8(i)]), to: h, mode: .withoutResponse) }
        r.port.canWriteWithoutResponse = true; r.port.send(.writable)
        #expect(r.port.bleWrites.count == 1)
        #expect(r.port.effects.filter { if case .scheduleDrain = $0 { true } else { false } }.count == 1)
        r.port.send(.writable)
        #expect(r.port.effects.filter { if case .scheduleDrain = $0 { true } else { false } }.count == 1)
    }
    @Test func sequenceOverflowFailsClosedWithoutCrash() throws {
        #expect(try TransportEngine.nextSequence(UInt64.max - 1) == UInt64.max)
        #expect(throws: TransportError.driverContractViolation) { try TransportEngine.nextSequence(UInt64.max) }
    }
    @Test func deinitRetiresPreparedPort() throws {
        let port = FakePort()
        var engine: TransportEngine? = .init(kind: .bluetooth, limits: try .init(), port: port)
        try engine?.prepare(); engine = nil
        #expect(port.effects.contains { if case .close = $0 { true } else { false } })
        #expect(port.receive == nil)
    }
    @Test func writeErrorKeepsUncertainNativeAttempt() throws {
        let r = Rig(.externalAccessory); try r.ea(); r.port.writeResults = [-1]
        try r.engine.write(Data([1]))
        #expect(r.engine.snapshot.terminalWriteFailures[0].submittedByteCount == 0)
        #expect(r.engine.snapshot.terminalWriteFailures[0].deliveryUncertain)
    }
    @Test func nativeWriteReturningAfterDeadlineCannotReportCompletion() throws {
        let r = Rig(.externalAccessory); try r.ea()
        r.port.onStreamWrite = { r.now += 1_000_000_000 }
        try r.engine.write(Data([1]), timeout: 1)
        #expect(r.engine.snapshot.terminalReason == .timedOut)
        #expect(r.engine.snapshot.terminalWriteFailures[0].submittedByteCount == 1)
        #expect(try r.drain().allSatisfy { if case .writeCompleted = $0 { false } else { true } })
    }
    @Test func singleOperationBudgetAlternatesInputAndOutput() throws {
        let r = Rig(.externalAccessory, limits: try .init(scratchBytes: 1, drainBytes: 1, drainOperations: 1)); try r.ea()
        r.port.chunks = [Data(repeating: 9, count: 10)]
        try r.engine.write(Data([1, 2]))
        #expect(r.port.output.isEmpty)
        r.port.send(.continueDrain); #expect(r.port.output == Data([1]))
        r.port.send(.continueDrain); r.port.send(.continueDrain)
        #expect(r.port.output == Data([1, 2]))
    }
    @Test func rescanSameNativeIDDoesNotReviveOldSelectionHandle() throws {
        let r = Rig(); try r.engine.prepare(); r.port.send(.central(.poweredOn)); try r.engine.startScan()
        let native = UUID(); r.port.send(.candidate(native)); r.engine.stopScan()
        let old = r.engine.snapshotCandidates()[0].handle; _ = try r.drain()
        try r.engine.startScan(); r.port.send(.candidate(native)); r.engine.stopScan(); _ = try r.drain()
        #expect(old != r.engine.snapshotCandidates()[0].handle)
        #expect(throws: TransportError.staleHandle) { try r.engine.connect(old) }
        try r.engine.connect(r.engine.snapshotCandidates()[0].handle)
        #expect(r.engine.snapshot.phase == .connecting)
    }
}
