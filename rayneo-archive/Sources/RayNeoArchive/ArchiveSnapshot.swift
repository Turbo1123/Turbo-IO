import Foundation

/// Selection is explicit. An empty selected list exports the audio without any notes.
public enum SnapshotRevisionSelection: Sendable {
    case selected([UUID])
    case all
}

public struct SnapshotLimits: Sendable {
    /// Includes all exported audio, notes and the independent snapshot manifest.
    public var maximumTotalBytes: Int64
    public init(maximumTotalBytes: Int64 = 1_073_741_824) { self.maximumTotalBytes = maximumTotalBytes }
    func validate() throws {
        guard (1...17_179_869_184).contains(maximumTotalBytes) else { throw SnapshotError.invalidLimits }
    }
}

public enum SnapshotError: Error, Equatable, Sendable {
    case invalidLimits, invalidSelection, targetDirectoryRequired, targetNotLocal
    case symbolicLinkNotAllowed, targetInsideArchive, targetInsideSnapshot
    case sizeLimitExceeded, locationChanged, destinationConflict, publicationUnsupported
    /// Cleanup was deliberately incomplete; only this invocation's allocated name is reported.
    case retainedStage(snapshotID: UUID, directoryName: String)
    /// Publication already happened. Do not retry by deleting this directory.
    case publishedSnapshotRetained(snapshotID: UUID, directoryName: String)
}

public struct SnapshotFile: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case audio, note }
    public let kind: Kind
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let revisionID: UUID?
}

public struct SnapshotEvidence: Codable, Equatable, Sendable {
    public let sourceCopied: Bool
    public let checksumVerified: Bool
    public let transcriptProvided: Bool
    public let noteExported: Bool
    public let audioDecoding: String
    public let speechRecognition: String
    public let wirelessCompleteness: String
    public let serverUpload: String
    public let obsidianIndexing: String
}

/// Standalone description of one export; not an ArchiveStore manifest and not an upload receipt.
public struct ArchiveSnapshotManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let snapshotID: UUID
    public let createdAt: Date
    /// Only the explicitly selected revisions are included; numbering remains unchanged.
    public let recording: ArchivedRecording
    public let selection: String
    public let files: [SnapshotFile]
    public let evidence: SnapshotEvidence
}

public struct ArchiveSnapshotReceipt: Sendable {
    public let snapshotID: UUID
    public let directoryURL: URL
    public let manifestURL: URL
    public let manifest: ArchiveSnapshotManifest
    public let manifestSHA256: String
    public let totalByteCount: Int64
    public let verifiedAt: Date
    public var evidence: SnapshotEvidence { manifest.evidence }
}

enum SnapshotCheckpoint: Sendable { case stageCreated, fileChunkCopied, filesVerified, manifestVerified, published }

struct SnapshotExporter {
    let source: ArchiveFileSystem
    let archiveLimits: ArchiveLimits
    let limits: SnapshotLimits
    let checkpoint: (@Sendable (SnapshotCheckpoint) throws -> Void)?

    func export(recording: ArchivedRecording, selection: String, parent: URL, id: UUID) throws -> ArchiveSnapshotReceipt {
        var entries = [SnapshotFile(kind: .audio, relativePath: recording.audioRelativePath,
                                    byteCount: recording.byteCount, sha256: recording.sha256, revisionID: nil)]
        entries += recording.transcripts.map {
            SnapshotFile(kind: .note, relativePath: "notes/" + $0.filename(recordingID: recording.id),
                         byteCount: $0.byteCount, sha256: $0.noteSHA256, revisionID: $0.id)
        }
        var expectedBytes: Int64 = 0
        for entry in entries {
            guard entry.byteCount > 0, expectedBytes <= limits.maximumTotalBytes - entry.byteCount else {
                throw SnapshotError.sizeLimitExceeded
            }
            expectedBytes += entry.byteCount
        }
        let manifest = ArchiveSnapshotManifest(
            schemaVersion: 1, snapshotID: id, createdAt: Date(), recording: recording, selection: selection,
            files: entries, evidence: SnapshotEvidence(
                sourceCopied: true, checksumVerified: true, transcriptProvided: !recording.transcripts.isEmpty,
                noteExported: !recording.transcripts.isEmpty, audioDecoding: "not_assessed",
                speechRecognition: "not_performed_by_archive", wirelessCompleteness: "not_assessed",
                serverUpload: "not_performed", obsidianIndexing: "not_assessed"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let metadata = try encoder.encode(manifest)
        guard metadata.count <= archiveLimits.maximumManifestBytes else { throw ArchiveError.manifestSizeLimitExceeded }
        guard expectedBytes <= limits.maximumTotalBytes - Int64(metadata.count) else { throw SnapshotError.sizeLimitExceeded }
        expectedBytes += Int64(metadata.count)

        let target = try SnapshotDestination(parentURL: parent, sourceRoot: source.root.value, snapshotID: id)
        do {
            try target.createStage()
            try checkpoint?(.stageCreated)
            try Task.checkCancellation()
            for entry in entries {
                try source.verifyLocation()
                let directory = entry.kind == .audio ? source.audio.value : source.notes.value
                let bound = entry.kind == .audio ? archiveLimits.maximumFileBytes : Int64(archiveLimits.maximumTranscriptBytes) * 8 + 8_192
                try target.copy(entry, from: directory, limit: bound) { try checkpoint?(.fileChunkCopied) }
            }
            try checkpoint?(.filesVerified)
            try Task.checkCancellation()
            try target.writeManifest(metadata)
            try checkpoint?(.manifestVerified)
            try Task.checkCancellation()
            try source.verifyLocation()
            try target.publish()
            try checkpoint?(.published)
            try Task.checkCancellation()
            try source.verifyLocation()
            try target.verifyPublishedContents()
            return ArchiveSnapshotReceipt(snapshotID: id, directoryURL: target.finalURL,
                manifestURL: target.finalURL.appendingPathComponent("snapshot-manifest.json"), manifest: manifest,
                manifestSHA256: digest(metadata), totalByteCount: expectedBytes, verifiedAt: Date())
        } catch {
            if target.published { throw SnapshotError.publishedSnapshotRetained(snapshotID: id, directoryName: target.finalName) }
            guard target.cleanup() else { throw SnapshotError.retainedStage(snapshotID: id, directoryName: target.stageName) }
            throw error
        }
    }
}
