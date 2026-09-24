import Foundation
@preconcurrency import AVFAudio

// Ownership is transferred from the serial converter queue to the MainActor.
// Neither the tap nor the worker accesses an output buffer after delivery.
private struct CaptionOwnedAudio: @unchecked Sendable { let buffer: AVAudioPCMBuffer }

/// Not actor isolated. AVAudioNode's legacy callback is invoked on an audio thread.
/// The converter is only accessed by `queue`; pending and closed use `lock`.
final class CaptionAudioPipeline: @unchecked Sendable {
    private let source: AVAudioFormat, target: AVAudioFormat, converter: AVAudioConverter
    private let queue = DispatchQueue(label: "io.turboio.caption.pcm.offline04")
    private let lock = NSLock()
    private var pending = 0, closed = false
    private let deliver: @MainActor @Sendable (AVAudioPCMBuffer) -> Void
    private let failure: @MainActor @Sendable (String) -> Void
    init(source: AVAudioFormat, target: AVAudioFormat,
         deliver: @escaping @MainActor @Sendable (AVAudioPCMBuffer) -> Void,
         failure: @escaping @MainActor @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else { throw PipelineError.format }
        converter.downmix = true
        self.source = source; self.target = target; self.converter = converter
        self.deliver = deliver; self.failure = failure
    }
    enum PipelineError: Error { case format }
    func close() { lock.lock(); closed = true; lock.unlock() }
    private func reserve() -> Int {
        lock.lock(); defer { lock.unlock() }
        if closed { return 0 }; if pending >= 8 { closed = true; return -1 }; pending += 1; return 1
    }
    private func release() { lock.lock(); pending -= 1; lock.unlock() }
    private func isClosed() -> Bool { lock.lock(); defer { lock.unlock() }; return closed }
    private func fail(_ code: String) {
        close(); let failure = failure
        Task { @MainActor in failure(code) }
    }
    /// Created in a nonisolated context: cannot inherit a UI MainActor executor.
    func makeTap() -> AVAudioNodeTapBlock {
        return { [self] buffer, _ in consume(buffer) }
    }
    private func consume(_ buffer: AVAudioPCMBuffer) {
        let reservation = reserve()
        if reservation == 0 { return }
        if reservation < 0 { fail("capture_backpressure"); return }
        guard buffer.frameLength > 0, buffer.frameLength <= 8192,
              buffer.format == source,
              let copy = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: buffer.frameLength) else {
            release(); fail("capture_format"); return
        }
        copy.frameLength = buffer.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard src.count == dst.count else { release(); fail("capture_channels"); return }
        for i in 0..<src.count {
            guard let from = src[i].mData, let to = dst[i].mData, src[i].mDataByteSize <= dst[i].mDataByteSize else {
                release(); fail("capture_format"); return
            }
            memcpy(to, from, Int(src[i].mDataByteSize))
        }
        let owned = CaptionOwnedAudio(buffer: copy)
        queue.async { [self] in
            guard !isClosed() else { release(); return }
            let copy = owned.buffer
            let capacity = AVAudioFrameCount(ceil(Double(copy.frameLength) * target.sampleRate / source.sampleRate)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { release(); fail("capture_allocation"); return }
            var supplied = false, error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return copy
            }
            guard status != .error, error == nil else { release(); fail("pcm_conversion"); return }
            guard output.frameLength > 0 else { release(); return }
            let result = CaptionOwnedAudio(buffer: output)
            Task { @MainActor [self] in
                defer { release() }
                guard !isClosed() else { return }
                deliver(result.buffer)
            }
        }
    }
}
