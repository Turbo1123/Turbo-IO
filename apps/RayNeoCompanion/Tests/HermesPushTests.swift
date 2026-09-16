import XCTest
import RayNeoSession
@testable import RayNeoCompanion

@MainActor final class HermesPushTests: XCTestCase {
    @MainActor final class Fixture {
        let defaults = UserDefaults(suiteName: "HermesPushTests.\(UUID())")!
        var endpoint = "https://synthetic.invalid"
        var state: HermesTaskState?
        var unresolved = false
        var ready = true
        var succeeds = true
        var sent: [(String, String)] = []

        func push() -> HermesPush {
            HermesPush(defaults: defaults, endpoint: { [unowned self] in self.endpoint },
                       snapshot: { [unowned self] in self.state },
                       hasUnfinishedTask: { [unowned self] in self.unresolved },
                       canDeliver: { [unowned self] in self.ready },
                       deliver: { [unowned self] title, body in
                           self.sent.append((title, body))
                           return self.succeeds ? "synthetic-uid" : nil
                       })
        }

        func task(_ status: String, prompt: String? = nil) -> HermesTaskState {
            var payload: [String: Any] = [
                "requestId": "11111111-1111-1111-1111-111111111111",
                "conversationId": "22222222-2222-2222-2222-222222222222",
                "status": status, "answer": "private answer", "summary": "private summary", "revision": 1,
            ]
            if let prompt {
                payload["prompt"] = ["id": "33333333-3333-3333-3333-333333333333",
                                     "kind": prompt, "title": "private request", "options": []]
            }
            return try! JSONDecoder().decode(HermesTaskState.self, from: JSONSerialization.data(withJSONObject: payload))
        }
    }

    func testOffDoesNotSendAndEnablingBaselinesExistingResult() {
        let fixture = Fixture()
        fixture.state = fixture.task("completed")
        let push = fixture.push()
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertTrue(fixture.sent.isEmpty)
        push.setEnabled(true)
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertTrue(fixture.sent.isEmpty)
    }

    func testNewApprovalSendsGenericReminderOnceWithoutTaskContent() {
        let fixture = Fixture()
        fixture.state = fixture.task("running")
        let push = fixture.push()
        push.setEnabled(true)
        fixture.state = fixture.task("waiting", prompt: "approval")
        push.tick(locale: Locale(identifier: "en"))
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
        XCTAssertEqual(fixture.sent.first?.0, "Hermes")
        XCTAssertEqual(fixture.sent.first?.1, "Hermes needs approval. Review on your iPhone.")
        XCTAssertFalse(fixture.sent.first!.1.contains("private"))
    }

    func testFirstFastTaskAfterEnablingWithoutSnapshotStillAlerts() {
        let fixture = Fixture()
        let push = fixture.push()
        push.setEnabled(true)
        fixture.state = fixture.task("completed")
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
    }

    func testExistingUnresolvedTaskWithoutSnapshotIsBaselined() {
        let fixture = Fixture()
        fixture.unresolved = true
        let push = fixture.push()
        push.setEnabled(true)
        fixture.state = fixture.task("waiting", prompt: "approval")
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertTrue(fixture.sent.isEmpty)
    }

    func testFirstTaskAfterConfiguringEndpointStillAlerts() {
        let fixture = Fixture()
        fixture.endpoint = ""
        let push = fixture.push()
        push.setEnabled(true)
        fixture.endpoint = "https://synthetic.invalid"
        fixture.state = fixture.task("completed")
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
    }

    func testBusyReminderSurvivesRestartAndSendsWhenReady() {
        let fixture = Fixture()
        fixture.state = fixture.task("running")
        let push = fixture.push()
        push.setEnabled(true)
        fixture.state = fixture.task("completed")
        fixture.ready = false
        push.tick(locale: Locale(identifier: "en"))
        XCTAssertTrue(fixture.sent.isEmpty)
        fixture.ready = true
        fixture.push().tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
        XCTAssertEqual(fixture.sent.first?.1, "Hermes task finished. Open Norman IO for the result.")
    }

    func testUncertainSendIsNotRepeatedAndEndpointChangeDoesNotReplay() {
        let fixture = Fixture()
        fixture.state = fixture.task("running")
        let push = fixture.push()
        push.setEnabled(true)
        fixture.state = fixture.task("failed")
        fixture.succeeds = false
        push.tick(locale: Locale(identifier: "en"))
        fixture.push().tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
        fixture.endpoint = "https://second.invalid"
        fixture.push().tick(locale: Locale(identifier: "en"))
        XCTAssertEqual(fixture.sent.count, 1)
    }
}
