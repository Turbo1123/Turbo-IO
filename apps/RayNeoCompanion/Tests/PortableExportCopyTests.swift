import XCTest
import RayNeoArchive
@testable import RayNeoCompanion

final class PortableExportCopyTests: XCTestCase {
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-copy-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func copy(_ root: URL, id: UUID = UUID(), trash: Bool = false) throws -> (UUID, URL) {
        let folder = root.appendingPathComponent(trash ? "PortableArchiveTrashV1" : "PortableArchiveExportsV1").appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("synthetic export".utf8).write(to: folder.appendingPathComponent("synthetic.zip.partial"), options: .withoutOverwriting)
        return (id, folder)
    }
    func testAbsentCatalogDoesNotCreateDirectories() throws {
        let root = try sandbox()
        XCTAssertTrue(try PortableExportCopies(parent: root).catalog().copies.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testMoveAndRestorePreserveEveryByteAndOriginalArchive() throws {
        let root = try sandbox(), (id, folder) = try copy(root)
        let original = root.appendingPathComponent("VerifiedRecordingArchiveV1")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let source = original.appendingPathComponent("original.wav"), data = Data("original synthetic".utf8)
        try data.write(to: source)
        let manager = PortableExportCopies(parent: root)
        XCTAssertEqual(try manager.catalog().copies[0].bytes, 16)
        try manager.move(id, toTrash: true)
        XCTAssertTrue(try manager.catalog().copies[0].inTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try Data(contentsOf: source), data)
        try manager.move(id, toTrash: false)
        XCTAssertFalse(try manager.catalog().copies[0].inTrash)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("synthetic.zip.partial")), Data("synthetic export".utf8))
    }
    func testUnknownFoldersArePreservedAndCannotBeSelectedAsUUID() throws {
        let root = try sandbox(), (_, folder) = try copy(root)
        let unknown = folder.deletingLastPathComponent().appendingPathComponent("unknown-originals")
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
        let result = try PortableExportCopies(parent: root).catalog()
        XCTAssertEqual(result.copies.count, 1); XCTAssertEqual(result.unrecognized, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
    func testNestedSymlinkIsRejectedWithoutMovingTarget() throws {
        let root = try sandbox(), (id, folder) = try copy(root)
        let outside = root.appendingPathComponent("original")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: outside)
        let manager = PortableExportCopies(parent: root)
        XCTAssertEqual(try manager.catalog().unrecognized, 1)
        XCTAssertThrowsError(try manager.move(id, toTrash: true))
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
    }
    func testRootSymlinkAndDanglingTrashCannotRedirectMove() throws {
        let root = try sandbox(), (id, folder) = try copy(root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("PortableArchiveTrashV1"), withDestinationURL: root.appendingPathComponent("nonexistent"))
        XCTAssertThrowsError(try PortableExportCopies(parent: root).move(id, toTrash: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        let other = try sandbox()
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("PortableArchiveExportsV1"), withDestinationURL: folder.deletingLastPathComponent())
        XCTAssertThrowsError(try PortableExportCopies(parent: other).catalog())
    }
    func testCollisionNeverOverwritesEitherCopy() throws {
        let root = try sandbox(), (id, folder) = try copy(root)
        let (_, target) = try copy(root, id: id, trash: true)
        XCTAssertThrowsError(try PortableExportCopies(parent: root).move(id, toTrash: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testTrashCapacityDoesNotDeleteOrMoveSource() throws {
        let root = try sandbox(), (id, folder) = try copy(root)
        for _ in 0..<20 { _ = try copy(root, trash: true) }
        XCTAssertThrowsError(try PortableExportCopies(parent: root).move(id, toTrash: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try PortableExportCopies(parent: root).catalog().copies.count, 21)
    }
    func testRepositoryMovesOnlyDerivedExportAndArchiveStillVerifies() async throws {
        let root = try sandbox(), source = root.appendingPathComponent("synthetic.wav")
        try Data("not actual audio".utf8).write(to: source)
        let repo = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source)
        let zip = try await repo.preparePortableShare(recordingID: receipt.recording.id, revisions: .selected([]))
        let before = try Data(contentsOf: zip)
        let catalog = try await repo.exportCopyCatalog()
        let entry = try XCTUnwrap(catalog.copies.first)
        try await repo.moveExportCopy(entry.id, toTrash: true)
        _ = try await repo.verify(receipt.recording.id)
        try await repo.moveExportCopy(entry.id, toTrash: false)
        XCTAssertEqual(try Data(contentsOf: zip), before)
    }
}
