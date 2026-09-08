import Foundation

public struct ArchiveLimits: Sendable {
    public var maximumFileBytes: Int64
    public var maximumTranscriptBytes: Int
    public var maximumManifestBytes: Int
    public var maximumRecordings: Int
    public var maximumRevisionsPerRecording: Int

    public init(
        maximumFileBytes: Int64 = 512 * 1_024 * 1_024,
        maximumTranscriptBytes: Int = 1_024 * 1_024,
        maximumManifestBytes: Int = 16 * 1_024 * 1_024,
        maximumRecordings: Int = 10_000,
        maximumRevisionsPerRecording: Int = 100
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumTranscriptBytes = maximumTranscriptBytes
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumRecordings = maximumRecordings
        self.maximumRevisionsPerRecording = maximumRevisionsPerRecording
    }

    func validate() throws {
        guard (1...8_589_934_592).contains(maximumFileBytes),
              (1...8_388_608).contains(maximumTranscriptBytes),
              (1_024...67_108_864).contains(maximumManifestBytes),
              (1...100_000).contains(maximumRecordings),
              (1...9_999).contains(maximumRevisionsPerRecording) else {
            throw ArchiveError.invalidLimits
        }
    }
}

/// These are local archive stages, not audio decoding, ASR, upload, or glasses-transfer evidence.
public struct ArchiveEvidence: Equatable, Sendable {
    public let sourceCopied: Bool
    public let checksumVerified: Bool
    public let transcriptProvided: Bool
    public let noteExported: Bool
}

public struct TranscriptRevision: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let number: Int
    public let title: String
    public let createdAt: Date
    public let inputSHA256: String
    public let noteSHA256: String
    public let byteCount: Int64

    func filename(recordingID: UUID) -> String {
        "\(recordingID.uuidString.lowercased())-r\(String(format: "%04d", number))-\(safeStem(title)).md"
    }
}

public struct ArchivedRecording: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let importedAt: Date
    public let recordedAt: Date?
    public let sha256: String
    public let byteCount: Int64
    /// Sanitized extension only. It is not a detected or validated audio format.
    public let fileExtension: String
    public let checksumVerifiedAt: Date
    public internal(set) var transcripts: [TranscriptRevision]

    public var audioRelativePath: String { "audio/\(audioFilename)" }
    var audioFilename: String { "\(id.uuidString.lowercased()).\(fileExtension)" }
    public var evidence: ArchiveEvidence {
        ArchiveEvidence(sourceCopied: true, checksumVerified: true,
                        transcriptProvided: !transcripts.isEmpty, noteExported: !transcripts.isEmpty)
    }
    public func noteRelativePath(for revision: TranscriptRevision) -> String? {
        guard transcripts.contains(revision) else { return nil }
        return "notes/\(revision.filename(recordingID: id))"
    }
}

public struct ArchiveReceipt: Sendable {
    public let recording: ArchivedRecording
    public let audioURL: URL
    public let reusedExistingContent: Bool
    /// The receipt verifies the archived copy at this time; listings do not rehash every file.
    public let verifiedAt: Date
    public var evidence: ArchiveEvidence { recording.evidence }
}

public struct NoteReceipt: Sendable {
    public let recording: ArchivedRecording
    public let revision: TranscriptRevision
    public let noteURL: URL
    public let reusedExistingRevision: Bool
    public var evidence: ArchiveEvidence { recording.evidence }
}

public struct RecoveryReport: Sendable, Equatable {
    public let recoveredTransactions: Int
    /// Unjournaled files are preserved, never guessed safe to delete.
    public let retainedUnjournaledFiles: Int
}

public enum ArchiveError: Error, Equatable, Sendable {
    case invalidLimits
    case invalidFileURL
    case targetDirectoryRequired
    case unsupportedFileType
    case emptySource
    case fileSizeLimitExceeded
    case sourceChangedDuringCopy
    case invalidTitle
    case invalidTranscript
    case transcriptSizeLimitExceeded
    case recordingLimitExceeded
    case revisionLimitExceeded
    case manifestSizeLimitExceeded
    case invalidManifest
    case invalidJournal
    case archiveBusy
    case archiveLocationChanged
    case recordingNotFound
    case archivedContentChanged
    case destinationConflict
    case missingRecoveryData
    case io(operation: String, code: Int32)
}

struct Manifest: Codable {
    var version = 1
    var recordings: [ArchivedRecording] = []
}

enum Mutation: Codable {
    case imported(ArchivedRecording)
    case transcript(recordingID: UUID, revision: TranscriptRevision)
}

struct Journal: Codable {
    var version = 1
    let transactionID: UUID
    let mutation: Mutation
}

let supportedExtensions: Set<String> = ["opus", "ogg", "wav", "mp3", "m4a", "aac", "flac", "caf", "bin"]

func validatedTitle(_ value: String) throws -> String {
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.isEmpty, result.utf8.count <= 256,
          !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        throw ArchiveError.invalidTitle
    }
    return result
}

func normalizedTranscript(_ value: String, limit: Int) throws -> String {
    guard value.utf8.count <= limit else { throw ArchiveError.transcriptSizeLimitExceeded }
    let result = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !result.unicodeScalars.contains(where: {
              CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
          }) else { throw ArchiveError.invalidTranscript }
    return result
}

func safeStem(_ title: String) -> String {
    var result = ""
    for scalar in title.unicodeScalars {
        let piece = CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        if result.utf8.count + piece.utf8.count > 48 { break }
        if piece != "-" || !result.hasSuffix("-") { result += piece }
    }
    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "recording" : trimmed
}
