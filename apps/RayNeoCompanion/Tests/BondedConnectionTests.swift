import XCTest
@testable import RayNeoCompanion

final class BondedConnectionTests: XCTestCase {
    func testColdLaunchReconnectsExistingBondWithoutVoiceOrCredentials() {
        var policy = BondedConnectionPolicy()
        XCTAssertEqual(policy.reconnectTarget(now: 0, bonded: ["a"], linked: [],
            authenticated: false, bluetoothOn: true, transportBusy: false), "a")
        XCTAssertEqual(policy.attempts, 1)
    }
    func testMissingAmbiguousOrCompetingTargetsNeverReconnect() {
        for (bonded, linked) in [([], []), (["a", "b"], []), (["a"], ["b"]), ([""], [])] as [([String], [String])] {
            var policy = BondedConnectionPolicy()
            XCTAssertNil(policy.reconnectTarget(now: 0, bonded: bonded, linked: linked,
                authenticated: false, bluetoothOn: true, transportBusy: false))
            XCTAssertEqual(policy.attempts, 0)
        }
    }
    func testBluetoothOffOrSDKConnectingDoesNotDrainBudget() {
        var policy = BondedConnectionPolicy()
        for now in 0..<20 {
            XCTAssertNil(policy.reconnectTarget(now: Double(now), bonded: ["a"], linked: [],
                authenticated: false, bluetoothOn: false, transportBusy: false))
            XCTAssertNil(policy.reconnectTarget(now: Double(now), bonded: ["a"], linked: ["a"],
                authenticated: false, bluetoothOn: true, transportBusy: true))
        }
        XCTAssertEqual(policy.attempts, 0)
    }
    func testBoundedBackoffAndExplicitBudgetReset() {
        var policy = BondedConnectionPolicy()
        func tick(_ now: Double) -> String? {
            policy.reconnectTarget(now: now, bonded: ["a"], linked: [],
                authenticated: false, bluetoothOn: true, transportBusy: false)
        }
        XCTAssertEqual(tick(0), "a")
        XCTAssertNil(tick(1.9))
        XCTAssertEqual(tick(2), "a")
        XCTAssertNil(tick(5.9))
        for time in [6.0, 14, 30, 60, 90, 120] { XCTAssertEqual(tick(time), "a") }
        XCTAssertEqual(policy.attempts, 8)
        XCTAssertNil(tick(1000))
        policy.resetBudget()
        XCTAssertEqual(tick(1001), "a")
    }
    func testReadyThenDisconnectResetsBudgetAndDoesNotSendWhileReady() {
        var policy = BondedConnectionPolicy()
        _ = policy.reconnectTarget(now: 0, bonded: ["a"], linked: [], authenticated: false,
            bluetoothOn: true, transportBusy: false)
        XCTAssertNil(policy.reconnectTarget(now: 1, bonded: ["a"], linked: ["a"],
            authenticated: true, bluetoothOn: true, transportBusy: true))
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertEqual(policy.reconnectTarget(now: 2, bonded: ["a"], linked: [],
            authenticated: false, bluetoothOn: true, transportBusy: false), "a")
    }
    func testUnbindRemovesTargetAndNewUniqueBondGetsFreshBudget() {
        var policy = BondedConnectionPolicy()
        _ = policy.reconnectTarget(now: 0, bonded: ["a"], linked: [], authenticated: false,
            bluetoothOn: true, transportBusy: false)
        XCTAssertNil(policy.reconnectTarget(now: 1, bonded: [], linked: [], authenticated: false,
            bluetoothOn: true, transportBusy: false))
        XCTAssertNil(policy.target)
        XCTAssertEqual(policy.reconnectTarget(now: 2, bonded: ["b"], linked: [], authenticated: false,
            bluetoothOn: true, transportBusy: false), "b")
        XCTAssertEqual(policy.attempts, 1)
    }
}
