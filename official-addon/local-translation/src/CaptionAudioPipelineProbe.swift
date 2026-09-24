import Foundation
@preconcurrency import AVFAudio

// The test hands each buffer to exactly one background invocation, then waits for delivery.
private struct ProbeAudio: @unchecked Sendable { let buffer: AVAudioPCMBuffer; let tap: AVAudioNodeTapBlock }

@MainActor enum CaptionAudioPipelineProbe {
    enum Failure: Error { case invalidFixture, conversion, timeout, callback(String), wrongExecutor }
    static func run(url: URL) async throws -> [String: Int] {
        let file = try AVAudioFile(forReading: url)
        guard let all = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw Failure.invalidFixture }
        try file.read(into: all)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { throw Failure.invalidFixture }
        var total = 0, delivered = 0, background = 0
        for rate in [16000.0, 48000.0, 16000.0] {
            // Feed real public audio through the same resampler at mono16k / stereo48k, not a model mock.
            let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: rate == 48000 ? 2 : 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: all.format, to: source),
                  let expanded = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(Double(all.frameLength) * rate / all.format.sampleRate) + 256) else { throw Failure.conversion }
            var supplied = false, convertError: NSError?
            converter.convert(to: expanded, error: &convertError) { _, state in
                if supplied { state.pointee = .endOfStream; return nil }; supplied = true; state.pointee = .haveData; return all
            }
            guard convertError == nil else { throw Failure.conversion }
            var failure: String?
            let pipeline = try CaptionAudioPipeline(source: source, target: target, deliver: { buffer in
                MainActor.preconditionIsolated()
                if buffer.format.sampleRate != 16000 || buffer.format.channelCount != 1 { failure = "output_format" }
                delivered += 1; total += Int(buffer.frameLength)
            }, failure: { failure = $0 })
            let tap = pipeline.makeTap()
            for offset in stride(from: 0, to: Int(expanded.frameLength), by: 4096) {
                let count = min(4096, Int(expanded.frameLength) - offset)
                let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                for channel in 0..<Int(source.channelCount) { buffer.floatChannelData![channel].update(from: expanded.floatChannelData![channel] + offset, count: count) }
                let data = ProbeAudio(buffer: buffer, tap: tap), before = delivered
                let offMain = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let offMain = !Thread.isMainThread
                        data.tap(data.buffer, AVAudioTime(sampleTime: 0, atRate: rate))
                        continuation.resume(returning: offMain)
                    }
                }
                guard offMain else { throw Failure.wrongExecutor }; background += 1
                for _ in 0..<500 {
                    if delivered > before || failure != nil { break }
                    try await Task.sleep(for: .milliseconds(2))
                }
                if let failure { pipeline.close(); throw Failure.callback(failure) }
                guard delivered == before + 1 else { pipeline.close(); throw Failure.timeout }
            }
            pipeline.close()
            // A late callback after stop must not deliver old audio into the next session.
            let before = delivered
            let late = ProbeAudio(buffer: expanded, tap: tap)
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async { late.tap(late.buffer, AVAudioTime(sampleTime: 0, atRate: rate)); continuation.resume() }
            }
            try await Task.sleep(for: .milliseconds(20))
            guard delivered == before else { throw Failure.callback("late_delivery") }
        }
        return ["backgroundCallbacks": background, "deliveredBuffers": delivered, "convertedFrames": total, "restartCycles": 3]
    }
}
