import Foundation

enum RemoteAction: String, Codable, CaseIterable {
    case previous, next, press, back
    var title: String {
        switch self {
        case .previous: return "上一项"
        case .next: return "下一项"
        case .press: return "确认"
        case .back: return "返回 / 长按"
        }
    }
}

enum RemoteInputMapping: String, CaseIterable {
    case doubleTapBrowses, doubleTapConfirms
    var title: String { self == .doubleTapBrowses ? "双指翻项 · 转腕确认" : "双指确认 · 转腕翻项" }
    var doubleTapAction: RemoteAction { self == .doubleTapBrowses ? .next : .press }
    func wristAction(direction: Int) -> RemoteAction {
        self == .doubleTapBrowses ? .press : (direction > 0 ? .next : .previous)
    }
}

// R0 transport only. There is deliberately no firmware opcode in this envelope.
struct RemoteCommand: Codable {
    let version: Int
    let id: UUID
    let session: UUID
    let sequence: UInt64
    let sentAt: Double
    let action: RemoteAction
}

struct RemoteGate {
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var lastAccepted: Double = -.infinity

    mutating func begin(_ newSession: UUID) {
        session = newSession
        sequence = 0
        lastAccepted = -.infinity
    }

    mutating func accept(_ command: RemoteCommand, now: Double, enabled: Bool) -> Bool {
        guard enabled, command.version == 1, command.session == session,
              command.sequence > sequence, command.sentAt.isFinite, now.isFinite,
              now - command.sentAt >= -1, now - command.sentAt <= 2,
              now - lastAccepted >= 0.35 else { return false }
        sequence = command.sequence
        lastAccepted = now
        return true
    }
}

// Quantized, one step per change, no queued backlog after fast crown spinning.
// The caller rebases whenever the control page is hidden or disarmed.
struct CrownDetector {
    private var anchor: Double?
    mutating func reset(at value: Double? = nil) { anchor = value }
    mutating func sample(_ value: Double) -> RemoteAction? {
        guard value.isFinite else { anchor = nil; return nil }
        guard let origin = anchor else { anchor = value; return nil }
        let delta = value - origin
        // Continuous binding wraps at +/-1000; never interpret wrap as motion.
        guard abs(delta) < 100 else { anchor = value; return nil }
        guard abs(delta) >= 1 else { return nil }
        anchor = value
        return delta > 0 ? .next : .previous
    }
}

// Relative roll excursion AND return-to-neutral. One excursion yields one step.
// Thresholds are conservative starting values, not measured S12 accuracy.
struct WristDetector {
    private var origin: Double?
    private var lastTime: Double?
    private var candidate: (direction: Int, started: Double)?
    private var neutralSince: Double?
    private var ready = false
    private var cooldownUntil = 0.0

    mutating func reset() { self = WristDetector() }

    mutating func sample(roll: Double, acceleration: Double, time: Double) -> Int? {
        guard roll.isFinite, acceleration.isFinite, time.isFinite else { reset(); return nil }
        if let lastTime, time <= lastTime || time - lastTime > 0.25 { reset() }
        lastTime = time
        if origin == nil { origin = roll; neutralSince = time; return nil }
        let delta = atan2(sin(roll - origin!), cos(roll - origin!))
        guard acceleration < 0.65 else {
            candidate = nil; ready = false; neutralSince = nil
            cooldownUntil = time + 0.7; return nil
        }
        guard time >= cooldownUntil else { return nil }
        if let pending = candidate {
            let elapsed = time - pending.started
            if elapsed > 1.2 || delta * Double(pending.direction) < -0.35 {
                candidate = nil; ready = false; neutralSince = nil
                return nil
            }
            if abs(delta) < 0.20 {
                candidate = nil; ready = false; neutralSince = nil
                cooldownUntil = time + 0.65
                return elapsed >= 0.12 ? pending.direction : nil
            }
            return nil
        }
        if abs(delta) < 0.20 {
            if neutralSince == nil { neutralSince = time }
            if time - neutralSince! >= 0.35 { ready = true }
        } else if ready && abs(delta) >= 0.70 {
            candidate = (delta > 0 ? 1 : -1, time)
            neutralSince = nil
        } else if !ready { neutralSince = nil }
        return nil
    }
}
