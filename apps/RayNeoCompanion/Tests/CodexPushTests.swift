import XCTest
@testable import RayNeoCompanion

@MainActor final class CodexPushTests: XCTestCase {
    @MainActor final class Fixture {
        var time = 10_000.0
        var packets = 0
        var network = 0
        var ready = true
        var succeeds = true
        var events: [[String: Any]] = []
        var pending: [[String: Any]] = []
        let defaults = UserDefaults(suiteName: "CodexPushTests.\(UUID())")!
        lazy var codex = CodexCompanion(defaults: defaults, key: { _ in "synthetic" }, send: { [unowned self] _, _, _, _ in
            self.network += 1
            return try JSONSerialization.data(withJSONObject: ["protocolVersion":1,"online":true,"workspace":"synthetic","readOnly":true,
                "tasks":[["id":"task-a","threadId":"thread-a","status":"已完成","answer":"sample","pending":self.pending]],"events":self.events])
        })
        func controller() -> CodexPush {
            CodexPush(codex: codex, defaults: defaults, now: { [unowned self] in self.time },
                canDeliver: { [unowned self] in self.ready }, deliver: { [unowned self] _,_ in self.packets += 1; return self.succeeds ? "123" : nil })
        }
        init() { defaults.set("https://synthetic.invalid", forKey:"companion.codex.v1.endpoint") }
        func event(_ id: String = "event-a", kind: String = "completed", created: Double = 10_001, expiry: Double = 100_000) -> [String: Any] {
            ["id":id,"taskId":"task-a","turnId":"turn-a","kind":kind,"title":"Codex test","content":"7392","createdAt":created,"expiresAt":expiry]
        }
    }
    func testOffDoesNotPollOrSend() async {
        let f = Fixture(); let p = f.controller(); f.events = [f.event()]
        await p.tick(); XCTAssertEqual(f.network,0); XCTAssertEqual(f.packets,0)
    }
    func testOldEventsIgnoredAndNewEventSentOnceAcrossRestart() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        f.events = [f.event("old",created:9999), f.event()]
        await p.tick(); await p.tick(); XCTAssertEqual(f.packets,1)
        let restored = f.controller(); await restored.tick(); XCTAssertEqual(f.packets,1)
    }
    func testBusyDefersWithoutLosingThenDispatches() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        f.events = [f.event()]; f.ready = false
        await p.tick(); XCTAssertEqual(p.pendingCount,1); XCTAssertEqual(f.packets,0)
        f.ready = true; await p.tick(); XCTAssertEqual(f.packets,1)
    }
    func testExpiredAndResolvedApprovalDoNotNotify() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        var approval = f.event("approval",kind:"approval"); approval["approvalId"]="request-a"
        f.events = [f.event("expired",expiry:10_001), approval]; await p.tick(); XCTAssertEqual(f.packets,0)
    }
    func testLiveApprovalOnlyNotifiesAndDoesNotAnswer() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        var event = f.event("approval",kind:"approval"); event["approvalId"]="request-a"; f.events=[event]
        f.pending=[["id":"request-a","taskId":"task-a","turnId":"turn-a","kind":"approval","summary":"review","questions":[],"expiresAt":100_000]]
        await p.tick(); XCTAssertEqual(f.packets,1); XCTAssertEqual(f.network,1)
    }
    func testUnknownSendNotRepeated() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        f.events=[f.event()]; f.succeeds=false
        await p.tick(); f.time += 10_000; await p.tick(); XCTAssertEqual(f.packets,1)
        XCTAssertTrue(p.status.contains("不自动重发"))
    }
    func testTwoTurnsSameAnswerStillTwoNotificationsSpacedOut() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        f.events=[f.event("one"),f.event("two")]
        await p.tick(); await p.tick(); XCTAssertEqual(f.packets,1)
        f.time += 8001; await p.tick(); XCTAssertEqual(f.packets,2)
    }
    func testChangedEndpointDoesNotReplayOldEvents() async {
        let f = Fixture(); let p = f.controller(); p.setEnabled(true); f.time += 10
        f.events=[f.event()]; try? f.codex.save(endpoint:"https://second.invalid",token:"",voiceTools:false)
        await p.tick(); XCTAssertEqual(f.packets,0)
    }
}
