import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    count += 1
    if !condition() { fatalError("FAIL: \(label)") }
}
let sid = UUID()
check(RemoteInputMapping.doubleTapBrowses.doubleTapAction == .next, "default double tap browses")
check(RemoteInputMapping.doubleTapBrowses.wristAction(direction: 1) == .press, "default right wrist confirms")
check(RemoteInputMapping.doubleTapBrowses.wristAction(direction: -1) == .press, "default left wrist confirms")
check(RemoteInputMapping.doubleTapConfirms.doubleTapAction == .press, "alternate double tap confirms")
check(RemoteInputMapping.doubleTapConfirms.wristAction(direction: -1) == .previous, "alternate left wrist previous")
check(RemoteInputMapping.doubleTapConfirms.wristAction(direction: 1) == .next, "alternate right wrist next")
func command(_ seq: UInt64, at: Double = 100, session: UUID = sid) -> RemoteCommand {
    RemoteCommand(version: 1, id: UUID(), session: session, sequence: seq, sentAt: at, action: .press)
}
var gate = RemoteGate()
check(!gate.accept(command(1), now: 100, enabled: true), "must handshake")
gate.begin(sid)
check(!gate.accept(command(1), now: 100, enabled: false), "disabled")
check(!gate.accept(command(1, session: UUID()), now: 100, enabled: true), "foreign session")
check(!gate.accept(command(1, at: 95), now: 100, enabled: true), "expired")
check(!gate.accept(command(1, at: 103), now: 100, enabled: true), "future")
check(gate.accept(command(1), now: 100, enabled: true), "first")
check(!gate.accept(command(1), now: 100.5, enabled: true), "duplicate")
check(!gate.accept(command(2), now: 100.1, enabled: true), "rate limited")
check(gate.accept(command(3, at: 100.5), now: 100.5, enabled: true), "next")
check(!gate.accept(command(2), now: 101, enabled: true), "out of order")
var detector = WristDetector()
func feed(_ roll: Double, _ time: Double, acceleration: Double = 0) -> Int? {
    detector.sample(roll: roll, acceleration: acceleration, time: time)
}
for i in 0...10 { check(feed(Double(i % 2) * 0.05, Double(i) * 0.05) == nil, "neutral jitter") }
check(feed(0.8, 0.6) == nil, "excursion alone not step")
check(feed(0.9, 0.7) == nil, "held")
check(feed(0.0, 0.85) == 1, "right return")
check(feed(-0.8, 0.95) == nil, "cooldown")
detector.reset()
for i in 0...10 { _ = feed(0, Double(i) * 0.05) }
_ = feed(-0.8, 0.6)
_ = feed(-0.7, 0.7)
check(feed(0, 0.85) == -1, "left return")
detector.reset()
for i in 0...10 { _ = feed(0, Double(i) * 0.05) }
_ = feed(0.8, 0.6)
check(feed(0, 0.65) == nil, "very fast spike")
detector.reset()
for i in 0...10 { _ = feed(0, Double(i) * 0.05) }
_ = feed(0.8, 0.6, acceleration: 1)
check(feed(0, 0.8) == nil, "impact rejection")
check(feed(.nan, 0.9) == nil, "nonfinite")
detector.reset()
for i in 0...10 { _ = feed(0, Double(i) * 0.05) }
_ = feed(0.8, 0.6)
check(feed(0, 4) == nil, "sample gap invalidates gesture")
let data = try JSONEncoder().encode(command(1))
let decoded = try JSONDecoder().decode(RemoteCommand.self, from: data)
check(decoded.action == .press, "wire roundtrip")
var crown = CrownDetector()
check(crown.sample(0) == nil, "crown initial anchor")
check(crown.sample(0.4) == nil, "crown jitter")
check(crown.sample(1) == .next, "crown next")
check(crown.sample(0) == .previous, "crown previous")
check(crown.sample(50) == .next, "fast crown one step only")
check(crown.sample(50) == nil, "no deferred backlog")
check(crown.sample(-999) == nil, "crown wrap ignored")
crown.reset(at: 3)
check(crown.sample(3) == nil, "rearm rebases")
check(crown.sample(.nan) == nil, "crown nonfinite")
check(crown.sample(100) == nil, "after invalid rebase")
print("PASS \(count) core checks; no hardware actions")
