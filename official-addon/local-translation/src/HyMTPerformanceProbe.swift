import UIKit

// Explicit synthetic-only opt-in, no capture, key access, networking, or glasses writes.
@MainActor enum HyMTPerformanceProbe {
    static let hamlet = """
    To be, or not to be, that is the question:
    Whether ’tis nobler in the mind to suffer
    The slings and arrows of outrageous fortune,
    Or to take arms against a sea of troubles,
    And by opposing end them. To die—to sleep,
    No more; and by a sleep to say we end
    The heart-ache and the thousand natural shocks
    That flesh is heir to: ’tis a consummation
    Devoutly to be wish’d.
    """
    static var running = false
    static func run() {
        guard !running else { return }; running = true
        Task {
            let engine = CaptionHyMTTranslation()
            var report: [String: Any] = ["build": "LOCAL-TRANSLATION-PERF-02", "syntheticOnly": true,
                "microphoneUsed": false, "networkUsed": false, "glassesWrites": false,
                "os": UIDevice.current.systemVersion, "processors": ProcessInfo.processInfo.activeProcessorCount]
            func save(_ phase: String) {
                report["phase"] = phase
                do {
                    var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TurboCaptionTests", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
                    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("perf02.json"), options: .atomic)
                } catch {}
            }
            defer { engine.unload(); running = false }
            save("loading")
            do {
                let start = Date(); try await engine.load(url: TIOCaptionPhoneProbe.modelURL())
                report["load_ms"] = Date().timeIntervalSince(start) * 1000
                // Warm up once. Reverse the order on the second pass to expose heat/order bias.
                _ = try await engine.translate("Please turn left at the next intersection.", source: "en", target: "zh")
                var results: [[String: Any]] = []
                let candidates = [2, 3, 4, 6].filter { $0 <= ProcessInfo.processInfo.activeProcessorCount }
                for (index, count) in (candidates + candidates.reversed()).enumerated() {
                    try Task.checkCancellation()
                    guard ProcessInfo.processInfo.thermalState != .critical else { throw CancellationError() }
                    engine.preferredThreads = count
                    let thermal = ProcessInfo.processInfo.thermalState.rawValue, begin = Date()
                    var firstVisible: Double?, updates = 0
                    let text = try await engine.translate(hamlet, source: "en", target: "zh") { _ in
                        if firstVisible == nil { firstVisible = Date().timeIntervalSince(begin) * 1000 }
                        updates += 1
                    }
                    guard let timing = engine.lastTiming else { throw HyMTFailure.invalidText }
                    results.append(["pass": index / candidates.count, "requestedThreads": count, "effectiveThreads": timing.threads,
                        "firstTokenMS": timing.firstTokenMS, "firstVisibleMS": firstVisible ?? -1, "totalMS": timing.totalMS,
                        "promptTokens": timing.promptTokens, "outputTokens": timing.outputTokens, "updates": updates,
                        "thermalStart": thermal, "thermalEnd": ProcessInfo.processInfo.thermalState.rawValue,
                        "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled, "output": text])
                    report["results"] = results; save("measuring")
                    try await Task.sleep(for: .milliseconds(500))
                }
                report["passed"] = true; save("completed")
            } catch { report["passed"] = false; report["error"] = TIOCaptionPhoneProbe.safeError(error); save("failed") }
        }
    }
}
