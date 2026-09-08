import XCTest
@testable import RayNeoCompanion

final class RecordingRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL,GlassesRecordingInbox,String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-test-"+UUID().uuidString)
        let inbox = GlassesRecordingInbox(root:root.appendingPathComponent("inbox"))
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        try inbox.begin(device:"synthetic-device",id:"synthetic-recording")
        let id = try XCTUnwrap(inbox.catalog().entries.first?.id)
        return (root,inbox,id)
    }
    private func append(_ inbox: GlassesRecordingInbox, offset: Int = 0) throws {
        try inbox.append(device:"synthetic-device",id:"synthetic-recording",offset:offset,data:Data(repeating:0xAF,count:720))
    }
    func testColdOpenRetainsCompletionAndAllowsContainerRecovery() throws {
        let (root,inbox,id) = try fixture()
        try append(inbox); try inbox.recordCompletion(device:"synthetic-device",id:"synthetic-recording")
        let reopened = GlassesRecordingInbox(root:root.appendingPathComponent("inbox"))
        let entry = try XCTUnwrap(reopened.catalog().entries.first)
        XCTAssertTrue(entry.completionReported); XCTAssertTrue(entry.mayRecover); XCTAssertEqual(entry.receivedBytes,720)
        let output = try reopened.recoverContainer(id)
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.path))
        XCTAssertEqual(try Data(contentsOf:reopened.rawForRecovery(id)),Data(repeating:0xAF,count:720))
    }
    func testCoverageWithoutEndEventCannotBeRecoveredAsComplete() throws {
        let (_,inbox,id) = try fixture(); try append(inbox)
        XCTAssertFalse(try XCTUnwrap(inbox.catalog().entries.first).mayRecover)
        XCTAssertThrowsError(try inbox.recoverContainer(id))
    }
    func testEndEventDoesNotHideGapsOrConflict() throws {
        let (_,inbox,id) = try fixture(); try append(inbox,offset:720)
        try inbox.recordCompletion(device:"synthetic-device",id:"synthetic-recording")
        XCTAssertFalse(try XCTUnwrap(inbox.catalog().entries.first).mayRecover)
        XCTAssertThrowsError(try inbox.recoverContainer(id))
        try append(inbox)
        inbox.invalidate(device:"synthetic-device",id:"synthetic-recording")
        XCTAssertFalse(try XCTUnwrap(inbox.catalog().entries.first).mayRecover)
        XCTAssertThrowsError(try inbox.recoverContainer(id))
    }
    func testSealedRawMustMatchPriorHashAfterRestart() throws {
        let (_,inbox,id) = try fixture(); try append(inbox)
        try inbox.recordCompletion(device:"synthetic-device",id:"synthetic-recording")
        _ = try inbox.recoverContainer(id)
        let raw = try inbox.rawForRecovery(id), changed = Data(repeating:3,count:720)
        try changed.write(to:raw)
        XCTAssertThrowsError(try inbox.recoverContainer(id))
        XCTAssertEqual(try Data(contentsOf:raw),changed)
    }
    func testRawExportIsIndependentAndNeverClaimsCompletion() throws {
        let (_,inbox,id) = try fixture(); try append(inbox)
        let raw = try inbox.rawForRecovery(id), copy = try inbox.exportRawCopy(id)
        XCTAssertNotEqual(raw,copy); XCTAssertEqual(try Data(contentsOf:raw),try Data(contentsOf:copy))
        try append(inbox,offset:720)
        XCTAssertEqual(try Data(contentsOf:copy).count,720)
        XCTAssertFalse(try XCTUnwrap(inbox.catalog().entries.first).completionReported)
    }
    func testBrokenMetadataIsReportedAndNotDeleted() throws {
        let (root,inbox,id) = try fixture()
        let manifest = root.appendingPathComponent("inbox/\(id)/receipt.json")
        let bytes = Data("broken metadata".utf8); try bytes.write(to:manifest)
        let catalog = try inbox.catalog()
        XCTAssertEqual(catalog.unreadable,1); XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf:manifest),bytes)
    }
    func testTraversalAndLinkedDirectoriesCannotBeUsedForRecovery() throws {
        let (root,inbox,_) = try fixture()
        XCTAssertThrowsError(try inbox.rawForRecovery("../source.rawopus"))
        let name = String(repeating:"f",count:64)
        let target = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("inbox/\(name)"),withDestinationURL:target)
        XCTAssertThrowsError(try inbox.rawForRecovery(name))
        XCTAssertEqual(try inbox.catalog().unreadable,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.path))
    }
    func testOldManifestWithoutCompletionFieldIsNotInventedComplete() throws {
        let (root,inbox,id) = try fixture(); try append(inbox)
        let file = root.appendingPathComponent("inbox/\(id)/receipt.json")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        value.removeValue(forKey:"completionReported")
        try JSONSerialization.data(withJSONObject:value).write(to:file)
        XCTAssertFalse(try XCTUnwrap(inbox.catalog().entries.first).mayRecover)
        XCTAssertThrowsError(try inbox.recoverContainer(id))
    }
}
