import XCTest
@testable import RayNeoCompanion

final class NotificationWireTests: XCTestCase {
    func testProductRenamePreservesSavedSourceIdentityAndPermissions() throws {
        var old = NotificationPreferences()
        old.enabled = true; old.displayTime = 15
        old.sources[0].name = "伴镜" // Historical preference fixture, not current UI copy.
        old.sources[0].allowed = false
        old.sources[2].name = "用户自定义名称"; old.sources[2].allowed = false
        let restored = try JSONDecoder().decode(NotificationPreferences.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(restored.sources[0].name, "Turbo IO")
        XCTAssertEqual(restored.sources.map(\.id), old.sources.map(\.id))
        XCTAssertEqual(restored.sources.map(\.allowed), old.sources.map(\.allowed))
        XCTAssertEqual(restored.sources.dropFirst(), old.sources.dropFirst())
        XCTAssertEqual(restored.enabled, old.enabled)
        XCTAssertEqual(restored.displayTime, old.displayTime)
        XCTAssertEqual(try GlassesNotificationProtocol.settings(restored), try GlassesNotificationProtocol.settings(old))
    }
    func testDuration15ChangesOnlyDisplayTime() throws {
        var p = NotificationPreferences(); p.enabled = true; p.sources[2].allowed = false
        var original = try DeviceBusinessWire(GlassesNotificationProtocol.settings(p)).json
        p.displayTime = 15
        var updated = try DeviceBusinessWire(GlassesNotificationProtocol.settings(p)).json
        XCTAssertEqual(DeviceBusinessWire.integer(updated,"displayTime"),15)
        original.removeValue(forKey:"displayTime"); updated.removeValue(forKey:"displayTime")
        XCTAssertEqual(NSDictionary(dictionary:original),NSDictionary(dictionary:updated))
        p.displayTime = 0; XCTAssertThrowsError(try GlassesNotificationProtocol.settings(p))
    }
    func testLegacyDurationDecodePreservesSources() throws {
        var p = NotificationPreferences(); p.enabled=true; p.sources[2].allowed=false
        let data = try JSONEncoder().encode(p)
        var json = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        json.removeValue(forKey:"displayTime")
        let restored = try JSONDecoder().decode(NotificationPreferences.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(restored.displayTime,5); XCTAssertEqual(restored.sources,p.sources); XCTAssertTrue(restored.enabled)
    }
    func testIOSDirectTemplateMatchesHiddenOfficialDevButton() throws {
        let wire = try DeviceBusinessWire(GlassesNotificationProtocol.notification(uid: "12345", title: "合成标题", content: "第一行\n第二行", date: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertEqual(GlassesNotificationProtocol.business, 21)
        XCTAssertEqual(wire.type, 2); XCTAssertTrue(wire.bytes.isEmpty)
        XCTAssertEqual(Set(wire.json.keys), Set(["notificationUID","appId","appName","title","subtitle","content","timestamp","category","reply","type"]))
        XCTAssertEqual(wire.json["notificationUID"] as? String, "12345")
        XCTAssertEqual(wire.json["appId"] as? String, "io.turboio.companion")
        XCTAssertEqual(wire.json["appName"] as? String, "Turbo IO")
        XCTAssertEqual(wire.json["subtitle"] as? String, "")
        XCTAssertEqual(DeviceBusinessWire.integer(wire.json, "category"), 0)
        XCTAssertEqual(DeviceBusinessWire.boolean(wire.json, "reply"), false)
        XCTAssertEqual(DeviceBusinessWire.integer(wire.json, "type"), 1)
        let timestamp = try XCTUnwrap(wire.json["timestamp"] as? String)
        XCTAssertEqual(timestamp.count, 23); XCTAssertTrue(timestamp.contains("T")); XCTAssertFalse(timestamp.hasSuffix("Z"))
    }
    func testInvalidNotificationInputIsRejectedNotSilentlyTruncated() {
        for uid in ["0", "-1", "01", "2147483648", "uuid", "1.5"] {
            XCTAssertThrowsError(try GlassesNotificationProtocol.notification(uid: uid, title: "合成", content: "合成"))
        }
        for (title, content) in [("", "合成"), ("合成", "  \n"), (String(repeating:"字",count:81), "合成"), ("合成", String(repeating:"字",count:501)), ("合成", "bad\u{0000}")] {
            XCTAssertThrowsError(try GlassesNotificationProtocol.notification(uid: "1", title: title, content: content))
        }
    }
    func testFilterUIDContainsDisabledAppsNotAllowedApps() throws {
        var p = NotificationPreferences(); p.enabled = true
        p.sources[1].allowed = false; p.sources[3].allowed = false
        let wire = try DeviceBusinessWire(GlassesNotificationProtocol.settings(p))
        XCTAssertEqual(wire.type, 17)
        XCTAssertEqual(DeviceBusinessWire.boolean(wire.json,"notification"), true)
        XCTAssertEqual(DeviceBusinessWire.boolean(wire.json,"callNotification"), false)
        XCTAssertEqual(DeviceBusinessWire.boolean(wire.json,"avoidDuplicate"), false)
        XCTAssertEqual(DeviceBusinessWire.integer(wire.json,"displayTime"), 5)
        XCTAssertEqual(DeviceBusinessWire.integer(wire.json,"intervalTime"), 2)
        XCTAssertEqual(wire.json["filterUID"] as? [String], ["com.apple.mobilemail", "com.apple.mobilephone"])
    }
    func testSourceIDsRemainCaseSensitiveAndRejectUnsafeOrDuplicateIdentifiers() throws {
        XCTAssertTrue(GlassesNotificationProtocol.validAppID("com.apple.MobileSMS"))
        for id in ["", "plain", "com..app", "com.foo/bar", "com.应用", "com.app\n"] { XCTAssertFalse(GlassesNotificationProtocol.validAppID(id)) }
        var p = NotificationPreferences(); p.sources.append(p.sources[0])
        XCTAssertThrowsError(try GlassesNotificationProtocol.settings(p))
        XCTAssertTrue(GlassesNotificationProtocol.stateLabel(0).contains("不代表已读"))
        XCTAssertTrue(GlassesNotificationProtocol.stateLabel(99).contains("未知"))
    }
}

@MainActor final class NotificationControllerTests: XCTestCase {
    final class Link {
        var device: String? = "synthetic-glasses-A"
        var busy = false
        var fails = false
        var packets: [DeviceBusinessWire] = []
        var immediate: ((DeviceBusinessWire) -> Void)?
    }
    private func fixture(_ link: Link = Link(), timeout: UInt64 = 30_000_000) -> (CompanionNotifications, Link, UserDefaults) {
        let suite = "notification-unit-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let c = CompanionNotifications(defaults: defaults, device: { link.device }, isBusy: { link.busy }, timeoutNanoseconds: timeout) { business, data in
            XCTAssertEqual(business, 21)
            if link.fails { throw DeviceFeatureError.disconnected }
            let wire = try DeviceBusinessWire(data)
            link.packets.append(wire); link.immediate?(wire)
        }
        return (c, link, defaults)
    }
    private func receive(_ c: CompanionNotifications, type: UInt32, json: [String: Any], device: String = "synthetic-glasses-A", bytes: Data = Data()) throws {
        c.receive(device: device, wire: try DeviceBusinessWire(DeviceBusinessWire.encode(type:type,json:json,bytes:bytes)))
    }
    func testDurationDraftPersistsWithoutImplicitFullSettingsSend() throws {
        let (c, link, defaults) = fixture()
        c.setDisplayTime(15); XCTAssertTrue(link.packets.isEmpty)
        let restored = CompanionNotifications(defaults:defaults,device:{link.device},isBusy:{false}) {_,_ in}
        XCTAssertEqual(restored.preferences.displayTime,15)
        c.applySources(); XCTAssertEqual(DeviceBusinessWire.integer(link.packets[0].json,"displayTime"),15)
    }
    func testOpeningControllerNeverSendsAndOfflineEditsPersistWithoutEnablingDevice() {
        let link = Link(); link.device = nil
        let (c, _, defaults) = fixture(link)
        XCTAssertTrue(link.packets.isEmpty); XCTAssertFalse(c.preferences.enabled)
        c.setEnabled(true); c.setAllowed("com.apple.MobileSMS",false)
        XCTAssertTrue(link.packets.isEmpty); XCTAssertTrue(c.sourcesNeedApply)
        let restored = CompanionNotifications(defaults: defaults, device: { nil }, isBusy: { false }) { _,_ in XCTFail("unexpected write") }
        XCTAssertTrue(restored.preferences.enabled)
        XCTAssertEqual(restored.preferences.sources.first(where: { $0.id == "com.apple.MobileSMS" })?.allowed, false)
        XCTAssertNil(restored.reportedEnabled)
        XCTAssertFalse(restored.canTest)
    }
    func testMasterAndSourceApplicationAreDifferentWireTypes() throws {
        let (c, link, _) = fixture()
        c.setEnabled(true)
        XCTAssertEqual(link.packets.map(\.type), [18]); XCTAssertTrue(c.sourcesNeedApply)
        c.setAllowed("com.apple.MobileSMS",false)
        XCTAssertEqual(link.packets.count,1)
        c.applySources()
        XCTAssertEqual(link.packets.map(\.type), [18,17]); XCTAssertFalse(c.sourcesNeedApply)
        XCTAssertEqual(link.packets.last?.json["filterUID"] as? [String], ["com.apple.MobileSMS"])
        XCTAssertNil(c.reportedEnabled) // Submission is not a device ACK.
    }
    func testNewSourceValidationDedupAndCorruptPreferencesFallback() {
        let (c, _, defaults) = fixture()
        XCTAssertTrue(c.addSource(name:"合成 App",id:"com.example.synthetic"))
        XCTAssertFalse(c.addSource(name:"重复",id:"com.example.synthetic"))
        XCTAssertFalse(c.addSource(name:"坏标识",id:"com..bad"))
        defaults.set(Data("not JSON".utf8),forKey:"companion.v1.notificationPreferences")
        let restored = CompanionNotifications(defaults:defaults,device:{nil},isBusy:{false}) {_,_ in XCTFail()}
        XCTAssertFalse(restored.preferences.enabled); XCTAssertEqual(restored.preferences.sources.count,5)
    }
    func testDirectSendIsBlockedOfflineBusyDisabledOrOwnSourceDenied() {
        let (c, link, _) = fixture()
        XCTAssertNil(c.send(title:"合成",content:"合成")); XCTAssertTrue(link.packets.isEmpty)
        c.setEnabled(true); link.packets = []
        c.setAllowed(GlassesNotificationProtocol.companionAppID,false)
        XCTAssertNil(c.send(title:"合成",content:"合成"))
        c.setAllowed(GlassesNotificationProtocol.companionAppID,true); link.busy = true
        XCTAssertNil(c.send(title:"合成",content:"合成"))
        link.busy = false; link.device = nil
        XCTAssertNil(c.send(title:"合成",content:"合成")); XCTAssertTrue(link.packets.isEmpty)
    }
    func testSameUIDAndDeviceRequiredForStateAndRawOperation() throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        let uid = try XCTUnwrap(c.send(title:"合成",content:"合成"))
        XCTAssertTrue(c.awaitingState); XCTAssertEqual(link.packets.last?.type,2)
        try receive(c,type:3,json:["notificationUID":"other","state":1])
        try receive(c,type:3,json:["notificationUID":uid,"state":1],device:"other-device")
        try receive(c,type:3,json:["notificationUID":uid,"state":true])
        try receive(c,type:3,json:["notificationUID":uid,"state":1],bytes:Data([1]))
        XCTAssertTrue(c.awaitingState)
        try receive(c,type:4,json:["notificationUID":uid,"cmd":1])
        XCTAssertTrue(c.operationStatus?.contains("不执行任何工具") == true)
        XCTAssertTrue(c.awaitingState)
        try receive(c,type:3,json:["notificationUID":uid,"state":3])
        XCTAssertFalse(c.awaitingState); XCTAssertTrue(c.testStatus.contains("免打扰"))
    }
    func testImmediateCallbackDuringSubmissionIsNotLost() throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        link.immediate = { [weak c] wire in
            guard wire.type == 2, let c else { return }
            try? self.receive(c,type:3,json:["notificationUID":wire.json["notificationUID"]!,"state":1])
        }
        XCTAssertNotNil(c.send(title:"合成",content:"合成"))
        XCTAssertFalse(c.awaitingState); XCTAssertTrue(c.testStatus.contains("显示中或间隔期"))
    }
    func testTimeoutDoesNotRetryOrTurnSDKSubmissionIntoSuccess() async throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        _ = c.send(title:"合成",content:"合成")
        XCTAssertNil(c.send(title:"不应并发",content:"合成"))
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertFalse(c.awaitingState); XCTAssertTrue(c.testStatus.contains("超时"))
        XCTAssertEqual(link.packets.map(\.type),[18,2])
    }
    func testReconnectNeverReplaysOrAcceptsOldPendingMessage() throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        let uid = try XCTUnwrap(c.send(title:"合成",content:"合成"))
        link.device = nil; c.connectionChanged()
        link.device = "synthetic-glasses-A"; c.connectionChanged()
        XCTAssertTrue(c.sourcesNeedApply); XCTAssertNil(c.reportedEnabled)
        try receive(c,type:3,json:["notificationUID":uid,"state":1])
        XCTAssertFalse(c.testStatus.contains("同 UID 眼镜回报"))
        XCTAssertNil(c.send(title:"合成",content:"合成")); XCTAssertTrue(c.error?.contains("先向当前眼镜") == true)
        XCTAssertEqual(link.packets.count,2)
    }
    func testTransportFailureAndCallbackLossRemainUnconfirmed() throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        link.fails = true
        XCTAssertNil(c.send(title:"合成",content:"合成")); XCTAssertFalse(c.awaitingState)
        XCTAssertTrue(c.testStatus.contains("失败"))
        link.fails = false; _ = c.send(title:"合成",content:"合成")
        let uid = try XCTUnwrap(c.lastUID); c.lostMessages()
        try receive(c,type:3,json:["notificationUID":uid,"state":1])
        XCTAssertFalse(c.awaitingState); XCTAssertTrue(c.testStatus.contains("丢失"))
    }
    func testAvailabilityStrictBooleanTimeoutAndNoFalseFilterACK() async throws {
        let (c, link, _) = fixture(); c.queryAvailability()
        XCTAssertEqual(link.packets.last?.type,20)
        try receive(c,type:21,json:["available":1])
        XCTAssertNil(c.ancsAvailable)
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertTrue(c.availabilityStatus.contains("超时"))
        try receive(c,type:21,json:["available":true])
        XCTAssertEqual(c.ancsAvailable,true)
        try receive(c,type:18,json:["notification":true])
        XCTAssertEqual(c.reportedEnabled,true); XCTAssertTrue(c.sourcesNeedApply)
    }
    func testDeviceDisabledReportPreventsDirectSendUntilExplicitReapply() throws {
        let (c, link, _) = fixture(); c.setEnabled(true)
        try receive(c,type:18,json:["notification":false])
        XCTAssertNil(c.send(title:"合成",content:"合成")); XCTAssertEqual(link.packets.count,1)
        c.applyMaster(); XCTAssertNotNil(c.send(title:"合成",content:"合成"))
    }
    func testUnknownStatesAndUnrelatedANCSDoNotExecuteOrPersistContent() throws {
        let (c, _, defaults) = fixture(); c.setEnabled(true)
        let uid = try XCTUnwrap(c.send(title:"private-test-title",content:"private-test-body"))
        try receive(c,type:1,json:["appId":"com.example.private","title":"other-private-title","content":"other-private-body"])
        try receive(c,type:3,json:["notificationUID":uid,"state":999])
        XCTAssertTrue(c.testStatus.contains("未知状态"))
        let data = try XCTUnwrap(defaults.data(forKey:"companion.v1.notificationPreferences"))
        let text = String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("private-test")); XCTAssertFalse(text.contains("other-private"))
    }
}
