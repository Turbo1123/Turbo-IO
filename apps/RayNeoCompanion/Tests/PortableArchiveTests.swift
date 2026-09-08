import XCTest
import ZIPFoundation
import RayNeoArchive
import CryptoKit
@testable import RayNeoCompanion

final class PortableArchiveTests: XCTestCase {
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }; return root
    }
    private func source(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("synthetic-not-audio.wav")
        try Data(String(repeating:"SYNTHETIC NO AUDIO\n",count:50).utf8).write(to:url,options:.withoutOverwriting)
        return url
    }
    private func contents(_ zip: ZIPFoundation.Archive, _ entry: Entry) throws -> Data {
        var data = Data()
        let crc = try zip.extract(entry) { data.append($0) }
        XCTAssertEqual(crc,entry.checksum); return data
    }
    func testLatestRevisionZIPKeepsRelativeAudioLinkAndExcludesOlderText() async throws {
        let root = try sandbox(), source = try source(root)
        let repo = LocalArchiveRepository(rootDirectory:root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source)
        let old = try await repo.saveTranscript(recordingID:receipt.recording.id,text:"OLD SECRET NOT SELECTED",title:"Old")
        let latest = try await repo.saveTranscript(recordingID:receipt.recording.id,text:"Selected synthetic text",title:"Current")
        let url = try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.selected([latest.revision.id]))
        let zip = try ZIPFoundation.Archive(url:url,accessMode:.read)
        XCTAssertEqual(Array(zip).count,4)
        let audio = try XCTUnwrap(zip.first(where:{$0.path.contains("/audio/")}))
        XCTAssertEqual(try contents(zip,audio),try Data(contentsOf:source))
        let note = try XCTUnwrap(zip.first(where:{$0.path.contains("/notes/")}))
        let text = String(decoding:try contents(zip,note),as:UTF8.self)
        XCTAssertTrue(text.contains("Selected synthetic text")); XCTAssertFalse(text.contains("OLD SECRET"))
        XCTAssertTrue(text.contains("../" + receipt.recording.audioRelativePath))
        let manifestEntry = try XCTUnwrap(zip.first(where:{$0.path.hasSuffix("snapshot-manifest.json")}))
        let manifest = try JSONDecoder().decode(ArchiveSnapshotManifest.self,from:contents(zip,manifestEntry))
        XCTAssertEqual(manifest.recording.transcripts.map(\.id),[latest.revision.id])
        XCTAssertEqual(manifest.evidence.serverUpload,"not_performed")
        XCTAssertEqual(manifest.evidence.obsidianIndexing,"not_assessed")
        XCTAssertTrue(FileManager.default.fileExists(atPath:old.noteURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    func testAudioOnlyHasNoTranscriptAndRepeatedExportNeverOverwrites() async throws {
        let root = try sandbox(), repo = LocalArchiveRepository(rootDirectory:root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source(root))
        _ = try await repo.saveTranscript(recordingID:receipt.recording.id,text:"Not selected",title:"Private")
        let first = try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.selected([]))
        let original = try Data(contentsOf:first)
        let second = try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.selected([]))
        XCTAssertNotEqual(first,second); XCTAssertEqual(try Data(contentsOf:first),original)
        let zip = try ZIPFoundation.Archive(url:first,accessMode:.read)
        XCTAssertEqual(Array(zip).count,3); XCTAssertFalse(zip.contains(where:{$0.path.contains("/notes/")}))
    }
    func testCorruptSourceIsNotExportedAndIsNeverRepaired() async throws {
        let root = try sandbox(), repo = LocalArchiveRepository(rootDirectory:root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source(root))
        let changed = Data("changed".utf8); try changed.write(to:receipt.audioURL)
        do { _ = try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.all); XCTFail("changed source") } catch {}
        XCTAssertEqual(try Data(contentsOf:receipt.audioURL),changed)
    }
    func testChangedIndependentSnapshotCannotPublishZIP() async throws {
        let root = try sandbox(); let archiveRoot = root.appendingPathComponent("archive"), parent = root.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at:archiveRoot,withIntermediateDirectories:false)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false)
        let store = try ArchiveStore(rootDirectory:archiveRoot)
        let receipt = try await store.importFile(at:source(root),title:"Synthetic")
        let snapshot = try await store.exportSnapshot(recordingID:receipt.recording.id,revisions:.all,toParentDirectory:parent)
        let file = snapshot.directoryURL.appendingPathComponent(receipt.recording.audioRelativePath)
        let damaged = Data(repeating:33,count:Int(receipt.recording.byteCount)); try damaged.write(to:file)
        XCTAssertThrowsError(try PortableArchiveZIP.create(snapshot))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:parent.path).contains(where:{$0.hasSuffix(".zip")}))
        XCTAssertEqual(try Data(contentsOf:file),damaged)
        _ = try await store.verifyRecording(receipt.recording.id)
    }
    func testUnsafeZIPPathsRejected() {
        for value in ["/root","../a","audio/../a","audio//a","a\\b","a\nb",""] { XCTAssertFalse(PortableArchiveZIP.validPath(value)) }
        XCTAssertTrue(PortableArchiveZIP.validPath("notes/synthetic.md"))
    }
    func testCancelledExportDoesNotPublish() async throws {
        let root = try sandbox(), repo = LocalArchiveRepository(rootDirectory:root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source(root))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.all)
        }
        do { _ = try await task.value; XCTFail("cancelled export") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath:receipt.audioURL.path))
    }
    func testUnknownRevisionFailsWithoutSendingAnyOtherNotes() async throws {
        let root = try sandbox(), repo = LocalArchiveRepository(rootDirectory:root.appendingPathComponent("archive"))
        let receipt = try await repo.importFile(source(root))
        do { _ = try await repo.preparePortableShare(recordingID:receipt.recording.id,revisions:.selected([UUID()])); XCTFail("unknown selection") }
        catch { XCTAssertEqual(error as? SnapshotError,.invalidSelection) }
    }
}
