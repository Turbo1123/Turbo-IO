import Foundation

private struct Failure: Error { let message: String }
private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
}

@main struct StandbyWakeTests {
    static func fixture(continuous: Bool = true) -> StandbyVoiceSession {
        let session = StandbyVoiceSession()
        session.cloudEnabled = true; session.vadEnabled = true
        session.continuousASREnabled = continuous
        session.send = { _, _ in true }
        session.enable(target: "fixture", connected: true)
        session.receive(from: "fixture", type: 1, audioBytes: 0, now: 0)
        return session
    }
    static func audio(_ session: StandbyVoiceSession, at time: TimeInterval) {
        session.receive(from: "fixture", type: 3, audioBytes: 20, now: time)
    }
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("countdown uses session deadline and clears after actual recognition", {
                let s = fixture()
                try check(s.initialSpeechSecondsRemaining(now: 0) == 8, "initial countdown")
                try check(s.initialSpeechSecondsRemaining(now: 6.1) == 2, "countdown must round up")
                try check(s.initialSpeechSecondsRemaining(now: 9) == 0, "negative countdown")
                s.cloudTranscript("查询时间", final: false, id: s.cloudRoundID!)
                try check(s.initialSpeechSecondsRemaining(now: 7) == nil, "recognized text retained countdown")
            }),
            ("continuous silence exits at eight seconds and keeps standby", {
                let s = fixture(); var commands: [StandbyVoiceSession.Command] = []
                s.send = { _, command in commands.append(command); return true }
                audio(s, at: 7); s.tick(now: 7.99)
                try check(s.phase == .recording, "closed before eight seconds")
                s.tick(now: 8)
                try check(s.phase == .idle, "silent wake still recording after eight seconds")
                try check(s.enabled && commands == [.stopAudio, .exit], "must stop and exit once while retaining standby")
                s.tick(now: 10); try check(commands.count == 2, "repeated exit")
            }),
            ("valid speech cancels initial wait without truncating the utterance", {
                let s = fixture(), session = s.cloudSessionID!, turn = UUID()
                s.cloudUtteranceBegan(id: turn, session: session, now: 7)
                s.cloudTranscript("读取文件", final: false, id: turn)
                audio(s, at: 8); s.tick(now: 8)
                try check(s.phase == .recording, "valid utterance was cut off")
                audio(s, at: 15); s.tick(now: 15)
                try check(s.phase == .recording, "initial timer survived valid speech")
            }),
            ("foreign and stale speech cannot extend a new silent wake", {
                let s = fixture(), old = s.cloudSessionID!
                s.cancelCurrentRound()
                s.receive(from: "fixture", type: 1, audioBytes: 0, now: 10)
                s.cloudUtteranceBegan(id: UUID(), session: old, now: 17)
                s.receive(from: "other", type: 1, audioBytes: 0, now: 17)
                audio(s, at: 17); s.tick(now: 18)
                try check(s.phase == .idle, "stale event extended initial wait")
            }),
            ("completed answer retains ten second follow-up window", {
                let s = fixture(), turn = UUID()
                s.cloudUtteranceBegan(id: turn, session: s.cloudSessionID!, now: 1)
                s.cloudTranscript("你好", final: true, id: turn)
                s.cloudEndpoint(id: turn, now: 2)
                s.cloudText("回答", final: true, id: turn, now: 3)
                audio(s, at: 8); s.tick(now: 8)
                try check(s.phase == .displaying, "initial timer closed answer")
                audio(s, at: 12); s.tick(now: 12.99)
                try check(s.phase == .displaying, "follow-up window shortened")
                s.tick(now: 13); try check(s.phase == .idle, "follow-up did not close")
            }),
            ("disconnect clears old wake timing", {
                let s = fixture(); s.connection(false); s.tick(now: 8)
                try check(s.initialSpeechSecondsRemaining(now: 8) == nil, "stale countdown after disconnect")
                try check(s.phase == .waitingForConnection, "disconnect state changed by old timer")
                s.connection(true); s.tick(now: 9)
                try check(s.phase == .idle, "reconnection auto-recorded")
            }),
            ("legacy mode retains its five second no-speech policy", {
                let s = fixture(continuous: false)
                s.tick(now: 4.99); try check(s.phase == .recording, "legacy closed early")
                s.tick(now: 5); try check(s.phase == .idle, "legacy no-speech changed")
            }),
            ("silent wake never sends fabricated transcript or speech events", {
                let s = StandbyVoiceSession(); var commands: [StandbyVoiceSession.Command] = []
                s.cloudEnabled = true; s.continuousASREnabled = true
                s.send = { _, command in commands.append(command); return true }
                s.enable(target: "fixture", connected: true)
                s.receive(from: "fixture", type: 1, audioBytes: 0, now: 0)
                audio(s, at: 7); s.tick(now: 8)
                try check(commands == [.startAudio, .stopAudio, .exit], "welcome or clock masqueraded as speech")
            }),
            ("failed exit requires connection review and clears countdown", {
                let s = fixture(); s.send = { _, command in command != .exit }
                audio(s, at: 7); s.tick(now: 8)
                try check(s.phase == .waitingForConnection, "failed exit was reported as idle")
                try check(s.initialSpeechSecondsRemaining(now: 8) == nil, "failed exit retained countdown")
            }),
            ("foreign transcript and whitespace do not cancel initial wait", {
                let s = fixture()
                s.cloudTranscript("other turn", final: false, id: UUID())
                s.cloudTranscript("  ", final: false, id: s.cloudRoundID!)
                audio(s, at: 7); s.tick(now: 8)
                try check(s.phase == .idle, "invalid text extended initial wait")
            })
        ]
        var failures = 0
        for (name, test) in tests {
            do { try test(); print("PASS: \(name)") }
            catch { failures += 1; print("FAIL: \(name): \(error)") }
        }
        print("Tests: \(tests.count), failures: \(failures)")
        if failures > 0 { exit(1) }
    }
}
