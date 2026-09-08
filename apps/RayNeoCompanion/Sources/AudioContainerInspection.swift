import Foundation
import Combine
import CryptoKit
import Darwin
import os
import RayNeoArchive
import RayNeoAudioContainer

struct AudioInspectionIdentity: Equatable, Sendable {
    let recordingID: UUID
    let sha256: String
    let byteCount: Int64
    init(_ recording: ArchivedRecording) {
        recordingID = recording.id; sha256 = recording.sha256; byteCount = recording.byteCount
    }
    init(recordingID: UUID, sha256: String, byteCount: Int64) {
        self.recordingID = recordingID; self.sha256 = sha256; self.byteCount = byteCount
    }
}

struct AudioInspectionSource: Sendable {
    let identity: AudioInspectionIdentity
    let url: URL
}

enum AudioContainerOutcome: Equatable, Sendable {
    case supported(OggOpusStructureReport)
    case unsupported(String)
    case invalid(String)
    case limited(String)
    var title: String {
        switch self {
        case .supported: return "声明子集的结构检查通过"
        case .unsupported: return "当前检查器不支持"
        case .invalid: return "发现容器结构错误"
        case .limited: return "超出本次检查预算"
        }
    }
}

struct AudioContainerCheckResult: Equatable, Sendable {
    let identity: AudioInspectionIdentity
    let checkedAt: Date
    let outcome: AudioContainerOutcome
    let peakParserPageBytes: Int
}

struct AudioContainerProgress: Equatable, Sendable {
    let bytesRead: Int64
    let totalBytes: Int64
    var fraction: Double { totalBytes > 0 ? min(1, max(0, Double(bytesRead) / Double(totalBytes))) : 0 }
}

enum AudioContainerHostError: Error, LocalizedError, Sendable, Equatable {
    case tooLarge, fileChanged, unreadable, sourceMismatch
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "本次检查最多读取 64 MiB；没有自动提高预算，也不因此判断文件损坏。"
        case .fileChanged: return "归档文件在检查期间发生变化，旧结果已失效；请先重新校验归档。"
        case .unreadable: return "无法读取稳定的本机普通文件，未给出结构结论。"
        case .sourceMismatch: return "文件与当前归档 ID、SHA-256 或长度不一致，未继续检查。"
        }
    }
}

private struct AudioFileSignature: Equatable {
    let device: dev_t
    let inode: ino_t
    let bytes: off_t
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    init(_ value: stat) throws {
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink > 0 else { throw AudioContainerHostError.unreadable }
        device = value.st_dev; inode = value.st_ino; bytes = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
    }
}

enum AudioContainerFileInspector {
    static let maximumInputBytes = 64 * 1_024 * 1_024
    static let chunkBytes = 65_536
    typealias ProgressHandler = @Sendable (AudioContainerProgress) async -> Void

    /// Only called with the archive adapter's verified local URL. No write, decode, ASR or upload.
    static func inspect(_ source: AudioInspectionSource, progress: ProgressHandler) async throws -> AudioContainerCheckResult {
        try Task.checkCancellation()
        guard source.identity.byteCount <= maximumInputBytes else { throw AudioContainerHostError.tooLarge }
        let descriptor = source.url.withUnsafeFileSystemRepresentation { path in
            // Nonblocking open prevents a swapped FIFO/device from trapping the worker before fstat.
            path.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw AudioContainerHostError.unreadable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw AudioContainerHostError.unreadable }
        let before = try AudioFileSignature(metadata)
        guard before.bytes == source.identity.byteCount, before.bytes > 0 else { throw AudioContainerHostError.sourceMismatch }

        var inspector = try OggOpusInspector(limits: InspectionLimits())
        var outcome: AudioContainerOutcome?
        var hash = SHA256()
        var total: Int64 = 0
        var lastProgressTime = ProcessInfo.processInfo.systemUptime
        var lastProgressBytes: Int64 = 0
        await progress(.init(bytesRead: 0, totalBytes: before.bytes))
        while let chunk = try file.read(upToCount: chunkBytes), !chunk.isEmpty {
            try Task.checkCancellation()
            guard total <= Int64(maximumInputBytes - chunk.count), total + Int64(chunk.count) <= before.bytes else {
                throw AudioContainerHostError.fileChanged
            }
            if total == 0, chunk.count >= 4, !chunk.prefix(4).elementsEqual("OggS".utf8) {
                outcome = .unsupported("未识别为 Ogg 容器；这不表示其他音频格式已经损坏。")
            }
            total += Int64(chunk.count)
            hash.update(data: chunk)
            if outcome == nil {
                do { try inspector.push(chunk) }
                catch let error as OggInspectionError { outcome = mapped(error) }
            }
            // Awaiting the consumer gives backpressure; no Task is spawned for progress updates.
            let now = ProcessInfo.processInfo.systemUptime
            if total - lastProgressBytes >= 1_024 * 1_024 || now - lastProgressTime >= 0.15 {
                await progress(.init(bytesRead: total, totalBytes: before.bytes))
                lastProgressBytes = total; lastProgressTime = now
            }
        }
        try Task.checkCancellation()
        if outcome == nil {
            do { outcome = .supported(try inspector.finish()) }
            catch let error as OggInspectionError { outcome = mapped(error) }
        }
        var afterFD = stat(), afterPath = stat()
        let pathExists = source.url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &afterPath) } ?? -1 }
        guard fstat(descriptor, &afterFD) == 0, pathExists == 0,
              try AudioFileSignature(afterFD) == before, try AudioFileSignature(afterPath) == before,
              total == before.bytes,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == source.identity.sha256 else {
            throw AudioContainerHostError.fileChanged
        }
        try Task.checkCancellation()
        await progress(.init(bytesRead: total, totalBytes: before.bytes))
        // The consumer can suspend here. Recheck after the *last* await, not just before it.
        try Task.checkCancellation()
        var finalFD = stat(), finalPath = stat()
        let finalPathExists = source.url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &finalPath) } ?? -1 }
        guard fstat(descriptor, &finalFD) == 0, finalPathExists == 0,
              try AudioFileSignature(finalFD) == before, try AudioFileSignature(finalPath) == before else {
            throw AudioContainerHostError.fileChanged
        }
        guard let outcome else { throw AudioContainerHostError.unreadable }
        return AudioContainerCheckResult(identity: source.identity, checkedAt: Date(), outcome: outcome,
                                         peakParserPageBytes: inspector.peakBufferedPageBytes)
    }

    private static func mapped(_ error: OggInspectionError) -> AudioContainerOutcome {
        switch error {
        case .unsupported(let reason): return .unsupported("声明子集未覆盖：\(reason.rawValue)。没有判定其余结构有效或文件损坏。")
        case .invalid(let reason): return .invalid("已检查结构违反约束：\(reason.rawValue)。原文件保留，未修复、未解码。")
        case .limitExceeded(let limit): return .limited("达到资源上限：\(limit.rawValue)。没有无限提高限额，也不当作文件损坏。")
        case .invalidConfiguration, .inspectorAlreadyFinished, .inspectorFailed: return .limited("检查器生命周期或配置异常，未给出通过结论。")
        }
    }
}

@MainActor
private final class AudioFileChangeMonitor {
    private let source: DispatchSourceFileSystemObject
    init(url: URL, changed: @escaping @Sendable () -> Void, closed: @escaping @Sendable () -> Void) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.open($0, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC) } ?? -1 }
        guard descriptor >= 0 else { throw AudioContainerHostError.unreadable }
        let once = OSAllocatedUnfairLock(initialState: false)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: DispatchQueue(label: "companion.audio-file-monitor"))
        source.setEventHandler {
            let shouldNotify = once.withLock { sent in
                guard !sent else { return false }; sent = true; return true
            }
            if shouldNotify { changed() }
        }
        source.setCancelHandler { Darwin.close(descriptor); closed() }
        source.resume()
    }
    func cancel() { source.cancel() }
    deinit { source.cancel() }
}

@MainActor
final class AudioContainerInspectionController: ObservableObject {
    enum Phase: Equatable { case idle, preparing, reading, cancelling, completed, cancelled, stale, failed, limited }
    typealias SourceProvider = @Sendable (AudioInspectionIdentity) async throws -> AudioInspectionSource
    typealias Work = @Sendable (AudioInspectionSource, @escaping AudioContainerFileInspector.ProgressHandler) async throws -> AudioContainerCheckResult
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: AudioContainerProgress?
    @Published private(set) var result: AudioContainerCheckResult?
    @Published private(set) var message: String?
    @Published private(set) var canStart = true
    @Published private(set) var identity: AudioInspectionIdentity?
    /// Reports only errors; the archive owner classifies integrity failures, never container outcomes.
    var onIntegrityFailure: ((AudioInspectionIdentity, Error) -> Void)?
    private struct Lease { let id: UUID; var workerFinished = false; var monitorClosed = true }
    private var lease: Lease?
    private var acceptedGeneration: UUID?
    private var worker: Task<Void, Never>?
    private var monitor: AudioFileChangeMonitor?
    private let sourceProvider: SourceProvider
    private let work: Work

    init(sourceProvider: @escaping SourceProvider,
         work: @escaping Work = { source, progress in try await AudioContainerFileInspector.inspect(source, progress: progress) }) {
        self.sourceProvider = sourceProvider; self.work = work
    }

    /// One global worker/monitor lease, no queue. Returns false while any old resources are retiring.
    @discardableResult func start(_ identity: AudioInspectionIdentity) -> Bool {
        guard canStart, lease == nil else { return false }
        self.identity = identity; result = nil; progress = nil; message = nil
        guard identity.byteCount <= AudioContainerFileInspector.maximumInputBytes else {
            phase = .limited; message = AudioContainerHostError.tooLarge.localizedDescription; return false
        }
        let generation = UUID()
        lease = Lease(id: generation); acceptedGeneration = generation; canStart = false; phase = .preparing
        let sourceProvider = sourceProvider, work = work
        worker = Task { [weak self] in
            do {
                let source = try await sourceProvider(identity)
                try Task.checkCancellation()
                guard source.identity == identity else { throw AudioContainerHostError.sourceMismatch }
                guard try self?.installMonitor(source.url, generation: generation) == true else { throw CancellationError() }
                let inspection = Task.detached(priority: .utility) { [weak self] in
                    try await work(source) { [weak self] value in await self?.receive(value, generation: generation) }
                }
                let value = try await withTaskCancellationHandler(operation: { try await inspection.value }, onCancel: { inspection.cancel() })
                self?.finish(generation, value: value, error: nil)
            } catch { self?.finish(generation, value: nil, error: error) }
        }
        return true
    }

    func cancel() { invalidate(to: .cancelled, message: "已请求取消；旧任务与文件监视器退出前不能开始新的检查。") }
    func clear() { invalidate(to: .idle, message: nil) }
    func leave(recordingID: UUID) {
        guard identity?.recordingID == recordingID else { return }
        invalidate(to: .idle, message: nil)
    }
    func reconcile(recordings: [ArchivedRecording], issues: [UUID: String]) {
        guard let identity else { return }
        guard let current = recordings.first(where: { $0.id == identity.recordingID }), AudioInspectionIdentity(current) == identity,
              issues[identity.recordingID] == nil else {
            invalidate(to: .stale, message: "归档记录或校验状态变化；此前容器检查结果已失效。")
            return
        }
    }

    private func installMonitor(_ url: URL, generation: UUID) throws -> Bool {
        guard acceptedGeneration == generation, lease?.id == generation else { return false }
            monitor = try AudioFileChangeMonitor(url: url, changed: { [weak self] in
                Task { @MainActor [weak self] in
                    guard self?.lease?.id == generation else { return }
                    if let self, let identity = self.identity {
                        self.onIntegrityFailure?(identity, AudioContainerHostError.fileChanged)
                    }
                    self?.invalidate(to: .stale, message: "检测到本机归档文件变化，旧结构结果已失效。请重新校验归档。")
                }
            }, closed: { [weak self] in
                Task { @MainActor [weak self] in self?.monitorDidClose(generation) }
            })
            lease?.monitorClosed = false
            return true
    }
    private func receive(_ value: AudioContainerProgress, generation: UUID) {
        guard acceptedGeneration == generation, lease?.id == generation else { return }
        guard value.totalBytes == identity?.byteCount, value.bytesRead >= (progress?.bytesRead ?? 0), value.bytesRead <= value.totalBytes else { return }
        progress = value; phase = .reading
    }
    private func finish(_ generation: UUID, value: AudioContainerCheckResult?, error: Error?) {
        guard lease?.id == generation else { return }
        lease?.workerFinished = true; worker = nil
        if let error, let identity { onIntegrityFailure?(identity, error) }
        if acceptedGeneration == generation {
            if let value, value.identity == identity {
                result = value; phase = .completed; message = nil
                // Keep exactly one watcher while this historical result is visible.
            } else {
                result = nil
                if error is CancellationError { phase = .cancelled }
                else if let error = error as? AudioContainerHostError, case .tooLarge = error { phase = .limited }
                else { phase = .failed }
                message = error?.localizedDescription ?? "检查未完成，没有通过结论。"
                monitor?.cancel()
            }
        } else { monitor?.cancel() }
        releaseIfFinished()
    }
    private func invalidate(to phase: Phase, message: String?) {
        acceptedGeneration = nil; result = nil; progress = nil; self.phase = phase; self.message = message
        worker?.cancel(); monitor?.cancel()
        releaseIfFinished()
    }
    private func monitorDidClose(_ generation: UUID) {
        guard lease?.id == generation else { return }
        lease?.monitorClosed = true; monitor = nil
        releaseIfFinished()
    }
    private func releaseIfFinished() {
        guard let lease, lease.workerFinished, lease.monitorClosed else { return }
        self.lease = nil; worker = nil; monitor = nil; acceptedGeneration = nil; canStart = true
    }
}
