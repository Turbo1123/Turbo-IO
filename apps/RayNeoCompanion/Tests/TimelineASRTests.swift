import XCTest
import AVFoundation
@testable import RayNeoCompanion

final class TimelineASRTests: XCTestCase {
    private func decodeToneChannels(_ gains: [Double], selected: Int? = nil) throws -> [Int16] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(gains.count)))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, interleaved: false, channelLayout: layout)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        buffer.frameLength = 48000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in gains.indices {
            for frame in 0..<48000 { channels[channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48000) * gains[channel]) }
        }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let bytes = [UInt8](try RecordingPCMDecoder.decode(url, inputChannel: selected))
        return stride(from: 0, to: bytes.count, by: 2).map { Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0+1]) << 8) }
    }
    func testDefaultDownmixIncludesEitherStereoSideEqually() throws {
        let left = try decodeToneChannels([0.8, 0]), right = try decodeToneChannels([0, 0.8])
        XCTAssertEqual(left, right)
        XCTAssertGreaterThan(left.map { abs(Int($0)) }.max()!, 12000)
        XCTAssertLessThan(left.map { abs(Int($0)) }.max()!, 14000)
    }
    func testDefaultDownmixAveragesFullScaleChannelsWithoutOverflow() throws {
        let samples = try decodeToneChannels([0.95, 0.95])
        XCTAssertEqual(samples, try decodeToneChannels([0.95]))
        let peak = samples.map { abs(Int($0)) }.max()!
        XCTAssertGreaterThan(peak, 30000); XCTAssertLessThan(peak, 32767)
    }
    func testMonoDefaultPreservesExplicitMonoConversion() throws {
        XCTAssertEqual(try decodeToneChannels([0.4]), try decodeToneChannels([0.4], selected: 0))
    }
    func testDefaultDownmixIncludesMoreThanTwoChannels() throws {
        let samples = try decodeToneChannels([0, 0, 0.9])
        let peak = samples.map { abs(Int($0)) }.max()!
        XCTAssertGreaterThan(peak, 9000); XCTAssertLessThan(peak, 10500)
    }
    func testSilenceStaysSilentWithoutInventedGainOrSpeech() throws {
        XCTAssertTrue(try decodeToneChannels([0, 0]).allSatisfy { $0 == 0 })
    }
    func testExplicitRightChannelDecodesSpeechWhenLeftIsSilent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        buffer.frameLength = 48000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<48000 {
            channels[0][i] = 0
            channels[1][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48000) * 0.25)
        }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let left = try RecordingPCMDecoder.decode(url, inputChannel: 0)
        let right = try RecordingPCMDecoder.decode(url, inputChannel: 1)
        XCTAssertEqual(left.count, right.count)
        XCTAssertTrue(left.allSatisfy { $0 == 0 })
        XCTAssertTrue(right.contains { $0 != 0 })
        XCTAssertGreaterThan(right.count, 31000); XCTAssertLessThan(right.count, 33000)
        XCTAssertThrowsError(try RecordingPCMDecoder.decode(url, inputChannel: 2))
    }
    func testASRDiagnosticPreservesResponseAndRedactsSecret() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pcm = Data([1, 0, 2, 0])
        let capture = try FileASRDiagnostic(root: root, pcm: pcm, secret: "synthetic-secret")
        let raw = "{\"event\":\"task-failed\",\"message\":\"synthetic-secret denied\"}"
        try capture.record("received", raw)
        let log = try String(contentsOf: capture.directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertFalse(log.contains("synthetic-secret")); XCTAssertTrue(log.contains("[REDACTED]"))
        XCTAssertTrue(log.contains("task-failed"))
        XCTAssertEqual(try Data(contentsOf: capture.directory.appendingPathComponent("sent-16000-mono-s16le.pcm")), pcm)
        XCTAssertThrowsError(try capture.record("oversized", String(repeating: "x", count: 2_097_153)))
    }
    @MainActor func testFileASRControlsUseTextFramesNotAudioFrames() throws {
        for action in ["run-task", "finish-task"] {
            let message = try FileASRClient.controlMessage(["header": ["action": action, "task_id": "fixture"], "payload": ["input": [:]]])
            guard case .string(let text) = message else { return XCTFail("JSON controls must not be binary PCM frames") }
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let header = try XCTUnwrap(object["header"] as? [String: String])
            XCTAssertEqual(header["action"], action)
            XCTAssertEqual(header["task_id"], "fixture")
        }
    }
    func testJournalPersistsOrderedEventsAndDoesNotAppendToTornTail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = TimelineJournal(directory: root)
        let initial = await withCheckedContinuation { continuation in journal.load { continuation.resume(returning: $0) } }
        XCTAssertTrue(try initial.get().isEmpty)
        let id = UUID()
        for event in [ConversationEvent(id: id, kind: .transcript, text: "真实存盘合成测试", final: true), ConversationEvent(id: id, kind: .answerDelta, text: "答复"), ConversationEvent(id: id, kind: .completed)] {
            let saved = await withCheckedContinuation { continuation in journal.append(event) { continuation.resume(returning: $0) } }
            XCTAssertTrue(saved)
        }
        let second = TimelineJournal(directory: root)
        let replayed = await withCheckedContinuation { continuation in second.load { continuation.resume(returning: $0) } }
        XCTAssertEqual(try replayed.get().first?.answer, "答复")
        XCTAssertEqual(try replayed.get().first?.outcome, "模型已完成")
        let url = root.appendingPathComponent("events.jsonl")
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"torn".utf8)); try handle.close()
        let before = try Data(contentsOf: url)
        let broken = TimelineJournal(directory: root)
        let recovered = await withCheckedContinuation { continuation in broken.load { continuation.resume(returning: $0) } }
        XCTAssertEqual(try recovered.get().count, 1)
        let saved = await withCheckedContinuation { continuation in broken.append(ConversationEvent(id: UUID(), kind: .completed)) { continuation.resume(returning: $0) } }
        XCTAssertFalse(saved); XCTAssertEqual(try Data(contentsOf: url), before)
    }
    @MainActor func testManualASRDoesNotStartInSimulatorAndExposesReason() {
        let client = ManualRecordingASR(), id = UUID()
        client.start(id: id, title: "synthetic", archive: LocalArchiveController(rootDirectory: nil))
        XCTAssertFalse(client.busy); XCTAssertEqual(client.recordingID, id)
        XCTAssertTrue(client.status.contains("模拟器")); XCTAssertTrue(client.resultText.isEmpty)
    }
    func testTimelinePreservesFullQuestionAndInterruptedAnswer() throws {
        let first = UUID(), second = UUID()
        var turns: [ConversationTurn] = []
        let full = String(repeating: "完整识别文字", count: 150)
        for event in [ConversationEvent(id: first, kind: .transcript, text: "临时"),
                      ConversationEvent(id: first, kind: .transcript, text: full, final: true),
                      ConversationEvent(id: first, kind: .answerDelta, text: "前半段"),
                      ConversationEvent(id: first, kind: .interrupted),
                      ConversationEvent(id: second, kind: .transcript, text: "新问题", final: true),
                      ConversationEvent(id: second, kind: .answerDelta, text: "完整回答"),
                      ConversationEvent(id: second, kind: .completed),
                      ConversationEvent(id: second, kind: .interrupted)] { TimelineReplay.apply(event, to: &turns) }
        XCTAssertEqual(turns.count, 2); XCTAssertEqual(turns[0].question, full)
        XCTAssertEqual(turns[0].answer, "前半段"); XCTAssertEqual(turns[0].outcome, "已中断/结束")
        XCTAssertEqual(turns[1].outcome, "模型已完成")
    }
    func testTimelineReplayTornTailAndInvalidMiddleAreDifferent() throws {
        let event = ConversationEvent(id: UUID(), kind: .transcript, text: "保留", final: true)
        var data = try JSONEncoder().encode(event); data.append(10)
        data.append(Data("{\"partial".utf8))
        let turns = try TimelineReplay.decode(data)
        XCTAssertEqual(turns.count, 1); XCTAssertEqual(turns.first?.outcome, "上次未完成")
        data.append(10)
        XCTAssertThrowsError(try TimelineReplay.decode(data))
    }
    func testTimelineMarkdownUsesLiteralFencesForUntrustedContent() {
        let turn = ConversationTurn(id: UUID(), startedAt: Date(timeIntervalSince1970: 0), updatedAt: Date(), question: "```\n![image](https://example.invalid/a)\n````", answer: "文字")
        let markdown = TimelineReplay.markdown([turn])
        XCTAssertTrue(markdown.contains("1970-01-01T00:00:00Z"))
        XCTAssertTrue(markdown.contains("`````text")); XCTAssertTrue(markdown.contains(turn.question))
    }
    func testFileASROnlySavesFinalSentencesInNumericOrder() throws {
        var accumulator = FileASRAccumulator()
        try accumulator.accept(id: 2, text: "第二句", final: true)
        try accumulator.accept(id: 1, text: "临时错误", final: false)
        try accumulator.accept(id: 1, text: "第一句", final: true)
        XCTAssertEqual(accumulator.text, "第一句\n第二句")
        try accumulator.accept(id: 2, text: "第二句修订", final: true)
        XCTAssertEqual(accumulator.text, "第一句\n第二句修订")
        XCTAssertThrowsError(try accumulator.accept(id: -1, text: "", final: true))
    }
    func testRealWAVDecodesLocallyWithoutCallingASR() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic-tone.wav")
        // Independent PCM WAV fixture; header is finalized before decoder opens it.
        var wav = Data()
        func four(_ s: String) { wav.append(Data(s.utf8)) }
        func word(_ n: UInt16) { wav.append(UInt8(n & 255)); wav.append(UInt8(n >> 8)) }
        func dword(_ n: UInt32) { word(UInt16(n & 65535)); word(UInt16(n >> 16)) }
        four("RIFF"); dword(36 + 96_000); four("WAVE"); four("fmt "); dword(16)
        word(1); word(1); dword(48_000); dword(96_000); word(2); word(16)
        four("data"); dword(96_000)
        for i in 0..<48_000 { word(UInt16(bitPattern: Int16(sin(Double(i) * 2 * .pi * 440 / 48_000) * 6000))) }
        try wav.write(to: url)
        let pcm = try RecordingPCMDecoder.decode(url) { print("Synthetic decoder: \($0)") }
        XCTAssertGreaterThanOrEqual(pcm.count, 31_000); XCTAssertLessThanOrEqual(pcm.count, 33_000)
        XCTAssertEqual(pcm.count % 2, 0); XCTAssertTrue(pcm.contains { $0 != 0 })
    }
    @MainActor func testOldTodoMetadataDecodesAndEditingIsRecoverable() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "title": "旧版", "completed": false, "createdAt": 0])
        let old = try JSONDecoder().decode(LocalTodo.self, from: data)
        XCTAssertNil(old.dueAt); XCTAssertNil(old.archivedAt)
        let suite = "todo-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = CompanionStore(defaults: defaults)
        store.addTodo("初稿")
        let todo = try XCTUnwrap(store.todos.first)
        store.editTodo(todo.id, title: "修改稿", dueAt: Date(timeIntervalSince1970: 123))
        store.archiveTodo(todo.id, archived: true)
        XCTAssertNotNil(store.todos[0].archivedAt)
        store.archiveTodo(todo.id, archived: false)
        XCTAssertEqual(store.todos[0].title, "修改稿"); XCTAssertNil(store.todos[0].archivedAt)
        XCTAssertEqual(store.todos[0].dueAt, Date(timeIntervalSince1970: 123))
    }
}
