import Foundation

/// One owner-authorized parameter experiment, not a supported custom-word API.
public struct WakeWordDataTrial {
    public enum Phase { case idle, testing, needsRestore, restoreSubmitted }
    public private(set) var phase: Phase = .idle
    public private(set) var target: String?
    public private(set) var attempted = false
    private var restoreAt: TimeInterval?
    public enum TrialError: Error { case invalidInput, invalidState, wrongTarget }

    public init(recoveryTarget: String? = nil, attempted: Bool = false) {
        target = recoveryTarget.flatMap { $0.isEmpty ? nil : $0 }
        self.attempted = attempted || target != nil
        phase = target == nil ? .idle : .needsRestore
    }

    /// Only data changes from the observed mode=1/value=0/empty-data command.
    /// Whether firmware interprets data as a keyword is the hypothesis under test.
    public static func candidatePacket() throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["cmd": "set_ai_wakeup_word", "payload": ["data": "Hey Norman", "mode": 1, "value": 0]], options: [.sortedKeys])
        precondition(body.count < 128)
        return Data([8,1,16,16,26,UInt8(body.count)]) + body + Data([34,0])
    }
    public static func restorePacket() throws -> Data {
        try LauncherControlPrototype.encode(.officialWakeWord)
    }
    /// Caller persists target/attempted before submitting the returned packet.
    public mutating func begin(device: String, now: TimeInterval) throws -> Data {
        guard !device.isEmpty, now.isFinite else { throw TrialError.invalidInput }
        guard !attempted, target == nil else { throw TrialError.invalidState }
        let packet = try Self.candidatePacket()
        target = device; attempted = true; phase = .testing; restoreAt = now + 120
        return packet
    }
    public mutating func automaticRestore(device: String?, now: TimeInterval) throws -> Data? {
        guard now.isFinite, let target, target == device else { return nil }
        guard phase == .needsRestore || (phase == .testing && restoreAt.map { now >= $0 } == true) else { return nil }
        return try restore(device: device)
    }
    /// Submission is not evidence that the original wake phrase is restored.
    public mutating func restore(device: String?) throws -> Data {
        guard let target, target == device else { throw TrialError.wrongTarget }
        let packet = try Self.restorePacket()
        phase = .restoreSubmitted; restoreAt = nil
        return packet
    }
    public mutating func confirmRestored(device: String?) throws {
        guard let target, target == device else { throw TrialError.wrongTarget }
        guard phase == .restoreSubmitted else { throw TrialError.invalidState }
        self.target = nil; phase = .idle; restoreAt = nil
    }
    public mutating func requireRecovery() {
        if target != nil, phase == .testing { phase = .needsRestore; restoreAt = nil }
    }
}
