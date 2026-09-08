import Foundation
import Testing
@testable import RayNeoTransportCore

@MainActor private final class BoundaryPort: TransportPort {
    var receive: (@MainActor (UUID, NativeEvent) -> Void)?
    var token = UUID()
    var effects: [NativeEffect] = []
    var bleBytes: [Data] = []
    var canWriteWithoutResponse = true
    var outputAvailable = true
    var inputAvailable = false
    var readHook: (@MainActor () -> Void)?
    var writeHook: (@MainActor () -> Void)?
    var inputByte: UInt8 = 0x7f
    var readResult = 1
    var writeResult: Int?
    func perform(_ effect: NativeEffect) {
        effects.append(effect)
        if case .prepare(let generation, _) = effect { token = generation }
    }
    func event(_ event: NativeEvent, token: UUID? = nil) { receive?(token ?? self.token, event) }
    func maximumWriteLength(_ mode: BLEWriteMode) -> Int { 512 }
    func writeBLE(_ bytes: Data, characteristic: UUID, mode: BLEWriteMode) { bleBytes.append(bytes) }
    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        if !buffer.isEmpty { buffer[0] = inputByte }
        inputAvailable = false; readHook?(); return readResult
    }
    func write(_ bytes: UnsafeBufferPointer<UInt8>) -> Int { writeHook?(); return writeResult ?? bytes.count }
}

@MainActor private final class BoundarySetup {
    let port = BoundaryPort()
    var time: UInt64 = 100_000_000_000
    var channel: TransportEngine!
    init(_ kind: TransportKind) throws {
        channel = TransportEngine(kind: kind, limits: try TransportLimits(), port: port, clock: { [weak self] in self?.time ?? 0 })
    }
    func drain() throws -> [TransportEvent] { try channel.drainEvents() }
    func prepareBLE() throws -> CharacteristicHandle {
        try channel.prepare(); port.event(.central(.poweredOn)); _ = try drain()
        try channel.startScan(); port.event(.candidate(UUID())); channel.stopScan(); _ = try drain()
        try channel.connect(channel.snapshotCandidates()[0].handle); port.event(.connected); _ = try drain()
        try channel.discover()
        port.event(.characteristics([
            .init(id: UUID(), uuid: RayNeoIOProfile.outbound, properties: [.write, .writeWithoutResponse]),
            .init(id: UUID(), uuid: RayNeoIOProfile.inbound, properties: [.notify])
        ])); _ = try drain()
        return channel.snapshotCharacteristics()[0].handle
    }
    func prepareEA() throws {
        try channel.refreshCandidates(); port.event(.candidate(UUID())); _ = try drain()
        try channel.open(channel.snapshotCandidates()[0].handle)
        port.event(.streamsOpen(input: false)); port.event(.streamsOpen(input: true)); _ = try drain()
    }
}

@Suite @MainActor struct IndependentBoundaryTests {
    @Test func expiredQueuedCancellationCannotEraseGlobalDeadlineBeforeNextDrain() throws {
        let setup = try BoundarySetup(.bluetooth), outbound = try setup.prepareBLE()
        let first = try setup.channel.write(Data([1]), to: outbound, mode: .withResponse, timeout: 10)
        let second = try setup.channel.write(Data([2]), to: outbound, mode: .withResponse, timeout: 1)
        setup.time += 1_000_000_000 // Timer callback is deliberately delayed, as on a busy main loop.
        try setup.channel.cancel(second)
        let snapshot = setup.channel.snapshot
        print("TRANSPORT_REPRO expired_queued_cancel terminal_is_timeout=\(snapshot.terminalReason == .timedOut) active_count=\(snapshot.queuedWriteCount)")
        #expect(snapshot.terminalReason == .timedOut)
        #expect(snapshot.terminalWriteFailures.map(\.handle) == [first, second])
    }

    @Test func preDeadlineQueuedCancellationDoesNotCloseActiveWrite() throws {
        let setup = try BoundarySetup(.bluetooth), outbound = try setup.prepareBLE()
        try setup.channel.write(Data([1]), to: outbound, mode: .withResponse, timeout: 10)
        let second = try setup.channel.write(Data([2]), to: outbound, mode: .withResponse, timeout: 1)
        setup.time += 999_999_999
        try setup.channel.cancel(second)
        #expect(setup.channel.snapshot.terminalReason == nil)
        #expect(setup.channel.snapshot.queuedWriteCount == 1)
        #expect(setup.port.bleBytes == [Data([1])])
    }

    @Test func deadlineCrossingInsideNativeReadDiscardsBytesAndDoesNotWriteQueuedData() throws {
        let setup = try BoundarySetup(.externalAccessory); try setup.prepareEA()
        setup.port.outputAvailable = false
        let write = try setup.channel.write(Data([1, 2]), timeout: 1)
        setup.port.inputAvailable = true
        setup.port.readHook = { setup.time += 1_000_000_000 }
        setup.port.event(.inputReady)
        #expect(setup.channel.snapshot.terminalReason == .timedOut)
        #expect(setup.channel.snapshot.terminalWriteFailures.map(\.handle) == [write])
        #expect(!setup.channel.snapshot.deliveryUncertain)
        #expect(try setup.drain().allSatisfy { if case .received = $0 { false } else { true } })
    }

    @Test func oldDrainAndStreamEventsDoNotActAfterEAGenerationReplacement() throws {
        let setup = try BoundarySetup(.externalAccessory); try setup.prepareEA()
        let old = setup.port.token
        setup.channel.close(); _ = try setup.drain()
        try setup.channel.refreshCandidates()
        let effectCount = setup.port.effects.count
        for event in [NativeEvent.continueDrain, .deadline, .outputReady, .streamsOpen(input: true), .failure(.nativeFailure)] {
            setup.port.event(event, token: old)
        }
        #expect(setup.channel.snapshot.phase == .prepared)
        #expect(setup.channel.snapshot.terminalReason == nil)
        #expect(setup.port.effects.count == effectCount)
    }
}
