#if os(iOS)
import Foundation
import CoreBluetooth
import ExternalAccessory
import RayNeoTransportCore

/// Public-API raw BLE transport. Constructing it performs no Apple manager operation.
@MainActor public final class CoreBluetoothTransport {
    public let channel: TransportEngine
    public init(limits: TransportLimits) {
        channel = TransportEngine(kind: .bluetooth, limits: limits, port: AppleTransportPort(limits: limits))
    }
}

/// Public-API EA transport. No enumeration or session opening before explicit calls.
@MainActor public final class ExternalAccessoryTransport {
    public let channel: TransportEngine
    public init(limits: TransportLimits) {
        channel = TransportEngine(kind: .externalAccessory, limits: limits, port: AppleTransportPort(limits: limits))
    }
}

@MainActor private final class AppleTransportPort: NSObject, TransportPort {
    var receive: (@MainActor (UUID, NativeEvent) -> Void)?
    private let limits: TransportLimits
    private var generation: UUID?
    private var bridge: AppleDelegate?
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var service: CBService?
    private var characteristics: [UUID: CBCharacteristic] = [:]
    private var accessories: [UUID: EAAccessory] = [:]
    private var session: EASession?
    private var input: InputStream?
    private var output: OutputStream?
    private var deadlineTimer: Timer?
    private var drainTimer: Timer?
    init(limits: TransportLimits) { self.limits = limits; super.init() }
    isolated deinit { closeNative() }

    func perform(_ effect: NativeEffect) {
        switch effect {
        case let .prepare(token, kind):
            closeNative()
            generation = token
            let delegate = AppleDelegate(owner: self, generation: token)
            bridge = delegate
            if kind == .bluetooth { central = CBCentralManager(delegate: delegate, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false]) }
        case .scan:
            peripherals = [:]
            guard let central, central.state == .poweredOn else { fail(.poweredOff); return }
            central.scanForPeripherals(withServices: [CBUUID(nsuuid: RayNeoIOProfile.service)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .stopScan: central?.stopScan()
        case .enumerateAccessories:
            // Explicit enumeration; no serial, name, cloud or manufacturer data is requested.
            accessories = [:]
            for accessory in EAAccessoryManager.shared().connectedAccessories {
                guard accessory.isConnected, accessory.protocolStrings.contains(RayNeoIOProfile.accessoryProtocol) else { continue }
                guard accessories.count < limits.candidates else { fail(.candidateLimit); return }
                let id = UUID(); accessories[id] = accessory; emit(.candidate(id))
                if generation == nil { return }
            }
        case let .connect(id):
            guard let central, let target = peripherals[id], central.state == .poweredOn else { fail(.staleHandle); return }
            peripheral = target; target.delegate = bridge
            central.connect(target, options: nil)
        case .discover:
            guard let peripheral, peripheral.state == .connected else { fail(.disconnected); return }
            peripheral.discoverServices([CBUUID(nsuuid: RayNeoIOProfile.service)])
        case let .subscribe(id):
            guard let peripheral, let characteristic = characteristics[id] else { fail(.staleHandle); return }
            peripheral.setNotifyValue(true, for: characteristic)
        case let .openAccessory(id):
            guard let accessory = accessories[id], accessory.isConnected,
                  accessory.protocolStrings.contains(RayNeoIOProfile.accessoryProtocol), session == nil,
                  let created = EASession(accessory: accessory, forProtocol: RayNeoIOProfile.accessoryProtocol),
                  let incoming = created.inputStream, let outgoing = created.outputStream else { fail(.nativeFailure); return }
            session = created; input = incoming; output = outgoing
            for stream in [incoming as Stream, outgoing as Stream] {
                stream.delegate = bridge; stream.schedule(in: .main, forMode: .common); stream.open()
            }
        case let .scheduleDeadline(deadline):
            deadlineTimer?.invalidate(); deadlineTimer = nil
            guard let deadline, let bridge else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            let delay = deadline > now ? Double(deadline - now) / 1_000_000_000 : 0
            let timer = Timer(timeInterval: delay, target: bridge, selector: #selector(AppleDelegate.deadline(_:)), userInfo: nil, repeats: false)
            deadlineTimer = timer; RunLoop.main.add(timer, forMode: .common)
        case .scheduleDrain:
            guard drainTimer == nil, let bridge else { return }
            let timer = Timer(timeInterval: 0, target: bridge, selector: #selector(AppleDelegate.drain(_:)), userInfo: nil, repeats: false)
            drainTimer = timer; RunLoop.main.add(timer, forMode: .common)
        case .close: closeNative()
        }
    }
    private func closeNative() {
        // Retiring callbacks does NOT revoke bytes already handed to native IO.
        generation = nil
        deadlineTimer?.invalidate(); deadlineTimer = nil
        drainTimer?.invalidate(); drainTimer = nil
        let oldCentral = central, oldPeripheral = peripheral
        oldCentral?.delegate = nil; oldPeripheral?.delegate = nil
        oldCentral?.stopScan()
        if let oldPeripheral { oldCentral?.cancelPeripheralConnection(oldPeripheral) }
        for stream in [input as Stream?, output as Stream?].compactMap({ $0 }) {
            stream.delegate = nil; stream.close(); stream.remove(from: .main, forMode: .common)
        }
        central = nil; peripheral = nil; peripherals = [:]; characteristics = [:]; service = nil
        input = nil; output = nil; session = nil; accessories = [:]; bridge = nil
    }
    private func emit(_ event: NativeEvent) { if let generation { receive?(generation, event) } }
    private func fail(_ error: TransportError) { emit(.failure(error)) }
    func maximumWriteLength(_ mode: BLEWriteMode) -> Int {
        peripheral?.maximumWriteValueLength(for: mode == .withResponse ? .withResponse : .withoutResponse) ?? 0
    }
    var canWriteWithoutResponse: Bool { peripheral?.canSendWriteWithoutResponse ?? false }
    func writeBLE(_ bytes: Data, characteristic id: UUID, mode: BLEWriteMode) {
        guard let peripheral, peripheral.state == .connected, let characteristic = characteristics[id] else { fail(.disconnected); return }
        peripheral.writeValue(bytes, for: characteristic, type: mode == .withResponse ? .withResponse : .withoutResponse)
    }
    var inputAvailable: Bool { input?.hasBytesAvailable ?? false }
    var outputAvailable: Bool { output?.hasSpaceAvailable ?? false }
    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        guard let input, let address = buffer.baseAddress, !buffer.isEmpty else { return -1 }
        return input.read(address, maxLength: buffer.count)
    }
    func write(_ bytes: UnsafeBufferPointer<UInt8>) -> Int {
        guard let output, let address = bytes.baseAddress, !bytes.isEmpty else { return -1 }
        return output.write(address, maxLength: bytes.count)
    }
    fileprivate func state(_ manager: CBCentralManager, token: UUID) {
        guard generation == token, central === manager else { return }
        let state: CentralState
        switch manager.state {
        case .unknown: state = .unknown
        case .resetting: state = .resetting
        case .unsupported: state = .unsupported
        case .unauthorized: state = .unauthorized
        case .poweredOff: state = .poweredOff
        case .poweredOn: state = .poweredOn
        @unknown default: state = .unknown
        }
        emit(.central(state))
    }
    fileprivate func discovered(_ target: CBPeripheral, manager: CBCentralManager, token: UUID) {
        guard generation == token, central === manager, manager.isScanning else { return }
        guard peripherals[target.identifier] == nil else { return }
        guard peripherals.count < limits.candidates else {
            // Let the shared core perform its scanStopped(candidateLimit) transition.
            emit(.candidate(UUID())); return
        }
        peripherals[target.identifier] = target; emit(.candidate(target.identifier))
    }
    fileprivate func connected(_ target: CBPeripheral, manager: CBCentralManager, token: UUID, failed: Bool) {
        guard generation == token, central === manager, peripheral === target else { return }
        emit(failed ? .failure(.nativeFailure) : .connected)
    }
    fileprivate func disconnected(_ target: CBPeripheral, manager: CBCentralManager, token: UUID) {
        guard generation == token, central === manager, peripheral === target else { return }
        fail(.disconnected)
    }
    fileprivate func services(_ target: CBPeripheral, token: UUID, failed: Bool) {
        guard generation == token, peripheral === target else { return }
        guard !failed, let services = target.services else { fail(.nativeFailure); return }
        guard services.count <= limits.characteristics else { fail(.characteristicLimit); return }
        let matching = services.filter { $0.uuid == CBUUID(nsuuid: RayNeoIOProfile.service) }
        guard matching.count == 1, let selected = matching.first else { fail(matching.isEmpty ? .missingCharacteristic : .ambiguousCharacteristic); return }
        service = selected
        target.discoverCharacteristics(nil, for: selected)
    }
    fileprivate func discoveredCharacteristics(_ target: CBPeripheral, service discovered: CBService, token: UUID, failed: Bool) {
        guard generation == token, peripheral === target, service === discovered else { return }
        guard !failed, let values = discovered.characteristics else { fail(.nativeFailure); return }
        guard values.count <= limits.characteristics else { fail(.characteristicLimit); return }
        var records: [NativeCharacteristic] = []
        characteristics = [:]
        for value in values {
            guard let uuid = Self.uuid(value.uuid) else { fail(.invalidNativeEvent); return }
            let id = UUID(); characteristics[id] = value
            var properties: CharacteristicProperties = []
            if value.properties.contains(.read) { properties.insert(.read) }
            if value.properties.contains(.write) { properties.insert(.write) }
            if value.properties.contains(.writeWithoutResponse) { properties.insert(.writeWithoutResponse) }
            if value.properties.contains(.notify) { properties.insert(.notify) }
            if value.properties.contains(.indicate) { properties.insert(.indicate) }
            records.append(.init(id: id, uuid: uuid, properties: properties))
        }
        emit(.characteristics(records))
    }
    private static func uuid(_ value: CBUUID) -> UUID? {
        let data = value.data
        if data.count == 16 { return UUID(uuidString: value.uuidString) }
        if data.count == 2 { return UUID(uuidString: "0000" + value.uuidString + "-0000-1000-8000-00805F9B34FB") }
        if data.count == 4 { return UUID(uuidString: value.uuidString + "-0000-1000-8000-00805F9B34FB") }
        return nil
    }
    fileprivate func characteristic(_ target: CBPeripheral, characteristic: CBCharacteristic, token: UUID, kind: Int, failed: Bool) {
        guard generation == token, peripheral === target,
              let id = characteristics.first(where: { $0.value === characteristic })?.key else { return }
        if kind == 0 { emit(.notification(id, enabled: characteristic.isNotifying, failed: failed)) }
        else if kind == 1 {
            if failed { fail(.nativeFailure) } else { emit(.value(id, characteristic.value)) }
        } else { emit(.writeResponse(id, failed: failed)) }
    }
    fileprivate func ready(_ target: CBPeripheral, token: UUID) {
        guard generation == token, peripheral === target else { return }; emit(.writable)
    }
    fileprivate func invalidated(_ target: CBPeripheral, token: UUID) {
        guard generation == token, peripheral === target else { return }; fail(.serviceInvalidated)
    }
    fileprivate func stream(_ stream: Stream, event: Stream.Event, token: UUID) {
        guard generation == token, stream === input || stream === output else { return }
        if event.contains(.errorOccurred) { fail(.nativeFailure); return }
        if event.contains(.endEncountered) { fail(.streamEnded); return }
        if event.contains(.openCompleted) { emit(.streamsOpen(input: stream === input)) }
        guard generation == token else { return }
        if event.contains(.hasBytesAvailable), stream === input { emit(.inputReady) }
        if event.contains(.hasSpaceAvailable), stream === output { emit(.outputReady) }
    }
    fileprivate func fired(_ timer: Timer, token: UUID, isDrain: Bool) {
        guard generation == token else { timer.invalidate(); return }
        if isDrain {
            guard drainTimer === timer else { return }; drainTimer = nil; emit(.continueDrain)
        } else {
            guard deadlineTimer === timer else { return }; deadlineTimer = nil; emit(.deadline)
        }
    }
}

// Each generation gets a different bridge capturing its original token. These
// @preconcurrency conformances are narrowly confined to the documented main queue
// (CB manager) and main run loop (streams/timers), never arbitrary executors.
@MainActor private final class AppleDelegate: NSObject, @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate, @preconcurrency StreamDelegate {
    private weak var owner: AppleTransportPort?
    private let generation: UUID
    init(owner: AppleTransportPort, generation: UUID) { self.owner = owner; self.generation = generation }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { owner?.state(central, token: generation) }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        owner?.discovered(peripheral, manager: central, token: generation)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { owner?.connected(peripheral, manager: central, token: generation, failed: false) }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) { owner?.connected(peripheral, manager: central, token: generation, failed: true) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) { owner?.disconnected(peripheral, manager: central, token: generation) }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) { owner?.services(peripheral, token: generation, failed: error != nil) }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) { owner?.discoveredCharacteristics(peripheral, service: service, token: generation, failed: error != nil) }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) { owner?.characteristic(peripheral, characteristic: characteristic, token: generation, kind: 0, failed: error != nil) }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) { owner?.characteristic(peripheral, characteristic: characteristic, token: generation, kind: 1, failed: error != nil) }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) { owner?.characteristic(peripheral, characteristic: characteristic, token: generation, kind: 2, failed: error != nil) }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { owner?.ready(peripheral, token: generation) }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) { owner?.invalidated(peripheral, token: generation) }
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) { owner?.stream(aStream, event: eventCode, token: generation) }
    @objc func deadline(_ timer: Timer) { owner?.fired(timer, token: generation, isDrain: false) }
    @objc func drain(_ timer: Timer) { owner?.fired(timer, token: generation, isDrain: true) }
}
#endif
