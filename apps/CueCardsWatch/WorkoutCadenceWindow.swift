import Foundation

/// Cadence derived only from current-workout HealthKit cumulative step samples.
/// A 10–30 second observed window avoids treating irregular callbacks as 1 Hz samples.
struct WorkoutCadenceWindow {
    private var points: [(steps: Double, date: Date)] = []
    mutating func reset() { points.removeAll() }
    mutating func add(totalSteps: Double, date: Date) -> Double? {
        guard totalSteps.isFinite, totalSteps >= 0 else { return nil }
        if let last = points.last {
            guard date > last.date else { return nil }
            if totalSteps < last.steps || date.timeIntervalSince(last.date) > 30 { reset() }
        }
        points.append((totalSteps, date))
        points.removeAll { date.timeIntervalSince($0.date) > 30 }
        guard let first = points.first else { return nil }
        let seconds = date.timeIntervalSince(first.date)
        guard seconds >= 10 else { return nil }
        let cadence = (totalSteps - first.steps) * 60 / seconds
        return cadence.isFinite && (0...400).contains(cadence) ? cadence : nil
    }
}
