import XCTest
import RayNeoArchive
@testable import RayNeoCompanion

final class ArchiveIntegrationTests: XCTestCase {
    func testRepositoryCopiesSourceDeduplicatesAndKeepsFourEvidenceLayers() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try syntheticSource(in: root)
        let original = try Data(contentsOf: source)
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("verified"))
        let first = try await repository.importFile(source, title: "合成样本，不是录音")
        let duplicate = try await repository.importFile(source, title: "不能覆盖原有标题")
        XCTAssertEqual(first.recording.id, duplicate.recording.id)
        XCTAssertTrue(duplicate.reusedExistingContent)
        XCTAssertEqual(duplicate.recording.title, "合成样本，不是录音")
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: first.audioURL), original)
        XCTAssertTrue(first.evidence.sourceCopied)
        XCTAssertTrue(first.evidence.checksumVerified)
        XCTAssertFalse(first.evidence.transcriptProvided)
        XCTAssertFalse(first.evidence.noteExported)
        XCTAssertNil(first.recording.recordedAt)
    }

    func testTranscriptRevisionsAndShareKeepFirstFileUnchanged() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("verified"))
        let recording = try await repository.importFile(syntheticSource(in: root))
        let first = try await repository.saveTranscript(recordingID: recording.recording.id, text: "Synthetic manually supplied text one.", title: "Manual QA")
        let originalNote = try Data(contentsOf: first.noteURL)
        let second = try await repository.saveTranscript(recordingID: recording.recording.id, text: "Synthetic manually supplied text two.", title: "Manual QA")
        let repeatFirst = try await repository.saveTranscript(recordingID: recording.recording.id, text: "Synthetic manually supplied text one.", title: "Manual QA")
        XCTAssertEqual(second.revision.number, 2)
        XCTAssertNotEqual(first.noteURL, second.noteURL)
        XCTAssertTrue(repeatFirst.reusedExistingRevision)
        XCTAssertEqual(repeatFirst.revision.number, 1)
        XCTAssertEqual(try Data(contentsOf: first.noteURL), originalNote)
        XCTAssertTrue(second.evidence.transcriptProvided)
        XCTAssertTrue(second.evidence.noteExported)
        let shared = try await repository.prepareNoteShare(recordingID: recording.recording.id, revisionID: first.revision.id)
        XCTAssertEqual(shared, first.noteURL)
        let markdown = String(decoding: originalNote, as: UTF8.self)
        XCTAssertTrue(markdown.contains("not_performed_by_archive"))
        XCTAssertTrue(markdown.contains("not_performed"))
    }

    @MainActor func testOldImportMetadataAndFileAreNotAutomaticallyMigrated() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "companion-archive-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyRoot = root.appendingPathComponent("ImportedRecordings")
        let newRoot = root.appendingPathComponent("VerifiedRecordingArchiveV1")
        let store = CompanionStore(defaults: defaults, recordingRoot: legacyRoot, archiveRoot: newRoot)
        try await store.importRecording(syntheticSource(in: root))
        let metadata = defaults.data(forKey: "companion.v1.recordings")
        let legacy = try XCTUnwrap(store.recordings.first)
        let url = try XCTUnwrap(store.recordingURL(legacy))
        let original = try Data(contentsOf: url)
        await store.archive.load()
        XCTAssertTrue(store.archive.recordings.isEmpty)
        XCTAssertNil(store.archive.errorMessage)
        XCTAssertEqual(defaults.data(forKey: "companion.v1.recordings"), metadata)
        // This explicit call represents the user's per-item copy confirmation, not startup migration.
        await store.archive.importFile(url, title: legacy.name)
        XCTAssertEqual(store.archive.recordings.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(defaults.data(forKey: "companion.v1.recordings"), metadata)
        XCTAssertEqual(store.recordings.count, 1)
    }

    @MainActor func testControllerPersistsRevisionsButFreshVerificationIsNotInferredAtReopen() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveRoot = root.appendingPathComponent("verified")
        let controller = LocalArchiveController(rootDirectory: archiveRoot)
        await controller.importFile(try syntheticSource(in: root))
        let recording = try XCTUnwrap(controller.recordings.first)
        XCTAssertNotNil(controller.latestVerifications[recording.id])
        let saved = await controller.saveTranscript(recordingID: recording.id, text: "Hand supplied synthetic words.", title: "Revision")
        XCTAssertNotNil(saved)
        let reopened = LocalArchiveController(rootDirectory: archiveRoot)
        await reopened.load()
        XCTAssertEqual(reopened.recordings.first?.transcripts.count, 1)
        XCTAssertTrue(reopened.latestVerifications.isEmpty)
        let fresh = await reopened.verify(recording.id)
        XCTAssertNotNil(fresh)
        XCTAssertNotNil(reopened.latestVerifications[recording.id])
        XCTAssertFalse(reopened.isBusy)
    }

    func testModifiedNoteIsNotSharedOrOverwritten() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("verified"))
        let recording = try await repository.importFile(syntheticSource(in: root))
        let note = try await repository.saveTranscript(recordingID: recording.recording.id, text: "Synthetic text.", title: "QA")
        let modified = Data("Synthetic externally modified note.".utf8)
        try modified.write(to: note.noteURL)
        do {
            _ = try await repository.prepareNoteShare(recordingID: recording.recording.id, revisionID: note.revision.id)
            XCTFail("Modified note must not be shared as verified")
        } catch { XCTAssertTrue(error is LocalArchiveError) }
        XCTAssertEqual(try Data(contentsOf: note.noteURL), modified)
    }

    @MainActor func testFailureStaysVisibleAndDoesNotClaimRollbackOrFreshVerification() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LocalArchiveController(rootDirectory: root.appendingPathComponent("verified"))
        await controller.importFile(try syntheticSource(in: root))
        let recording = try XCTUnwrap(controller.recordings.first)
        let verifiedURL = await controller.verify(recording.id)
        let url = try XCTUnwrap(verifiedURL)
        let modified = Data([17, 23, 47])
        try modified.write(to: url)
        let failure = await controller.verify(recording.id)
        XCTAssertNil(failure)
        XCTAssertNil(controller.latestVerifications[recording.id])
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.errorMessage?.contains("不承诺失败即回滚") == true)
        XCTAssertNil(controller.statusMessage)
        XCTAssertEqual(try Data(contentsOf: url), modified)
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor func testShareAndTranscriptFailuresInvalidateFreshDateAndSurviveRefresh() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try syntheticSource(in: root)
        let original = try Data(contentsOf: source)
        let controller = LocalArchiveController(rootDirectory: root.appendingPathComponent("verified"))
        await controller.importFile(source)
        let recording = try XCTUnwrap(controller.recordings.first)
        let saved = await controller.saveTranscript(recordingID: recording.id, text: "Hand supplied synthetic words.", title: "Revision")
        let note = try XCTUnwrap(saved)
        for useSharePath in [true, false] {
            let fresh = await controller.verify(recording.id)
            let audioURL = try XCTUnwrap(fresh)
            XCTAssertNotNil(controller.latestVerifications[recording.id])
            try Data([8, 9, 10]).write(to: audioURL)
            if useSharePath {
                let result = await controller.prepareNoteShare(recordingID: recording.id, revisionID: note.revision.id)
                XCTAssertNil(result)
            } else {
                let result = await controller.saveTranscript(recordingID: recording.id, text: "New words must not bypass audio failure.", title: "Revision")
                XCTAssertNil(result)
            }
            XCTAssertNil(controller.latestVerifications[recording.id])
            XCTAssertNotNil(controller.verificationIssues[recording.id])
            controller.errorMessage = nil
            await controller.load()
            XCTAssertNotNil(controller.verificationIssues[recording.id])
            XCTAssertNil(controller.latestVerifications[recording.id])
            // Test-owned repair, not a production repair API; verifies that only complete recheck clears the issue.
            try original.write(to: audioURL)
            let repaired = await controller.verify(recording.id)
            XCTAssertNotNil(repaired)
            XCTAssertNil(controller.verificationIssues[recording.id])
        }
    }

    @MainActor func testFullRecheckIncludesAllNotesBeforeClearingIntegrityIssue() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LocalArchiveController(rootDirectory: root.appendingPathComponent("verified"))
        await controller.importFile(try syntheticSource(in: root))
        let recording = try XCTUnwrap(controller.recordings.first)
        let saved = await controller.saveTranscript(recordingID: recording.id, text: "Synthetic first note.", title: "Revision")
        let note = try XCTUnwrap(saved)
        let originalNote = try Data(contentsOf: note.noteURL)
        try Data("Synthetic modified note.".utf8).write(to: note.noteURL)
        let badShare = await controller.prepareNoteShare(recordingID: recording.id, revisionID: note.revision.id)
        XCTAssertNil(badShare)
        let audioAloneIsNotEnough = await controller.verify(recording.id)
        XCTAssertNil(audioAloneIsNotEnough)
        XCTAssertNotNil(controller.verificationIssues[recording.id])
        try originalNote.write(to: note.noteURL)
        let fullyChecked = await controller.verify(recording.id)
        XCTAssertNotNil(fullyChecked)
        XCTAssertNil(controller.verificationIssues[recording.id])
    }

    func testBoundedInputsAndUnicodeTitles() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try syntheticSource(in: root)
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("verified"), limits: ArchiveLimits(maximumFileBytes: 3))
        do { _ = try await repository.importFile(source); XCTFail("Oversized source accepted") }
        catch { XCTAssertTrue(error is RecordingImportError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let title = LocalArchiveRepository.defaultTitle(String(repeating: "眼镜👨‍👩‍👧‍👦", count: 50) + "\n尾部")
        XCTAssertLessThanOrEqual(title.utf8.count, 256)
        XCTAssertFalse(title.contains("\n"))
        XCTAssertEqual(LocalArchiveRepository.defaultTitle("\n\t"), "本地录音")
    }

    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("companion-archive-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func syntheticSource(in root: URL) throws -> URL {
        let source = root.appendingPathComponent("synthetic-\(UUID().uuidString).wav")
        try Data("SYNTHETIC BYTES, NOT VALID AUDIO; NO ASR.".utf8).write(to: source, options: .withoutOverwriting)
        return source
    }
}
