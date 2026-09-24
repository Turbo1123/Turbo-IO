import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreML
import CryptoKit
import FluidAudio

enum ParakeetFailure: Error { case missingModel, integrity, audioOverflow, thermal, invalidAudio }

/// Bundled, pinned assets only. Deliberately never calls FluidAudio's download API.
actor ParakeetWorker {
    private let manager: StreamingEouAsrManager
    private var samplesInSegment = 0
    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        manager = StreamingEouAsrManager(configuration: config, chunkSize: .ms320, eouDebounceMs: 640)
    }
    func load(directory: URL) async throws {
        struct Manifest: Decodable {
            struct File: Decodable { let path: String; let size: Int; let sha256: String }
            let revision: String; let files: [File]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.revision == "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355", manifest.files.count == 16 else { throw ParakeetFailure.integrity }
        for file in manifest.files {
            try Task.checkCancellation()
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { throw ParakeetFailure.integrity }
            let data = try Data(contentsOf: directory.appendingPathComponent(file.path), options: .mappedIfSafe)
            guard data.count == file.size, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw ParakeetFailure.integrity }
        }
        try await manager.loadModels(from: directory)
    }
    func step(_ samples: [Float]) async throws -> (String, Bool) {
        try Task.checkCancellation()
        guard !samples.isEmpty, samples.count <= 16000 else { throw ParakeetFailure.invalidAudio }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw ParakeetFailure.invalidAudio }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        _ = try await manager.process(audioBuffer: buffer)
        samplesInSegment += samples.count
        let text = await manager.getPartialTranscript().replacingOccurrences(of: "<EOU>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A hard 25 s segment ceiling bounds model token/cache growth during long uninterrupted speech.
        let final = await manager.eouDetected || samplesInSegment >= 400000 || text.utf8.count >= 1800
        if final { await manager.reset(); samplesInSegment = 0 }
        return (text, final)
    }
    func close() async { await manager.cleanup() }
}

@MainActor final class CaptionParakeetSpeech {
    var onText: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private var stream: AsyncStream<[Float]>.Continuation?
    private var task: Task<Void, Never>?
    private var worker: ParakeetWorker?
    private var epoch = 0
    private var loading = false
    static func modelURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "ParakeetEOU320", withExtension: nil, subdirectory: "TurboCaptionModels") else { throw ParakeetFailure.missingModel }
        return url
    }
    func prepare() async throws {
        guard task == nil, !loading else { throw CaptionFailure.configuration }
        loading = true; epoch += 1; let generation = epoch
        defer { loading = false }
        let worker = ParakeetWorker()
        do { try await worker.load(directory: Self.modelURL()) }
        catch { await worker.close(); throw error }
        guard generation == epoch, !Task.isCancelled else { await worker.close(); throw CancellationError() }
        self.worker = worker
        let pair = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingOldest(32))
        stream = pair.continuation
        task = Task { [weak self] in
            do {
                var previous = ""
                for await samples in pair.stream {
                    try Task.checkCancellation()
                    guard ProcessInfo.processInfo.thermalState != .critical else { throw ParakeetFailure.thermal }
                    let (text, final) = try await worker.step(samples)
                    guard let self, self.epoch == generation, !Task.isCancelled else { break }
                    if !text.isEmpty && (text != previous || final) { self.onText?(text, final) }
                    previous = final ? "" : text
                }
            } catch {
                if let self, self.epoch == generation, !Task.isCancelled { self.onFailure?("asr_processing_failed") }
            }
            await worker.close()
        }
    }
    func offer(_ buffer: AVAudioPCMBuffer) {
        guard let stream, buffer.format.sampleRate == 16000, buffer.format.channelCount == 1,
              let p = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: p, count: Int(buffer.frameLength)))
        if case .dropped = stream.yield(samples) { stop(); onFailure?("asr_audio_backpressure") }
    }
    func stop() {
        epoch += 1; stream?.finish(); stream = nil; task?.cancel(); task = nil; worker = nil
    }
}

@objc(TIOCaptionHost)
@MainActor final class CaptionHost: NSObject {
    private static var handler: ((String, NSDictionary) -> NSDictionary)?
    @objc(configure:) static func configure(_ callback: @escaping (String, NSDictionary) -> NSDictionary) { handler = callback }
    static func call(_ name: String, _ args: NSDictionary = [:]) -> NSDictionary { handler?(name, args) ?? ["available": false] }
}
