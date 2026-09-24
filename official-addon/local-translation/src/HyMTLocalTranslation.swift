import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

enum HyMTFailure: Error { case busy, notLoaded, invalidModel, invalidText, unsupportedLanguage, native(Int32) }

// At most one main-actor delivery is queued. An overloaded UI receives the latest
// complete UTF-8 prefix, not a backlog of one task per generated token.
private final class HyMTPartialDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: String?
    private var scheduled = false
    private var closed = false
    let receive: @MainActor @Sendable (String) -> Void
    init(_ receive: @escaping @MainActor @Sendable (String) -> Void) { self.receive = receive }
    func offer(_ text: String) {
        lock.lock()
        if closed { lock.unlock(); return }
        latest = text
        let enqueue = !scheduled; scheduled = true
        lock.unlock()
        if enqueue { Task { @MainActor [self] in if let value = take() { receive(value) } } }
    }
    private func take() -> String? {
        lock.lock(); defer { lock.unlock() }
        let value = closed ? nil : latest
        latest = nil; scheduled = false
        return value
    }
    func close() { lock.lock(); closed = true; latest = nil; lock.unlock() }
}
private func hymtPartial(_ bytes: UnsafePointer<CChar>?, _ count: Int, _ context: UnsafeMutableRawPointer?) {
    guard let bytes, let context, count > 0, count < 8192,
          let text = String(data: Data(bytes: bytes, count: count), encoding: .utf8) else { return }
    Unmanaged<HyMTPartialDelivery>.fromOpaque(context).takeUnretainedValue().offer(text)
}

struct HyMTTiming: Sendable {
    let firstTokenMS: Double
    let totalMS: Double
    let promptTokens: Int
    let outputTokens: Int
    let threads: Int
}

// Only the worker queue accesses the engine. A request's atomic cancel may be set anywhere.
private final class HyMTNativeState: @unchecked Sendable {
    var engine: OpaquePointer?
    func unload() { if let engine { tio_hymt_free(engine) }; engine = nil }
    deinit { unload() }
}
private final class HyMTRequest: @unchecked Sendable {
    let handle: OpaquePointer
    init(milliseconds: Int32) throws {
        guard let handle = tio_hymt_request_new(milliseconds) else { throw HyMTFailure.native(1) }
        self.handle = handle
    }
    func cancel() { tio_hymt_request_cancel(handle) }
    deinit { tio_hymt_request_free(handle) }
}

/// Optional, entirely local text engine. One active operation; no hidden waiting queue.
/// UI supplies a local, compatible GGUF URL. No automatic download or cloud fallback.
@MainActor final class CaptionHyMTTranslation {
    nonisolated static let modelSHA256 = "e482a38ceaaf8420573483c96ddc8449922b5f5de6a8023b70316e65d41e6de7"
    nonisolated static let modelSize: UInt64 = 461860800
    private let worker = DispatchQueue(label: "org.turboio.caption.hymt", qos: .userInitiated)
    private let state = HyMTNativeState()
    private var current: HyMTRequest?
    private var generation = 0
    private var busy = false
    private var unloading = false
    private(set) var loaded = false
    private var memoryObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?
    var preferredThreads = min(6, ProcessInfo.processInfo.activeProcessorCount)
    private(set) var lastTiming: HyMTTiming?
    var effectiveThreads: Int {
        let requested = min(max(1, preferredThreads), min(8, ProcessInfo.processInfo.activeProcessorCount))
        return ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.isLowPowerModeEnabled ? min(2, requested) : requested
    }
    init() {
        #if canImport(UIKit)
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unload() }
        }
        #endif
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Abort current decoding at critical temperature. Serious temperature
                // uses a lower thread budget on the next request without racing native state.
                if ProcessInfo.processInfo.thermalState == .critical { self?.cancel() }
            }
        }
    }
    isolated deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
    }
    func cancel() { generation += 1; current?.cancel() }
    func unload() {
        cancel(); loaded = false
        guard !unloading else { return }
        unloading = true
        let state = state
        worker.async { [weak self] in
            state.unload()
            Task { @MainActor in self?.unloading = false }
        }
    }
    func load(url: URL, threads: Int32 = 6) async throws {
        guard !busy, !unloading else { throw HyMTFailure.busy }
        guard url.isFileURL, (1...8).contains(threads) else { throw HyMTFailure.invalidModel }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw HyMTFailure.native(Int32(TIO_HY_CANCELLED)) }
        preferredThreads = Int(threads)
        let threads = Int32(effectiveThreads)
        let request = try HyMTRequest(milliseconds: 60000)
        busy = true; current = request; loaded = false
        let epoch = generation, state = state
        defer { busy = false; current = nil }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                worker.async {
                    do {
                        // Access is balanced, including checksum/load errors.
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        try Self.verify(url)
                        state.unload()
                        var status: Int32 = 0
                        state.engine = url.path.withCString { tio_hymt_load($0, threads, request.handle, &status) }
                        guard state.engine != nil, status == 0 else { throw HyMTFailure.native(status) }
                        continuation.resume()
                    } catch { state.unload(); continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { request.cancel() })
        guard epoch == generation, !Task.isCancelled else { unload(); throw CancellationError() }
        loaded = true
    }
    func translate(_ text: String, source: String, target: String,
                   onPartial: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> String {
        guard !busy, !unloading else { throw HyMTFailure.busy }
        guard loaded else { throw HyMTFailure.notLoaded }
        guard !text.isEmpty, text.utf8.count <= 4096, !text.contains("\0") else { throw HyMTFailure.invalidText }
        guard let language = Self.languageName(target), Self.languageName(source) != nil else { throw HyMTFailure.unsupportedLanguage }
        if Self.languageName(source) == language { return text }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw HyMTFailure.native(Int32(TIO_HY_CANCELLED)) }
        let request = try HyMTRequest(milliseconds: 15000)
        busy = true; current = request
        let epoch = generation, state = state
        let threads = Int32(effectiveThreads)
        lastTiming = nil
        let delivery = HyMTPartialDelivery { [weak self] value in
            guard let self, self.generation == epoch, self.busy else { return }
            onPartial?(value)
        }
        defer { delivery.close(); busy = false; current = nil }
        let translated: (String, HyMTTiming) = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                worker.async {
                    var output = [CChar](repeating: 0, count: 8192)
                    var metrics = TIOHyMTMetrics()
                    let status = text.withCString { input in
                        language.withCString { language in
                            tio_hymt_translate_stream(state.engine, request.handle, input, language, 384, &output, output.count, &metrics,
                                threads, hymtPartial, Unmanaged.passUnretained(delivery).toOpaque())
                        }
                    }
                    guard status == 0 else { continuation.resume(throwing: HyMTFailure.native(status)); return }
                    let bytes = output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    guard let result = String(bytes: bytes, encoding: .utf8), !result.isEmpty else {
                        continuation.resume(throwing: HyMTFailure.invalidText); return
                    }
                    withExtendedLifetime(delivery) {}
                    continuation.resume(returning: (result, HyMTTiming(firstTokenMS: metrics.first_token_ms, totalMS: metrics.total_ms,
                        promptTokens: Int(metrics.prompt_tokens), outputTokens: Int(metrics.output_tokens), threads: Int(threads))))
                }
            }
        }, onCancel: { request.cancel() })
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
        lastTiming = translated.1
        return translated.0
    }
    nonisolated private static func verify(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == modelSize else { throw HyMTFailure.invalidModel }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == modelSHA256 else { throw HyMTFailure.invalidModel }
    }
    nonisolated static func languageName(_ code: String) -> String? {
        // Initial caption UI scope; model itself supports more languages.
        let language = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        return ["zh": "Chinese", "en": "English", "ja": "Japanese", "ko": "Korean", "fr": "French", "de": "German", "es": "Spanish", "it": "Italian", "ru": "Russian", "pt": "Portuguese"][language]
    }
}
