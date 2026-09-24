import Foundation
@preconcurrency import AVFAudio

// Requires the host to grant exclusive capture ownership first. Never starts on initialization.
@MainActor final class CaptionMicrophoneInput {
    struct Port { let uid: String; let name: String; let type: String }
    var onPCM16: ((Data) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onFailure: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var selectedUID = ""
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var previous: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions, String?)?
    private var prepared = false
    private var preparing = false
    private var pipeline: CaptionAudioPipeline?

    // Call after explicit capture selection and host busy check, not just opening settings.
    func prepare() async throws -> [Port] {
        guard !prepared, !preparing, engine == nil else { throw CaptionFailure.configuration }
        preparing = true; let epoch = generation
        defer { preparing = false }
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { throw CaptionFailure.unavailable }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
        guard granted else { throw CaptionFailure.unavailable }
        let session = AVAudioSession.sharedInstance()
        previous = (session.category, session.mode, session.categoryOptions, session.preferredInput?.uid)
        prepared = true
        do {
            // HFP prioritizes latency. A2DP is not a microphone selection mechanism.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
            try session.setActive(true)
            prepared = true
            return (session.availableInputs ?? []).map { Port(uid: $0.uid, name: $0.portName, type: $0.portType.rawValue) }
        } catch { stop(); throw error }
    }
    func start(uid: String, format: AVAudioFormat? = nil) async throws {
        guard prepared, engine == nil else { throw CaptionFailure.configuration }
        let session = AVAudioSession.sharedInstance()
        guard let input = session.availableInputs?.first(where: { $0.uid == uid }) else { throw CaptionFailure.unavailable }
        generation += 1; let epoch = generation
        try session.setPreferredInput(input)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard epoch == generation, session.currentRoute.inputs.first?.uid == uid else { throw CaptionFailure.routeChanged }
        selectedUID = uid
        let engine = AVAudioEngine(), node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = format ?? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else { throw CaptionFailure.unavailable }
        let pipeline = try CaptionAudioPipeline(source: source, target: target, deliver: { [weak self] output in
            guard let self, self.generation == epoch, self.engine != nil else { return }
            guard AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid == self.selectedUID else { self.fail("input_route_changed", epoch: epoch); return }
            self.onBuffer?(output)
            if target.commonFormat == .pcmFormatInt16, target.sampleRate == 16000, target.channelCount == 1, let bytes = output.int16ChannelData {
                let data = Data(bytes: bytes[0], count: Int(output.frameLength) * 2)
                for start in stride(from: 0, to: data.count, by: 3200) { self.onPCM16?(data.subdata(in: start..<min(start + 3200, data.count))) }
            }
        }, failure: { [weak self] code in self?.fail(code, epoch: epoch) })
        self.engine = engine; self.pipeline = pipeline
        node.installTap(onBus: 0, bufferSize: 1024, format: source, block: pipeline.makeTap())
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch, self.engine != nil else { return }
                // Any active-route reconfiguration stops capture; no silent fallback.
                self.fail("input_route_changed", epoch: epoch)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fail("audio_interrupted", epoch: epoch) }
        })
        do { try engine.start() } catch { stop(); throw error }
    }
    func stop() {
        generation += 1
        pipeline?.close(); pipeline = nil
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        engine = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        let session = AVAudioSession.sharedInstance()
        // Never overwrite a different owner's new category; host must arbitrate all captures.
        if prepared, session.category == .playAndRecord, session.mode == .default,
           session.categoryOptions == [.allowBluetoothHFP], let previous {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
            try? session.setPreferredInput(session.availableInputs?.first { $0.uid == previous.3 })
        }
        prepared = false; previous = nil; selectedUID = ""
    }
    private func fail(_ code: String, epoch: Int) { guard generation == epoch else { return }; stop(); onFailure?(code) }
}
