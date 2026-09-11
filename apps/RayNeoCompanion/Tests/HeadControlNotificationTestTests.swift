import XCTest
@testable import RayNeoCompanion

@MainActor
final class HeadControlNotificationTestTests: XCTestCase {
    final class Link {
        var device: String? = "synthetic-glasses"
        var available = true
        var packets: [(UInt8, DeviceBusinessWire)] = []
    }

    private func fixture(_ link: Link = Link()) -> (HeadControlNotificationTest, Link) {
        let test = HeadControlNotificationTest(
            device: { link.device }, available: { link.available },
            transport: { business, data in link.packets.append((business, try DeviceBusinessWire(data))) },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }, scheduleTimers: false)
        return (test, link)
    }

    func testMatchingGestureDeletesCardAndAcknowledgesWithoutExternalAction() throws {
        let (test, link) = fixture()
        test.send(title: "测试", source: "Turbo IO", content: "点头确认")
        XCTAssertEqual(link.packets.count, 1)
        XCTAssertEqual(link.packets[0].0, 21)
        XCTAssertEqual(link.packets[0].1.type, 33)
        let id = try XCTUnwrap(link.packets[0].1.json["suggestUID"] as? String)
        XCTAssertEqual(DeviceBusinessWire.integer(link.packets[0].1.json, "type"), 1)
        XCTAssertEqual(DeviceBusinessWire.integer(link.packets[0].1.json, "suggestType"), 2)

        let callback = try DeviceBusinessWire(DeviceBusinessWire.encode(type: 34, json: [
            "suggestUID": id, "suggestType": 2, "cmd": 1
        ]))
        test.receive(device: "synthetic-glasses", wire: callback)

        XCTAssertNil(test.pendingID)
        XCTAssertEqual(test.lastDecision, "已收到点头确认（仅测试回调）")
        XCTAssertEqual(link.packets.count, 3)
        XCTAssertEqual(link.packets[1].1.type, 33)
        XCTAssertEqual(DeviceBusinessWire.integer(link.packets[1].1.json, "type"), 2)
        XCTAssertEqual(link.packets[2].1.type, 35)
        XCTAssertEqual(DeviceBusinessWire.integer(link.packets[2].1.json, "code"), 0)
    }

    func testMismatchedCallbackCannotConsumePendingTest() throws {
        let (test, link) = fixture()
        test.send(title: "测试", source: "Turbo IO", content: "点头确认")
        let id = try XCTUnwrap(test.pendingID)
        let callback = try DeviceBusinessWire(DeviceBusinessWire.encode(type: 34, json: [
            "suggestUID": UUID().uuidString, "suggestType": 2, "cmd": 1
        ]))
        test.receive(device: "synthetic-glasses", wire: callback)
        XCTAssertEqual(test.pendingID, id)
        XCTAssertEqual(link.packets.count, 1)
    }

    func testManualCancelOnlyDeletesTheLocalTestCard() throws {
        let (test, link) = fixture()
        test.send(title: "测试", source: "Turbo IO", content: "点头确认")
        test.cancel()
        XCTAssertNil(test.pendingID)
        XCTAssertEqual(link.packets.count, 2)
        XCTAssertEqual(link.packets[1].1.type, 33)
        XCTAssertEqual(DeviceBusinessWire.integer(link.packets[1].1.json, "type"), 2)
    }
}
