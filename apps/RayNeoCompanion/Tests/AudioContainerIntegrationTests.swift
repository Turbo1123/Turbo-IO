import XCTest
import CryptoKit
import Darwin
import RayNeoArchive
@testable import RayNeoCompanion

private actor InspectionGate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private actor InspectionProgressLog {
    var values: [AudioContainerProgress] = []
    func append(_ value: AudioContainerProgress) { values.append(value) }
}
private actor InspectionCounter {
    var count = 0
    func increment() { count += 1 }
}

final class AudioContainerIntegrationTests: XCTestCase {
    func testSupportedSyntheticStructureIsBoundToEntireFileAndNoSourceMutation() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = ContainerSyntheticFixture.supported.bytes()
        let source = try source(bytes, in: root)
        let progress = InspectionProgressLog()
        let before = Date()
        let result = try await AudioContainerFileInspector.inspect(source) { await progress.append($0) }
        guard case .supported(let report) = result.outcome else { return XCTFail("Expected declared structure subset") }
        XCTAssertEqual(report.pageCount, 3); XCTAssertEqual(report.crcCheckedPages, 3)
        XCTAssertEqual(report.audioPacketCount, 1); XCTAssertEqual(report.packetCountIncludingHeaders, 3)
        XCTAssertEqual(report.finalPCMPosition, 648)
        XCTAssertEqual(result.identity, source.identity)
        XCTAssertGreaterThanOrEqual(result.checkedAt, before)
        XCTAssertLessThanOrEqual(result.peakParserPageBytes, 65_307)
        XCTAssertEqual(try Data(contentsOf: source.url), bytes)
        let values = await progress.values
        XCTAssertEqual(values.first?.bytesRead, 0); XCTAssertEqual(values.last?.bytesRead, Int64(bytes.count))
    }

    func testInvalidCRCAndUnsupportedVersionRemainDifferentConclusions() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let bad = try source(ContainerSyntheticFixture.badCRC.bytes(), in: root)
        let unsupported = try source(ContainerSyntheticFixture.unsupportedVersion.bytes(), in: root)
        let badResult = try await AudioContainerFileInspector.inspect(bad) { _ in }
        let unsupportedResult = try await AudioContainerFileInspector.inspect(unsupported) { _ in }
        guard case .invalid(let reason) = badResult.outcome else { return XCTFail("CRC corruption must be invalid") }
        XCTAssertTrue(reason.contains("pageCRC"))
        guard case .unsupported(let reason) = unsupportedResult.outcome else { return XCTFail("Version must not be called damaged") }
        XCTAssertTrue(reason.contains("opusVersion"))
        XCTAssertEqual(try Data(contentsOf: bad.url), ContainerSyntheticFixture.badCRC.bytes())
    }

    func testNonOggStillHashesAllBytesWithBoundedMonotonicProgress() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0x55, count: 2 * 1_024 * 1_024 + 31)
        let source = try source(bytes, in: root)
        let log = InspectionProgressLog()
        let result = try await AudioContainerFileInspector.inspect(source) { await log.append($0) }
        guard case .unsupported = result.outcome else { return XCTFail("Unknown container is unsupported") }
        let values = await log.values
        XCTAssertEqual(values.last?.bytesRead, Int64(bytes.count))
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0.0.bytesRead <= $0.1.bytesRead })
        XCTAssertTrue(values.allSatisfy { $0.bytesRead <= $0.totalBytes && $0.fraction <= 1 })
        XCTAssertLessThanOrEqual(values.count, 35) // Each callback needs a new 64 KiB chunk at minimum.
        XCTAssertEqual(result.peakParserPageBytes, 0)
        XCTAssertEqual(result.identity.sha256, digest(bytes))
    }

    func testWrongHashAndMidReadChangesCannotPublishPartialConclusion() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let wrong = AudioInspectionSource(identity: .init(recordingID: original.identity.recordingID,
            sha256: String(repeating: "0", count: 64), byteCount: original.identity.byteCount), url: original.url)
        do { _ = try await AudioContainerFileInspector.inspect(wrong) { _ in }; XCTFail("Must reject wrong hash") }
        catch { XCTAssertEqual(error as? AudioContainerHostError, .fileChanged) }
        let changed = Data(repeating: 0x41, count: Int(original.identity.byteCount))
        do {
            _ = try await AudioContainerFileInspector.inspect(original) { value in
                if value.bytesRead == 0 { try? changed.write(to: original.url) }
            }
            XCTFail("Must reject changed source")
        } catch { XCTAssertEqual(error as? AudioContainerHostError, .fileChanged) }
        XCTAssertEqual(try Data(contentsOf: original.url), changed)
    }

    func testCancellationStopsReaderWithoutChangingSource() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let gate = InspectionGate()
        let task = Task { try await AudioContainerFileInspector.inspect(source) { value in
            if value.bytesRead == 0 { await gate.hold() }
        } }
        for _ in 0..<500 { if await gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let entered = await gate.entered; XCTAssertTrue(entered)
        task.cancel(); await gate.release()
        do { _ = try await task.value; XCTFail("Cancellation must not produce a result") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source.url), ContainerSyntheticFixture.supported.bytes())
    }

    func testFinalProgressCancellationCannotReturnResult() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let task = Task {
            try await AudioContainerFileInspector.inspect(source) { value in
                if value.bytesRead == value.totalBytes { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; XCTFail("Final callback cancellation must be observed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source.url), ContainerSyntheticFixture.supported.bytes())
    }

    func testFinalProgressFileMutationCannotReturnOldSupportedResult() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        do {
            _ = try await AudioContainerFileInspector.inspect(source) { value in
                if value.bytesRead == value.totalBytes {
                    // Same inode and length; ctime/mtime must be checked again after this suspension.
                    if let output = try? FileHandle(forWritingTo: source.url) {
                        try? output.write(contentsOf: Data([0x01])); try? output.synchronize(); try? output.close()
                    }
                }
            }
            XCTFail("Late source mutation must invalidate the conclusion")
        } catch { XCTAssertEqual(error as? AudioContainerHostError, .fileChanged) }
        XCTAssertEqual(try Data(contentsOf: source.url).first, 0x01)
    }

    func testFIFOIsRejectedWithoutWaitingForPeerOrCancellation() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("synthetic-only.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let source = AudioInspectionSource(identity: .init(recordingID: UUID(), sha256: "unused", byteCount: 1), url: fifo)
        let finished = InspectionCounter()
        let task = Task.detached {
            do { _ = try await AudioContainerFileInspector.inspect(source) { _ in }; await finished.increment(); return false }
            catch { await finished.increment(); return error as? AudioContainerHostError == .unreadable }
        }
        for _ in 0..<100 { if await finished.count > 0 { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let countBeforePeer = await finished.count
        if countBeforePeer == 0 {
            // Regression escape hatch only: release our own FIFO so a broken open cannot hang XCTest.
            let peer = Darwin.open(fifo.path, O_RDWR | O_NONBLOCK | O_NOFOLLOW)
            if peer >= 0 { Darwin.close(peer) }
        }
        let rejected = await task.value
        XCTAssertEqual(countBeforePeer, 1, "Reader must not require a FIFO peer to leave open()")
        XCTAssertTrue(rejected)
    }

    @MainActor func testBudgetRejectsBeforeSourceProviderAndDoesNotClaimDamage() async throws {
        let calls = InspectionCounter()
        let controller = AudioContainerInspectionController { identity in
            await calls.increment(); throw AudioContainerHostError.unreadable
        }
        let tooLarge = AudioInspectionIdentity(recordingID: UUID(), sha256: "unused", byteCount: 64 * 1_024 * 1_024 + 1)
        XCTAssertFalse(controller.start(tooLarge)); XCTAssertTrue(controller.canStart)
        XCTAssertEqual(controller.phase, .limited); XCTAssertNil(controller.result)
        let count = await calls.count; XCTAssertEqual(count, 0)
    }

    @MainActor func testCancelledUncooperativeWorkerRetainsLeaseAndDropsLateProgressAndResult() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let gate = InspectionGate()
        let controller = AudioContainerInspectionController(sourceProvider: { _ in source }, work: { source, progress in
            await gate.hold() // Intentionally ignores cancellation until released by the test.
            await progress(.init(bytesRead: source.identity.byteCount, totalBytes: source.identity.byteCount))
            return .init(identity: source.identity, checkedAt: Date(), outcome: .unsupported("synthetic delayed work"), peakParserPageBytes: 0)
        })
        XCTAssertTrue(controller.start(source.identity))
        for _ in 0..<500 { if await gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let entered = await gate.entered; XCTAssertTrue(entered)
        XCTAssertFalse(controller.start(source.identity))
        controller.cancel()
        XCTAssertFalse(controller.canStart); XCTAssertFalse(controller.start(source.identity))
        await gate.release()
        await eventually { controller.canStart }
        XCTAssertEqual(controller.phase, .cancelled); XCTAssertNil(controller.result); XCTAssertNil(controller.progress)
    }

    @MainActor func testCancelDuringSourceVerificationDoesNotOpenASecondWorker() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let gate = InspectionGate(), calls = InspectionCounter()
        let controller = AudioContainerInspectionController(sourceProvider: { _ in await gate.hold(); return source }, work: { _, _ in
            await calls.increment(); throw AudioContainerHostError.unreadable
        })
        XCTAssertTrue(controller.start(source.identity))
        for _ in 0..<500 { if await gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        controller.leave(recordingID: source.identity.recordingID)
        XCTAssertFalse(controller.start(source.identity)); XCTAssertNil(controller.result)
        await gate.release(); await eventually { controller.canStart }
        let count = await calls.count; XCTAssertEqual(count, 0)
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor func testCompletedFileMutationInvalidatesGreenAndReleasesWatcher() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let controller = AudioContainerInspectionController { _ in source }
        XCTAssertTrue(controller.start(source.identity))
        await eventually { controller.result != nil }
        XCTAssertEqual(controller.phase, .completed); XCTAssertFalse(controller.canStart)
        try Data(repeating: 0, count: Int(source.identity.byteCount)).write(to: source.url)
        await eventually { controller.phase == .stale && controller.canStart }
        XCTAssertNil(controller.result); XCTAssertNil(controller.progress)
    }

    @MainActor func testLeavingSuccessfulCheckClearsResultAndReentryDoesNotAutostart() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let calls = InspectionCounter()
        let controller = AudioContainerInspectionController { _ in await calls.increment(); return source }
        XCTAssertNil(controller.result)
        let countBefore = await calls.count; XCTAssertEqual(countBefore, 0)
        XCTAssertTrue(controller.start(source.identity)); await eventually { controller.result != nil }
        controller.leave(recordingID: source.identity.recordingID)
        await eventually { controller.canStart }
        XCTAssertEqual(controller.phase, .idle); XCTAssertNil(controller.result)
        let countAfter = await calls.count; XCTAssertEqual(countAfter, 1)
    }

    @MainActor func testArchiveIssueInvalidatesResultAndCannotBeClearedBySimpleRefresh() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("archive"))
        let receipt = try await repository.importFile(source.url)
        let identity = AudioInspectionIdentity(receipt.recording)
        let controller = AudioContainerInspectionController { identity in try await repository.sourceForContainerInspection(identity) }
        XCTAssertTrue(controller.start(identity)); await eventually { controller.result != nil }
        controller.reconcile(recordings: [receipt.recording], issues: [receipt.recording.id: "Synthetic integrity failure"])
        await eventually { controller.canStart }
        XCTAssertEqual(controller.phase, .stale); XCTAssertNil(controller.result)
        controller.reconcile(recordings: [receipt.recording], issues: [:])
        XCTAssertNil(controller.result); XCTAssertEqual(controller.phase, .stale)
    }

    func testRepositoryProvidesOnlyMatchingVerifiedArchiveCopy() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let repository = LocalArchiveRepository(rootDirectory: root.appendingPathComponent("archive"))
        let receipt = try await repository.importFile(original.url)
        let identity = AudioInspectionIdentity(receipt.recording)
        let local = try await repository.sourceForContainerInspection(identity)
        XCTAssertNotEqual(local.url, original.url); XCTAssertEqual(local.identity, identity)
        let mismatched = AudioInspectionIdentity(recordingID: identity.recordingID, sha256: "not-the-archive-hash", byteCount: identity.byteCount)
        do { _ = try await repository.sourceForContainerInspection(mismatched); XCTFail("Must reject mismatched identity") }
        catch { XCTAssertEqual(error as? AudioContainerHostError, .sourceMismatch) }
        try Data(repeating: 0, count: Int(identity.byteCount)).write(to: local.url)
        do { _ = try await repository.sourceForContainerInspection(identity); XCTFail("Must not inspect modified archive") }
        catch { XCTAssertTrue(error is ArchiveError) }
        XCTAssertEqual(try Data(contentsOf: original.url), ContainerSyntheticFixture.supported.bytes())
    }

    @MainActor func testContainerPreflightFailureInvalidatesArchiveFreshEvidenceAndSurvivesLoad() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try source(ContainerSyntheticFixture.supported.bytes(), in: root)
        let archive = LocalArchiveController(rootDirectory: root.appendingPathComponent("archive"))
        await archive.importFile(original.url)
        let recording = try XCTUnwrap(archive.recordings.first)
        let copy = await archive.verify(recording.id)
        let url = try XCTUnwrap(copy)
        XCTAssertNotNil(archive.latestVerifications[recording.id])
        try Data(repeating: 0x01, count: Int(recording.byteCount)).write(to: url)
        XCTAssertTrue(archive.audioInspection.start(.init(recording)))
        await eventually { archive.audioInspection.canStart }
        XCTAssertNil(archive.latestVerifications[recording.id])
        XCTAssertNotNil(archive.verificationIssues[recording.id])
        XCTAssertNil(archive.audioInspection.result)
        archive.audioInspection.leave(recordingID: recording.id)
        await archive.load(); archive.errorMessage = nil
        XCTAssertNil(archive.latestVerifications[recording.id]); XCTAssertNotNil(archive.verificationIssues[recording.id])
        XCTAssertEqual(try Data(contentsOf: original.url), ContainerSyntheticFixture.supported.bytes())
    }

    @MainActor func testContainerInvalidStructureDoesNotBecomeArchiveIntegrityFailureButFileWatchDoes() async throws {
        let root = try sandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try source(ContainerSyntheticFixture.badCRC.bytes(), in: root)
        let archive = LocalArchiveController(rootDirectory: root.appendingPathComponent("archive"))
        await archive.importFile(original.url)
        let recording = try XCTUnwrap(archive.recordings.first)
        let copy = await archive.verify(recording.id)
        let url = try XCTUnwrap(copy)
        XCTAssertTrue(archive.audioInspection.start(.init(recording)))
        await eventually { archive.audioInspection.result != nil }
        guard case .invalid = archive.audioInspection.result?.outcome else { return XCTFail("Expected structural CRC failure") }
        XCTAssertNotNil(archive.latestVerifications[recording.id]); XCTAssertNil(archive.verificationIssues[recording.id])
        try Data(repeating: 0x01, count: Int(recording.byteCount)).write(to: url)
        await eventually { archive.audioInspection.canStart }
        XCTAssertNil(archive.audioInspection.result)
        XCTAssertNil(archive.latestVerifications[recording.id]); XCTAssertNotNil(archive.verificationIssues[recording.id])
    }

    @MainActor private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 { if condition() { return }; try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for bounded test transition", file: file, line: line)
    }
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("container-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func source(_ bytes: Data, in root: URL) throws -> AudioInspectionSource {
        let url = root.appendingPathComponent("synthetic-\(UUID().uuidString).ogg")
        try bytes.write(to: url, options: .withoutOverwriting)
        return .init(identity: .init(recordingID: UUID(), sha256: digest(bytes), byteCount: Int64(bytes.count)), url: url)
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
