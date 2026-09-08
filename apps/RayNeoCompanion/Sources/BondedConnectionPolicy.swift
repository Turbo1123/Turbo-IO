import Foundation

/// Device transport only: deliberately has no voice, recording, or cloud switch.
struct BondedConnectionPolicy {
    private(set) var target: String?
    private(set) var attempts = 0
    private var nextAttempt: TimeInterval = 0

    mutating func resetBudget() { attempts = 0; nextAttempt = 0 }

    mutating func reconnectTarget(now: TimeInterval, bonded: [String], linked: [String],
                                  authenticated: Bool, bluetoothOn: Bool,
                                  transportBusy: Bool) -> String? {
        // Never choose arbitrarily among multiple bonds, or replace another link.
        guard bonded.count == 1, let selected = bonded.first, !selected.isEmpty else {
            target = nil; resetBudget(); return nil
        }
        if target != selected { target = selected; resetBudget() }
        guard linked.allSatisfy({ $0 == selected }) else { return nil }
        if authenticated { resetBudget(); return nil }
        guard bluetoothOn, !transportBusy, attempts < 8, now >= nextAttempt else { return nil }
        attempts += 1
        nextAttempt = now + min(30, pow(2, Double(attempts)))
        return selected
    }
}
