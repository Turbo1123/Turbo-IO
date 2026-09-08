import Foundation

public enum TransportKind: Sendable { case bluetooth, externalAccessory }
public enum CentralState: Sendable { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
public enum TransportPhase: Sendable { case idle, prepared, scanning, connecting, connected, discovering, discovered, subscribing, openingStreams, streamsOpened, closed }
public enum BLEWriteMode: Sendable { case withResponse, withoutResponse }
public enum WriteReceipt: Sendable { case coreBluetoothResponseReceived, submittedWithoutResponse, outputStreamConsumed }

public enum TransportError: Error, Equatable, Sendable {
    case invalidLimits, invalidTimeout, invalidClock, wrongKind, invalidState, pendingEvents
    case staleHandle, poweredOff, candidateLimit, characteristicLimit, missingCharacteristic
    case ambiguousCharacteristic, unsupportedProperty, emptyWrite, writeTooLarge, queueFull
    case eventBufferOverflow, timedOut, cancelled, nativeFailure, disconnected, serviceInvalidated
    case invalidNativeEvent, nilValue, streamEnded, noProgress, driverContractViolation
}

public struct TransportLimits: Equatable, Sendable {
    public let candidates, characteristics, writeBytes, queuedBytes, queuedWrites: Int
    public let eventBytes, events, scratchBytes, drainBytes, drainOperations: Int
    public init(candidates: Int = 64, characteristics: Int = 16, writeBytes: Int = 65_536,
                queuedBytes: Int = 131_072, queuedWrites: Int = 32, eventBytes: Int = 262_144,
                events: Int = 128, scratchBytes: Int = 4_096, drainBytes: Int = 65_536,
                drainOperations: Int = 16) throws {
        guard (1...256).contains(candidates), (1...64).contains(characteristics),
              (1...1_048_576).contains(writeBytes), (writeBytes...4_194_304).contains(queuedBytes),
              (1...128).contains(queuedWrites), (1...4_194_304).contains(eventBytes),
              (1...1_024).contains(events), (1...65_536).contains(scratchBytes),
              (scratchBytes...1_048_576).contains(drainBytes), (1...256).contains(drainOperations)
        else { throw TransportError.invalidLimits }
        self.candidates = candidates; self.characteristics = characteristics
        self.writeBytes = writeBytes; self.queuedBytes = queuedBytes; self.queuedWrites = queuedWrites
        self.eventBytes = eventBytes; self.events = events; self.scratchBytes = scratchBytes
        self.drainBytes = drainBytes; self.drainOperations = drainOperations
    }
}

public struct CandidateHandle: Hashable, Sendable {
    let owner: UUID, generation: UUID, discovery: UUID, native: UUID
}
public struct CharacteristicHandle: Hashable, Sendable {
    let owner: UUID, generation: UUID, native: UUID
}
public struct WriteHandle: Hashable, Sendable {
    let owner: UUID, generation: UUID, sequence: UInt64
}
public struct Candidate: Sendable {
    public let handle: CandidateHandle
    // The library deliberately does not request or retain names/serial numbers.
}
public struct CharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let read = Self(rawValue: 1)
    public static let write = Self(rawValue: 2)
    public static let writeWithoutResponse = Self(rawValue: 4)
    public static let notify = Self(rawValue: 8)
    public static let indicate = Self(rawValue: 16)
}
public struct Characteristic: Sendable {
    public let handle: CharacteristicHandle
    public let uuid: UUID
    public let properties: CharacteristicProperties
}
public enum RayNeoIOProfile {
    public static let service = UUID(uuidString: "0000B81D-0000-1000-8000-00805F9B34FB")!
    public static let outbound = UUID(uuidString: "EA8B70D5-2BD3-49AB-9C31-9C38B2C3C4F9")!
    public static let inbound = UUID(uuidString: "7DB3E235-3608-41F3-A03C-955FCBD2EA4B")!
    public static let file = UUID(uuidString: "87654321-4321-4321-4321-ABCDEF123456")!
    public static let heart = UUID(uuidString: "EA8B61C6-2BD3-49AB-9C31-9D38B2C6C6F9")!
    public static let paired = UUID(uuidString: "EA8B60C5-2BD3-49AB-9C31-9D38B1C5C5F9")!
    public static let accessoryProtocol = "com.rayneo.venus.pub"
}
public struct WriteFailure: Sendable {
    public let handle: WriteHandle
    public let reason: TransportError
    public let submittedByteCount: Int
    public let deliveryUncertain: Bool
}
public enum ByteSource: Sendable { case bluetooth(CharacteristicHandle), externalAccessory }
public enum TransportEvent: Sendable {
    case centralState(CentralState)
    case candidate(Candidate)
    case scanStopped(TransportError?)
    case connected
    case discovered([Characteristic])
    case subscriptionConfirmed(CharacteristicHandle)
    case streamsOpened
    case received(ByteSource, Data)
    case writeCompleted(WriteHandle, WriteReceipt)
    case writeFailed(WriteFailure)
    case closedLocally(TransportError)
}
public struct TransportSnapshot: Sendable {
    public let phase: TransportPhase
    public let centralState: CentralState
    public let terminalReason: TransportError?
    public let queuedWriteCount, retainedWriteBytes, pendingEventCount, pendingEventBytes: Int
    /// Sticky for the life of this object; prepare never claims earlier bytes were revoked.
    public let deliveryUncertain: Bool
    /// Remains available even when the event buffer overflowed. Bounded by queuedWrites.
    public let terminalWriteFailures: [WriteFailure]
}

// Backend SPI: public to permit the separate Apple target and deterministic fake ports.
// Apps normally use the IOS façades, not this trusted-driver interface.
public struct NativeCharacteristic: Sendable {
    public let id: UUID, uuid: UUID
    public let properties: CharacteristicProperties
    public init(id: UUID, uuid: UUID, properties: CharacteristicProperties) {
        self.id = id; self.uuid = uuid; self.properties = properties
    }
}
public enum NativeEvent: Sendable {
    case central(CentralState), candidate(UUID), connected
    case characteristics([NativeCharacteristic])
    case notification(UUID, enabled: Bool, failed: Bool)
    case value(UUID, Data?)
    case writeResponse(UUID, failed: Bool)
    case writable, inputReady, outputReady, streamsOpen(input: Bool)
    case deadline, continueDrain
    case failure(TransportError)
}
public enum NativeEffect: Sendable {
    case prepare(UUID, TransportKind), scan, stopScan, enumerateAccessories
    case connect(UUID), discover, subscribe(UUID), openAccessory(UUID)
    case scheduleDeadline(UInt64?), scheduleDrain, close
}
@MainActor public protocol TransportPort: AnyObject {
    var receive: (@MainActor (UUID, NativeEvent) -> Void)? { get set }
    func perform(_ effect: NativeEffect)
    func maximumWriteLength(_ mode: BLEWriteMode) -> Int
    var canWriteWithoutResponse: Bool { get }
    func writeBLE(_ bytes: Data, characteristic: UUID, mode: BLEWriteMode)
    var inputAvailable: Bool { get }
    var outputAvailable: Bool { get }
    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> Int
    func write(_ bytes: UnsafeBufferPointer<UInt8>) -> Int
}
