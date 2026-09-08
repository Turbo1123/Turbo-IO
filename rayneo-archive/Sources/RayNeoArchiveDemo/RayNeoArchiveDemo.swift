import Foundation
import RayNeoArchive
import Darwin

private struct EvidenceSnapshot: Encodable, Sendable {
    let sourceCopied: Bool
    let checksumVerified: Bool
    let transcriptProvided: Bool
    let noteExported: Bool

    init(_ evidence: ArchiveEvidence) {
        sourceCopied = evidence.sourceCopied
        checksumVerified = evidence.checksumVerified
        transcriptProvided = evidence.transcriptProvided
        noteExported = evidence.noteExported
    }
}

private struct ImportSnapshot: Encodable, Sendable {
    let recordingID: String
    let byteCount: Int64
    let reusedExistingContent: Bool
    let evidence: EvidenceSnapshot

    init(_ receipt: ArchiveReceipt) {
        recordingID = receipt.recording.id.uuidString.lowercased()
        byteCount = receipt.recording.byteCount
        reusedExistingContent = receipt.reusedExistingContent
        evidence = EvidenceSnapshot(receipt.evidence)
    }
}

private struct NoteSnapshot: Encodable, Sendable {
    let revisionNumber: Int
    let reusedExistingRevision: Bool
    let evidence: EvidenceSnapshot

    init(_ receipt: NoteReceipt) {
        revisionNumber = receipt.revision.number
        reusedExistingRevision = receipt.reusedExistingRevision
        evidence = EvidenceSnapshot(receipt.evidence)
    }
}

private struct RecoverySnapshot: Encodable, Sendable {
    let mode = "clean_store_reopen_no_crash_injection"
    let recoveredTransactions: Int
    let retainedUnjournaledFiles: Int
    let recordingsAfterReopen: Int
    let revisionsAfterReopen: Int
}

private struct DemoSafety: Encodable, Sendable {
    let inputBytes = "synthetic_not_valid_audio"
    let transcriptText = "explicitly_synthetic_host_provided_text"
    let realAudioRead = false
    let audioDecoded = false
    let speechRecognitionPerformed = false
    let microphoneOpened = false
    let networkRequestsMade = false
    let glassesOrPhoneAccessed = false
    let obsidianOrNASAccessed = false
    let exampleDirectoryAutomaticallyDeleted = false
}

private struct DemoReport: Encodable, Sendable {
    let schemaVersion = 1
    let demonstration = "local_sdk_integration_example_not_device_acceptance"
    let safety = DemoSafety()
    let firstImport: ImportSnapshot
    let duplicateImport: ImportSnapshot
    let firstTranscript: NoteSnapshot
    let secondTranscript: NoteSnapshot
    let repeatedFirstTranscript: NoteSnapshot
    let recovery: RecoverySnapshot
    let freshVerification: ImportSnapshot
    let portableSnapshot: PortableSnapshot
    let sourcePreserved: Bool
    let firstRevisionPreserved: Bool
    let artifactPaths: [String: String]
}

private struct PortableSnapshot: Encodable, Sendable {
    let snapshotID: UUID
    let fileCount: Int
    let revisionCount: Int
    let totalByteCount: Int64
    let manifestSHA256: String
    let verifiedAt: Date
    let files: [SnapshotFile]
    let relativeAudioLinkResolved: Bool
    let evidence: SnapshotEvidence
}

private enum DemoError: Error, CustomStringConvertible {
    case unexpectedOutcome(String)
    case failedWithRetainedDirectory(directory: String, reason: String)

    var description: String {
        switch self {
        case .unexpectedOutcome(let reason): return reason
        case .failedWithRetainedDirectory(let directory, let reason):
            return "Demo failed: \(reason). Any generated artifacts are retained at: \(directory)"
        }
    }
}

@main
struct RayNeoArchiveDemo {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print("""
            Usage: rayneo-archive-demo
            Creates a NEW private temporary directory and uses only synthetic non-audio bytes/text.
            Demonstrates local import, deduplication, Markdown revisions, clean recovery, verification and a portable snapshot.
            Prints JSON and saves demo-report.json. Leaves every generated artifact in place.
            No real-file, Obsidian, NAS, phone or network arguments are accepted.
            """)
            return
        }
        guard arguments.isEmpty else {
            FileHandle.standardError.write(Data("Only --help is supported. This demo never accepts real-file or network inputs.\n".utf8))
            exit(2)
        }
        do {
            let report = try await runSyntheticDemonstration()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            guard let reportPath = report.artifactPaths["report"] else { throw DemoError.unexpectedOutcome("Report path missing") }
            try data.write(to: URL(fileURLWithPath: reportPath), options: .withoutOverwriting)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    private static func runSyntheticDemonstration() async throws -> DemoReport {
        let fileManager = FileManager.default
        let exampleDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("rayneo-archive-demo-" + UUID().uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        // No caller path is accepted, and no cleanup follows this exclusive new-directory creation.
        guard mkdir(exampleDirectory.path, mode_t(0o700)) == 0 else {
            throw DemoError.unexpectedOutcome("Unable to exclusively create a new example directory (errno \(errno))")
        }
        do {
            let archiveDirectory = exampleDirectory.appendingPathComponent("archive", isDirectory: true)
            try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let source = exampleDirectory.appendingPathComponent("synthetic-not-audio.bin")
            var bytes = Data("RayNeoArchive demo: SYNTHETIC BYTES, NOT AUDIO.\n".utf8)
            bytes.append(Data((0..<(8_193 - bytes.count)).map { UInt8($0 % 251) }))
            try bytes.write(to: source, options: .withoutOverwriting)

            let store = try ArchiveStore(rootDirectory: archiveDirectory)
            let imported = try await store.importFile(at: source, title: "合成归档演示（不是实际录音）")
            let duplicate = try await store.importFile(at: source, title: "重复导入不会更改原标题")
            guard imported.recording.id == duplicate.recording.id, duplicate.reusedExistingContent else {
                throw DemoError.unexpectedOutcome("Content deduplication did not reuse the recording")
            }

            let firstText = "这是软件集成测试用的合成文字。\n没有麦克风录音，也没有调用任何识别或模型服务。"
            let secondText = "这是软件集成测试用的合成文字，修订二。\n旧稿应保持不变；这些文字不是语音识别结果。"
            let firstNote = try await store.exportTranscript(for: imported.recording.id, text: firstText)
            let firstNoteBytes = try Data(contentsOf: firstNote.noteURL)
            let secondNote = try await store.exportTranscript(for: imported.recording.id, text: secondText)
            let repeated = try await store.exportTranscript(for: imported.recording.id, text: firstText)
            guard firstNote.revision.number == 1, secondNote.revision.number == 2,
                  firstNote.noteURL != secondNote.noteURL, repeated.noteURL == firstNote.noteURL,
                  repeated.reusedExistingRevision else {
                throw DemoError.unexpectedOutcome("Immutable revision or transcript deduplication invariant failed")
            }

            // Public recovery API on a clean reopened store: zero recovered transactions is the expected honest result.
            // Crash-boundary injection stays in the SDK tests, not this public integration executable.
            let reopened = try ArchiveStore(rootDirectory: archiveDirectory)
            let recovered = try await reopened.recover()
            let recordings = try await reopened.listRecordings()
            let verified = try await reopened.verifyRecording(imported.recording.id)
            let sourcePreserved = try Data(contentsOf: source) == bytes
            let firstRevisionPreserved = try Data(contentsOf: firstNote.noteURL) == firstNoteBytes
            guard recordings.count == 1, recordings[0].transcripts.count == 2,
                  recovered.recoveredTransactions == 0, recovered.retainedUnjournaledFiles == 0,
                  sourcePreserved, firstRevisionPreserved else {
                throw DemoError.unexpectedOutcome("Reopen, recovery, or source preservation invariant failed")
            }
            // The executable chooses only its own new local directory, never a caller's vault/NAS.
            let exportParent = exampleDirectory.appendingPathComponent("exports", isDirectory: true)
            try fileManager.createDirectory(at: exportParent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            // Preserve Darwin's physical path: Foundation standardization can turn /private/var into /var.
            guard let physical = realpath(exportParent.path, nil) else { throw DemoError.unexpectedOutcome("Cannot resolve own synthetic export directory") }
            let physicalParent = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            free(physical)
            let snapshot = try await reopened.exportSnapshot(recordingID: imported.recording.id, revisions: .all, toParentDirectory: physicalParent)
            let firstExportedNote = snapshot.directoryURL.appendingPathComponent("notes").appendingPathComponent(firstNote.noteURL.lastPathComponent)
            let noteText = String(decoding: try Data(contentsOf: firstExportedNote), as: UTF8.self)
            let prefix = "[打开本地音频]("
            guard let link = noteText.components(separatedBy: "\n").first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(")") }) else {
                throw DemoError.unexpectedOutcome("Synthetic Markdown audio link missing")
            }
            let relative = String(link.dropFirst(prefix.count).dropLast())
            let linkedBytes = try Data(contentsOf: firstExportedNote.deletingLastPathComponent().appendingPathComponent(relative))
            guard linkedBytes == bytes, snapshot.manifest.files.count == 3,
                  snapshot.manifest.recording.transcripts.count == 2,
                  try Data(contentsOf: source) == bytes,
                  try Data(contentsOf: firstNote.noteURL) == firstNoteBytes else { throw DemoError.unexpectedOutcome("Portable snapshot relative link/source preservation invariant failed") }
            return DemoReport(
                firstImport: ImportSnapshot(imported), duplicateImport: ImportSnapshot(duplicate),
                firstTranscript: NoteSnapshot(firstNote), secondTranscript: NoteSnapshot(secondNote),
                repeatedFirstTranscript: NoteSnapshot(repeated),
                recovery: RecoverySnapshot(recoveredTransactions: recovered.recoveredTransactions,
                                           retainedUnjournaledFiles: recovered.retainedUnjournaledFiles,
                                           recordingsAfterReopen: recordings.count,
                                           revisionsAfterReopen: recordings[0].transcripts.count),
                freshVerification: ImportSnapshot(verified),
                portableSnapshot: PortableSnapshot(snapshotID: snapshot.snapshotID, fileCount: snapshot.manifest.files.count,
                    revisionCount: snapshot.manifest.recording.transcripts.count, totalByteCount: snapshot.totalByteCount,
                    manifestSHA256: snapshot.manifestSHA256, verifiedAt: snapshot.verifiedAt, files: snapshot.manifest.files,
                    relativeAudioLinkResolved: true, evidence: snapshot.evidence),
                sourcePreserved: sourcePreserved,
                firstRevisionPreserved: firstRevisionPreserved,
                artifactPaths: [
                    "exampleDirectory": exampleDirectory.path,
                    "selectedSyntheticSource": source.path,
                    "archiveDirectory": archiveDirectory.path,
                    "audioBytesNotValidAudio": verified.audioURL.path,
                    "firstMarkdownRevision": firstNote.noteURL.path,
                    "secondMarkdownRevision": secondNote.noteURL.path,
                    "manifest": archiveDirectory.appendingPathComponent("manifest.json").path,
                    "portableSnapshotDirectory": snapshot.directoryURL.path,
                    "portableSnapshotManifest": snapshot.manifestURL.path,
                    "report": exampleDirectory.appendingPathComponent("demo-report.json").path
                ]
            )
        } catch {
            throw DemoError.failedWithRetainedDirectory(directory: exampleDirectory.path, reason: String(describing: error))
        }
    }
}
