import XCTest
import Foundation
import Darwin
@testable import RayNeoArchive

final class Sandbox {
    let base: URL
    let root: URL
    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("rayneo-archive-tests-" + UUID().uuidString, isDirectory: true)
        root = base.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func source(_ name: String = "synthetic-not-audio.opus", bytes: Data = Data((0..<8_193).map { UInt8($0 % 251) })) throws -> URL {
        let url = base.appendingPathComponent(name)
        try bytes.write(to: url, options: .withoutOverwriting)
        return url
    }
    /// Only this test's generated sandbox, bounded to the known two-level layout, is cleaned.
    /// No recursive removeItem call and no cleanup of a caller's source directory.
    func cleanup() throws {
        func removeLevel(_ directory: URL, depth: Int) throws {
            guard depth <= 3, directory.path.hasPrefix(base.path) else { throw ArchiveError.invalidFileURL }
            let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard entries.count < 100 else { throw ArchiveError.invalidFileURL }
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true && values.isSymbolicLink != true {
                    try removeLevel(entry, depth: depth + 1)
                } else {
                    guard unlink(entry.path) == 0 else { throw ArchiveFileSystem.failure("clean synthetic test file") }
                }
            }
            guard rmdir(directory.path) == 0 else { throw ArchiveFileSystem.failure("clean synthetic test directory") }
        }
        try removeLevel(base, depth: 0)
    }
}

private enum SimulatedStop: Error { case afterDurableBoundary }

final class ArchiveStoreTests: XCTestCase {
    func testCopyHasIndependentEvidenceAndPreservesSource() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let before = try Data(contentsOf: source)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let store = try ArchiveStore(rootDirectory: box.root)
        let receipt = try await store.importFile(at: source, title: "每日测试")
        XCTAssertEqual(try Data(contentsOf: receipt.audioURL), before)
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date, attributes[.modificationDate] as? Date)
        XCTAssertEqual(receipt.recording.byteCount, 8_193) // More than two streaming buffers; not valid audio.
        XCTAssertEqual(receipt.evidence, ArchiveEvidence(sourceCopied: true, checksumVerified: true, transcriptProvided: false, noteExported: false))
        XCTAssertFalse(receipt.reusedExistingContent)
        let manifest = box.root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifest)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(source.path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: manifest.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let listed = try await store.listRecordings()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].id, receipt.recording.id)
        let reopened = try ArchiveStore(rootDirectory: box.root)
        let verified = try await reopened.verifyRecording(receipt.recording.id)
        XCTAssertEqual(verified.recording.sha256, receipt.recording.sha256)
    }

    func testKnownDigestAndContentDedupAcrossNames() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let original = try box.source("one.wav", bytes: Data("123456789".utf8))
        let renamed = try box.source("two.mp3", bytes: Data("123456789".utf8))
        let store = try ArchiveStore(rootDirectory: box.root)
        let first = try await store.importFile(at: original, title: "Original")
        let second = try await store.importFile(at: renamed, title: "Different name")
        XCTAssertEqual(first.recording.sha256, "15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225")
        XCTAssertEqual(second.recording.id, first.recording.id)
        XCTAssertEqual(second.recording.title, "Original")
        XCTAssertTrue(second.reusedExistingContent)
        let recordings = try await store.listRecordings()
        XCTAssertEqual(recordings.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testSizeAndEmptyInputRejectedWithoutDeletingSource() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let empty = try box.source("empty.opus", bytes: Data())
        let store = try ArchiveStore(rootDirectory: box.root, limits: ArchiveLimits(maximumFileBytes: 128))
        do { _ = try await store.importFile(at: source, title: "Too large"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .fileSizeLimitExceeded) }
        do { _ = try await store.importFile(at: empty, title: "Empty"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .emptySource) }
        XCTAssertEqual(try Data(contentsOf: source).count, 8_193)
        let report = try await store.recover()
        XCTAssertEqual(report.retainedUnjournaledFiles, 0)
    }

    func testTitleAndTranscriptBounds() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let store = try ArchiveStore(rootDirectory: box.root, limits: ArchiveLimits(maximumTranscriptBytes: 12))
        for title in ["", "\n", "bad\u{0000}title", String(repeating: "x", count: 257)] {
            do { _ = try await store.importFile(at: source, title: title); XCTFail("must reject") }
            catch { XCTAssertEqual(error as? ArchiveError, .invalidTitle) }
        }
        let item = try await store.importFile(at: source, title: "Valid")
        do { _ = try await store.exportTranscript(for: item.recording.id, text: String(repeating: "x", count: 13)); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .transcriptSizeLimitExceeded) }
        for text in ["  \n", "bad\u{0000}"] {
            do { _ = try await store.exportTranscript(for: item.recording.id, text: text); XCTFail("must reject") }
            catch { XCTAssertEqual(error as? ArchiveError, .invalidTranscript) }
        }
    }

    func testHostTranscriptIdempotencyAndImmutableRevisions() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let item = try await store.importFile(at: box.source(), title: "归档演示")
        let first = try await store.exportTranscript(for: item.recording.id, text: "第一行\r\n第二行")
        let originalData = try Data(contentsOf: first.noteURL)
        let same = try await store.exportTranscript(for: item.recording.id, text: "第一行\n第二行")
        XCTAssertEqual(first.noteURL, same.noteURL)
        XCTAssertTrue(same.reusedExistingRevision)
        let edited = try await store.exportTranscript(for: item.recording.id, text: "第一行\n改稿")
        XCTAssertEqual(edited.revision.number, 2)
        XCTAssertNotEqual(first.noteURL, edited.noteURL)
        XCTAssertEqual(try Data(contentsOf: first.noteURL), originalData)
        XCTAssertEqual(edited.evidence, ArchiveEvidence(sourceCopied: true, checksumVerified: true, transcriptProvided: true, noteExported: true))
        XCTAssertEqual(edited.recording.transcripts.count, 2)
        let text = String(decoding: originalData, as: UTF8.self)
        XCTAssertTrue(text.contains("audio_decoding: \"not_assessed\""))
        XCTAssertTrue(text.contains("speech_recognition: \"not_performed_by_archive\""))
        XCTAssertTrue(text.contains("../audio/\(item.recording.id.uuidString.lowercased()).opus"))
    }

    func testMarkdownAndFilenameAreNotExecutableUserMarkup() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let item = try await store.importFile(at: box.source("opaque.unknown"), title: "../测试: \"x\" [link](evil)")
        XCTAssertEqual(item.recording.fileExtension, "bin")
        let hostile = "[click](https://invalid.example)\n![[private]]\n<script>alert(1)</script>\n---\n# Heading\n```run\n"
        let note = try await store.exportTranscript(for: item.recording.id, text: hostile)
        let markdown = try String(contentsOf: note.noteURL, encoding: .utf8)
        XCTAssertFalse(markdown.contains("<script>"))
        XCTAssertFalse(markdown.contains("[click](https://invalid.example)"))
        XCTAssertFalse(markdown.contains("![[private]]"))
        XCTAssertTrue(markdown.contains("&lt;script&gt;"))
        XCTAssertEqual(note.noteURL.deletingLastPathComponent(), box.root.appendingPathComponent("notes", isDirectory: true).resolvingSymlinksInPath())
        XCTAssertFalse(note.noteURL.lastPathComponent.contains(".."))
        XCTAssertFalse(note.noteURL.lastPathComponent.contains(":"))
    }

    func testChangedArchivedAudioAndEditedNoteAreNotOverwritten() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let store = try ArchiveStore(rootDirectory: box.root)
        let item = try await store.importFile(at: source, title: "Keep original")
        let note = try await store.exportTranscript(for: item.recording.id, text: "First text")
        let userEdit = Data("User edited this note".utf8)
        try userEdit.write(to: note.noteURL)
        do { _ = try await store.exportTranscript(for: item.recording.id, text: "First text"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .archivedContentChanged) }
        XCTAssertEqual(try Data(contentsOf: note.noteURL), userEdit)
        let changed = Data("Changed archived bytes".utf8)
        try changed.write(to: item.audioURL)
        do { _ = try await store.importFile(at: source, title: "Duplicate"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .archivedContentChanged) }
        XCTAssertEqual(try Data(contentsOf: item.audioURL), changed)
        XCTAssertEqual(try Data(contentsOf: source).count, 8_193)
    }

    func testSymbolicLinksAndNonRegularSourceAreRejected() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let link = box.base.appendingPathComponent("source-link.opus")
        XCTAssertEqual(symlink(source.path, link.path), 0)
        let store = try ArchiveStore(rootDirectory: box.root)
        do { _ = try await store.importFile(at: link, title: "Link"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .io(operation: "open selected source", code: ELOOP)) }
        do { _ = try await store.importFile(at: box.base, title: "Directory"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .unsupportedFileType) }
        let fifo = box.base.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        do { _ = try await store.importFile(at: fifo, title: "FIFO"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .unsupportedFileType) }
    }

    func testArchiveSubdirectoryLinkCannotRedirectWrites() throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let outside = box.base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        XCTAssertEqual(symlink(outside.path, box.root.appendingPathComponent("audio").path), 0)
        XCTAssertThrowsError(try ArchiveStore(rootDirectory: box.root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testCorruptManifestIsRetainedAndNeverBlindlyReplaced() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        _ = try await store.importFile(at: box.source(), title: "One")
        let manifestURL = box.root.appendingPathComponent("manifest.json")
        let bad = Data("not a manifest".utf8)
        try bad.write(to: manifestURL)
        do { _ = try await store.listRecordings(); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .invalidManifest) }
        XCTAssertEqual(try Data(contentsOf: manifestURL), bad)
    }

    func testImportRecoversAtEachDurableCheckpoint() async throws {
        for stop in [TransactionCheckpoint.journalDurable, .filePublished, .manifestPublished] {
            let box = try Sandbox(); defer { try? box.cleanup() }
            let source = try box.source()
            let interrupted = try ArchiveStore(rootDirectory: box.root) { point in
                if point == stop { throw SimulatedStop.afterDurableBoundary }
            }
            do { _ = try await interrupted.importFile(at: source, title: "Recovery"); XCTFail("checkpoint must stop") }
            catch { XCTAssertTrue(error is SimulatedStop) }
            let restored = try ArchiveStore(rootDirectory: box.root)
            let report = try await restored.recover()
            XCTAssertEqual(report, RecoveryReport(recoveredTransactions: 1, retainedUnjournaledFiles: 0))
            let records = try await restored.listRecordings()
            XCTAssertEqual(records.count, 1)
            let verified = try await restored.verifyRecording(records[0].id)
            XCTAssertEqual(try Data(contentsOf: verified.audioURL), try Data(contentsOf: source))
            let repeated = try await restored.importFile(at: source, title: "Repeat")
            XCTAssertTrue(repeated.reusedExistingContent)
        }
    }

    func testTranscriptRecoversAtEachDurableCheckpoint() async throws {
        for stop in [TransactionCheckpoint.journalDurable, .filePublished, .manifestPublished] {
            let box = try Sandbox(); defer { try? box.cleanup() }
            let initial = try ArchiveStore(rootDirectory: box.root)
            let imported = try await initial.importFile(at: box.source(), title: "Recovery")
            let first = try await initial.exportTranscript(for: imported.recording.id, text: "Original text")
            let original = try Data(contentsOf: first.noteURL)
            let interrupted = try ArchiveStore(rootDirectory: box.root) { point in
                if point == stop { throw SimulatedStop.afterDurableBoundary }
            }
            do { _ = try await interrupted.exportTranscript(for: imported.recording.id, text: "Revised text"); XCTFail("checkpoint must stop") }
            catch { XCTAssertTrue(error is SimulatedStop) }
            let restored = try ArchiveStore(rootDirectory: box.root)
            let report = try await restored.recover()
            XCTAssertEqual(report.recoveredTransactions, 1)
            let result = try await restored.exportTranscript(for: imported.recording.id, text: "Revised text")
            XCTAssertTrue(result.reusedExistingRevision)
            XCTAssertEqual(result.revision.number, 2)
            XCTAssertEqual(try Data(contentsOf: first.noteURL), original)
        }
    }

    func testOrphanStageIsReportedAndPreserved() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let orphan = box.root.appendingPathComponent(".staging/\(UUID().uuidString.lowercased()).blob")
        try Data("Unjournaled synthetic bytes".utf8).write(to: orphan)
        let report = try await store.recover()
        XCTAssertEqual(report.retainedUnjournaledFiles, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testMalformedRecoveryCannotCreatePathsFromMetadata() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let transactionID = UUID()
        let malicious = ArchivedRecording(id: UUID(), title: "Not trusted", importedAt: Date(), recordedAt: nil,
            sha256: String(repeating: "0", count: 64), byteCount: 1, fileExtension: "../../escape",
            checksumVerifiedAt: Date(), transcripts: [])
        let journal = Journal(transactionID: transactionID, mutation: .imported(malicious))
        let location = box.root.appendingPathComponent(".staging/\(transactionID.uuidString.lowercased()).journal")
        let data = try JSONEncoder().encode(journal)
        try data.write(to: location)
        do { _ = try await store.recover(); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .invalidManifest) }
        XCTAssertEqual(try Data(contentsOf: location), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: box.base.appendingPathComponent("escape").path))
    }

    func testAdvisoryLockPreventsConcurrentManifestWriters() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let fd = open(box.root.appendingPathComponent(".archive.lock").path, O_RDWR | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        do { _ = try await store.listRecordings(); XCTFail("must reject while locked") }
        catch { XCTAssertEqual(error as? ArchiveError, .archiveBusy) }
        XCTAssertEqual(flock(fd, LOCK_UN), 0)
        let records = try await store.listRecordings()
        XCTAssertEqual(records.count, 0)
    }

    func testExplicitRootAndLimitsAreRequired() throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        XCTAssertThrowsError(try ArchiveStore(rootDirectory: box.root.appendingPathComponent("missing"))) {
            XCTAssertEqual($0 as? ArchiveError, .targetDirectoryRequired)
        }
        XCTAssertThrowsError(try ArchiveStore(rootDirectory: URL(string: "https://invalid.example")!)) {
            XCTAssertEqual($0 as? ArchiveError, .invalidFileURL)
        }
        XCTAssertThrowsError(try ArchiveStore(rootDirectory: box.root, limits: ArchiveLimits(maximumFileBytes: 0))) {
            XCTAssertEqual($0 as? ArchiveError, .invalidLimits)
        }
    }

    func testCapacityLimitsDoNotPreventDuplicateReuse() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let second = try box.source("different.bin", bytes: Data("another synthetic sample".utf8))
        let store = try ArchiveStore(rootDirectory: box.root, limits: ArchiveLimits(maximumRecordings: 1, maximumRevisionsPerRecording: 1))
        let first = try await store.importFile(at: source, title: "One")
        let duplicate = try await store.importFile(at: source, title: "Same")
        XCTAssertTrue(duplicate.reusedExistingContent)
        do { _ = try await store.importFile(at: second, title: "Two"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .recordingLimitExceeded) }
        let note = try await store.exportTranscript(for: first.recording.id, text: "One")
        let noteDuplicate = try await store.exportTranscript(for: first.recording.id, text: "One")
        XCTAssertEqual(note.noteURL, noteDuplicate.noteURL)
        do { _ = try await store.exportTranscript(for: first.recording.id, text: "Two"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .revisionLimitExceeded) }
    }

    func testManifestLimitFailureLeavesPreviousManifestAndNoteSetUntouched() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root, limits: ArchiveLimits(maximumManifestBytes: 1_024))
        let first = try await store.importFile(at: box.source(), title: String(repeating: "T", count: 256))
        let manifest = box.root.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: manifest)
        do {
            _ = try await store.exportTranscript(for: first.recording.id, text: "Synthetic text", title: String(repeating: "R", count: 256))
            XCTFail("must exceed manifest capacity")
        } catch { XCTAssertEqual(error as? ArchiveError, .manifestSizeLimitExceeded) }
        XCTAssertEqual(try Data(contentsOf: manifest), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: box.root.appendingPathComponent("notes").path), [])
        let report = try await store.recover()
        XCTAssertEqual(report.retainedUnjournaledFiles, 0)
    }

    func testCancellationBeforeJournalCleansOnlyThisCallsStaging() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let interrupted = try ArchiveStore(rootDirectory: box.root) { point in
            if point == .sourceChunkCopied { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let orphan = box.root.appendingPathComponent(".staging/\(UUID().uuidString.lowercased()).blob")
        let orphanBytes = Data("Other transaction's synthetic bytes".utf8)
        try orphanBytes.write(to: orphan)
        let job = Task { try await interrupted.importFile(at: source, title: "Cancelled") }
        do { _ = try await job.value; XCTFail("must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        let restored = try ArchiveStore(rootDirectory: box.root)
        let records = try await restored.listRecordings()
        XCTAssertTrue(records.isEmpty)
        let report = try await restored.recover()
        XCTAssertEqual(report.retainedUnjournaledFiles, 1)
        XCTAssertEqual(try Data(contentsOf: orphan), orphanBytes)
        XCTAssertEqual(try Data(contentsOf: source).count, 8_193)
    }

    func testCancellationAfterJournalPreservesRecoverableTransaction() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let interrupted = try ArchiveStore(rootDirectory: box.root) { point in
            if point == .journalDurable { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let job = Task { try await interrupted.importFile(at: source, title: "Resume cancelled import") }
        do { _ = try await job.value; XCTFail("must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        let restored = try ArchiveStore(rootDirectory: box.root)
        let report = try await restored.recover()
        XCTAssertEqual(report.recoveredTransactions, 1)
        let records = try await restored.listRecordings()
        XCTAssertEqual(records.count, 1)
        let receipt = try await restored.verifyRecording(records[0].id)
        XCTAssertEqual(try Data(contentsOf: receipt.audioURL), try Data(contentsOf: source))
    }

    func testMovedOrReplacedRootCannotReturnWrongShareURL() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let moved = box.base.appendingPathComponent("moved-archive", isDirectory: true)
        let originalRoot = box.root
        let source = try box.source()
        let store = try ArchiveStore(rootDirectory: box.root) { point in
            if point == .manifestPublished {
                try FileManager.default.moveItem(at: originalRoot, to: moved)
                try FileManager.default.createDirectory(at: originalRoot, withIntermediateDirectories: false)
            }
        }
        do { _ = try await store.importFile(at: source, title: "Moved archive"); XCTFail("must not return stale URL") }
        catch { XCTAssertEqual(error as? ArchiveError, .archiveLocationChanged) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: box.root.path), [])
        let reopened = try ArchiveStore(rootDirectory: moved)
        let records = try await reopened.listRecordings()
        XCTAssertEqual(records.count, 1)
        let verified = try await reopened.verifyRecording(records[0].id)
        XCTAssertTrue(verified.audioURL.path.hasPrefix(moved.resolvingSymlinksInPath().path))
    }

    func testSourceMutationDuringStreamingIsRejected() async throws {
        let box = try Sandbox(); defer { try? box.cleanup() }
        let source = try box.source()
        let store = try ArchiveStore(rootDirectory: box.root) { point in
            if point == .sourceChunkCopied {
                let handle = try FileHandle(forWritingTo: source)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 1)
            }
        }
        do { _ = try await store.importFile(at: source, title: "Not a stable source"); XCTFail("must reject") }
        catch { XCTAssertEqual(error as? ArchiveError, .sourceChangedDuringCopy) }
        XCTAssertEqual(try Data(contentsOf: source).count, 1) // The test's competing writer, not archive code, changed it.
        let report = try await store.recover()
        XCTAssertEqual(report.retainedUnjournaledFiles, 0)
        let records = try await store.listRecordings()
        XCTAssertEqual(records.count, 0)
    }
}
