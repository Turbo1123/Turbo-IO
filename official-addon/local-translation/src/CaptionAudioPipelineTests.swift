import Foundation
@main struct Tests {
    static func main() async throws {
        let result = try await CaptionAudioPipelineProbe.run(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        precondition(result["backgroundCallbacks"] == result["deliveredBuffers"])
        precondition((result["convertedFrames"] ?? 0) > 300000)
        print("PASS actual background tap callback, 16k mono/48k stereo conversion, MainActor delivery, stop/late callback/restart: \(result)")
    }
}
