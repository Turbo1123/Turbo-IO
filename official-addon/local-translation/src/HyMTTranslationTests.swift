import Foundation

@main struct HyMTTranslationTests {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { fatalError("supply original and adapted model") }
        let engine = CaptionHyMTTranslation()
        do {
            try await engine.load(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            fatalError("original ID-42 model must be rejected by SHA gate")
        } catch HyMTFailure.invalidModel {}
        try await engine.load(url: URL(fileURLWithPath: CommandLine.arguments[2]))
        precondition(engine.loaded)
        var partials: [String] = []
        let text = try await engine.translate("Please turn left at the next intersection.", source: "en-US", target: "zh-CN") { partials.append($0) }
        precondition(!text.isEmpty)
        precondition(!partials.isEmpty && partials.allSatisfy { text.hasPrefix($0) })
        precondition(engine.lastTiming!.firstTokenMS > 0)
        print("Swift translation: \(text)")
        do {
            _ = try await engine.translate("hello", source: "en", target: "unknown")
            fatalError("unsupported language must fail")
        } catch HyMTFailure.unsupportedLanguage {}
        let running = Task { try await engine.translate("Please stand behind the yellow line and wait for the next train.", source: "en", target: "zh") }
        try await Task.sleep(for: .milliseconds(20))
        do {
            _ = try await engine.translate("hello", source: "en", target: "zh")
            fatalError("busy must fail, not silently enqueue")
        } catch HyMTFailure.busy {}
        engine.cancel()
        do { _ = try await running.value; fatalError("cancelled work must not return text") }
        catch HyMTFailure.native(let status) { precondition(status == TIO_HY_CANCELLED) }
        catch is CancellationError {}
        let recovery = try await engine.translate("Thank you.", source: "en", target: "zh")
        precondition(!recovery.isEmpty)
        engine.unload()
        precondition(!engine.loaded)
        print("PASS Swift SHA gate, worker bridge, busy, cancel, recovery, unload")
    }
}
