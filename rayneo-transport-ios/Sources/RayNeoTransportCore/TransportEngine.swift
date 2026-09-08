import Foundation

/// The actual lifecycle, limits and IO queue used by BOTH Apple adapters and fake IO.
/// Main-actor confined, no native activity at init. No wire protocol or authentication.
@MainActor public final class TransportEngine {
    public let kind: TransportKind
    public let limits: TransportLimits
    private let port: any TransportPort
    private let clock: @MainActor () -> UInt64
    private let owner = UUID()
    private var generation = UUID()
    private var discovery = UUID()
    private var phase: TransportPhase = .idle
    private var central: CentralState = .unknown
    private var reason: TransportError?
    private var candidates: [UUID] = []
    private var characteristics: [Characteristic] = []
    private var subscribed: Set<UUID> = []
    private var subscribing: UUID?
    private var events: [TransportEvent] = []
    private var eventBytes = 0
    private var sequence: UInt64 = 0
    private var lastClock: UInt64 = 0
    private var controlDeadline: UInt64?
    private var scheduledDeadline: UInt64?
    private var inputOpen = false, outputOpen = false
    private var draining = false, continuationScheduled = false
    private var preferInput = true
    private var uncertain = false
    private var failures: [WriteFailure] = []
    private struct Pending {
        let handle: WriteHandle, bytes: Data, characteristic: UUID?, mode: BLEWriteMode?, deadline: UInt64
        var submitted = 0
        var nativeCallInProgress = false
    }
    private var writes: [Pending] = []
    private var retainedBytes = 0

    public init(kind: TransportKind, limits: TransportLimits, port: any TransportPort,
                clock: @escaping @MainActor () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.kind = kind; self.limits = limits; self.port = port; self.clock = clock
        port.receive = { [weak self] generation, event in self?.receive(generation, event) }
    }
    isolated deinit {
        if phase != .idle && phase != .closed { port.perform(.close) }
        port.receive = nil
    }
    public var snapshot: TransportSnapshot {
        .init(phase: phase, centralState: central, terminalReason: reason,
              queuedWriteCount: writes.count, retainedWriteBytes: retainedBytes,
              pendingEventCount: events.count, pendingEventBytes: eventBytes,
              deliveryUncertain: uncertain, terminalWriteFailures: failures)
    }
    public func snapshotCandidates() -> [Candidate] {
        candidates.map { Candidate(handle: CandidateHandle(owner: owner, generation: generation, discovery: discovery, native: $0)) }
    }
    public func snapshotCharacteristics() -> [Characteristic] { characteristics }

    public func prepare() throws {
        guard kind == .bluetooth else { throw TransportError.wrongKind }
        try beginGeneration()
    }
    private func beginGeneration() throws {
        guard phase == .idle || phase == .closed else { throw TransportError.invalidState }
        guard events.isEmpty else { throw TransportError.pendingEvents }
        generation = UUID(); discovery = UUID(); candidates = []; characteristics = []; subscribed = []
        subscribing = nil; reason = nil; central = .unknown
        inputOpen = false; outputOpen = false; controlDeadline = nil; scheduledDeadline = nil
        continuationScheduled = false; lastClock = clock(); phase = .prepared
        // Deliberately preserve uncertain and terminal failures across prepare.
        port.perform(.prepare(generation, kind))
    }
    public func startScan(timeout: TimeInterval = 15) throws {
        guard kind == .bluetooth else { throw TransportError.wrongKind }
        guard phase == .prepared else { throw TransportError.invalidState }
        guard central == .poweredOn else { throw TransportError.poweredOff }
        controlDeadline = try deadline(timeout); discovery = UUID(); candidates = []; phase = .scanning
        port.perform(.scan); schedule()
    }
    public func stopScan() {
        guard phase == .scanning else { return }
        phase = .prepared; controlDeadline = nil; port.perform(.stopScan)
        emit(.scanStopped(nil)); schedule()
    }
    public func refreshCandidates() throws {
        guard kind == .externalAccessory else { throw TransportError.wrongKind }
        if phase == .prepared {
            guard events.isEmpty else { throw TransportError.pendingEvents }
            phase = .closed; port.perform(.close)
        }
        try beginGeneration()
        port.perform(.enumerateAccessories)
    }
    public func connect(_ handle: CandidateHandle, timeout: TimeInterval = 15) throws {
        guard kind == .bluetooth else { throw TransportError.wrongKind }
        guard phase == .prepared, central == .poweredOn else { throw TransportError.invalidState }
        try validate(handle)
        controlDeadline = try deadline(timeout); phase = .connecting
        port.perform(.connect(handle.native)); schedule()
    }
    public func discover(timeout: TimeInterval = 10) throws {
        guard kind == .bluetooth else { throw TransportError.wrongKind }
        guard phase == .connected else { throw TransportError.invalidState }
        controlDeadline = try deadline(timeout); phase = .discovering
        port.perform(.discover); schedule()
    }
    public func subscribe(_ handle: CharacteristicHandle, timeout: TimeInterval = 10) throws {
        guard kind == .bluetooth else { throw TransportError.wrongKind }
        guard phase == .discovered, writes.isEmpty else { throw TransportError.invalidState }
        let characteristic = try validate(handle)
        guard !characteristic.properties.intersection([.notify, .indicate]).isEmpty else { throw TransportError.unsupportedProperty }
        guard !subscribed.contains(handle.native) else { throw TransportError.invalidState }
        controlDeadline = try deadline(timeout); subscribing = handle.native; phase = .subscribing
        port.perform(.subscribe(handle.native)); schedule()
    }
    public func open(_ handle: CandidateHandle, timeout: TimeInterval = 10) throws {
        guard kind == .externalAccessory else { throw TransportError.wrongKind }
        guard phase == .prepared else { throw TransportError.invalidState }
        try validate(handle)
        controlDeadline = try deadline(timeout); phase = .openingStreams
        port.perform(.openAccessory(handle.native)); schedule()
    }
    @discardableResult public func write(_ bytes: Data, to handle: CharacteristicHandle? = nil,
                                         mode: BLEWriteMode? = nil, timeout: TimeInterval = 10) throws -> WriteHandle {
        if kind == .bluetooth {
            guard phase == .discovered, let handle, let mode else { throw TransportError.invalidState }
            let characteristic = try validate(handle)
            guard characteristic.properties.contains(mode == .withResponse ? .write : .writeWithoutResponse) else { throw TransportError.unsupportedProperty }
            let maximum = port.maximumWriteLength(mode)
            guard maximum > 0, bytes.count <= maximum else { throw TransportError.writeTooLarge }
        } else {
            guard phase == .streamsOpened, handle == nil, mode == nil else { throw TransportError.invalidState }
        }
        guard !bytes.isEmpty else { throw TransportError.emptyWrite }
        guard bytes.count <= limits.writeBytes else { throw TransportError.writeTooLarge }
        guard writes.count < limits.queuedWrites, bytes.count <= limits.queuedBytes - retainedBytes else { throw TransportError.queueFull }
        let until = try deadline(timeout)
        do { sequence = try Self.nextSequence(sequence) }
        catch { terminate(.driverContractViolation); throw error }
        let id = WriteHandle(owner: owner, generation: generation, sequence: sequence)
        // Force bounded ownership; do not keep a tiny slice's potentially huge backing store.
        let copied = bytes.withUnsafeBytes { Data($0) }
        writes.append(Pending(handle: id, bytes: copied, characteristic: handle?.native, mode: mode, deadline: until))
        retainedBytes += copied.count
        pump(); schedule()
        return id
    }
    public func cancel(_ handle: WriteHandle) throws {
        guard handle.owner == owner, handle.generation == generation,
              let i = writes.firstIndex(where: { $0.handle == handle }) else { throw TransportError.staleHandle }
        // A delayed timer cannot let cancellation erase an already-expired
        // queue deadline. Validate ownership first, then expire the intact queue.
        expireIfNeeded()
        guard phase != .closed else { return }
        if writes[i].submitted > 0 || writes[i].nativeCallInProgress { terminate(.cancelled); return }
        guard events.count < limits.events else { terminate(.eventBufferOverflow); return }
        let item = writes.remove(at: i); retainedBytes -= item.bytes.count
        emit(.writeFailed(.init(handle: item.handle, reason: .cancelled, submittedByteCount: 0, deliveryUncertain: false)))
        pump(); schedule()
    }
    public func close() { if phase != .idle && phase != .closed { terminate(.cancelled) } }
    public func drainEvents(maxCount: Int = 128) throws -> [TransportEvent] {
        guard (1...limits.events).contains(maxCount) else { throw TransportError.invalidLimits }
        let n = min(maxCount, events.count), result = Array(events.prefix(n))
        for event in result { if case let .received(_, data) = event { eventBytes -= data.count } }
        events.removeFirst(n)
        return result
    }
    private func validate(_ handle: CandidateHandle) throws {
        guard handle.owner == owner, handle.generation == generation, handle.discovery == discovery,
              candidates.contains(handle.native) else { throw TransportError.staleHandle }
    }
    private func validate(_ handle: CharacteristicHandle) throws -> Characteristic {
        guard handle.owner == owner, handle.generation == generation,
              let result = characteristics.first(where: { $0.handle == handle }) else { throw TransportError.staleHandle }
        return result
    }
    private func deadline(_ seconds: TimeInterval) throws -> UInt64 {
        guard seconds.isFinite, seconds > 0, seconds <= 300 else { throw TransportError.invalidTimeout }
        let now = clock()
        guard now >= lastClock else { terminate(.invalidClock); throw TransportError.invalidClock }
        lastClock = now
        let delta = UInt64(seconds * 1_000_000_000)
        let (value, overflow) = now.addingReportingOverflow(delta)
        guard !overflow, delta > 0 else { terminate(.invalidClock); throw TransportError.invalidClock }
        return value
    }
    private func schedule() {
        guard phase != .closed else { return }
        let next = ([controlDeadline].compactMap { $0 } + writes.map(\.deadline)).min()
        guard next != scheduledDeadline else { return }
        scheduledDeadline = next; port.perform(.scheduleDeadline(next))
    }
    private func emit(_ event: TransportEvent) {
        guard phase != .closed else { return }
        let size: Int
        if case let .received(_, data) = event { size = data.count } else { size = 0 }
        guard events.count < limits.events, size <= limits.eventBytes - eventBytes else {
            terminate(.eventBufferOverflow); return
        }
        events.append(event); eventBytes += size
    }
    private func terminate(_ error: TransportError) {
        guard phase != .closed else { return }
        phase = .closed; reason = error; controlDeadline = nil; scheduledDeadline = nil
        continuationScheduled = false
        failures = writes.map { .init(handle: $0.handle, reason: error, submittedByteCount: $0.submitted, deliveryUncertain: $0.submitted > 0 || $0.nativeCallInProgress) }
        uncertain = uncertain || writes.contains { $0.submitted > 0 || $0.nativeCallInProgress }
        writes = []; retainedBytes = 0; candidates = []; characteristics = []; subscribed = []
        port.perform(.close)
        // Terminal snapshot is authoritative if the bounded event buffer cannot fit these.
        for failure in failures where events.count < limits.events { events.append(.writeFailed(failure)) }
        if events.count < limits.events { events.append(.closedLocally(error)) }
    }
    private func receive(_ token: UUID, _ event: NativeEvent) {
        guard token == generation, phase != .closed, phase != .idle else { return }
        expireIfNeeded()
        guard phase != .closed else { return }
        switch event {
        case let .central(value):
            guard kind == .bluetooth else { return }
            central = value; emit(.centralState(value))
            if value != .poweredOn && phase != .prepared { terminate(.disconnected) }
        case let .candidate(id):
            guard (kind == .bluetooth && phase == .scanning) || (kind == .externalAccessory && phase == .prepared) else { return }
            guard !candidates.contains(id) else { return }
            if candidates.count >= limits.candidates {
                if kind == .bluetooth {
                    phase = .prepared; controlDeadline = nil; port.perform(.stopScan); emit(.scanStopped(.candidateLimit))
                } else { terminate(.candidateLimit) }
                break
            }
            candidates.append(id); emit(.candidate(Candidate(handle: .init(owner: owner, generation: generation, discovery: discovery, native: id))))
        case .connected:
            guard kind == .bluetooth, phase == .connecting else { return }
            phase = .connected; controlDeadline = nil; emit(.connected)
        case let .characteristics(values):
            guard kind == .bluetooth, phase == .discovering else { return }
            guard values.count <= limits.characteristics else { terminate(.characteristicLimit); return }
            guard Set(values.map(\.id)).count == values.count, Set(values.map(\.uuid)).count == values.count else { terminate(.ambiguousCharacteristic); return }
            guard values.contains(where: { $0.uuid == RayNeoIOProfile.outbound }), values.contains(where: { $0.uuid == RayNeoIOProfile.inbound }) else { terminate(.missingCharacteristic); return }
            characteristics = values.map { .init(handle: .init(owner: owner, generation: generation, native: $0.id), uuid: $0.uuid, properties: $0.properties) }
            phase = .discovered; controlDeadline = nil; emit(.discovered(characteristics))
        case let .notification(id, enabled, failed):
            guard characteristics.contains(where: { $0.handle.native == id }) else { return }
            if failed || !enabled { terminate(.nativeFailure); return }
            guard phase == .subscribing, subscribing == id else { return }
            subscribed.insert(id); subscribing = nil; phase = .discovered; controlDeadline = nil
            emit(.subscriptionConfirmed(.init(owner: owner, generation: generation, native: id)))
        case let .value(id, bytes):
            guard subscribed.contains(id) || subscribing == id else { return }
            guard let bytes else { terminate(.nilValue); return }
            guard bytes.count <= limits.eventBytes - eventBytes else { terminate(.eventBufferOverflow); return }
            let data = bytes.withUnsafeBytes { Data($0) }
            emit(.received(.bluetooth(.init(owner: owner, generation: generation, native: id)), data))
        case let .writeResponse(id, failed):
            guard let first = writes.first, first.mode == .withResponse, first.submitted > 0, first.characteristic == id else { return }
            if failed { terminate(.nativeFailure) } else { complete(.coreBluetoothResponseReceived); pump() }
        case .writable: pump()
        case let .streamsOpen(input):
            guard kind == .externalAccessory, phase == .openingStreams else { return }
            if input { inputOpen = true } else { outputOpen = true }
            if inputOpen && outputOpen { phase = .streamsOpened; controlDeadline = nil; emit(.streamsOpened); pump() }
        case .inputReady, .outputReady: pump()
        case .continueDrain: continuationScheduled = false; pump()
        case .deadline:
            scheduledDeadline = nil
        case let .failure(error): terminate(error)
        }
        schedule()
    }
    private func complete(_ receipt: WriteReceipt) {
        guard !writes.isEmpty else { return }
        // If a completion cannot be retained, keep it among terminal failures
        // with deliveryUncertain rather than silently removing its handle.
        guard events.count < limits.events else { terminate(.eventBufferOverflow); return }
        let item = writes.removeFirst(); retainedBytes -= item.bytes.count
        if receipt != .coreBluetoothResponseReceived { uncertain = true }
        emit(.writeCompleted(item.handle, receipt))
    }
    private func pump() {
        guard !draining, phase != .closed else { return }
        expireIfNeeded()
        guard phase != .closed else { return }
        draining = true
        defer { draining = false }
        if kind == .bluetooth {
            var operations = 0
            while phase == .discovered, !writes.isEmpty, operations < limits.drainOperations {
                guard writes[0].submitted == 0 else { return }
                let item = writes[0]
                guard let mode = item.mode, let characteristic = item.characteristic else { terminate(.driverContractViolation); return }
                let maximum = port.maximumWriteLength(mode)
                guard maximum > 0, item.bytes.count <= maximum else { terminate(.writeTooLarge); return }
                if mode == .withoutResponse && !port.canWriteWithoutResponse { return }
                writes[0].submitted = item.bytes.count // commit before a synchronous fake callback
                port.writeBLE(item.bytes, characteristic: characteristic, mode: mode); operations += 1
                expireIfNeeded()
                guard phase != .closed else { return }
                if mode == .withoutResponse, writes.first?.handle == item.handle { complete(.submittedWithoutResponse) }
                if mode == .withResponse, writes.first?.handle == item.handle { return }
            }
            if !writes.isEmpty, writes[0].submitted == 0 { continueLater() }
        } else {
            guard phase == .streamsOpened else { return }
            var operations = 0, total = 0
            var scratch = [UInt8](repeating: 0, count: limits.scratchBytes)
            let sharing = !writes.isEmpty && port.outputAvailable && port.inputAvailable
            let readOperations = sharing ? (limits.drainOperations > 1 ? max(1, limits.drainOperations / 2) : (preferInput ? 1 : 0)) : limits.drainOperations
            let readBytes = sharing ? (limits.drainBytes > 1 ? max(1, limits.drainBytes / 2) : (preferInput ? 1 : 0)) : limits.drainBytes
            if sharing { preferInput.toggle() }
            while phase == .streamsOpened, port.inputAvailable, operations < readOperations, total < readBytes {
                let requested = min(scratch.count, readBytes - total)
                let n = scratch.withUnsafeMutableBufferPointer { port.read(UnsafeMutableBufferPointer(rebasing: $0.prefix(requested))) }
                operations += 1
                expireIfNeeded()
                guard phase == .streamsOpened else { return }
                guard n >= 0, n <= requested else { terminate(n == -1 ? .nativeFailure : .driverContractViolation); return }
                guard n > 0 else { terminate(.streamEnded); return }
                total += n
                guard n <= limits.eventBytes - eventBytes else { terminate(.eventBufferOverflow); return }
                emit(.received(.externalAccessory, Data(scratch.prefix(n))))
            }
            var zeroWrite = false
            while phase == .streamsOpened, !writes.isEmpty, port.outputAvailable, operations < limits.drainOperations, total < limits.drainBytes {
                let item = writes[0], remaining = item.bytes.count - item.submitted
                let requested = min(remaining, limits.drainBytes - total)
                writes[0].nativeCallInProgress = true
                let n = item.bytes.withUnsafeBytes { raw in
                    let b = raw.bindMemory(to: UInt8.self)
                    return port.write(UnsafeBufferPointer(rebasing: b[item.submitted..<(item.submitted + requested)]))
                }
                operations += 1
                guard phase == .streamsOpened else { return }
                guard n >= 0, n <= requested else { terminate(n == -1 ? .nativeFailure : .driverContractViolation); return }
                writes[0].nativeCallInProgress = false
                if n > 0 { writes[0].submitted += n; total += n }
                expireIfNeeded()
                guard phase == .streamsOpened else { return }
                if n == 0 { zeroWrite = true; break }
                if writes[0].submitted == writes[0].bytes.count { complete(.outputStreamConsumed) }
            }
            if phase == .streamsOpened && (port.inputAvailable || (!zeroWrite && !writes.isEmpty && port.outputAvailable)) { continueLater() }
        }
    }
    private func continueLater() {
        guard !continuationScheduled, phase != .closed else { return }
        continuationScheduled = true; port.perform(.scheduleDrain)
    }
    private func expireIfNeeded() {
        guard phase != .closed else { return }
        let now = clock()
        guard now >= lastClock else { terminate(.invalidClock); return }
        lastClock = now
        if let until = controlDeadline, now >= until {
            if phase == .scanning {
                phase = .prepared; controlDeadline = nil; port.perform(.stopScan); emit(.scanStopped(.timedOut))
            } else { terminate(.timedOut) }
        }
        if writes.contains(where: { now >= $0.deadline }) { terminate(.timedOut) }
    }
    static func nextSequence(_ current: UInt64) throws -> UInt64 {
        guard current < UInt64.max else { throw TransportError.driverContractViolation }
        return current + 1
    }
}
