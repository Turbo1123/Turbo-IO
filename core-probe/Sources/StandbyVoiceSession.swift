import Foundation

/// Pure, clock-driven service/session separation. Receives metadata only.
/// The host owns transport, background execution and the single serial queue.
final class StandbyVoiceSession {
    enum Command: Equatable { case startAudio, stopAudio, vadStart, vadStop, vadTimeout, text(String), streamText(String, Bool), answer(String, Bool, UUID, String), responseComplete, exit }
    enum Phase: String { case disabled, waitingForConnection, idle, recording, processing, displaying }
    var send: ((String, Command) -> Bool)?
    var log: ((String) -> Void)?
    var phaseChanged: ((Phase) -> Void)?
    var makeText: () -> String = { "待命测试 " + UUID().uuidString.prefix(8) }
    var vadEnabled = false // Set before enabling; legacy fixtures stay unchanged.
    var cloudEnabled = false
    var continuousASREnabled = false // Explicit experimental opt-in, not persisted.
    private(set) var cloudSessionID: UUID?
    private(set) var cloudRoundID: UUID?
    private var sessionDeadline: TimeInterval?
    private var followupWait: (round: UUID, deadline: TimeInterval)?
    private var lastDuplexAudio: TimeInterval?
    private var duplexPackets = 0
    private var endpoint = SpeechEndpointDetector()
    private var noSpeechDeadline: TimeInterval?
    private(set) var target: String?
    private(set) var phase: Phase = .disabled
    private var deadline: TimeInterval?
    private var packets = 0
    private var bytes = 0
    private var response = ""
    private var transcript = ""
    private var transcriptFinal = false
    private var answerBytes = 0
    private var round = 0
    var enabled: Bool { target != nil }
    var active: Bool { phase == .recording || phase == .processing || phase == .displaying }

    func enable(target: String, connected: Bool) {
        disable()
        self.target = target
        setPhase(connected ? .idle : .waitingForConnection)
        log?("持续服务已开启；等待真实唤醒，无90秒arm超时；未请求收音")
    }
    func disable() {
        closeRound(sendExit: true)
        target = nil
        setPhase(.disabled)
    }
    func connection(_ ready: Bool) {
        guard enabled else { return }
        if !ready, phase != .waitingForConnection {
            // No write to an invalid/replaced transport; remote stop not guaranteed.
            deadline = nil
            followupWait = nil
            sessionDeadline = nil; cloudSessionID = nil; cloudRoundID = nil
            setPhase(.waitingForConnection)
            log?("持续服务连接未就绪，本轮取消；未声称远端已停止")
        } else if ready, phase == .waitingForConnection {
            setPhase(.idle)
            log?("持续服务认证连接恢复，回到待命；不自动收音")
        }
    }
    func receive(from source: String, type: UInt32, audioBytes: Int, now: TimeInterval) {
        guard source == target, phase != .waitingForConnection, phase != .disabled else { return }
        if type == 8 {
            log?("眼镜主动type8退出 phase=\(phase.rawValue)；尊重退出，不自动重新点亮")
            closeRound(sendExit: false)
            return
        }
        if type == 3 {
            if continuousASREnabled, active, audioBytes > 0 {
                lastDuplexAudio = now
                if phase != .recording {
                    duplexPackets += 1
                    if duplexPackets == 1 || duplexPackets % 100 == 0 {
                        log?("持续ASR输出期音频 packets=\(duplexPackets) phase=\(phase.rawValue)；只统计长度")
                    }
                }
            }
            guard phase == .recording, audioBytes > 0 else { return }
            packets += 1
            bytes += min(audioBytes, 1_048_576)
            if packets == 1 { log?("持续会话收到首条非空type3；只统计长度，不保存音频") }
            return
        }
        if continuousASREnabled, active, type == 11 {
            // Next-turn request, NOT a render-complete ACK. Completion owns
            // the idle deadline; early/missing/duplicate requests cannot change it.
            log?("持续ASR收到type11 phase=\(phase.rawValue)；不改变回答完成后的静默计时")
            return
        }
        // 0x0B is a next-round event, not permission to start from idle.
        guard type == 1 || (type == 11 && phase == .displaying) else { return }
        guard phase == .idle || phase == .displaying || (cloudEnabled && phase == .processing) else { return }
        deadline = nil // Supersede the old display exit; never closes a newer round.
        followupWait = nil
        endpoint = SpeechEndpointDetector()
        noSpeechDeadline = vadEnabled && !continuousASREnabled ? now + 5 : nil
        packets = 0; bytes = 0; round += 1; response = makeText()
        cloudRoundID = cloudEnabled ? UUID() : nil
        cloudSessionID = cloudRoundID
        sessionDeadline = continuousASREnabled ? now + 120 : nil
        lastDuplexAudio = now; duplexPackets = 0
        transcript = ""; transcriptFinal = false
        answerBytes = 0
        guard write(.startAudio) else { failRound(); return }
        deadline = now + (cloudEnabled ? 20 : 8)
        setPhase(.recording)
        log?("持续会话 round=\(round) type\(type)→type2/rc1；\(cloudEnabled ? 20 : 8)秒上限 cloud=\(cloudEnabled)")
    }
    func vadFrame(speech: Bool, now: TimeInterval) {
        guard vadEnabled, !continuousASREnabled, phase == .recording else { return }
        tick(now:now)
        guard phase == .recording else { return }
        switch endpoint.accept(speech:speech) {
        case .none: break
        case .began: log?("VAD检测到语音开始；120ms/200ms窗口")
        case .ended:
            if cloudEnabled { log?("本地VAD旁路观察到停顿；由云端决定句末，不截断"); return }
            log?("VAD检测到语音结束；连续900ms非语音；提前停止")
            finishRecording(now:now, reply:true)
        }
    }
    func audioDiscontinuity() { endpoint.discontinuity() }
    func audioFailed() {
        guard vadEnabled, (phase == .recording || (continuousASREnabled && active)) else { return }
        log?("VAD解码/分类失败，本轮停止且不生成回答；不是静音判定")
        closeRound(sendExit:true)
    }
    func tick(now: TimeInterval) {
        if continuousASREnabled, active {
            if let sessionDeadline, now >= sessionDeadline {
                log?("持续ASR实验达到120秒上限，停止收音并退出"); closeRound(sendExit:true); return
            }
            if let lastDuplexAudio, now-lastDuplexAudio > 5 {
                log?("持续ASR超过5秒没有音频回调，取消；缺流不当成静音句末"); closeRound(sendExit:true); return
            }
        }
        if phase == .displaying, let wait = followupWait,
           wait.round == cloudRoundID, now >= wait.deadline {
            followupWait = nil
            log?("回答完成后10秒无有效续说→停止音频/退出；服务保留待命")
            if continuousASREnabled, !write(.vadTimeout) { failRound(); return }
            closeRound(sendExit:true)
            return
        }
        if vadEnabled, phase == .recording, !endpoint.hasSpeech,
           let noSpeechDeadline, now >= noSpeechDeadline {
            log?("VAD等待5秒未确认语音，退出且不生成回答")
            closeRound(sendExit:true)
            return
        }
        guard let deadline, now >= deadline else { return }
        self.deadline = nil
        if phase == .recording {
            if cloudEnabled {
                log?("云对话达到20秒收音保护；取消本轮，不把超时当云句末")
                closeRound(sendExit:true)
                return
            }
            if vadEnabled { log?("VAD达到8秒保护上限；不是检测到句末") }
            finishRecording(now:now, reply:!vadEnabled || endpoint.hasSpeech)
        } else if phase == .processing {
            log?("云对话处理超过30秒，取消并退出")
            closeRound(sendExit:true)
        } else if phase == .displaying {
            guard write(.exit) else { failRound(); return }
            setPhase(.idle)
            log?("持续会话type7退出已提交，服务仍开启，等待下次唤醒")
        }
    }
    func cloudEndpoint(id: UUID, now: TimeInterval) {
        guard cloudEnabled, cloudRoundID == id, phase == .recording else { return }
        guard write(continuousASREnabled ? .vadStop : .stopAudio) else { failRound(); return }
        deadline = now + 30
        setPhase(.processing)
        log?(continuousASREnabled ? "云ASR句末→type4/rc2；持续收音并行等待模型，不结束ASR任务" : "云ASR句末→type2/rc2停止收音，等待云回答；音频不落盘")
    }
    func cloudUtteranceBegan(id: UUID, session: UUID, now: TimeInterval) {
        guard continuousASREnabled, cloudEnabled, active, cloudSessionID == session,
              cloudRoundID != id else { return }
        let interrupting = phase == .processing || phase == .displaying
        if followupWait != nil { log?("有效新句取消旧轮续说退出计时") }
        followupWait = nil
        cloudRoundID = id; transcript = ""; transcriptFinal = false; answerBytes = 0
        deadline = now + 20
        guard write(.vadStart) else { failRound(); return }
        setPhase(.recording)
        log?("云起句→type4/rc1，更新回答代际 interrupting=\(interrupting)；ASR会话保持，不用本地VAD")
    }
    func cloudEmptyUtterance(id: UUID, now: TimeInterval) {
        guard continuousASREnabled, cloudRoundID == id, phase == .recording else { return }
        // Reached only if earlier partial text already committed a new turn.
        // An empty final retracts it; do not invent a final or leave loading.
        log?("有效临时文字后云端空句撤回，退出本轮避免loading；不拿临时文字生成回答")
        closeRound(sendExit:true)
    }
    func cloudTranscript(_ text: String, final: Bool, id: UUID) {
        guard cloudEnabled, cloudRoundID == id, phase == .recording, !transcriptFinal,
              !text.isEmpty, text.utf8.count <= 512 else { return }
        guard write(.streamText(text,final)) else { failRound(); return }
        transcript = text; transcriptFinal = final
        log?("云识别type5提交 utf8Bytes=\(text.utf8.count) wireKey=final final=\(final)；正文不入日志")
    }
    func cloudText(_ text: String, final: Bool, id: UUID, now: TimeInterval) {
        guard cloudEnabled, cloudRoundID == id, phase == .processing,
              (!text.isEmpty || (final && answerBytes > 0)), text.utf8.count <= 512 else { return }
        guard answerBytes + text.utf8.count <= 8192 else { failRound(); return }
        // Cloud EOF is NOT the wire answer.isFinal flag. Official successful
        // workflow/chat sessions sent only false text chunks, then type12.
        // An empty EOF flush must not invent an empty wire-final packet.
        if !text.isEmpty {
            guard write(.answer(text, false, id, transcript)) else { failRound(); return }
            answerBytes += text.utf8.count
            // Processing timeout measures a stalled stream, not total answer length.
            deadline = now + 30
            log?("增量回答type32提交 chunkBytes=\(text.utf8.count) totalBytes=\(answerBytes) wireFinal=false cloudEOF=\(final)；正文不入日志")
        }
        if final { cloudComplete(id:id,now:now) }
    }
    func cloudComplete(id: UUID, now: TimeInterval) {
        guard cloudEnabled, cloudRoundID == id, phase == .processing, answerBytes > 0 else { return }
        guard write(.responseComplete) else { failRound(); return }
        deadline = nil
        // The coalescer has flushed all deltas before this call. This is SDK
        // submission completion, not a lens render ACK. Never start at first token.
        followupWait = (id, now + 10)
        setPhase(.displaying)
        log?("workflow回答type12完成已提交；启动10秒静默退出，有效新句取消；非镜片渲染回执")
    }
    func cloudFailed(id: UUID) {
        guard cloudRoundID == id || cloudSessionID == id, active else { return }
        log?("云对话失败或取消，退出本轮；不伪造模型回答")
        closeRound(sendExit:true)
    }
    private func finishRecording(now: TimeInterval, reply: Bool) {
        deadline = nil
        guard write(.stopAudio) else { failRound(); return }
        log?("持续会话type2/rc2已提交 packets=\(packets) dataBytes=\(bytes) 音频保存=0")
        guard reply, packets > 0, bytes > 0 else { closeRound(sendExit:true); return }
        guard write(.text(response)) else { failRound(); return }
        deadline = now + 10
        setPhase(.displaying)
        log?("持续会话type5合成随机文字已提交，显示10秒；不是识别或模型回答")
    }
    func executionExpired() {
        guard active else { return }
        log?("系统后台执行时间到期，停止本轮，保留待命意图；后台运行不保证")
        closeRound(sendExit: true)
    }
    func cancelCurrentRound() { if active { closeRound(sendExit:true) } }
    private func closeRound(sendExit: Bool) {
        let wasActive = active
        var ok = true
        if phase == .recording || (continuousASREnabled && wasActive) { ok = write(.stopAudio) }
        if wasActive && sendExit { ok = write(.exit) && ok }
        deadline = nil
        cloudRoundID = nil
        followupWait = nil
        cloudSessionID = nil; sessionDeadline = nil; lastDuplexAudio = nil
        answerBytes = 0
        if enabled { setPhase(ok ? .idle : .waitingForConnection) }
        if !ok { log?("持续会话停止/退出提交失败；需要连接复核，不声称远端已停止") }
    }
    private func failRound() {
        // Best-effort bounded cleanup; no repeated sends or automatic recording.
        _ = write(.stopAudio); _ = write(.exit)
        deadline = nil
        cloudRoundID = nil
        followupWait = nil
        cloudSessionID = nil; sessionDeadline = nil; lastDuplexAudio = nil
        answerBytes = 0
        setPhase(.waitingForConnection)
        log?("持续会话发送失败，取消本轮并等待连接复核")
    }
    private func write(_ command: Command) -> Bool {
        guard let target else { return false }
        return send?(target, command) ?? false
    }
    private func setPhase(_ value: Phase) {
        guard phase != value else { return }
        phase = value
        phaseChanged?(value)
    }
}

/// Bounded retries of an already bonded target. No scanning, pairing or unbind.
struct StandbyReconnectPolicy {
    private(set) var attempts = 0
    private var next: TimeInterval = 0
    mutating func reset() { attempts = 0; next = 0 }
    mutating func shouldAttempt(now: TimeInterval, eligible: Bool) -> Bool {
        guard eligible, attempts < 8, now >= next else { return false }
        next = now + [5.0, 10, 20, 40, 60, 60, 60, 60][attempts]
        attempts += 1
        return true
    }
}
