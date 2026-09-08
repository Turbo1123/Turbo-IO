import XCTest
import RayNeoAudioContainer
@testable import RayNeoCompanion

final class DeviceFeatureTests: XCTestCase {
    func testBusinessEnvelopeRoundTripAndRejectsAmbiguousTags() throws {
        let packet = try DeviceBusinessWire.encode(type:3,json:["uuid":"fixture","offset":720],bytes:Data(repeating:0xAF,count:720))
        let result = try DeviceBusinessWire(packet)
        XCTAssertEqual(result.type,3); XCTAssertEqual(result.bytes.count,720)
        XCTAssertEqual(DeviceBusinessWire.integer(result.json,"offset"),720)
        XCTAssertThrowsError(try DeviceBusinessWire(packet + Data([16,4])))
        XCTAssertThrowsError(try DeviceBusinessWire(Data([8,1,16,3,26,255])))
    }
    func testWireIntegersRejectBooleanFractionAndHugeValues() {
        XCTAssertNil(DeviceBusinessWire.integer(["n":true],"n"))
        XCTAssertNil(DeviceBusinessWire.integer(["n":1.5],"n"))
        XCTAssertNil(DeviceBusinessWire.integer(["n":1e20],"n"))
        XCTAssertEqual(DeviceBusinessWire.integer(["n":42],"n"),42)
    }
    func testCompletionRequiresJSONBooleanNotNumericOne() throws {
        for text in [#"{"completed":1}"#, #"{"completed":0}"#, #"{"completed":"true"}"#] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any])
            XCTAssertNil(DeviceBusinessWire.boolean(object,"completed"))
        }
        XCTAssertEqual(DeviceBusinessWire.boolean(["completed":true],"completed"),true)
        XCTAssertEqual(DeviceBusinessWire.boolean(["completed":false],"completed"),false)
    }
    func testCoverageMergesOutOfOrderAndDetectsPrefixGap() {
        var coverage = RecordingCoverage()
        coverage.insert(720..<1440); XCTAssertFalse(coverage.contiguous)
        coverage.insert(0..<240); XCTAssertFalse(coverage.contiguous)
        coverage.insert(240..<720); XCTAssertEqual(coverage.ranges,[0..<1440])
        coverage.insert(0..<240); XCTAssertTrue(coverage.contiguous)
    }
    private func fixture() throws -> (URL,GlassesRecordingInbox) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let inbox = GlassesRecordingInbox(root:root)
        try inbox.begin(device:"synthetic-device",id:"../synthetic-id")
        return (root,inbox)
    }
    private var chunk: Data { Data(repeating:0xAF,count:720) }
    func testOutOfOrderDurableRecordingAndOggCRC() throws {
        let (root,inbox) = try fixture()
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:720,data:chunk)
        XCTAssertThrowsError(try inbox.finish(device:"synthetic-device",id:"../synthetic-id"))
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:chunk)
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:chunk)
        let output = try inbox.finish(device:"synthetic-device",id:"../synthetic-id")
        XCTAssertTrue(output.path.hasPrefix(root.path + "/"))
        var inspector = try OggOpusInspector(); try inspector.push(Data(contentsOf:output))
        _ = try inspector.finish() // Structure/CRC only; these are not valid speech packets.
        let source = output.deletingLastPathComponent().appendingPathComponent("source.rawopus")
        XCTAssertEqual(try Data(contentsOf:source),chunk+chunk)
        XCTAssertEqual(try inbox.finish(device:"synthetic-device",id:"../synthetic-id"),output)
        XCTAssertThrowsError(try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:1440,data:chunk))
    }
    func testConflictingReplayDoesNotOverwriteOriginal() throws {
        let (root,inbox) = try fixture()
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:chunk)
        XCTAssertThrowsError(try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:Data(repeating:9,count:720)))
        XCTAssertThrowsError(try inbox.finish(device:"synthetic-device",id:"../synthetic-id"))
        let dir = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).first)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("source.rawopus")),chunk)
    }
    func testRecordingColdOpenDoesNotTruncateAndRetainsCoverage() throws {
        let (root,inbox) = try fixture()
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:chunk)
        let reopened = GlassesRecordingInbox(root:root)
        try reopened.begin(device:"synthetic-device",id:"../synthetic-id")
        XCTAssertEqual(try reopened.append(device:"synthetic-device",id:"../synthetic-id",offset:720,data:chunk),1440)
        _ = try reopened.finish(device:"synthetic-device",id:"../synthetic-id")
    }
    func testRecordingBoundsAndMissingTailFailClosed() throws {
        let (_,inbox) = try fixture()
        XCTAssertThrowsError(try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:-1,data:chunk))
        XCTAssertThrowsError(try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:GlassesRecordingInbox.limit,data:chunk))
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:Data(repeating:5,count:241))
        XCTAssertThrowsError(try inbox.finish(device:"synthetic-device",id:"../synthetic-id"))
    }
    func testAllZeroAudioIsNotSilentlyRepaired() throws {
        let (_,inbox) = try fixture()
        try inbox.append(device:"synthetic-device",id:"../synthetic-id",offset:0,data:Data(repeating:0,count:240))
        XCTAssertThrowsError(try inbox.finish(device:"synthetic-device",id:"../synthetic-id"))
    }
    @MainActor func testTodoReverseMappingPersistsAndRejectsOtherDevice() throws {
        let name = "companion.device.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name)); defer { defaults.removePersistentDomain(forName:name) }
        let store = CompanionStore(defaults:defaults)
        store.addTodo("手机与眼镜同一测试项")
        let id = try XCTUnwrap(store.todos.first?.id)
        let wireID = store.assignWireID(id,device:"synthetic-device")
        XCTAssertFalse(store.applyGlassesTodo(device:"other",id:wireID,status:1,important:nil))
        XCTAssertFalse(store.applyGlassesTodo(device:"synthetic-device",id:wireID,status:8,important:nil))
        XCTAssertTrue(store.applyGlassesTodo(device:"synthetic-device",id:wireID,status:1,important:true))
        XCTAssertFalse(store.applyGlassesTodo(device:"synthetic-device",id:wireID,status:1,important:true))
        let reopened = CompanionStore(defaults:defaults)
        XCTAssertEqual(reopened.todos.first?.wireID,wireID); XCTAssertEqual(reopened.todos.first?.completed,true)
    }
    @MainActor func testSimulatorCannotSendOrStartRecording() throws {
        let store = CompanionStore()
        XCTAssertThrowsError(try store.voice.sendBusiness(14,payload:Data()))
        store.features.startRecording()
        XCTAssertNotNil(store.features.error); XCTAssertNil(store.features.recordingID)
        XCTAssertFalse(store.features.acceptsEyeRecording)
    }
}
