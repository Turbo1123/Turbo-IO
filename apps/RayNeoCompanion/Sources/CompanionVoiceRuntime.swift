import SwiftUI
import Combine

@MainActor final class CompanionVoiceRuntime: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var enabled = false
    @Published private(set) var phase = "disabled"
    @Published private(set) var transcript = ""
    @Published private(set) var answer = ""
    @Published private(set) var transcriptFinal = false
    @Published private(set) var modelComplete = false
    @Published private(set) var hasCredentials = false
    @Published private(set) var continuous = false
    @Published private(set) var cloud = false
    @Published private(set) var latestEvent = "尚未加载设备通信核心"
    @Published var error: String?
    private let timeline: ConversationTimeline?
    weak var codex: CodexCompanion?
    private var activeTurn: UUID?
    var onBusiness: ((String, UInt8, Data) -> Void)?
    var onBusinessLoss: (() -> Void)?
    var featureIsBusy: (() -> Bool)?
    var onConnectionChange: ((String?) -> Void)?
    var onRuntimeRefresh: (() -> Void)?
    private var previousDeviceID: String?
    var deviceID: String? {
        #if COMPANION_DEVICE
        return controller.companionDeviceID
        #else
        return nil
        #endif
    }
    func sendBusiness(_ index: UInt8, payload: Data) throws {
        #if COMPANION_DEVICE
        prepare(); try controller.companionSendBusiness(index, payload: payload)
        #else
        throw DeviceFeatureError.disconnected
        #endif
    }
    func sendFile(_ url: URL, id: String) throws -> String {
        #if COMPANION_DEVICE
        return try controller.companionSendFile(url,id:id)
        #else
        throw DeviceFeatureError.disconnected
        #endif
    }
    func cancelFile(_ task: String) {
        #if COMPANION_DEVICE
        controller.companionCancelFile(task)
        #endif
    }
    init(timeline: ConversationTimeline? = nil) { self.timeline = timeline }
    deinit {
        #if COMPANION_DEVICE
        poll?.invalidate()
        #endif
    }
    #if COMPANION_DEVICE
    let controller = ProbeController()
    private var poll: Timer?
    #endif
    var supportsDevice: Bool {
        #if COMPANION_DEVICE
        return true
        #else
        return false
        #endif
    }
    var phaseLabel: String {
        ["disabled": "待命已关闭", "waitingForConnection": "等待认证连接", "idle": "等待眼镜唤醒",
         "recording": "正在听你说", "processing": "正在生成回答", "displaying": "回答已发完，可继续说"] [phase] ?? "等待状态"
    }
    func prepare() {
        #if COMPANION_DEVICE
        guard poll == nil else { refresh(); return }
        controller.companionBusiness = { [weak self] in self?.onBusiness?($0,$1,$2) }
        controller.companionTools = { [weak self] in self?.codex?.toolDefinitions ?? [] }
        controller.companionExecuteTool = { [weak self] name, arguments, id in
            guard let codex = self?.codex else { return "Codex工具未配置，未执行。" }
            return await codex.executeTool(name: name, arguments: arguments, requestID: id)
        }
        controller.companionBusinessLoss = { [weak self] in self?.onBusinessLoss?() }
        controller.companionLog = { [weak self] line in self?.latestEvent = String(line.prefix(200)) }
        controller.companionTranscript = { [weak self] id, text, final in
            guard let self, !text.isEmpty else { return }
            if self.activeTurn != id { self.finishTimelineTurn(); self.activeTurn = id }
            self.timeline?.record(ConversationEvent(id: id, kind: .transcript, text: text, final: final))
        }
        controller.companionCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .startAudio, .vadStart:
                DisplayObservation.shared.newUtterance()
                self.finishTimelineTurn()
                self.clearText()
            case .streamText(let text, let final): self.transcript = text; self.transcriptFinal = final
            case .text(let text): self.answer = text
            case .answer(let text, _, let id, _):
                self.answer = String((self.answer + text).prefix(8192))
                self.timeline?.record(ConversationEvent(id: id, kind: .answerDelta, text: text))
            case .responseComplete:
                self.modelComplete = true
                if let id = self.activeTurn { self.timeline?.record(ConversationEvent(id: id, kind: .completed)) }
            default: break
            }
        }
        controller.loadViewIfNeeded()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        poll = timer; RunLoop.main.add(timer, forMode: .common); refresh()
        #endif
    }
    func refresh() {
        #if COMPANION_DEVICE
        ready = controller.companionReady; enabled = controller.companionEnabled
        phase = controller.companionPhase; hasCredentials = CloudVoiceKeys.ready
        DisplayObservation.shared.connection(ready, phase:phase)
        if ["disabled", "waitingForConnection", "idle"].contains(phase) { finishTimelineTurn() }
        continuous = controller.companionContinuous; cloud = controller.companionCloud
        let current = deviceID
        if previousDeviceID != current { previousDeviceID = current; onConnectionChange?(current) }
        onRuntimeRefresh?()
        #endif
    }
    func discover() {
        #if COMPANION_DEVICE
        prepare(); controller.companionDiscover(); refresh()
        #endif
    }
    func connect() {
        #if COMPANION_DEVICE
        prepare(); controller.companionConnect(); refresh()
        #endif
    }
    func reconnectBonded() {
        #if COMPANION_DEVICE
        prepare(); controller.companionReconnectBonded(); refresh()
        #endif
    }
    func start(cloud: Bool, continuous: Bool) {
        guard featureIsBusy?() != true else { error = "请先结束眼镜录音或提词器任务，再开启语音待命。"; return }
        #if COMPANION_DEVICE
        prepare()
        guard controller.companionStart(cloud: cloud, continuous: continuous) else {
            error = "需要唯一已认证的眼镜；云对话还需要本 App 的两项密钥。"; refresh(); return
        }
        refresh()
        #endif
    }
    func stop() {
        #if COMPANION_DEVICE
        controller.companionStop(); refresh()
        #endif
    }
    func endRound() {
        #if COMPANION_DEVICE
        controller.companionEndRound(); refresh()
        #endif
    }
    func saveKeys(asr: String, llm: String, host: String, enableDefault: Bool = false) -> Bool {
        #if COMPANION_DEVICE
        guard !enabled else { error = "请先关闭待命，再修改云端凭据。"; return false }
        guard let target = CloudASRHostSettings.normalize(host) else { error = "请填写自己的阿里云 ASR 主机名（aliyuncs.com），不含协议、路径或端口。"; return false }
        let service = CloudASRHostSettings.service(for: target)
        let a = asr.isEmpty ? CloudVoiceKeys.get(service) != nil : CloudVoiceKeys.save(asr, service: service)
        let b = llm.isEmpty ? CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil : CloudVoiceKeys.save(llm, service: CloudVoiceKeys.llmService)
        if a && b {
            CloudASRHostSettings.save(target)
            if enableDefault { controller.companionEnableDefaultCloudVoice() }
        }
        refresh()
        if !a || !b { error = "密钥未完整保存；没有启用云上传。" }
        return a && b
        #else
        error = "模拟器不保存真机语音凭据。"; return false
        #endif
    }
    func clearText() { transcript = ""; answer = ""; transcriptFinal = false; modelComplete = false }
    private func finishTimelineTurn() {
        if let id = activeTurn { timeline?.record(ConversationEvent(id: id, kind: .interrupted)); activeTurn = nil }
    }
}

#if COMPANION_DEVICE
struct VoiceDiagnosticsView: UIViewControllerRepresentable {
    let runtime: CompanionVoiceRuntime
    func makeUIViewController(context: Context) -> ProbeController { runtime.prepare(); return runtime.controller }
    func updateUIViewController(_ controller: ProbeController, context: Context) {}
}
#endif
