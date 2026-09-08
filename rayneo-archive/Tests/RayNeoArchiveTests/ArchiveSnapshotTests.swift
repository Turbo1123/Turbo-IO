import XCTest
import Foundation
import CryptoKit
import Darwin
@testable import RayNeoArchive

private enum SnapshotTestStop: Error { case injected }

/// Separate fixture preserves a POSIX physical path without Foundation's /private/var -> /var alias.
private final class SnapshotSandbox {
    let base: URL
    let root: URL
    init() throws {
        guard let physical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw ArchiveFileSystem.failure("resolve synthetic temporary root")
        }
        defer { free(physical) }
        base = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("rayneo-snapshot-tests-" + UUID().uuidString, isDirectory: true)
        root = base.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func source(_ name: String = "synthetic-not-audio.opus", bytes: Data = Data((0..<8_193).map { UInt8($0 % 251) })) throws -> URL {
        let url = base.appendingPathComponent(name)
        try bytes.write(to: url, options: .withoutOverwriting)
        return url
    }
    func cleanup() throws {
        func removeLevel(_ directory: URL, depth: Int) throws {
            guard depth <= 3 else { throw ArchiveError.invalidFileURL }
            let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard entries.count < 100 else { throw ArchiveError.invalidFileURL }
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true && values.isSymbolicLink != true { try removeLevel(entry, depth: depth + 1) }
                else { guard unlink(entry.path) == 0 else { throw ArchiveFileSystem.failure("clean synthetic snapshot test file") } }
            }
            guard rmdir(directory.path) == 0 else { throw ArchiveFileSystem.failure("clean synthetic snapshot test directory") }
        }
        try removeLevel(base, depth: 0)
    }
}

final class ArchiveSnapshotTests: XCTestCase {
    private func parent(in box: SnapshotSandbox) throws -> URL {
        let parent = box.base.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        return parent
    }
    private func names(_ directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testSelectedRevisionSnapshotHasWorkingRelativeAudioLinkAndIndependentManifest() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let store = try ArchiveStore(rootDirectory: box.root)
        let source = try box.source()
        let sourceBytes = try Data(contentsOf: source)
        let audio = try await store.importFile(at: source, title: "Synthetic export; not valid audio")
        let first = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC MANUAL TEXT ONE", title: "旧版")
        let second = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC MANUAL TEXT TWO", title: "第二版 / ../ [test]")
        let firstBytes = try Data(contentsOf: first.noteURL), secondBytes = try Data(contentsOf: second.noteURL)
        let parent = try parent(in: box)
        let receipt = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .selected([second.revision.id]), toParentDirectory: parent)
        let rawManifest = try Data(contentsOf: receipt.manifestURL)
        let manifest = try JSONDecoder().decode(ArchiveSnapshotManifest.self, from: rawManifest)
        XCTAssertEqual(manifest, receipt.manifest)
        XCTAssertEqual(hash(rawManifest), receipt.manifestSHA256)
        XCTAssertEqual(manifest.recording.transcripts.map(\.id), [second.revision.id])
        XCTAssertEqual(manifest.recording.transcripts[0].number, 2)
        XCTAssertEqual(manifest.files.count, 2)
        XCTAssertEqual(try names(receipt.directoryURL), ["audio", "notes", "snapshot-manifest.json"])
        XCTAssertEqual(try names(receipt.directoryURL.appendingPathComponent("notes")), [second.noteURL.lastPathComponent])
        XCTAssertFalse(String(decoding: rawManifest, as: UTF8.self).contains(source.path))
        XCTAssertFalse(String(decoding: rawManifest, as: UTF8.self).contains("SYNTHETIC MANUAL TEXT TWO"))
        var total = Int64(rawManifest.count)
        for file in manifest.files {
            XCTAssertFalse(file.relativePath.hasPrefix("/"))
            XCTAssertFalse(file.relativePath.split(separator: "/").contains(".."))
            let copied = try Data(contentsOf: receipt.directoryURL.appendingPathComponent(file.relativePath))
            XCTAssertEqual(Int64(copied.count), file.byteCount)
            XCTAssertEqual(hash(copied), file.sha256)
            total += file.byteCount
        }
        XCTAssertEqual(receipt.totalByteCount, total)
        let noteEntry = try XCTUnwrap(manifest.files.first { $0.kind == .note })
        let exportedNote = receipt.directoryURL.appendingPathComponent(noteEntry.relativePath)
        let markdown = String(decoding: try Data(contentsOf: exportedNote), as: UTF8.self)
        let linkPrefix = "[打开本地音频]("
        let linkLine = try XCTUnwrap(markdown.components(separatedBy: "\n").first { $0.hasPrefix(linkPrefix) })
        let relative = String(linkLine.dropFirst(linkPrefix.count).dropLast())
        let resolvedAudio = exportedNote.deletingLastPathComponent().appendingPathComponent(relative).standardizedFileURL
        XCTAssertEqual(resolvedAudio, receipt.directoryURL.appendingPathComponent(audio.recording.audioRelativePath).standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: resolvedAudio), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: exportedNote), secondBytes)
        XCTAssertEqual(try Data(contentsOf: first.noteURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: second.noteURL), secondBytes)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertTrue(receipt.evidence.sourceCopied && receipt.evidence.checksumVerified && receipt.evidence.transcriptProvided && receipt.evidence.noteExported)
        XCTAssertEqual(receipt.evidence.serverUpload, "not_performed")
        XCTAssertEqual(receipt.evidence.speechRecognition, "not_performed_by_archive")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: receipt.directoryURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: receipt.manifestURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testAllAudioOnlyAndRepeatExportsDoNotOverwriteOrIncludeUnselectedRecording() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic one")
        _ = try await store.importFile(at: box.source("different.bin", bytes: Data([1, 2, 3])), title: "UNSELECTED TITLE")
        _ = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC ONE", title: "One")
        _ = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC TWO", title: "Two")
        let all = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent)
        let oldManifest = try Data(contentsOf: all.manifestURL)
        let only = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .selected([]), toParentDirectory: parent)
        XCTAssertNotEqual(all.snapshotID, only.snapshotID)
        XCTAssertNotEqual(all.directoryURL, only.directoryURL)
        XCTAssertEqual(all.manifest.files.count, 3)
        XCTAssertEqual(only.manifest.files.count, 1)
        XCTAssertTrue(try names(only.directoryURL.appendingPathComponent("notes")).isEmpty)
        XCTAssertFalse(only.evidence.transcriptProvided || only.evidence.noteExported)
        XCTAssertEqual(try Data(contentsOf: all.manifestURL), oldManifest)
        XCTAssertFalse(String(decoding: oldManifest, as: UTF8.self).contains("UNSELECTED TITLE"))
        XCTAssertEqual(try names(parent).count, 2)
    }

    func testSelectionAndTotalBudgetRejectBeforeCreatingStage() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let note = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC", title: "One")
        for selection in [SnapshotRevisionSelection.selected([UUID()]), .selected([note.revision.id, note.revision.id])] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: selection, toParentDirectory: parent); XCTFail("invalid selection") }
            catch { XCTAssertEqual(error as? SnapshotError, .invalidSelection) }
        }
        for cap in [Int64(1), audio.recording.byteCount, audio.recording.byteCount + note.revision.byteCount] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, limits: SnapshotLimits(maximumTotalBytes: cap)); XCTFail("budget includes manifest") }
            catch { XCTAssertEqual(error as? SnapshotError, .sizeLimitExceeded) }
        }
        for invalid in [Int64.min, Int64(0), Int64.max] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, limits: SnapshotLimits(maximumTotalBytes: invalid)); XCTFail("invalid limits") }
            catch { XCTAssertEqual(error as? SnapshotError, .invalidLimits) }
        }
        XCTAssertTrue(try names(parent).isEmpty)
    }

    func testDestinationInsideArchiveAndSymbolicLinkAreRejectedByIdentity() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        for forbidden in [box.root, box.root.appendingPathComponent("notes")] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: forbidden); XCTFail("inside archive") }
            catch { XCTAssertEqual(error as? SnapshotError, .targetInsideArchive) }
        }
        let link = parent.appendingPathComponent("linked-source")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.root)
        do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: link.appendingPathComponent("notes")); XCTFail("ancestor link") }
        catch { XCTAssertEqual(error as? SnapshotError, .symbolicLinkNotAllowed) }
        let missing = parent.appendingPathComponent("not-created")
        do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: missing); XCTFail("must exist") }
        catch { XCTAssertEqual(error as? SnapshotError, .targetDirectoryRequired) }
        for invalid in [URL(string: "https://example.invalid/snapshot")!, URL(fileURLWithPath: parent.path + "\0ignored"),
                        URL(string: parent.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "%2Flinked-source%2Fnotes")!] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: invalid); XCTFail("invalid destination URL") }
            catch { XCTAssertEqual(error as? ArchiveError, .invalidFileURL) }
        }
        XCTAssertEqual(try names(parent), ["linked-source"])
    }

    func testExistingSnapshotCannotBeModifiedOrUsedAsParent() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let snapshot = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent)
        let bytes = try Data(contentsOf: snapshot.manifestURL)
        for target in [snapshot.directoryURL, snapshot.directoryURL.appendingPathComponent("notes")] {
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: target); XCTFail("old snapshot parent") }
            catch { XCTAssertEqual(error as? SnapshotError, .targetInsideSnapshot) }
        }
        do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: snapshot.snapshotID, checkpoint: nil); XCTFail("exclusive publication") }
        catch { XCTAssertEqual(error as? SnapshotError, .destinationConflict) }
        XCTAssertEqual(try Data(contentsOf: snapshot.manifestURL), bytes)
        XCTAssertEqual(try names(parent), [snapshot.directoryURL.lastPathComponent])
        let id = UUID()
        // Independent deterministic staging collision, not a broad search/delete operation.
        let exactName = ".rayneo-snapshot-\(id.uuidString.lowercased()).staging"
        let existing = parent.appendingPathComponent(exactName)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        try Data("DO NOT TOUCH".utf8).write(to: existing.appendingPathComponent("sentinel"), options: .withoutOverwriting)
        do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id, checkpoint: nil); XCTFail("staging collision") }
        catch { XCTAssertEqual(error as? SnapshotError, .destinationConflict) }
        XCTAssertEqual(try names(existing), ["sentinel"])
    }

    func testFaultsBeforePublicationCleanOnlyTheirOwnStage() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let sentinel = parent.appendingPathComponent("unrelated.txt")
        try Data("UNRELATED SYNTHETIC".utf8).write(to: sentinel, options: .withoutOverwriting)
        for stop in [SnapshotCheckpoint.stageCreated, .fileChunkCopied, .filesVerified, .manifestVerified] {
            do {
                _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: UUID()) {
                    if $0 == stop { throw SnapshotTestStop.injected }
                }
                XCTFail("fault must propagate")
            } catch { XCTAssertTrue(error is SnapshotTestStop) }
            XCTAssertEqual(try names(parent), ["unrelated.txt"])
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("UNRELATED SYNTHETIC".utf8))
    }

    func testCancellationDuringStreamingCleansStageButAfterPublicationRetainsIdentifier() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        for stop in [SnapshotCheckpoint.fileChunkCopied, .published] {
            let id = UUID()
            let operation = Task {
                try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                    if $0 == stop { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            do { _ = try await operation.value; XCTFail("cancelled export") }
            catch {
                if stop == .published {
                    let name = "rayneo-snapshot-\(id.uuidString.lowercased())"
                    XCTAssertEqual(error as? SnapshotError, .publishedSnapshotRetained(snapshotID: id, directoryName: name))
                    let bytes = try Data(contentsOf: parent.appendingPathComponent(name).appendingPathComponent("snapshot-manifest.json"))
                    XCTAssertEqual(try JSONDecoder().decode(ArchiveSnapshotManifest.self, from: bytes).snapshotID, id)
                } else { XCTAssertTrue(error is CancellationError); XCTAssertTrue(try names(parent).isEmpty) }
            }
        }
    }

    func testMidCopySourceChangeFailsWithoutRepairingOrDeletingIt() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let source = try box.source(), original = try Data(contentsOf: source)
        let audio = try await store.importFile(at: source, title: "Synthetic")
        let changedURL = audio.audioURL
        do {
            _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: UUID()) {
                if $0 == .fileChunkCopied {
                    let handle = try FileHandle(forWritingTo: changedURL)
                    defer { try? handle.close() }
                    try handle.truncate(atOffset: 0)
                }
            }
            XCTFail("changed source")
        } catch { XCTAssertEqual(error as? ArchiveError, .archivedContentChanged) }
        XCTAssertTrue(try names(parent).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: changedURL).count, 0)
    }

    func testUnknownStageEntryIsNotPublishedOrDeleted() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let id = UUID()
        let stageName = ".rayneo-snapshot-\(id.uuidString.lowercased()).staging"
        let marker = parent.appendingPathComponent(stageName).appendingPathComponent("foreign-marker")
        do {
            _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                if $0 == .filesVerified { try Data("FOREIGN SYNTHETIC".utf8).write(to: marker, options: .withoutOverwriting) }
            }
            XCTFail("unselected entry cannot be published")
        } catch { XCTAssertEqual(error as? SnapshotError, .retainedStage(snapshotID: id, directoryName: stageName)) }
        XCTAssertEqual(try Data(contentsOf: marker), Data("FOREIGN SYNTHETIC".utf8))
        XCTAssertEqual(try names(parent), [stageName])
    }

    func testReplacedStageAndSubdirectoryAreNeverCleanedByNameAlone() async throws {
        for replaceEntireStage in [true, false] {
            let box = try SnapshotSandbox(); defer { try? box.cleanup() }
            let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
            let audio = try await store.importFile(at: box.source(), title: "Synthetic")
            let id = UUID()
            let exactStage = ".rayneo-snapshot-\(id.uuidString.lowercased()).staging"
            let original = parent.appendingPathComponent(exactStage)
            let moved = parent.appendingPathComponent("moved-owned-" + id.uuidString)
            let replaced = replaceEntireStage ? original : original.appendingPathComponent("audio")
            let foreign = replaced.appendingPathComponent("foreign-marker")
            do {
                _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                    if $0 == .filesVerified {
                        try FileManager.default.moveItem(at: replaced, to: moved)
                        try FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: false)
                        try Data("FOREIGN SYNTHETIC".utf8).write(to: foreign, options: .withoutOverwriting)
                    }
                }
                XCTFail("replacement")
            } catch { XCTAssertEqual(error as? SnapshotError, .retainedStage(snapshotID: id, directoryName: exactStage)) }
            XCTAssertEqual(try Data(contentsOf: foreign), Data("FOREIGN SYNTHETIC".utf8))
            let movedAudio = replaceEntireStage ? moved.appendingPathComponent(audio.recording.audioRelativePath) : moved.appendingPathComponent(audio.audioURL.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: movedAudio), try Data(contentsOf: audio.audioURL))
        }
    }

    func testArchiveLockBlocksExportBeforeCreatingAnything() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let lock = Darwin.open(box.root.appendingPathComponent(".archive.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(lock, 0)
        defer { flock(lock, LOCK_UN); Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent); XCTFail("locked") }
        catch { XCTAssertEqual(error as? ArchiveError, .archiveBusy) }
        XCTAssertTrue(try names(parent).isEmpty)
    }

    func testSelectedSourceSymlinkAndDamagedNoteNeverProduceSnapshot() async throws {
        for useAudioSymlink in [true, false] {
            let box = try SnapshotSandbox(); defer { try? box.cleanup() }
            let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
            let source = try box.source(), originalBytes = try Data(contentsOf: source)
            let audio = try await store.importFile(at: source, title: "Synthetic")
            let note = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC TEXT", title: "One")
            if useAudioSymlink {
                let moved = box.base.appendingPathComponent("test-owned-original-audio")
                try FileManager.default.moveItem(at: audio.audioURL, to: moved)
                try FileManager.default.createSymbolicLink(at: audio.audioURL, withDestinationURL: source)
            } else {
                try Data("SYNTHETIC DAMAGED NOTE".utf8).write(to: note.noteURL)
            }
            do { _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent); XCTFail("invalid selected source") }
            catch {
                if useAudioSymlink {
                    guard case .io = error as? ArchiveError else { return XCTFail("expected no-follow I/O rejection") }
                } else { XCTAssertEqual(error as? ArchiveError, .archivedContentChanged) }
            }
            XCTAssertTrue(try names(parent).isEmpty)
            XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        }
    }

    func testIndependentReadbackRejectsDestinationBytesChangedDuringCopy() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let sourceBytes = try Data(contentsOf: audio.audioURL)
        let id = UUID()
        let copyURL = parent.appendingPathComponent(".rayneo-snapshot-\(id.uuidString.lowercased()).staging")
            .appendingPathComponent(audio.recording.audioRelativePath)
        do {
            _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                if $0 == .fileChunkCopied {
                    let handle = try FileHandle(forWritingTo: copyURL)
                    defer { try? handle.close() }
                    try handle.write(contentsOf: Data([255]))
                }
            }
            XCTFail("source-side hash alone must not verify the destination")
        } catch { XCTAssertEqual(error as? ArchiveError, .archivedContentChanged) }
        XCTAssertTrue(try names(parent).isEmpty)
        XCTAssertEqual(try Data(contentsOf: audio.audioURL), sourceBytes)
    }

    func testMovedParentAfterPublicationRetainsSnapshotInsteadOfReturningWrongURL() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let id = UUID()
        let exactName = "rayneo-snapshot-\(id.uuidString.lowercased())"
        let moved = box.base.appendingPathComponent("moved-exports")
        do {
            _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                if $0 == .published {
                    try FileManager.default.moveItem(at: parent, to: moved)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                }
            }
            XCTFail("stale URL must not be returned")
        } catch { XCTAssertEqual(error as? SnapshotError, .publishedSnapshotRetained(snapshotID: id, directoryName: exactName)) }
        XCTAssertTrue(try names(parent).isEmpty)
        let metadata = try Data(contentsOf: moved.appendingPathComponent(exactName).appendingPathComponent("snapshot-manifest.json"))
        XCTAssertEqual(try JSONDecoder().decode(ArchiveSnapshotManifest.self, from: metadata).snapshotID, id)
    }

    func testArchiveLockIsHeldThroughVerificationAndPublication() async throws {
        let box = try SnapshotSandbox(); defer { try? box.cleanup() }
        let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
        let audio = try await store.importFile(at: box.source(), title: "Synthetic")
        let lockURL = box.root.appendingPathComponent(".archive.lock")
        let receipt = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: UUID()) {
            if $0 == .filesVerified || $0 == .published {
                let descriptor = Darwin.open(lockURL.path, O_RDWR)
                guard descriptor >= 0 else { throw SnapshotTestStop.injected }
                defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
                guard flock(descriptor, LOCK_EX | LOCK_NB) != 0, errno == EWOULDBLOCK else { throw SnapshotTestStop.injected }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.manifestURL.path))
    }

    func testPostVerificationSameInodeModificationIsRejectedIncludingOldNotes() async throws {
        for stop in [SnapshotCheckpoint.filesVerified, .manifestVerified, .published] {
            let box = try SnapshotSandbox(); defer { try? box.cleanup() }
            let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
            let audio = try await store.importFile(at: box.source(), title: "Synthetic")
            let first = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC FIRST", title: "Old note")
            _ = try await store.exportTranscript(for: audio.recording.id, text: "SYNTHETIC SECOND", title: "New note")
            let originalAudio = try Data(contentsOf: audio.audioURL), originalNote = try Data(contentsOf: first.noteURL)
            let id = UUID()
            let exactFinal = "rayneo-snapshot-\(id.uuidString.lowercased())"
            let outputName = stop == .published ? exactFinal : ".rayneo-snapshot-\(id.uuidString.lowercased()).staging"
            let relative = stop == .filesVerified ? audio.recording.audioRelativePath : "notes/" + first.noteURL.lastPathComponent
            let changed = parent.appendingPathComponent(outputName).appendingPathComponent(relative)
            do {
                let unexpectedReceipt = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                    if $0 == stop {
                        // Write through the same inode without changing byte count, after its hash readback.
                        let handle = try FileHandle(forWritingTo: changed)
                        defer { try? handle.close() }
                        try handle.write(contentsOf: Data([255]))
                        try handle.synchronize()
                    }
                }
                let entry = try XCTUnwrap(unexpectedReceipt.manifest.files.first { $0.relativePath == relative })
                let publishedBytes = try Data(contentsOf: unexpectedReceipt.directoryURL.appendingPathComponent(relative))
                let matches = hash(publishedBytes) == entry.sha256
                print("SNAPSHOT_REPRO checkpoint=\(stop) returned_success_receipt=true published_hash_matches_manifest=\(matches)")
                XCTAssertTrue(matches, "Returned snapshot receipt must not certify changed bytes")
                XCTFail("Must not return a success receipt for post-verification changed bytes at \(stop)")
            } catch {
                if stop == .published {
                    XCTAssertEqual(error as? SnapshotError, .publishedSnapshotRetained(snapshotID: id, directoryName: exactFinal))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: changed.path))
                } else {
                    XCTAssertEqual(error as? ArchiveError, .archivedContentChanged)
                    XCTAssertTrue(try names(parent).isEmpty)
                }
            }
            XCTAssertEqual(try Data(contentsOf: audio.audioURL), originalAudio)
            XCTAssertEqual(try Data(contentsOf: first.noteURL), originalNote)
        }
    }

    func testUnknownEntriesAddedAfterPublicationPreventReceiptAndArePreserved() async throws {
        for subdirectory in ["", "audio", "notes"] {
            let box = try SnapshotSandbox(); defer { try? box.cleanup() }
            let parent = try parent(in: box), store = try ArchiveStore(rootDirectory: box.root)
            let audio = try await store.importFile(at: box.source(), title: "Synthetic")
            let originalAudio = try Data(contentsOf: audio.audioURL)
            let id = UUID(), extraBytes = Data("SYNTHETIC FOREIGN ENTRY; NOT AUDIO".utf8)
            let name = "rayneo-snapshot-\(id.uuidString.lowercased())"
            let final = parent.appendingPathComponent(name)
            let extra = final.appendingPathComponent(subdirectory).appendingPathComponent("foreign-marker")
            do {
                _ = try await store.exportSnapshot(recordingID: audio.recording.id, revisions: .all, toParentDirectory: parent, snapshotID: id) {
                    if $0 == .published { try extraBytes.write(to: extra, options: .withoutOverwriting) }
                }
                XCTFail("A receipt must not omit an extra published entry in \(subdirectory)")
            } catch { XCTAssertEqual(error as? SnapshotError, .publishedSnapshotRetained(snapshotID: id, directoryName: name)) }
            XCTAssertEqual(try Data(contentsOf: extra), extraBytes)
            XCTAssertEqual(try Data(contentsOf: audio.audioURL), originalAudio)
            XCTAssertEqual(try Data(contentsOf: final.appendingPathComponent(audio.recording.audioRelativePath)), originalAudio)
            XCTAssertTrue(FileManager.default.fileExists(atPath: final.appendingPathComponent("snapshot-manifest.json").path))
        }
    }
}
