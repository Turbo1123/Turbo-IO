import XCTest
@testable import RayNeoCompanion

@MainActor final class AlwaysOnTests: XCTestCase {
    func testGuideAndSwitchUseValueNotMode() throws {
        for cmd in ["life_log_guide", "life_log_switch"] {
            for enabled in [false, true] {
                let wire = try DeviceBusinessWire(AlwaysOnWire.launcher(cmd, enabled: enabled))
                XCTAssertEqual(wire.type, 20); XCTAssertEqual(wire.json["cmd"] as? String, cmd)
                let payload = try XCTUnwrap(wire.json["payload"] as? [String: Any])
                XCTAssertEqual(DeviceBusinessWire.integer(payload, "value"), enabled ? 1 : 0)
                XCTAssertEqual(DeviceBusinessWire.integer(payload, "mode"), 0)
                XCTAssertEqual(payload["data"] as? String, cmd == "life_log_switch" && enabled ? "{\"delay\":2}" : "")
            }
        }
        XCTAssertThrowsError(try AlwaysOnWire.launcher("unsupported", enabled: true))
        XCTAssertThrowsError(try AlwaysOnWire.start(""))
        let start = try DeviceBusinessWire(AlwaysOnWire.start("fixture"))
        XCTAssertEqual(start.type, 162); XCTAssertEqual(DeviceBusinessWire.integer(start.json, "idleTimeoutSec"), 30)
    }
    func testBatchSummaryPreservesUnusedBytesAndLegacy() throws {
        let batch = try DeviceBusinessWire(DeviceBusinessWire.encode(type: 163, json: ["frameCount": 99, "mode": 0], bytes: Data(repeating: 0, count: 240 * 32 + 3)))
        let summary = AlwaysOnWire.batchSummary(batch)
        XCTAssertEqual(summary.frames, 31); XCTAssertEqual(summary.unusedBytes, 243)
        let legacy = try DeviceBusinessWire(DeviceBusinessWire.encode(type: 163, json: [:], bytes: Data([1,2,3])))
        XCTAssertEqual(AlwaysOnWire.batchSummary(legacy).frames, 1)
    }
    func testBoundedProbeNeedsWakeStopsAndStoresMatchingTailWithoutQueryCache() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100
        var sends: [(UInt8, DeviceBusinessWire)] = []
        var voiceSuspended = false
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { "fixture-device" }, available: { true },
            suspendVoice: { voiceSuspended = true }, send: { sends.append(($0, try DeviceBusinessWire($1))) }, now: { now }, scheduleTimers: false)
        XCTAssertFalse(probe.active); XCTAssertTrue(sends.isEmpty)
        probe.start(); XCTAssertTrue(voiceSuspended); XCTAssertEqual(sends.count, 2)
        let wake = try DeviceBusinessWire.encode(type: 161, json: [:])
        probe.receive(device: "other", business: 13, packet: wake); XCTAssertEqual(sends.count, 2)
        probe.receive(device: "fixture-device", business: 13, packet: wake)
        probe.receive(device: "fixture-device", business: 13, packet: wake)
        XCTAssertEqual(sends.filter { $0.1.type == 162 }.count, 1)
        let task = try XCTUnwrap(sends.first { $0.1.type == 162 }?.1.json["taskId"] as? String)
        let packet = try DeviceBusinessWire.encode(type: 163, json: ["taskId": task, "frameCount": 1], bytes: Data(repeating: 1, count: 240))
        probe.receive(device: "fixture-device", business: 13, packet: packet)
        XCTAssertEqual(probe.audioBytes, 240)
        now = 125; probe.tick()
        XCTAssertTrue(sends.contains { $0.1.type == 166 })
        probe.receive(device: "fixture-device", business: 13, packet: packet)
        XCTAssertEqual(probe.audioBytes, 480); XCTAssertEqual(probe.tailPackets, 1)
        XCTAssertEqual(probe.receivedPackets, 2); XCTAssertEqual(probe.droppedPackets, 0)
        let off = try DeviceBusinessWire.encode(type: 21, json: ["cmd": "life_log_switch", "payload": ["value": 0, "mode": 1]])
        probe.receive(device: "fixture-device", business: 15, packet: off)
        now = 130; probe.tick()
        XCTAssertFalse(probe.active); XCTAssertFalse(probe.pendingStop)
        XCTAssertFalse(sends.contains { $0.1.type == 167 })
        let raw = try Data(contentsOf: XCTUnwrap(probe.directory).appendingPathComponent("envelopes.rnp"))
        XCTAssertEqual(raw.count, (packet.count + 4) * 2)
        XCTAssertEqual(raw.prefix(packet.count + 4).dropFirst(4), packet)
        XCTAssertEqual(raw.suffix(packet.count), packet)
    }
    func testStopFailureRetainedAcrossRelaunchAndNoAutomaticStart() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100; var connected = true; var calls = 0
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { connected ? "fixture" : nil }, available: { true }, suspendVoice: {}, send: { _,_ in calls += 1 }, now: { now }, scheduleTimers: false)
        probe.start(); connected = false; probe.connectionChanged(); now = 105; probe.tick()
        XCTAssertFalse(probe.active); XCTAssertTrue(probe.pendingStop)
        let restored = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { nil }, available: { true }, suspendVoice: {}, send: { _,_ in calls += 1 }, scheduleTimers: false)
        XCTAssertTrue(restored.pendingStop); XCTAssertFalse(restored.canStart); XCTAssertEqual(calls, 2)
    }
    func testResultSuccessRequiresSeparatePhysicalConfirmation() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { "fixture" }, available: { true },
            suspendVoice: {}, send: { _,_ in }, now: { now }, scheduleTimers: false)
        let ack = try DeviceBusinessWire.encode(type: 21, json: ["cmd": "life_log_switch_result", "payload": ["value": 0]])
        probe.start()
        probe.receive(device: "fixture", business: 15, packet: ack)
        XCTAssertFalse(probe.stopResultAcknowledged) // An ON reply is not a stop reply.
        probe.stop()
        probe.receive(device: "other", business: 15, packet: ack)
        XCTAssertFalse(probe.stopResultAcknowledged)
        probe.receive(device: "fixture", business: 15, packet: ack)
        XCTAssertTrue(probe.stopResultAcknowledged)
        probe.confirmPhysicalStop(); XCTAssertTrue(probe.pendingStop) // Active tail window.
        now = 105; probe.tick()
        XCTAssertTrue(probe.pendingStop); XCTAssertTrue(probe.canConfirmPhysicalStop)
        let manifest = try Data(contentsOf: XCTUnwrap(probe.directory).appendingPathComponent("manifest.json"))
        probe.confirmPhysicalStop()
        XCTAssertFalse(probe.pendingStop); XCTAssertFalse(probe.active)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(probe.directory).appendingPathComponent("manifest.json")), manifest)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("stop-confirmation-") })
    }
    func testRelaunchRequiresFreshStopAckAndLateAudioRevokesConfirmation() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        defaults.set("fixture", forKey: "companion.alwaysOn.localProbe.pendingDevice")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100; var connected = true
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { connected ? "fixture" : nil }, available: { true },
            suspendVoice: {}, send: { _,_ in }, now: { now }, scheduleTimers: false)
        let ack = try DeviceBusinessWire.encode(type: 21, json: ["cmd": "life_log_switch_result", "payload": ["value": 0]])
        probe.receive(device: "fixture", business: 15, packet: ack)
        XCTAssertFalse(probe.canConfirmPhysicalStop)
        probe.stop(); now = 111
        probe.receive(device: "fixture", business: 15, packet: ack)
        XCTAssertFalse(probe.canConfirmPhysicalStop) // Too late, no request ID on wire.
        probe.stop(); probe.receive(device: "fixture", business: 15, packet: ack)
        XCTAssertTrue(probe.canConfirmPhysicalStop)
        let audio = try DeviceBusinessWire.encode(type: 163, json: [:], bytes: Data([1,2,3]))
        probe.receive(device: "fixture", business: 13, packet: audio)
        XCTAssertFalse(probe.canConfirmPhysicalStop); XCTAssertEqual(probe.audioBytes, 0)
        probe.stop(); probe.receive(device: "fixture", business: 15, packet: ack)
        connected = false; probe.connectionChanged()
        XCTAssertFalse(probe.canConfirmPhysicalStop); XCTAssertTrue(probe.pendingStop)
    }
    func testObservedNinePacketStopBurstIsSavedWithinThirtySeconds() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100; var task = ""
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { "fixture" }, available: { true },
            suspendVoice: {}, send: { _, packet in
                let wire = try DeviceBusinessWire(packet)
                if wire.type == 162 { task = wire.json["taskId"] as? String ?? "" }
            }, now: { now }, scheduleTimers: false)
        probe.start(); now = 110
        probe.receive(device: "fixture", business: 13, packet: try DeviceBusinessWire.encode(type: 161, json: [:]))
        XCTAssertFalse(task.isEmpty)
        now = 125; probe.tick()
        now = 126
        for size in Array(repeating: 7440, count: 8) + [2400] {
            let packet = try DeviceBusinessWire.encode(type: 163, json: ["taskId": task, "frameCount": size / 240], bytes: Data(repeating: 7, count: size))
            probe.receive(device: "fixture", business: 13, packet: packet)
        }
        XCTAssertEqual(probe.audioBytes, 61920); XCTAssertEqual(probe.receivedAudioBytes, 61920)
        XCTAssertEqual(probe.packetCount, 9); XCTAssertEqual(probe.tailPackets, 9)
        XCTAssertEqual(probe.droppedPackets, 0)
        now = 130; probe.tick(); XCTAssertFalse(probe.active)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(probe.directory).appendingPathComponent("manifest.json"))) as! [String: Any]
        XCTAssertEqual(manifest["savedTailPackets"] as? Int, 9)
        XCTAssertEqual(manifest["audioBytes"] as? Int, 61920)
    }
    func testMissingAndWrongTaskIDsRejectedAndHardDeadlineNotExtendedByDelayedTimer() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100; var task = ""
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { "fixture" }, available: { true },
            suspendVoice: {}, send: { _, packet in
                let wire = try DeviceBusinessWire(packet)
                if wire.type == 162 { task = wire.json["taskId"] as? String ?? "" }
            }, now: { now }, scheduleTimers: false)
        probe.start()
        probe.receive(device: "fixture", business: 13, packet: try DeviceBusinessWire.encode(type: 161, json: [:]))
        for json: [String: Any] in [[:], ["taskId": "other"]] {
            probe.receive(device: "fixture", business: 13, packet: try DeviceBusinessWire.encode(type: 163, json: json, bytes: Data([1,2,3])))
        }
        let valid = try DeviceBusinessWire.encode(type: 163, json: ["taskId": task], bytes: Data([1,2,3]))
        now = 130 // Timer never fired at 125: receive still enforces the hard cap.
        probe.receive(device: "fixture", business: 13, packet: valid)
        now = 140; probe.tick()
        XCTAssertFalse(probe.active); XCTAssertEqual(probe.audioBytes, 0)
        XCTAssertEqual(probe.receivedPackets, 3); XCTAssertEqual(probe.droppedPackets, 3)
        XCTAssertEqual(probe.droppedAudioBytes, 9)
    }
    func testManualStopTailIsShortAndDisconnectNeverResumesSaving() throws {
        let defaults = UserDefaults(suiteName: "AlwaysOnTests.\(UUID())")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AlwaysOnTests-\(UUID())")
        var now: TimeInterval = 100; var task = ""; var connected = true
        let probe = AlwaysOnLocalProbe(defaults: defaults, root: root, device: { connected ? "fixture" : nil }, available: { true },
            suspendVoice: {}, send: { _, packet in
                let wire = try DeviceBusinessWire(packet)
                if wire.type == 162 { task = wire.json["taskId"] as? String ?? "" }
            }, now: { now }, scheduleTimers: false)
        probe.start()
        probe.receive(device: "fixture", business: 13, packet: try DeviceBusinessWire.encode(type: 161, json: [:]))
        let valid = try DeviceBusinessWire.encode(type: 163, json: ["taskId": task], bytes: Data([1,2,3]))
        now = 105; probe.stop()
        now = 106; probe.receive(device: "fixture", business: 13, packet: valid)
        XCTAssertEqual(probe.audioBytes, 3)
        connected = false; probe.connectionChanged()
        connected = true; probe.connectionChanged()
        now = 107; probe.receive(device: "fixture", business: 13, packet: valid)
        XCTAssertEqual(probe.audioBytes, 3); XCTAssertEqual(probe.droppedPackets, 1)
        now = 110; probe.tick(); XCTAssertFalse(probe.active)
    }
}
