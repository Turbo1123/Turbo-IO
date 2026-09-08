import Foundation
import UIKit
import RayNeoProtocol

/// Main queue only. Standby VAD decodes bounded audio in memory only.
/// Legacy one-shot fixtures remain metadata-only; no disk/network audio output.
final class VoiceHandshakeProbe {
    var log: ((String) -> Void)?
    var send: ((String, Data) throws -> Void)?
    // Ephemeral presentation only; reports accepted send submission, not lens ACK.
    var onSubmittedCommand: ((StandbyVoiceSession.Command) -> Void)?
    var onArchiveTranscript: ((UUID,String,Bool) -> Void)?
    let standby = StandbyVoiceSession()
    private let cloud = CloudVoicePipeline()
    var cloudTools: (() -> [[String: Any]])? { didSet { cloud.toolDefinitions = cloudTools } }
    var executeCloudTool: ((String, String, UUID) async -> String)? { didSet { cloud.executeTool = executeCloudTool } }
    private var incrementalFixtureUntil: TimeInterval?
    private var nativeVAD = RNVoiceVADCreate()
    private var vadPackets = 0
    private var vadFrames = 0
    private var vadVoiced = 0
    private var lastAudioArrival: TimeInterval?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var deviceID: String?
    private var nonce: UUID?
    private var recording = false
    private var packets = 0
    private var bytes = 0
    private var auditDeviceID: String?
    private var postStopPackets = 0
    private var auditGeneration: UUID?
    private var deadline: DispatchWorkItem?
    private var pendingExit: DispatchWorkItem?
    private var backgroundObserver: NSObjectProtocol?
    private var text = ""
    private var displaySeconds: TimeInterval = 3

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object:nil, queue:.main) { [weak self] _ in
                if self?.standby.enabled != true { self?.stopDisplayTest() }
            }
        standby.log = { [weak self] in self?.log?($0) }
        cloud.log = { [weak self] in self?.log?($0) }
        cloud.onArchiveTranscript = { [weak self] id, text, final in self?.onArchiveTranscript?(id,text,final) }
        cloud.onEndpoint = { [weak self] id in self?.standby.cloudEndpoint(id:id,now:ProcessInfo.processInfo.systemUptime) }
        cloud.onTranscript = { [weak self] id, text, final in self?.standby.cloudTranscript(text,final:final,id:id) }
        cloud.onText = { [weak self] id, text, final in self?.standby.cloudText(text,final:final,id:id,now:ProcessInfo.processInfo.systemUptime) }
        cloud.onError = { [weak self] id in self?.standby.cloudFailed(id:id) }
        cloud.onUtteranceBegan = { [weak self] turn, session in
            self?.standby.cloudUtteranceBegan(id:turn,session:session,now:ProcessInfo.processInfo.systemUptime)
        }
        cloud.onEmptyUtterance = { [weak self] id in
            self?.standby.cloudEmptyUtterance(id:id,now:ProcessInfo.processInfo.systemUptime)
        }
        standby.send = { [weak self] target, command in
            guard let send = self?.send else { return false }
            do {
                let payload: Data
                switch command {
                case .startAudio: payload = AssistantRecorderPrototype.control(start:true)
                case .stopAudio: payload = AssistantRecorderPrototype.control(start:false)
                case .vadStart: payload = AssistantVADPrototype.status(.start)
                case .vadStop: payload = AssistantVADPrototype.status(.stop)
                case .vadTimeout: payload = AssistantVADPrototype.status(.timeout)
                case .text(let text): payload = try AssistantTextPrototype.asrText(text, isFinal:true)
                case .streamText(let text, let final): payload = try AssistantTextPrototype.asrText(text,isFinal:final)
                case .answer(let text, let final, let id, let query):
                    payload = try AssistantAnswerPrototype.chat(text,isFinal:final,roundID:id,query:query,
                        timestampMilliseconds:Int64(Date().timeIntervalSince1970 * 1000))
                case .responseComplete: payload = AssistantResponseCompletePrototype.complete()
                case .exit: payload = AssistantExitPrototype.normalExit()
                }
                try send(target, payload)
                self?.onSubmittedCommand?(command)
                return true
            } catch { return false }
        }
        standby.phaseChanged = { [weak self] phase in
            guard let self else { return }
            if phase == .recording {
                let sameASR = self.standby.continuousASREnabled && self.cloud.id != nil && self.cloud.id == self.standby.cloudSessionID
                if !sameASR {
                    self.vadPackets = 0; self.vadFrames = 0; self.vadVoiced = 0
                    self.lastAudioArrival = nil
                }
                if self.standby.vadEnabled && !sameASR {
                    let rc = RNVoiceVADReset(self.nativeVAD)
                    self.log?(self.standby.continuousASREnabled ? "持续ASR Opus解码器初始化 rc=\(rc)；只解码，不做本地VAD分类" : "VAD本地初始化 rc=\(rc) Opus输出16k/mono WebRTC模式2；PCM不落盘")
                    if rc != 0 {
                        self.standby.audioFailed()
                        return
                    }
                }
                if let id = self.standby.cloudSessionID, self.standby.cloudEnabled, !sameASR {
                    if let until = self.incrementalFixtureUntil, ProcessInfo.processInfo.systemUptime <= until {
                        self.incrementalFixtureUntil = nil
                        self.runIncrementalFixture(id:id)
                    } else {
                        self.incrementalFixtureUntil = nil
                        self.cloud.start(id:id)
                    }
                }
            } else if self.vadPackets > 0 && !self.standby.continuousASREnabled {
                self.log?("VAD本轮摘要 packets=\(self.vadPackets) frames10ms=\(self.vadFrames) voiced=\(self.vadVoiced)；无音频正文")
                self.vadPackets = 0
            }
            if phase == .displaying, self.standby.cloudEnabled, !self.standby.continuousASREnabled {
                // Output is complete on the phone. Do not keep a background
                // task whose expiry could close a still-rendering lens page.
                self.cloud.cancel()
                self.endBackgroundTask()
            } else if phase == .recording || phase == .processing || phase == .displaying {
                if self.backgroundTask == .invalid {
                    self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName:"RayNeo synthetic voice round") { [weak self] in
                        self?.standby.executionExpired()
                        self?.endBackgroundTask()
                    }
                }
            } else {
                self.cloud.cancel(clearHistory:phase == .disabled || phase == .waitingForConnection)
                self.endBackgroundTask()
            }
        }
    }
    func armIncrementalFixture() {
        guard standby.enabled, standby.cloudEnabled, standby.phase == .idle, !standby.continuousASREnabled else {
            log?("增量分段测试需要旧云模式已连接等待唤醒；请先关闭持续ASR实验"); return
        }
        incrementalFixtureUntil = ProcessInfo.processInfo.systemUptime + 90
        log?("下一次90秒内唤醒：A1-A4全为wireFinal=false，第12秒独立type12；不上云、不保存音频")
    }
    private func runIncrementalFixture(id: UUID) {
        cloud.cancel()
        let marker = String(id.uuidString.prefix(4))
        log?("合成增量测试开始 marker=\(marker)；只发送固定非私密文本，未启动ASR/模型请求")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self] in
            guard let self, self.standby.cloudRoundID == id, self.standby.phase == .recording else { return }
            self.standby.cloudTranscript("分段测试 \(marker)",final:true,id:id)
            self.standby.cloudEndpoint(id:id,now:ProcessInfo.processInfo.systemUptime)
        }
        let chunks = ["A1：这是第一段，只应出现一次。", "A2：这是第二段，请观察是否接在后面。",
                      "A3：这是第三段，前面的内容不应重播。", "A4：尾部校验 \(marker)，完整结束。"]
        for (index, text) in chunks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline:.now()+1+Double(index)*2) { [weak self] in
                guard let self, self.standby.cloudRoundID == id, self.standby.phase == .processing else { return }
                self.log?("合成分段提交 index=\(index+1)/4 marker=\(marker)")
                self.standby.cloudText(text,final:false,id:id,now:ProcessInfo.processInfo.systemUptime)
            }
        }
        // Diagnostic separation only, not a production reading-time estimate.
        // A4 at +7s, completion at +12s: correlate lens exit to either event.
        DispatchQueue.main.asyncAfter(deadline:.now()+12) { [weak self] in
            guard let self, self.standby.cloudRoundID == id, self.standby.phase == .processing else { return }
            self.log?("合成分段独立完成 marker=\(marker)；距A4计划5秒，发送type12")
            self.standby.cloudComplete(id:id,now:ProcessInfo.processInfo.systemUptime)
        }
    }
    deinit {
        cloud.cancel()
        RNVoiceVADDestroy(nativeVAD)
        deadline?.cancel()
        pendingExit?.cancel()
        endBackgroundTask()
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
    }
    func arm(deviceID: String, fixture: DisplayBoundaryFixture? = nil) {
        precondition(Thread.isMainThread)
        guard !standby.enabled else { log?("请先关闭持续待命再做单项显示测试"); return }
        guard nonce == nil, auditDeviceID == nil else { log?("语音测试已就绪/进行中/检查停止，不重复开启"); return }
        let id = UUID()
        // Synthetic response, never a transcript or model answer. New value for
        // each explicitly armed run lets the wearer detect stale lens content.
        text = fixture?.text ?? ("测试 " + id.uuidString.prefix(8))
        displaySeconds = fixture == nil ? 3 : 10
        if let fixture {
            log?("显示边界 case=\(fixture.id) utf8Bytes=\(fixture.text.utf8.count) lines=\(fixture.text.split(separator:"\n", omittingEmptySubsequences:false).count) holdSeconds=10；合成固定内容，未发送")
        }
        nonce = id; self.deviceID = deviceID; recording = false; packets = 0; bytes = 0
        let timeout = DispatchWorkItem { [weak self] in
            guard self?.nonce == id else { return }
            self?.finish(reason:"90秒内未收到主动唤醒", display:false)
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline:.now()+90, execute:timeout)
        log?("一次性语音测试已就绪：等待真实type1唤醒，90秒过期；尚未请求收音")
    }
    func receive(deviceID: String, metadata: BusinessEnvelopeMetadata, audio: Data? = nil,
                 arrival: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        precondition(Thread.isMainThread)
        if standby.enabled {
            standby.receive(from:deviceID, type:metadata.messageType ?? 0,
                audioBytes:metadata.dataBytes ?? 0, now:ProcessInfo.processInfo.systemUptime)
            if standby.vadEnabled, (standby.phase == .recording || (standby.continuousASREnabled && standby.active)),
               standby.target == deviceID, metadata.messageType == 3 {
                processAudio(audio, arrival:arrival)
            }
            return
        }
        if auditDeviceID == deviceID, [UInt32(1), 8, 11].contains(metadata.messageType ?? 0), pendingExit != nil {
            pendingExit?.cancel(); pendingExit = nil
            log?("收到新唤醒/轮次或眼镜退出，取消旧会话的延时退出")
        }
        if nonce == nil, auditDeviceID == deviceID, metadata.messageType == 3 {
            postStopPackets += 1
        }
        guard nonce != nil, self.deviceID == deviceID else { return }
        if metadata.messageType == 1 && !recording {
            guard let send else { finish(reason:"无发送路径", display:false); return }
            do { try send(deviceID, AssistantRecorderPrototype.control(start:true)) }
            catch { finish(reason:"开始命令发送失败", display:false); return }
            recording = true
            log?("收到真实唤醒，已发type2 rc=1；最多8秒，等待真实type3音频")
            deadline?.cancel()
            let id = nonce
            let timeout = DispatchWorkItem { [weak self] in
                guard self?.nonce == id else { return }
                self?.finish(reason:"8秒测试到时", display:true)
            }
            deadline = timeout
            DispatchQueue.main.asyncAfter(deadline:.now()+8, execute:timeout)
        } else if metadata.messageType == 3 && recording {
            packets += 1; bytes += metadata.dataBytes ?? 0
            if packets == 1 { log?("独立测试收到首条type3，dataBytes=\(metadata.dataBytes ?? 0)；正文不保存") }
        } else if metadata.messageType == 8 {
            finish(reason:"眼镜主动退出", display:false)
        }
    }
    func finish(reason: String, display: Bool) {
        precondition(Thread.isMainThread)
        guard nonce != nil else {
            pendingExit?.cancel(); pendingExit = nil
            return
        }
        deadline?.cancel(); deadline = nil
        let wasRecording = recording, target = deviceID
        nonce = nil; deviceID = nil; recording = false
        if wasRecording, let target, let send {
            auditDeviceID = target; postStopPackets = 0
            do {
                try send(target, AssistantRecorderPrototype.control(start:false))
                log?("已发type2 rc=2停止请求；仍需检查眼镜后续音频是否停止")
            } catch { log?("停止请求未成功提交，不能认定远端已停止；请退出眼镜语音界面") }
            if display && packets > 0 && bytes > 0 {
                do {
                    try send(target, AssistantTextPrototype.asrText(text,isFinal:true))
                    log?("已发type5合成测试文字 utf8Bytes=\(text.utf8.count) holdSeconds=\(Int(displaySeconds))；不是识别或模型结果，显示待确认")
                    let exit = DispatchWorkItem { [weak self] in
                        guard let self, self.auditDeviceID == target, let send = self.send else { return }
                        self.pendingExit = nil
                        do {
                            try send(target, AssistantExitPrototype.normalExit())
                            self.log?("显示保持期结束，已发type7 rc=1正常退出；眼镜页面自动隐藏待确认")
                        } catch { self.log?("正常退出命令未成功提交；请手动退出眼镜语音界面") }
                    }
                    pendingExit = exit
                    DispatchQueue.main.asyncAfter(deadline:.now()+displaySeconds, execute:exit)
                } catch { log?("固定文字未成功提交") }
            } else if display {
                log?("没有观察到非空type3音频，不发送随机回答，不认定语音上行通过")
                do { try send(target, AssistantExitPrototype.normalExit()) }
                catch { log?("无音频测试退出未成功提交；请手动退出眼镜语音界面") }
            }
            let auditSeconds = max(5, displaySeconds + 2)
            let auditID = UUID()
            auditGeneration = auditID
            DispatchQueue.main.asyncAfter(deadline:.now()+auditSeconds) { [weak self] in
                guard let self, self.auditGeneration == auditID else { return }
                self.log?("停止后\(Int(auditSeconds))秒观察：新增type3=\(self.postStopPackets)；仅统计回调，不声称麦克风电气状态")
                self.auditDeviceID = nil
                self.auditGeneration = nil
            }
        }
        log?("一次性语音测试结束：\(reason)，type3观察数=\(packets)，data总字节=\(bytes)，音频保存=0")
    }

    func stopDisplayTest() {
        precondition(Thread.isMainThread)
        finish(reason:"手动结束显示测试", display:false)
        if let target = auditDeviceID, let send {
            pendingExit?.cancel(); pendingExit = nil
            do { try send(target, AssistantExitPrototype.normalExit()) }
            catch { log?("手动退出请求失败；请用眼镜按钮退出") }
        }
    }

    func enableStandby(deviceID: String) {
        stopDisplayTest()
        // Cancel the old audit identity before switching ownership to the service.
        auditDeviceID = nil
        auditGeneration = nil
        standby.vadEnabled = true
        standby.enable(target:deviceID, connected:true)
    }
    func setCloudMode(_ enabled: Bool) {
        standby.cancelCurrentRound()
        cloud.cancel(clearHistory:true)
        standby.cloudEnabled = enabled
        standby.continuousASREnabled = false; cloud.continuousASR = false
        log?(enabled ? "云模式已开启：音频→用户阿里云，文字→DeepSeek；云端句末，不用本地900ms截断" : "云模式关闭：回到本地VAD随机文字，不上传")
    }
    func setContinuousASR(_ enabled: Bool) {
        guard !enabled || (standby.enabled && standby.cloudEnabled) else {
            log?("持续ASR实验需要已连接待命和用户云模式"); return
        }
        standby.cancelCurrentRound(); cloud.cancel()
        incrementalFixtureUntil = nil
        standby.continuousASREnabled = enabled; cloud.continuousASR = enabled
        log?(enabled ? "持续ASR并行实验已启用：下次唤醒持续音频→用户ASR，云起句打断，句末并行模型；无本地VAD，120秒保护" : "持续ASR实验已关闭，恢复已验收的轮流对话")
    }
    private func processAudio(_ audio: Data?, arrival: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        // Lost/delayed transport is not silence; don't endpoint on missing data.
        guard now - arrival <= 0.5 else { standby.audioDiscontinuity(); return }
        if let previous = lastAudioArrival, arrival - previous > 0.2 {
            standby.audioDiscontinuity()
        }
        lastAudioArrival = arrival
        guard let audio, !audio.isEmpty else { standby.audioFailed(); return }
        var mask: UInt32 = 0
        var pcm = [Int16](repeating:0,count:1920)
        let frames = audio.withUnsafeBytes { bytes in
            if standby.cloudEnabled {
                return pcm.withUnsafeMutableBufferPointer { samples in
                    if standby.continuousASREnabled {
                        return RNVoiceDecodePCM(nativeVAD,bytes.bindMemory(to:UInt8.self).baseAddress,bytes.count,samples.baseAddress,samples.count)
                    }
                    return RNVoiceVADProcessPCM(nativeVAD,bytes.bindMemory(to:UInt8.self).baseAddress,bytes.count,&mask,samples.baseAddress,samples.count)
                }
            }
            return RNVoiceVADProcess(nativeVAD, bytes.bindMemory(to:UInt8.self).baseAddress, bytes.count, &mask)
        }
        guard frames > 0, frames <= 12 else {
            log?("VAD音频处理失败 rc=\(frames) packetBytes=\(audio.count)；不保存坏包")
            standby.audioFailed(); return
        }
        vadPackets += 1; vadFrames += Int(frames); vadVoiced += mask.nonzeroBitCount
        if vadPackets == 1 { log?("VAD首包解码成功 packetBytes=\(audio.count) samples=\(frames * 160) frames10ms=\(frames)") }
        if standby.cloudEnabled {
            let data = pcm.withUnsafeBytes { Data($0.prefix(Int(frames) * 160 * 2)) }
            cloud.appendPCM(data)
        }
        guard !standby.continuousASREnabled else { return }
        for index in 0..<Int(frames) {
            standby.vadFrame(speech:(mask & (1 << index)) != 0, now:now)
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}
