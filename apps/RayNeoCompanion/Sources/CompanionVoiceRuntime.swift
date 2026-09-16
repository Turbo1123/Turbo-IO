import SwiftUI
import Combine
import Security
import RayNeoProtocol
import RayNeoSession

@MainActor final class CompanionVoiceRuntime: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var enabled = false
    @Published private(set) var phase = "disabled"
    @Published private(set) var initialSpeechSeconds: Int?
    @Published private(set) var transcript = ""
    @Published private(set) var answer = ""
    @Published private(set) var transcriptFinal = false
    @Published private(set) var modelComplete = false
    @Published private(set) var hasCredentials = false
    @Published private(set) var continuous = false
    @Published private(set) var cloud = false
    @Published private(set) var backendSelection = ConversationBackendSelection()
    @Published private(set) var answerBackend: ConversationBackend?
    @Published private(set) var textBusy = false
    @Published private(set) var hermesEndpoint = UserDefaults.standard.string(forKey: "companion.hermes.v1.endpoint") ?? ""
    @Published private(set) var hermesStatus = "尚未检查 Hermes 桥接"
    @Published private(set) var checkingHermes = false
    @Published private var hermesOperations = 0
    @Published private(set) var hermesTask: HermesTaskState?
    @Published private(set) var hermesTaskBusy = false
    @Published private(set) var hermesTaskUnresolved = false
    @Published private(set) var hermesDecisionUnconfirmed = false
    @Published private(set) var hermesTaskProblem: String?
    private var hermesTaskClient: HermesTaskClient?
    private var hermesPolling: Task<Void, Never>?
    private var typedTask: Task<Void, Never>?
    private var typedHistory: [[String: String]] = []
    var selectedBackend: ConversationBackend { backendSelection.selected }
    var canConfigureConversation: Bool { canEditHermesConfiguration && !hermesTaskUnresolved }
    var canEditHermesConfiguration: Bool { !enabled && !textBusy && hermesOperations == 0 && !checkingHermes && !hermesTaskBusy }
    var canStartStandby: Bool { !enabled && !textBusy && hermesOperations == 0 && !checkingHermes }
    var modelConfigured: Bool {
        selectedBackend == .hermes ? ConversationCredentials.hermes(hermesEndpoint) != nil : ConversationCredentials.deepSeek != nil
    }
    @Published private(set) var latestEvent = "尚未加载设备通信核心"
    @Published private(set) var wakeDiagnostics: [String] = []
    @Published private(set) var wakeSettingsDiagnostics: [String] = []
    @Published private(set) var wakeSettingsStatus = "尚未查询眼镜唤醒设置"
    @Published private(set) var queryingWakeSettings = false
    private var wakeSettingsDeadline: TimeInterval?
    private var launchWakeSettingsQuery = ProcessInfo.processInfo.arguments.contains("--wake-settings-diagnostic") || ProcessInfo.processInfo.arguments.contains("--wake-word-data-trial")
    private let wakeSettingsStartupDeadline = ProcessInfo.processInfo.systemUptime + 30
    @Published private(set) var wakeWordTrial = WakeWordDataTrial()
    @Published private(set) var wakeWordTrialStatus = "尚未试写自定义唤醒词"
    private var launchWakeWordDataTrial = ProcessInfo.processInfo.arguments.contains("--wake-word-data-trial")
    private var launchConfirmWakeRestored = ProcessInfo.processInfo.arguments.contains("--wake-word-confirm-restored")
    private var wakeWordObservationDeadline: TimeInterval?
    private static let trialRecoveryKey = "norman.wakeWordDataTrial.v1.recoveryTarget"
    private static let trialAttemptedKey = "norman.wakeWordDataTrial.v1.attempted"
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
    init(timeline: ConversationTimeline? = nil) {
        self.timeline = timeline
        if let saved = UserDefaults.standard.string(forKey: "companion.conversation.v1.backend"), let backend = ConversationBackend(rawValue: saved) {
            backendSelection = ConversationBackendSelection(selected: backend)
        }
        wakeWordTrial = WakeWordDataTrial(recoveryTarget: UserDefaults.standard.string(forKey: Self.trialRecoveryKey), attempted: UserDefaults.standard.bool(forKey: Self.trialAttemptedKey))
        if wakeWordTrial.target != nil { wakeWordTrialStatus = "上次试验尚未确认恢复；连接同一眼镜后提交原参数" }
        else if wakeWordTrial.attempted { wakeWordTrialStatus = "本项试验已执行；不会再次自动试写" }
    }
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
        restoreHermesTask()
        #if COMPANION_DEVICE
        guard poll == nil else { refresh(); return }
        controller.companionBusiness = { [weak self] id, business, packet in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let observingStartup = self.launchWakeSettingsQuery && now < self.wakeSettingsStartupDeadline
            let observingTrial = self.wakeWordTrial.target == id && self.wakeWordObservationDeadline.map({ now < $0 }) == true
            if business == 15, id == self.deviceID,
               observingStartup || observingTrial || self.wakeSettingsDeadline.map({ now < $0 }) == true,
               let summary = try? BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet) {
                let stage = observingTrial ? (self.wakeWordTrial.phase == .testing ? "trial " : "restore ") : (observingStartup ? "startup " : "")
                let line = stage + summary
                self.wakeSettingsDiagnostics.append(line)
                self.wakeSettingsDiagnostics = Array(self.wakeSettingsDiagnostics.suffix(6))
                NSLog("[WakeSettingsDiagnostic] %@", line)
            }
            self.onBusiness?(id, business, packet)
        }
        controller.companionTools = { [weak self] in self?.codex?.toolDefinitions ?? [] }
        controller.companionModelBackend = { [weak self] in self?.selectedBackend ?? .deepSeek }
        controller.companionModelAvailable = { [weak self] in self?.modelConfigured == true && self?.textBusy == false }
        controller.companionHermesResponse = { [weak self] text, id, onText in
            guard let self else { throw HermesConversationError.unavailable }
            try await self.respondHermes(text: text, id: id, onText: onText)
        }
        controller.companionExecuteTool = { [weak self] name, arguments, id in
            guard let codex = self?.codex else { return "Codex工具未配置，未执行。" }
            return await codex.executeTool(name: name, arguments: arguments, requestID: id)
        }
        controller.companionBusinessLoss = { [weak self] in self?.onBusinessLoss?() }
        controller.companionLog = { [weak self] line in
            guard let self else { return }
            self.latestEvent = String(line.prefix(200))
            if line.hasPrefix("唤醒诊断 ") {
                self.wakeDiagnostics.append(String(line.prefix(610)))
                self.wakeDiagnostics = Array(self.wakeDiagnostics.suffix(6))
                if self.wakeWordTrial.phase == .testing, self.wakeWordTrial.target == self.deviceID {
                    NSLog("[WakeWordDataTrial] wake-event source-unverified %@", String(line.prefix(610)))
                }
            }
        }
        controller.companionTranscript = { [weak self] id, text, final in
            guard let self, !text.isEmpty else { return }
            if self.activeTurn != id { self.finishTimelineTurn(); self.activeTurn = id }
            self.timeline?.record(ConversationEvent(id: id, kind: .transcript, text: text, final: final))
        }
        controller.companionCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .startAudio, .vadStart:
                self.answerBackend = self.selectedBackend
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
        phase = controller.companionPhase
        initialSpeechSeconds = controller.companionInitialSpeechSeconds
        hasCredentials = CloudASRHostSettings.normalize(CloudVoiceKeys.asrHost) != nil && CloudVoiceKeys.get(CloudVoiceKeys.asrService) != nil && modelConfigured
        DisplayObservation.shared.connection(ready, phase:phase)
        if !textBusy, ["disabled", "waitingForConnection", "idle"].contains(phase) { finishTimelineTurn() }
        continuous = controller.companionContinuous; cloud = controller.companionCloud
        let current = deviceID
        if previousDeviceID != current {
            if queryingWakeSettings { finishWakeSettingsQuery("连接已变化，请重新查询") }
            if wakeWordTrial.phase == .testing {
                wakeWordTrial.requireRecovery()
                trialNote("试验连接中断；恢复同一眼镜连接后提交原参数")
            }
            previousDeviceID = current; onConnectionChange?(current)
        }
        if let deadline = wakeSettingsDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
            finishWakeSettingsQuery(wakeSettingsDiagnostics.isEmpty ? "未收到可解析的设置回报；不能判断自定义支持情况" : "查询结束；回报字段不等于支持自定义唤醒词")
        }
        if launchWakeSettingsQuery, ready, ["idle", "disabled"].contains(phase), featureIsBusy?() != true {
            launchWakeSettingsQuery = false
            queryWakeSettings(preserveStartupObservations: true)
        }
        if let packet = try? wakeWordTrial.automaticRestore(device: current, now: ProcessInfo.processInfo.systemUptime) {
            submitWakeWordRestore(packet)
        }
        if launchWakeWordDataTrial, !launchWakeSettingsQuery, !queryingWakeSettings,
           ready, ["idle", "disabled"].contains(phase), featureIsBusy?() != true {
            launchWakeWordDataTrial = false
            beginWakeWordTrial()
        }
        if launchConfirmWakeRestored, ready, wakeWordTrial.phase == .restoreSubmitted {
            launchConfirmWakeRestored = false
            confirmOriginalWakeRestored()
        }
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
        guard !textBusy, hermesOperations == 0 else { error = "请先结束文字提问并等待本轮停止完成。"; return }
        guard featureIsBusy?() != true else { error = "请先结束眼镜录音或提词器任务，再开启语音待命。"; return }
        #if COMPANION_DEVICE
        prepare()
        guard controller.companionStart(cloud: cloud, continuous: continuous) else {
            error = "需要唯一已认证的眼镜；云对话还需要 ASR 凭据和所选后端的配置。没有自动切换模型。"; refresh(); return
        }
        refresh()
        #endif
    }
    func stop() {
        stopText()
        #if COMPANION_DEVICE
        controller.companionStop(); refresh()
        #endif
    }
    func endRound() {
        stopText()
        #if COMPANION_DEVICE
        controller.companionEndRound(); refresh()
        #endif
    }
    func queryWakeSettings(preserveStartupObservations: Bool = false) {
        guard ready, !queryingWakeSettings, ["idle", "disabled"].contains(phase), featureIsBusy?() != true else {
            error = "请连接眼镜并结束当前会话、录音或提词任务，再查询唤醒设置。"; return
        }
        if !preserveStartupObservations { wakeSettingsDiagnostics = [] }
        queryingWakeSettings = true
        wakeSettingsDeadline = ProcessInfo.processInfo.systemUptime + 8
        wakeSettingsStatus = "正在读取眼镜状态和设置；不修改唤醒词"
        NSLog("[WakeSettingsDiagnostic] read-only query started")
        do {
            try sendBusiness(15, payload: LauncherControlPrototype.encode(.requestGeneralStatus))
            try sendBusiness(15, payload: DeviceBusinessWire.encode(type: 4, json: ["cmd": "request_general_settings", "payload": ["value": 0, "mode": 0, "data": ""]]))
        } catch { finishWakeSettingsQuery("查询提交失败，未修改眼镜设置") }
    }
    private func finishWakeSettingsQuery(_ status: String) {
        queryingWakeSettings = false; wakeSettingsDeadline = nil; wakeSettingsStatus = status
        NSLog("[WakeSettingsDiagnostic] %@", status)
    }
    func beginWakeWordTrial() {
        guard ready, let device = deviceID, !queryingWakeSettings,
              ["idle", "disabled"].contains(phase), featureIsBusy?() != true else {
            error = "请先连接眼镜并结束当前任务，再试写唤醒词。"; return
        }
        do {
            let packet = try wakeWordTrial.begin(device: device, now: ProcessInfo.processInfo.systemUptime)
            wakeWordObservationDeadline = ProcessInfo.processInfo.systemUptime + 128
            // Only these new experiment keys are written; no pairing data or
            // existing user voice preferences are changed.
            guard persistWakeWordTrial() else {
                wakeWordTrial.requireRecovery()
                trialNote("恢复标记未保存；未提交试写"); return
            }
            try sendWakeWordTrialPacket(packet)
            trialNote("已提交 Hey Norman 试写（仅 data 改动）；120 秒后提交原参数，需真人验证")
        } catch {
            wakeWordTrial.requireRecovery()
            trialNote("试写未完成或本项已执行；若存在恢复标记，将提交原参数")
        }
    }
    func restoreOriginalWakeParameters() {
        do { try submitWakeWordRestore(wakeWordTrial.restore(device: deviceID)) }
        catch { self.error = "请连接执行本次试验的同一副眼镜，再恢复原参数。" }
    }
    private func submitWakeWordRestore(_ packet: Data) {
        // The state is already restoreSubmitted before sendBusiness can refresh
        // recursively. Keep the marker until the owner verifies the old phrase.
        wakeWordObservationDeadline = ProcessInfo.processInfo.systemUptime + 8
        do {
            try sendWakeWordTrialPacket(packet)
            trialNote("原参数已提交；请实测小雷小雷，再确认恢复")
        } catch { trialNote("原参数提交失败；保留恢复标记，请连接同一眼镜后重试") }
    }
    func confirmOriginalWakeRestored() {
        let previous = wakeWordTrial
        do {
            try wakeWordTrial.confirmRestored(device: deviceID)
            guard persistWakeWordTrial() else { wakeWordTrial = previous; trialNote("恢复确认尚未保存，请重试"); return }
            trialNote("用户已确认小雷小雷可唤醒；本次试验结束")
        } catch { self.error = "请先提交原参数，并实际验证小雷小雷能够唤醒。" }
    }
    private func persistWakeWordTrial() -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(wakeWordTrial.attempted, forKey: Self.trialAttemptedKey)
        if let target = wakeWordTrial.target { defaults.set(target, forKey: Self.trialRecoveryKey) }
        else { defaults.removeObject(forKey: Self.trialRecoveryKey) }
        // This explicit one-off flush precedes an experimental hardware write.
        return defaults.synchronize()
    }
    private func trialNote(_ text: String) {
        wakeWordTrialStatus = text
        NSLog("[WakeWordDataTrial] %@", text)
    }
    private func sendWakeWordTrialPacket(_ packet: Data) throws {
        // The trial already requires a prepared runtime. Avoid sendBusiness's
        // recursive refresh advancing a confirmation before the send returns.
        #if COMPANION_DEVICE
        try controller.companionSendBusiness(15, payload: packet)
        #else
        throw DeviceFeatureError.disconnected
        #endif
    }
    func saveKeys(asr: String, llm: String, host: String, enableDefault: Bool = false) -> Bool {
        #if COMPANION_DEVICE
        guard canConfigureConversation else { error = "请先关闭待命并结束文字提问，再修改凭据。"; return false }
        guard let target = CloudASRHostSettings.normalize(host) else { error = "请填写自己的阿里云 ASR 主机名（aliyuncs.com），不含协议、路径或端口。"; return false }
        let service = CloudASRHostSettings.service(for: target)
        let a = asr.isEmpty ? CloudVoiceKeys.get(service) != nil : CloudVoiceKeys.save(asr, service: service)
        let b = llm.isEmpty ? (selectedBackend == .hermes ? modelConfigured : CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil) : CloudVoiceKeys.save(llm, service: CloudVoiceKeys.llmService)
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
    func selectBackend(_ backend: ConversationBackend) {
        guard canConfigureConversation, backendSelection.select(backend, standbyEnabled: enabled) else { return }
        UserDefaults.standard.set(backend.rawValue, forKey: "companion.conversation.v1.backend")
        refresh()
    }
    func saveHermes(endpoint: String, token: String) -> Bool {
        guard canEditHermesConfiguration else { error = "请先关闭待命并等待当前网络操作结束，再修改 Hermes 配置。"; return false }
        do {
            let target = try HermesBridgeConfiguration.normalize(endpoint)
            guard !hermesTaskUnresolved || target == hermesEndpoint else { error = "原任务仍需核对；可以修正原地址的令牌，暂不能更换电脑。"; return false }
            hermesEndpoint = try ConversationCredentials.saveHermes(endpoint: endpoint, token: token)
            UserDefaults.standard.set(hermesEndpoint, forKey: "companion.hermes.v1.endpoint")
            hermesPolling?.cancel(); hermesPolling = nil; hermesTaskClient = nil
            restoreHermesTask()
            hermesStatus = "配置已保存，会话和原任务编号已保留"; error = nil; refresh(); return true
        } catch { self.error = "请填写 HTTPS 根地址和该地址的独立令牌；保存失败。"; return false }
    }
    func saveTextDeepSeekKey(_ key: String) -> Bool {
        guard canConfigureConversation else { return false }
        do { try ConversationCredentials.saveDeepSeek(key); error = nil; objectWillChange.send(); refresh(); return true }
        catch { self.error = "DeepSeek 密钥保存失败，请检查格式。"; return false }
    }
    func checkHermes() async {
        guard canEditHermesConfiguration else { return }
        checkingHermes = true; defer { checkingHermes = false }
        do { let client = try getHermesTaskClient(); try await client.health(); hermesStatus = "Hermes 已就绪 · 独立 IO 会话 · 支持电脑任务"; startHermesPolling() }
        catch { hermesStatus = error.localizedDescription }
    }
    private func getHermesTaskClient() throws -> HermesTaskClient {
        if let hermesTaskClient { return hermesTaskClient }
        guard let config = ConversationCredentials.hermes(hermesEndpoint) else { throw HermesConversationError.configuration }
        let storageKey = "companion.hermes.tasks.v2." + config.endpoint
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HermesTaskReferences", isDirectory: true)
        let store = try HermesTaskReferenceStore(directory: directory)
        let saved = try store.load(endpoint: config.endpoint) ?? UserDefaults.standard.data(forKey: storageKey)
        let client = try HermesTaskClient(configuration: config,
            load: { saved }, save: { try store.save($0, endpoint: config.endpoint) })
        UserDefaults.standard.removeObject(forKey: storageKey)
        hermesTaskClient = client
        client.onChange = { [weak self, weak client] in
            guard let self, let client, self.hermesTaskClient === client else { return }
            self.hermesTask = client.snapshot; self.hermesTaskBusy = client.busy
            self.hermesTaskUnresolved = client.hasUnfinishedTask
            self.hermesDecisionUnconfirmed = client.decisionNeedsReconciliation
            if let state = client.snapshot { self.hermesStatus = state.summary }
        }
        client.onChange?()
        return client
    }
    private func restoreHermesTask() {
        guard hermesTaskClient == nil, !hermesEndpoint.isEmpty else { return }
        do { _ = try getHermesTaskClient(); startHermesPolling() }
        catch { hermesTaskProblem = error.localizedDescription }
    }
    func resumeHermesTask() {
        restoreHermesTask(); startHermesPolling(force: true)
    }
    private func startHermesPolling(force: Bool = false) {
        guard hermesPolling == nil, let client = hermesTaskClient, client.reference.requestID != nil,
              force || client.hasUnfinishedTask else { return }
        hermesPolling = Task { @MainActor [weak self, weak client] in
            guard let self, let client else { return }
            defer { if self.hermesTaskClient === client { self.hermesPolling = nil } }
            repeat {
                do {
                    try await Task.sleep(nanoseconds: 750_000_000)
                    guard self.hermesTaskClient === client else { return }
                    if client.busy { continue }
                    try await client.refresh(); self.hermesTaskProblem = nil
                } catch {
                    if !Task.isCancelled { self.hermesTaskProblem = error.localizedDescription }
                    return
                }
            } while !Task.isCancelled && client.hasUnfinishedTask && client.snapshot?.status != .unknown
        }
    }
    func stopHermesTask() {
        guard let client = hermesTaskClient, !client.busy else { return }
        Task { @MainActor in
            do { try await client.stop(); hermesTaskProblem = nil; startHermesPolling() }
            catch { hermesTaskProblem = error.localizedDescription }
        }
    }
    func decideHermesTask(promptID: String, choice: String? = nil, text: String? = nil) {
        guard let client = hermesTaskClient, !client.busy else { return }
        Task { @MainActor in
            do { try await client.decide(promptID: promptID, choice: choice, text: text); hermesTaskProblem = nil; startHermesPolling() }
            catch { hermesTaskProblem = error.localizedDescription; startHermesPolling(force: true) }
        }
    }
    func acknowledgeHermesUnknown() {
        guard let client = hermesTaskClient, !client.busy else { return }
        Task { @MainActor in
            do { try await client.acknowledgeUnknown(); hermesTaskProblem = nil }
            catch { hermesTaskProblem = error.localizedDescription }
        }
    }
    private func respondHermes(text: String, id: UUID, onText: @escaping (String, Bool) -> Void, waitForResult: Bool = true) async throws {
        let client = try getHermesTaskClient()
        hermesOperations += 1; defer { hermesOperations -= 1 }
        try Task.checkCancellation()
        if client.hasUnfinishedTask {
            onText((client.snapshot?.summary ?? "上次提交结果待核对") + "。请在手机任务卡查看、回应或停止；这句话没有创建新任务。", true)
            startHermesPolling(force: true); return
        }
        hermesTaskProblem = nil
        do {
            try await client.submit(text: text)
        } catch {
            hermesTaskProblem = error.localizedDescription; startHermesPolling(force: true)
            throw error
        }
        startHermesPolling()
        onText("Hermes 已接收任务，正在电脑处理。进度和结果可在手机任务卡查看。\n", !waitForResult)
        guard waitForResult else { return }
        let requestID = client.reference.requestID
        // Listening may end after a receipt; the task client and Mac execution
        // continue independently. Cancellation here never calls stop().
        while client.reference.requestID == requestID {
            try await Task.sleep(nanoseconds: 350_000_000)
            if let state = client.snapshot {
                if state.status.terminal { onText(HermesTaskPresentation.glassesText(state.answer.isEmpty ? state.summary : state.answer), true); return }
                if state.status == .waiting || state.status == .unknown { onText(HermesTaskPresentation.glassesText(state.prompt?.title ?? state.summary), true); return }
            }
            if hermesTaskProblem != nil { onText("手机连接暂时中断，请在任务卡核对进度。", true); return }
        }
    }
    func sendText(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canConfigureConversation, modelConfigured else { error = "请先关闭眼镜待命、结束当前任务，并配置所选模型。"; return }
        guard !text.isEmpty, text.utf8.count <= 8192 else { error = "请输入非空文字，最多 8192 UTF-8 字节。"; return }
        let id = UUID()
        guard let binding = backendSelection.begin(id: id) else { return }
        finishTimelineTurn(); clearText(); error = nil; activeTurn = id; answerBackend = binding.backend
        textBusy = true; transcript = text; transcriptFinal = true
        timeline?.record(ConversationEvent(id: id, kind: .transcript, text: text, final: true))
        typedTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.backendSelection.finish(id: id); self.textBusy = false; self.typedTask = nil
                self.finishTimelineTurn()
            }
            let receive: (String, Bool) -> Void = { [weak self] delta, final in
                guard let self, self.activeTurn == id, !Task.isCancelled else { return }
                self.answer += delta
                if !delta.isEmpty { self.timeline?.record(ConversationEvent(id: id, kind: .answerDelta, text: delta)) }
                if final { self.modelComplete = true; self.timeline?.record(ConversationEvent(id: id, kind: .completed)) }
            }
            do {
                try await ConversationBackendRouter.respond(backend: binding.backend, deepSeek: {
                    guard let key = ConversationCredentials.deepSeek else { throw DeepSeekTypedConversation.Failure.invalidInput }
                    let answer = try await DeepSeekTypedConversation.respond(text: text, key: key, history: self.typedHistory)
                    try Task.checkCancellation(); receive(answer, true)
                    self.typedHistory += [["role": "user", "content": String(text.prefix(1000))], ["role": "assistant", "content": String(answer.prefix(1000))]]
                    self.typedHistory = Array(self.typedHistory.suffix(6))
                }, hermes: { try await self.respondHermes(text: text, id: id, onText: receive, waitForResult: false) })
            } catch {
                if !Task.isCancelled, self.error == nil { self.error = binding.backend == .hermes ? error.localizedDescription : "DeepSeek 请求失败，没有切换模型。" }
            }
        }
    }
    func stopText() {
        guard textBusy else { return }
        typedTask?.cancel()
        finishTimelineTurn()
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


/// Source and device builds share the app's existing DeepSeek key. Hermes has a
/// separate service and one account per validated origin; values are never shown.
enum ConversationCredentials {
    private static let hermesService = "io.turboio.hermes.conversation.v1"
    static let deepSeekService = "RayNeo.CloudLLM.https.api.deepseek.com.chat.completions"
    static func hermes(_ endpoint: String) -> HermesBridgeConfiguration? {
        guard let normalized = try? HermesBridgeConfiguration.normalize(endpoint),
              let token = read(service: hermesService, account: normalized) else { return nil }
        return try? HermesBridgeConfiguration(endpoint: normalized, token: token)
    }
    static var deepSeek: String? { read(service: deepSeekService, account: "user-api-key") }
    static func saveHermes(endpoint: String, token: String) throws -> String {
        let normalized = try HermesBridgeConfiguration.normalize(endpoint)
        if !token.isEmpty {
            let configuration = try HermesBridgeConfiguration(endpoint: normalized, token: token)
            try save(configuration.token, service: hermesService, account: normalized)
        }
        guard hermes(normalized) != nil else { throw HermesConversationError.configuration }
        return normalized
    }
    static func saveDeepSeek(_ key: String) throws {
        guard key.hasPrefix("sk-"), key.utf8.count <= 512, !key.contains(where: { $0.isWhitespace }) else { throw DeepSeekTypedConversation.Failure.invalidInput }
        try save(key, service: deepSeekService, account: "user-api-key")
    }
    private static func read(service: String, account: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func save(_ value: String, service: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil) == errSecSuccess else { throw HermesConversationError.configuration }
        } else if status != errSecSuccess { throw HermesConversationError.configuration }
    }
}
