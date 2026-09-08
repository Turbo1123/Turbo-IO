import Foundation
import RayNeoSession
import RayNeoSessionRuntime
import RayNeoSessionRuntimeTestSupport

@main
struct SyntheticSessionDemo {
    enum Failure: Error { case didNotComplete }
    static func main() async throws {
        let transport = RecordingGlassesTransport()
        let runtime = SessionRuntime(dependencies: .init(localASR: SyntheticASRProvider(),
            model: SyntheticConversationModel(), transport: transport))
        _ = await runtime.send(.connected)
        let round = await runtime.send(.wake).session.currentRound!
        _ = await runtime.send(.audioReceived(round: round,
            chunk: .init(data: Data([0, 0, 0, 0]), format: .pcm16LE(sampleRate: 16_000, channels: 1))))
        _ = await runtime.send(.audioEnded(round: round))
        var completed = false
        for _ in 0..<2_000 {
            let snapshot = await runtime.currentSnapshot()
            if snapshot.session.phase == .awaitingNextRound && snapshot.pendingTransportCommands == 0 {
                completed = true; break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let commands = await transport.admittedCommands.count
        _ = await runtime.shutdown()
        guard completed else { throw Failure.didNotComplete }
        print("SYNTHETIC ONLY: one text round completed; semantic commands admitted=\(commands). No microphone, network, speaker or glasses used.")
    }
}
