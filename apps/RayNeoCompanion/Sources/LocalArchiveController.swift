import Foundation
import Combine
import CryptoKit
import RayNeoArchive

struct ArchiveLibrarySnapshot: Sendable {
    let recordings: [ArchivedRecording]
    let recovery: RecoveryReport
}

enum LocalArchiveError: LocalizedError {
    case busy, fixtureUnavailable, coordinationFailed, noteMissing, noteChanged
    var errorDescription: String? {
        switch self {
        case .busy: return "归档正在处理另一项操作，请稍候。"
        case .fixtureUnavailable: return "合成样本仅供隔离的 Debug 验收使用。"
        case .coordinationFailed: return "文件提供器未能提供可读取的副本，请等文件下载完成后重试。"
        case .noteMissing: return "找不到这个 Markdown 修订，未准备分享。"
        case .noteChanged: return "Markdown 文件与保存的校验记录不一致，已停止分享，没有覆盖文件。"
        }
    }
}

/// Only local file work. No glasses transport, microphone, ASR, network or upload implementation.
actor LocalArchiveRepository {
    private let explicitRoot: URL?
    private let limits: ArchiveLimits
    private var archive: ArchiveStore?
    private var portableExportActive = false

    init(rootDirectory: URL?, limits: ArchiveLimits = ArchiveLimits()) {
        explicitRoot = rootDirectory
        self.limits = limits
    }

    private func open() throws -> ArchiveStore {
        if let archive { return archive }
        let root: URL
        if let explicitRoot { root = explicitRoot }
        else {
            root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("VerifiedRecordingArchiveV1", isDirectory: true)
        }
        // Never point this at the old ImportedRecordings directory or a File Provider/NAS destination.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let created = try ArchiveStore(rootDirectory: root, limits: limits)
        archive = created
        return created
    }

    func load() async throws -> ArchiveLibrarySnapshot {
        let store = try open()
        let recovery = try await store.recover()
        let rows = try await store.listRecordings().sorted { $0.importedAt > $1.importedAt }
        return ArchiveLibrarySnapshot(recordings: rows, recovery: recovery)
    }

    func importFile(_ source: URL, title: String? = nil) async throws -> ArchiveReceipt {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let staging = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        // The coordinator accessor must remain synchronous. Materialize a bounded local copy before
        // awaiting the archive actor, keeping the source's access scope open through the entire call.
        var coordinationError: NSError?
        var copied: Result<LocalRecording, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readableURL in
            copied = Result {
                try RecordingFileImporter.copy(source: readableURL, to: staging, maximumBytes: Int(limits.maximumFileBytes))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copied else { throw LocalArchiveError.coordinationFailed }
        let localCopy = try copied.get()
        let archive = try open()
        return try await archive.importFile(at: staging.appendingPathComponent(localCopy.storedFilename),
                                            title: Self.defaultTitle(title ?? source.deletingPathExtension().lastPathComponent))
    }

    func saveTranscript(recordingID: UUID, text: String, title: String) async throws -> NoteReceipt {
        try await open().exportTranscript(for: recordingID, text: text, title: title)
    }

    func verify(_ id: UUID) async throws -> ArchiveReceipt {
        let receipt = try await open().verifyRecording(id)
        for revision in receipt.recording.transcripts {
            _ = try verifiedNoteURL(receipt: receipt, revisionID: revision.id)
        }
        return receipt
    }

    func sourceForContainerInspection(_ identity: AudioInspectionIdentity) async throws -> AudioInspectionSource {
        let receipt = try await open().verifyRecording(identity.recordingID)
        guard AudioInspectionIdentity(receipt.recording) == identity else { throw AudioContainerHostError.sourceMismatch }
        return AudioInspectionSource(identity: identity, url: receipt.audioURL)
    }

    func prepareNoteShare(recordingID: UUID, revisionID: UUID) async throws -> URL {
        let receipt = try await open().verifyRecording(recordingID)
        return try verifiedNoteURL(receipt: receipt, revisionID: revisionID)
    }

    func preparePortableShare(recordingID: UUID, revisions: SnapshotRevisionSelection) async throws -> URL {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        portableExportActive = true
        defer { portableExportActive = false }
        let store = try open()
        let receipt = try await store.verifyRecording(recordingID)
        let exports = receipt.audioURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PortableArchiveExportsV1",isDirectory:true)
        try FileManager.default.createDirectory(at:exports,withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        guard try exports.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw PortableArchiveError.invalidSnapshot }
        guard try FileManager.default.contentsOfDirectory(atPath:exports.path).count < 20 else { throw PortableArchiveError.capacity }
        let parent = exports.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:false,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        let snapshot = try await store.exportSnapshot(recordingID:recordingID,revisions:revisions,toParentDirectory:parent)
        return try PortableArchiveZIP.create(snapshot)
    }

    private func exportCopies() -> PortableExportCopies {
        PortableExportCopies(parent: explicitRoot?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
    func exportCopyCatalog() throws -> PortableExportCatalog {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        return try exportCopies().catalog()
    }
    func moveExportCopy(_ id: UUID, toTrash: Bool) throws {
        guard !portableExportActive else { throw LocalArchiveError.busy }
        try exportCopies().move(id, toTrash: toTrash)
    }

    private func verifiedNoteURL(receipt: ArchiveReceipt, revisionID: UUID) throws -> URL {
        try Task.checkCancellation()
        guard let revision = receipt.recording.transcripts.first(where: { $0.id == revisionID }),
              let relative = receipt.recording.noteRelativePath(for: revision) else { throw LocalArchiveError.noteMissing }
        // The library has checked the pinned root location before providing this audio URL.
        let root = receipt.audioURL.deletingLastPathComponent().deletingLastPathComponent()
        let noteURL = root.appendingPathComponent(relative)
        let values = try noteURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == Int(revision.byteCount), revision.byteCount <= Int64(limits.maximumTranscriptBytes) * 8 + 8_192 else {
            throw LocalArchiveError.noteChanged
        }
        let input = try FileHandle(forReadingFrom: noteURL)
        defer { try? input.close() }
        var digest = SHA256()
        var count: Int64 = 0
        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            count += Int64(chunk.count)
            guard count <= revision.byteCount else { throw LocalArchiveError.noteChanged }
            digest.update(data: chunk)
        }
        guard count == revision.byteCount,
              digest.finalize().map({ String(format: "%02x", $0) }).joined() == revision.noteSHA256 else { throw LocalArchiveError.noteChanged }
        return noteURL
    }

    #if DEBUG
    func importContainerFixture(_ fixture: ContainerSyntheticFixture) async throws -> ArchiveReceipt {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic-container-\(fixture.rawValue).ogg")
        try fixture.bytes().write(to: source, options: .withoutOverwriting)
        return try await importFile(source, title: fixture.title)
    }

    func importSyntheticFixture() async throws -> ArchiveReceipt {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Simulator-QA-not-valid-audio.wav")
        // Deliberately not decodable audio: the test proves copy/checksum, not recording or ASR.
        try Data(String(repeating: "SYNTHETIC BYTES; NOT VALID AUDIO.\n", count: 31).utf8).write(to: source, options: .withoutOverwriting)
        return try await importFile(source, title: "合成验收样本 · 非有效音频")
    }
    #endif

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("companion-archive-incoming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }

    static func defaultTitle(_ value: String) -> String {
        let sanitized = value.components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in sanitized {
            guard result.utf8.count + String(character).utf8.count <= 256 else { break }
            result.append(character)
        }
        return result.isEmpty ? "本地录音" : result
    }
}

@MainActor
final class LocalArchiveController: ObservableObject {
    @Published private(set) var recordings: [ArchivedRecording] = [] {
        didSet { audioInspection.reconcile(recordings: recordings, issues: verificationIssues) }
    }
    @Published private(set) var isBusy = false
    @Published private(set) var activity = ""
    @Published private(set) var exportCopies = PortableExportCatalog()
    @Published private(set) var statusMessage: String?
    @Published private(set) var latestVerifications: [UUID: Date] = [:]
    @Published private(set) var verificationIssues: [UUID: String] = [:] {
        didSet { audioInspection.reconcile(recordings: recordings, issues: verificationIssues) }
    }
    let audioInspection: AudioContainerInspectionController
    @Published var errorMessage: String?
    let allowsTestFixture: Bool
    private let repository: LocalArchiveRepository

    init(rootDirectory: URL?, allowsTestFixture: Bool = false, limits: ArchiveLimits = ArchiveLimits()) {
        let repository = LocalArchiveRepository(rootDirectory: rootDirectory, limits: limits)
        self.repository = repository
        audioInspection = AudioContainerInspectionController { identity in try await repository.sourceForContainerInspection(identity) }
        self.allowsTestFixture = allowsTestFixture
        audioInspection.onIntegrityFailure = { [weak self] identity, error in
            self?.recordContainerIntegrityFailure(identity, error: error)
        }
    }

    func load() async {
        guard !isBusy else { return }
        await perform("读取本地归档…") {
            let snapshot = try await self.repository.load()
            self.recordings = snapshot.recordings
            if snapshot.recovery.recoveredTransactions > 0 || snapshot.recovery.retainedUnjournaledFiles > 0 {
                self.statusMessage = "已恢复 \(snapshot.recovery.recoveredTransactions) 项事务；保留 \(snapshot.recovery.retainedUnjournaledFiles) 个未登记临时文件，未自动删除。"
            }
        }
    }

    func loadExportCopies() async {
        guard !isBusy else { return }
        await perform("读取导出副本…") { self.exportCopies = try await self.repository.exportCopyCatalog() }
    }
    func moveExportCopy(_ id: UUID, toTrash: Bool) async {
        guard !isBusy else { return }
        await perform("整理导出副本…") {
            try await self.repository.moveExportCopy(id, toTrash: toTrash)
            self.exportCopies = try await self.repository.exportCopyCatalog()
            self.statusMessage = toTrash ? "已移入本机暂存箱，可恢复；未删除文件，不释放磁盘空间。" : "已恢复导出副本，未覆盖其他文件。"
        }
    }

    @discardableResult func importFile(_ source: URL, title: String? = nil) async -> Bool {
        var imported = false
        await perform("复制并校验本地文件…") {
            self.accept(try await self.repository.importFile(source, title: title))
            self.recordings = try await self.repository.load().recordings
            imported = true
        }
        return imported
    }

    func verify(_ id: UUID) async -> URL? {
        var output: URL?
        await perform("重新校验音频与已登记笔记…", recordingID: id) {
            self.latestVerifications.removeValue(forKey: id)
            let receipt = try await self.repository.verify(id)
            self.latestVerifications[id] = receipt.verifiedAt
            self.verificationIssues.removeValue(forKey: id)
            self.statusMessage = "音频与已登记笔记的字节复核通过；没有解码、识别或上传。"
            output = receipt.audioURL
        }
        return output
    }

    func saveTranscript(recordingID: UUID, text: String, title: String) async -> NoteReceipt? {
        var output: NoteReceipt?
        await perform("保存本地 Markdown 修订…", recordingID: recordingID) {
            self.latestVerifications.removeValue(forKey: recordingID)
            let receipt = try await self.repository.saveTranscript(recordingID: recordingID, text: text, title: title)
            self.recordings = try await self.repository.load().recordings
            self.statusMessage = receipt.reusedExistingRevision
                ? "相同文字与标题已存在，复用第 \(receipt.revision.number) 版；没有覆盖旧稿。"
                : "第 \(receipt.revision.number) 版 Markdown 已保存到本机；没有上传。"
            output = receipt
        }
        return output
    }

    func prepareNoteShare(recordingID: UUID, revisionID: UUID) async -> URL? {
        var output: URL?
        await perform("核对 Markdown 文件…", recordingID: recordingID) {
            self.latestVerifications.removeValue(forKey: recordingID)
            output = try await self.repository.prepareNoteShare(recordingID: recordingID, revisionID: revisionID)
        }
        return output
    }

    func preparePortableShare(recordingID: UUID, revisions: SnapshotRevisionSelection) async -> URL? {
        var output: URL?
        await perform("制作独立快照并校验 ZIP…",recordingID:recordingID) {
            self.latestVerifications.removeValue(forKey:recordingID)
            output = try await self.repository.preparePortableShare(recordingID:recordingID,revisions:revisions)
            self.statusMessage = "便携 ZIP 已逐项解包校验；音频与所选修订在同一包内。未上传，未验证 Obsidian 索引。"
        }
        return output
    }

    func importTestFixture() async {
        #if DEBUG
        guard allowsTestFixture else { errorMessage = LocalArchiveError.fixtureUnavailable.localizedDescription; return }
        await perform("导入明确标记的合成样本…") {
            self.accept(try await self.repository.importSyntheticFixture())
            self.recordings = try await self.repository.load().recordings
        }
        #endif
    }

    #if DEBUG
    func importContainerFixture(_ fixture: ContainerSyntheticFixture) async {
        guard allowsTestFixture else { errorMessage = LocalArchiveError.fixtureUnavailable.localizedDescription; return }
        await perform("创建并导入合成容器字节…") {
            self.accept(try await self.repository.importContainerFixture(fixture))
            self.recordings = try await self.repository.load().recordings
        }
    }
    #endif

    private func accept(_ receipt: ArchiveReceipt) {
        latestVerifications[receipt.recording.id] = receipt.verifiedAt
        statusMessage = receipt.reusedExistingContent ? "检测到相同字节，已复用原归档；来源与原条目未修改。" : "本机副本已复制并校验；未解码、未识别、未上传。"
    }

    private func recordContainerIntegrityFailure(_ identity: AudioInspectionIdentity, error: Error) {
        guard let current = recordings.first(where: { $0.id == identity.recordingID }),
              AudioInspectionIdentity(current) == identity, Self.isIntegrityFailure(error) else { return }
        latestVerifications.removeValue(forKey: identity.recordingID)
        verificationIssues[identity.recordingID] = Self.describe(error)
    }

    private func perform(_ activity: String, recordingID: UUID? = nil, operation: () async throws -> Void) async {
        guard !isBusy else { errorMessage = LocalArchiveError.busy.localizedDescription; return }
        isBusy = true; self.activity = activity; errorMessage = nil; statusMessage = nil
        defer { isBusy = false; self.activity = "" }
        do { try await operation() }
        catch {
            if let recordingID, Self.isIntegrityFailure(error) {
                verificationIssues[recordingID] = Self.describe(error)
                latestVerifications.removeValue(forKey: recordingID)
            }
            errorMessage = Self.describe(error) + "\n本 App 未修改或删除来源文件。已提交的恢复日志可能在下次刷新时完成，不承诺失败即回滚。"
        }
    }

    private static func isIntegrityFailure(_ error: Error) -> Bool {
        if let value = error as? AudioContainerHostError {
            switch value {
            case .fileChanged, .sourceMismatch, .unreadable: return true
            case .tooLarge: return false
            }
        }
        if let value = error as? ArchiveError {
            switch value {
            case .archivedContentChanged, .destinationConflict, .archiveLocationChanged, .missingRecoveryData,
                 .invalidManifest, .invalidJournal, .recordingNotFound, .io: return true
            default: return false
            }
        }
        if let value = error as? LocalArchiveError {
            switch value {
            case .noteChanged, .noteMissing: return true
            default: return false
            }
        }
        return (error as NSError).domain == NSCocoaErrorDomain
    }

    static func describe(_ error: Error) -> String {
        guard let archiveError = error as? ArchiveError else { return error.localizedDescription }
        switch archiveError {
        case .emptySource: return "所选文件为空。"
        case .fileSizeLimitExceeded: return "音频超过本地归档大小限制（默认 512 MiB）。"
        case .unsupportedFileType, .invalidFileURL: return "请选择已完成写入的普通本地文件。"
        case .sourceChangedDuringCopy: return "来源在复制时发生变化，请在录音写入结束后重试。"
        case .invalidTitle: return "标题必须是 1 至 256 UTF-8 字节的单行文本。"
        case .invalidTranscript: return "请提供非空文字，不支持除换行、制表符以外的控制字符。"
        case .transcriptSizeLimitExceeded: return "文字超过 1 MiB，请拆分整理后重试。"
        case .recordingLimitExceeded, .revisionLimitExceeded, .manifestSizeLimitExceeded: return "已达到归档容量或修订数量限制；原资料仍保留。"
        case .archivedContentChanged, .destinationConflict: return "已存文件与归档记录不一致或存在冲突，操作已停止，没有覆盖原文件。"
        case .archiveBusy: return "归档目录正被另一项操作占用，请稍后刷新。"
        case .archiveLocationChanged: return "归档目录发生移动或替换，已停止操作。请恢复原目录后重试。"
        case .recordingNotFound: return "录音已不在当前归档记录中，请刷新。"
        case .invalidManifest, .invalidJournal, .missingRecoveryData: return "归档记录或恢复数据需要检查，已保留现有文件，没有自动修复覆盖。"
        case .invalidLimits, .targetDirectoryRequired: return "本地归档目录或容量设置无效。"
        case .io: return "本机文件操作失败，请检查可用空间、设备解锁状态和文件权限。"
        }
    }
}
