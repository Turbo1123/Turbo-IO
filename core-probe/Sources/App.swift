import UIKit
import CoreBluetooth
import ExternalAccessory
import RayNeoProtocol

#if !COMPANION_DEVICE
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ProbeController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
#endif

final class ProbeController: UIViewController, CBCentralManagerDelegate, StreamDelegate {
    private let output = UITextView(usingTextLayoutManager: false)
    private var core: CoreHandle?
    private var central: CBCentralManager?
    private var seen = Set<UUID>()
    private var scanRequested = false
    private var devices: [UUID: CBPeripheral] = [:]
    private var eaSession: EASession?
    private var sdkDeviceIDs = Set<String>()
    private var parsedAdvertisements = Set<UUID>()
    private var sdkPeripherals: [UUID: NSObject] = [:]
    private var logLines: [String] = []
    private var renderPending = false
    private var modelCatalog: [String: Any]?
    private var messageReceiver: CoreMessageReceiver?
    private let voiceProbe = VoiceHandshakeProbe()
    private var standbyTimer: Timer?
    private var standbyButton: UIButton?
    private var reconnectPolicy = StandbyReconnectPolicy()
    private var standbyWasReady = false
    private var nextWakeInit: TimeInterval = 0
    private var standbyLifecycle: NSObjectProtocol?
    private let standbyPreferenceKey = "syntheticStandbyTarget.v1"

    #if COMPANION_DEVICE
    private var deviceConnectionTimer: Timer?
    private var deviceConnectionPolicy = BondedConnectionPolicy()
    // Thin host adapter: shared proven engine, no duplicate protocol implementation.
    var companionCommand: ((StandbyVoiceSession.Command) -> Void)?
    var companionTranscript: ((UUID,String,Bool) -> Void)?
    var companionLog: ((String) -> Void)?
    var companionBusiness: ((String, UInt8, Data) -> Void)?
    var companionBusinessLoss: (() -> Void)?
    var companionDeviceID: String? { companionReady ? core?.linkedDevices()?.first?.deviceID() : nil }
    func companionSendFile(_ url: URL, id: String) throws -> String {
        guard companionReady, RNProbeMessageImageMatches(), let device = companionDeviceID,
              let task = core?.shareFile(url, device, 0, id), !task.isEmpty else {
            throw NSError(domain: "CompanionFileSend", code: 1)
        }
        return task
    }
    func companionCancelFile(_ task: String) {
        guard companionReady, let device = companionDeviceID else { return }
        core?.cancelShare(device, task)
    }
    func companionSendBusiness(_ index: UInt8, payload: Data) throws {
        guard companionReady, let core, let target = companionDeviceID,
              let business = MessageBusinessIndex(rawValue: index), [13,14,15,20,21,22].contains(index) else {
            throw NSError(domain: "CompanionBusinessConnection", code: 1)
        }
        if index == 13 {
            let meta = try BusinessEnvelopeMetadata.inspect(payload)
            guard let type = meta.messageType, [162,166,168].contains(type) else {
                throw NSError(domain: "CompanionAlwaysOnCommand", code: 1)
            }
        }
        try core.sendMessage(MessageFactory.make(payload: payload, deviceID: target, business: business, messageID: UUID().uuidString))
        DisplayObservation.shared.packet(payload,business:index,inbound:false)
    }
    func companionDiscover() { loadViewIfNeeded(); loadCore(); sdkDiscovery(); scan() }
    var companionTools: (() -> [[String: Any]])?
    var companionExecuteTool: ((String, String, UUID) async -> String)?
    func companionConnect() { loadViewIfNeeded(); connectSDK() }
    func companionReconnectBonded() {
        loadViewIfNeeded()
        deviceConnectionPolicy.resetBudget()
        startDeviceConnectionMaintenance()
        if companionReady { log("已绑定眼镜已认证连接，无需重连") }
    }
    private func startDeviceConnectionMaintenance() {
        if core == nil { loadCore() }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        if deviceConnectionTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.deviceConnectionTick() }
            deviceConnectionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            log("设备连接维护已开启：独立于语音，仅重连本 App 唯一已有绑定")
        }
        deviceConnectionTick()
    }
    private func deviceConnectionTick() {
        guard let core else { return }
        // Re-read SDK objects on every attempt; never retain a stale handle.
        let bonded = core.bondedDevices() ?? []
        let linked = core.linkedDevices() ?? []
        let candidate = bonded.count == 1
            ? (linked.first(where: { $0.deviceID() == bonded[0].deviceID() }) ?? bonded[0]) : nil
        let peripheralState = candidate?.transport().rnSDKPeripheral()?.state
        let busy = peripheralState.map { $0 != .disconnected } ?? false
        guard let target = deviceConnectionPolicy.reconnectTarget(
            now: ProcessInfo.processInfo.systemUptime,
            bonded: bonded.map { $0.deviceID() }, linked: linked.map { $0.deviceID() },
            authenticated: companionReady, bluetoothOn: central?.state == .poweredOn,
            transportBusy: busy), let candidate, candidate.deviceID() == target else { return }
        do {
            try core.connectBLE(candidate)
            log("独立设备重连 attempt=\(deviceConnectionPolicy.attempts)/8；不启动语音/录音，等待认证")
        } catch { log("独立设备重连提交失败；保留绑定并退避") }
        if deviceConnectionPolicy.attempts == 8 {
            log("本轮设备重连预算用尽；回到前台、蓝牙恢复或手动重连可重试，不自动重新配对")
        }
    }
    var companionReady: Bool {
        let linked = core?.linkedDevices() ?? []
        return linked.count == 1 && linked[0].isConnected() && linked[0].bleStateByte() == 9
    }
    var companionPhase: String { voiceProbe.standby.phase.rawValue }
    var companionEnabled: Bool { voiceProbe.standby.enabled }
    var companionContinuous: Bool { voiceProbe.standby.continuousASREnabled }
    var companionCloud: Bool { voiceProbe.standby.cloudEnabled }
    func companionStart(cloud: Bool, continuous: Bool) -> Bool {
        loadViewIfNeeded()
        guard companionReady, let device = core?.linkedDevices()?.first,
              !cloud || CloudVoiceKeys.ready else { return false }
        UserDefaults.standard.set(true, forKey: "companion.autoVoice.v1")
        voiceProbe.setCloudMode(cloud)
        UserDefaults.standard.set(cloud, forKey: CloudVoiceKeys.enabledKey)
        UserDefaults.standard.set(continuous && cloud, forKey: "companion.continuousASR.v1")
        UserDefaults.standard.set(device.deviceID(), forKey: standbyPreferenceKey)
        startStandby(target: device.deviceID())
        if cloud && continuous { voiceProbe.setContinuousASR(true) }
        return true
    }
    func companionStop() {
        UserDefaults.standard.set(false, forKey: "companion.autoVoice.v1")
        disableStandby()
    }
    func companionEnableDefaultCloudVoice() {
        guard CloudVoiceKeys.ready else { return }
        UserDefaults.standard.set(true, forKey: "companion.autoVoice.v1")
        UserDefaults.standard.set(true, forKey: CloudVoiceKeys.enabledKey)
        UserDefaults.standard.set(true, forKey: "companion.continuousASR.v1")
        companionRestoreAutomaticVoice()
    }
    private func companionRestoreAutomaticVoice() {
        guard !voiceProbe.standby.enabled, CloudVoiceKeys.ready,
              UserDefaults.standard.bool(forKey: "companion.autoVoice.v1") else { return }
        loadCore()
        guard let bonded = core?.bondedDevices(), bonded.count == 1 else {
            log("自动语音已允许；等待唯一已绑定眼镜，不自动配对或抢绑"); return
        }
        let target = bonded[0].deviceID()
        voiceProbe.setCloudMode(UserDefaults.standard.bool(forKey: CloudVoiceKeys.enabledKey))
        UserDefaults.standard.set(target, forKey: standbyPreferenceKey)
        startStandby(target: target)
        if voiceProbe.standby.cloudEnabled {
            voiceProbe.setContinuousASR(UserDefaults.standard.bool(forKey: "companion.continuousASR.v1"))
        }
        log("恢复用户默认语音待命；仅唤醒后采音，已绑定目标自动重连")
    }
    func companionEndRound() { voiceProbe.standby.cancelCurrentRound() }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = "RayNeo Core Probe"
        title.font = .preferredFont(forTextStyle: .title1)
        stack.addArrangedSubview(title)
        for (title, action) in [("1 · 加载核心／刷新状态", #selector(loadCore)), ("2 · 只读发现 BLE", #selector(scan)), ("3 · 检查 MFi 会话", #selector(accessories)), ("4 · SDK 发现", #selector(sdkDiscovery)), ("5 · SDK BLE 连接验证", #selector(connectSDK)), ("6 · 解除绑定（清除眼镜数据）", #selector(confirmUnbind)), ("7 · 显示边界测试／结束", #selector(showDisplayBoundaryTests)), ("8 · 开启语音唤醒", #selector(confirmVoiceWakeup)), ("9 · 持续待命：关闭", #selector(toggleStandby)), ("10 · 云端对话／密钥设置",#selector(showCloudSettings))] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.addTarget(self, action: action, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(button)
            if title.hasPrefix("9 ·") { standbyButton = button }
        }
        output.isEditable = false
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stack.addArrangedSubview(output)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        log("独立 Bundle / 独立沙盒\n无 Hook、无 SSH、无越狱调用\nBLE 状态 9 才是 authSuccess；普通连接不算认证成功。")
        log("旧 getBTState 入口已确认无实际发包，不作为业务接口展示。")
        RNProbeSetLogSink { [weak self] line in self?.log(line) }
        voiceProbe.log = { [weak self] in self?.log($0) }
        #if COMPANION_DEVICE
        voiceProbe.onSubmittedCommand = { [weak self] in self?.companionCommand?($0) }
        voiceProbe.onArchiveTranscript = { [weak self] id, text, final in self?.companionTranscript?(id,text,final) }
        voiceProbe.cloudTools = { [weak self] in self?.companionTools?() ?? [] }
        voiceProbe.executeCloudTool = { [weak self] name, args, id in
            guard let execute = self?.companionExecuteTool else { return "Codex未配置，未执行。" }
            return await execute(name, args, id)
        }
        #endif
        voiceProbe.setCloudMode(UserDefaults.standard.bool(forKey:CloudVoiceKeys.enabledKey) && CloudVoiceKeys.ready)
        voiceProbe.send = { [weak self] deviceID, payload in
            guard let core = self?.core, let linked = core.linkedDevices(), linked.count == 1,
                  let device = linked.first, device.deviceID() == deviceID,
                  device.isConnected(), device.bleStateByte() == 9 else {
                throw NSError(domain:"VoiceProbeConnection", code:1)
            }
            try core.sendMessage(MessageFactory.make(payload:payload, deviceID:deviceID,
                business:.voiceAssistant, messageID:UUID().uuidString))
            #if COMPANION_DEVICE
            DisplayObservation.shared.packet(payload,business:13,inbound:false)
            #endif
        }
        standbyLifecycle = NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,
            object:nil, queue:.main) { [weak self] _ in
                #if COMPANION_DEVICE
                self?.deviceConnectionPolicy.resetBudget()
                self?.startDeviceConnectionMaintenance()
                #endif
                self?.standbyTick()
            }
        DispatchQueue.main.async { [weak self] in
            #if COMPANION_DEVICE
            self?.startDeviceConnectionMaintenance()
            #endif
            self?.restoreStandbyIfRequested()
        }
    }

    deinit {
        #if COMPANION_DEVICE
        deviceConnectionTimer?.invalidate()
        #endif
        standbyTimer?.invalidate()
        if let standbyLifecycle { NotificationCenter.default.removeObserver(standbyLifecycle) }
    }

    @objc private func toggleStandby() {
        if voiceProbe.standby.enabled { disableStandby(); return }
        guard let linked = core?.linkedDevices(), linked.count == 1, let device = linked.first,
              device.isConnected(), device.bleStateByte() == 9 else {
            log("持续待命开启需要唯一已认证设备，请先连接"); return
        }
        let target = device.deviceID()
        let message = voiceProbe.standby.cloudEnabled
            ? "当前是云对话：唤醒后音频发往已指定阿里云空间，识别文字发给DeepSeek Flash（关闭思考/流式）。云端判断句末；本地5秒无语音/20秒收音/30秒处理保护。无TTS、无工具执行。日志不记正文，服务可能计费。重开App恢复开关，按钮9关闭。"
            : "每次真实唤醒后，本机解码并检测语音；连续约0.9秒无语音即回复随机文字，显示10秒后待命。5秒无语音退出，最长收音8秒。不是识别或模型回答，不保存/上传音频。允许后台处理但系统可能挂起。仅对已绑定眼镜有限重连，不自动配对或重置。重开App恢复开关，按钮9关闭。"
        let alert = UIAlertController(title:"开启持续待命？", message:message, preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消", style:.cancel))
        alert.addAction(UIAlertAction(title:"开启持续待命", style:.default) { [weak self] _ in
            guard let self, let linked = self.core?.linkedDevices(), linked.count == 1,
                  let current = linked.first, current.deviceID() == target,
                  current.isConnected(), current.bleStateByte() == 9 else { return }
            UserDefaults.standard.set(target, forKey:self.standbyPreferenceKey)
            self.startStandby(target:target)
        })
        present(alert, animated:true)
    }
    @objc private func showCloudSettings() {
        let controller = CloudVoiceSettingsController()
        controller.changed = { [weak self] enabled in
            self?.voiceProbe.setCloudMode(enabled)
            self?.standbyTick()
        }
        present(controller,animated:true)
    }

    private func restoreStandbyIfRequested() {
        #if COMPANION_DEVICE
        companionRestoreAutomaticVoice()
        if voiceProbe.standby.enabled { return }
        #endif
        guard let target = UserDefaults.standard.string(forKey:standbyPreferenceKey) else { return }
        loadCore()
        guard let matches = core?.bondedDevices()?.filter({ $0.deviceID() == target }), matches.count == 1 else {
            UserDefaults.standard.removeObject(forKey:standbyPreferenceKey)
            log("旧持续服务目标不再绑定，未恢复、未自动配对"); return
        }
        log("按已保存的用户开关恢复持续服务；不代表系统能自动拉起App")
        startStandby(target:target)
        #if COMPANION_DEVICE
        if voiceProbe.standby.cloudEnabled, UserDefaults.standard.bool(forKey: "companion.continuousASR.v1") {
            voiceProbe.setContinuousASR(true)
        }
        #endif
    }

    private func startStandby(target: String) {
        reconnectPolicy.reset(); standbyWasReady = false; nextWakeInit = 0
        voiceProbe.enableStandby(deviceID:target)
        if central == nil { central = CBCentralManager(delegate:self, queue:.main) }
        standbyTimer?.invalidate()
        let timer = Timer(timeInterval:0.5, repeats:true) { [weak self] _ in self?.standbyTick() }
        standbyTimer = timer
        RunLoop.main.add(timer, forMode:.common)
        standbyTick()
    }

    private func disableStandby() {
        UserDefaults.standard.removeObject(forKey:standbyPreferenceKey)
        voiceProbe.standby.disable()
        standbyTimer?.invalidate(); standbyTimer = nil
        standbyWasReady = false
        standbyButton?.setTitle("9 · 持续待命：关闭", for:.normal)
        #if COMPANION_DEVICE
        log("语音待命已关闭，不再自动回应；设备独立重连仍保留，未改眼镜唤醒开关/绑定")
        #else
        log("持续服务已关闭，不再自动回应或重连；未改眼镜唤醒开关/绑定")
        #endif
    }

    private func standbyTick() {
        guard let target = voiceProbe.standby.target, let core else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let linked = core.linkedDevices() ?? []
        let ready = linked.count == 1 && linked.first?.deviceID() == target
            && linked.first?.isConnected() == true && linked.first?.bleStateByte() == 9
        // Retain no credential or stale RNDevice handle. Resolve each time.
        guard let bonded = core.bondedDevices()?.filter({ $0.deviceID() == target }), bonded.count == 1 else {
            log("持续服务目标已不在绑定列表，安全关闭；不重新绑定")
            disableStandby(); return
        }
        voiceProbe.standby.connection(ready)
        if ready {
            reconnectPolicy.reset()
            if !standbyWasReady && now >= nextWakeInit {
                nextWakeInit = now + 5
                do {
                    let payload = try LauncherControlPrototype.encode(.enableVoiceWakeup)
                    try core.sendMessage(MessageFactory.make(payload:payload, deviceID:target,
                        business:.launcher, messageID:UUID().uuidString))
                    standbyWasReady = true
                    log("持续服务连接就绪，提交唤醒初始化；眼镜true回传另行核对")
                } catch { log("持续服务初始化提交失败，5秒后复查") }
            }
        } else {
            if standbyWasReady { log("持续服务失去唯一认证连接；暂停本轮，保留重连意图") }
            standbyWasReady = false
            #if !COMPANION_DEVICE
            // Existing bond only; never steal another active target or race an
            // already connecting peripheral. SDK owns its background heartbeat.
            let candidate = linked.first(where:{ $0.deviceID() == target }) ?? bonded[0]
            let eligible = linked.allSatisfy({ $0.deviceID() == target }) && central?.state == .poweredOn
                && candidate.transport().rnSDKPeripheral()?.state == .disconnected
            if reconnectPolicy.shouldAttempt(now:now, eligible:eligible) {
                do {
                    try core.connectBLE(candidate)
                    log("持续服务已绑定目标重连 attempt=\(reconnectPolicy.attempts)/8；非认证成功")
                } catch { log("持续服务重连提交失败；有界退避，不重置设备") }
                if reconnectPolicy.attempts == 8 { log("本次重连预算已用尽；若SDK仍未恢复，请关闭再开启持续服务") }
            }
            #endif
        }
        voiceProbe.standby.tick(now:now)
        let labels: [StandbyVoiceSession.Phase:String] = [.disabled:"关闭", .waitingForConnection:"等待连接", .idle:"等待唤醒", .recording:"收音中", .processing:"云端回答中", .displaying:"显示中"]
        standbyButton?.setTitle("9 · 持续待命：\(labels[voiceProbe.standby.phase] ?? "未知")", for:.normal)
    }

    private func log(_ text: String) {
        #if COMPANION_DEVICE
        companionLog?(text)
        #endif
        logLines.append(text)
        if logLines.count > 100 { logLines.removeFirst(logLines.count - 100) }
        // Bound the visible buffer; full privacy-filtered output also goes to
        // NSLog. Avoid a growing accessibility text tree during live tests.
        NSLog("[CoreProbe] %@", text)
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.renderPending = false
            self.output.text = self.logLines.suffix(28).map { String($0.prefix(180)) }.joined(separator: "\n")
            self.output.layoutIfNeeded()
            self.output.setContentOffset(CGPoint(x: 0, y: max(0, self.output.contentSize.height - self.output.bounds.height)), animated: false)
        }
    }

    @objc private func loadCore() {
        guard RNProbeMessageImageMatches() else { log("SDK 版本不匹配，拒绝加载"); return }
        log("SDK version: \(coreVersion() ?? "nil")")
        core = coreShared()
        if messageReceiver == nil {
            let receiver = CoreMessageReceiver()
            receiver.onMetadata = { [weak self] in self?.log($0) }
            #if COMPANION_DEVICE
            receiver.onBusinessEnvelope = { [weak self] id, business, payload in
                guard let self, self.companionDeviceID == id else { return }
                DisplayObservation.shared.connection(true,phase:self.companionPhase)
                DisplayObservation.shared.packet(payload,business:business,inbound:true)
                self.companionBusiness?(id, business, payload)
            }
            receiver.onBusinessLoss = { [weak self] in DisplayObservation.shared.loss(); self?.companionBusinessLoss?() }
            #endif
            receiver.onVoiceEnvelope = { [weak self] deviceID, metadata, audio, arrival in
                #if COMPANION_DEVICE
                if self?.companionDeviceID == deviceID, let type = metadata.messageType {
                    DisplayObservation.shared.voiceMetadata(type:type)
                }
                #endif
                if metadata.messageType == 1 || metadata.messageType == 11 { self?.standbyTick() }
                self?.voiceProbe.receive(deviceID:deviceID, metadata:metadata, audio:audio, arrival:arrival)
            }
            messageReceiver = receiver
            core?.addMessageDelegate(receiver)
            log("本 App 原生消息回调已注册（只记类型/长度）")
        }
        if modelCatalog == nil { modelCatalog = sdkModelCatalog() }
        log("SDK 内置型号目录可用=\(modelCatalog != nil)")
        log("独立 SDK instance 已创建")
        let bonded = core?.bondedDevices() ?? []
        let linked = core?.linkedDevices() ?? []
        log("本 App 保存的设备: \(bonded.count)；SDK 已连设备: \(linked.count)")
        for device in linked { logDeviceState(device, prefix: "当前连接") }
    }

    @objc private func confirmVoiceProbe() {
        guard let core, let linked = core.linkedDevices(), linked.count == 1,
              let device = linked.first, device.isConnected(), device.bleStateByte() == 9 else {
            log("没有唯一已认证连接，未就绪语音测试"); return
        }
        let deviceID = device.deviceID()
        let alert = UIAlertController(title:"准备一次8秒语音测试？", message:"仅在你主动唤醒后请求音频；收到非空音频才在8秒后显示本轮随机测试串，内容与所说的话无关，再过3秒请求退出页面。不是语音识别或模型回答。只记类型/长度，不保存、不上传；90秒不唤醒自动取消。", preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消", style:.cancel))
        alert.addAction(UIAlertAction(title:"准备测试", style:.default) { [weak self] _ in
            guard let current = core.linkedDevices()?.first(where: { $0.deviceID() == deviceID }),
                  current.isConnected(), current.bleStateByte() == 9 else {
                self?.log("连接已变化，取消语音测试"); return
            }
            self?.voiceProbe.arm(deviceID:deviceID)
        })
        present(alert, animated:true)
    }

    @objc private func showDisplayBoundaryTests() {
        if voiceProbe.standby.enabled {
            let menu = UIAlertController(title:"持续待命显示测试",message:"下一次唤醒发送A1至A4四段合成文字，最后一段带校验码；不请求云服务。无10秒强制关闭，验收眼镜自己的收尾行为。",preferredStyle:.actionSheet)
            menu.addAction(UIAlertAction(title:"下一次唤醒：A1–A4增量测试",style:.default) { [weak self] _ in self?.voiceProbe.armIncrementalFixture() })
            let duplex = voiceProbe.standby.continuousASREnabled
            menu.addAction(UIAlertAction(title:duplex ? "关闭持续ASR并行实验" : "开启持续ASR并行实验（120秒）",style:.default) { [weak self] _ in self?.voiceProbe.setContinuousASR(!duplex) })
            menu.addAction(UIAlertAction(title:"结束本轮显示",style:.default) { [weak self] _ in self?.voiceProbe.standby.cancelCurrentRound() })
            menu.addAction(UIAlertAction(title:"取消",style:.cancel))
            menu.popoverPresentationController?.sourceView = view
            menu.popoverPresentationController?.sourceRect = CGRect(x:view.bounds.midX,y:440,width:1,height:1)
            present(menu,animated:true)
            return
        }
        let menu = UIAlertController(title:"显示边界：语音文字页", message:"只测试固件现有文字页，不是图片/任意UI。每项需主动唤醒，8秒后显示，保持10秒后退出。", preferredStyle:.actionSheet)
        for fixture in DisplayBoundaryFixture.all {
            menu.addAction(UIAlertAction(title:"\(fixture.id) · \(fixture.name)", style:.default) { [weak self] _ in
                self?.confirmDisplayFixture(fixture)
            })
        }
        menu.addAction(UIAlertAction(title:"结束当前测试", style:.destructive) { [weak self] _ in self?.voiceProbe.stopDisplayTest() })
        menu.addAction(UIAlertAction(title:"取消", style:.cancel))
        menu.popoverPresentationController?.sourceView = view
        menu.popoverPresentationController?.sourceRect = CGRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1)
        present(menu, animated:true)
    }

    private func confirmDisplayFixture(_ fixture: DisplayBoundaryFixture) {
        guard let core, let linked = core.linkedDevices(), linked.count == 1,
              let device = linked.first, device.isConnected(), device.bleStateByte() == 9 else {
            log("没有唯一已认证连接，不启动显示边界测试"); return
        }
        let deviceID = device.deviceID()
        let alert = UIAlertController(title:"\(fixture.id) · \(fixture.name)", message:"\(fixture.text)\n\n仅主动唤醒后短时收音，不保存/上传。8秒后发送上述合成文字，10秒后自动退出。每次只验本项，90秒未唤醒取消。", preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消", style:.cancel))
        alert.addAction(UIAlertAction(title:"准备本项测试", style:.default) { [weak self] _ in
            guard let linked = core.linkedDevices(), linked.count == 1,
                  let current = linked.first, current.deviceID() == deviceID,
                  current.isConnected(), current.bleStateByte() == 9 else {
                self?.log("连接已变化，不就绪显示测试"); return
            }
            self?.voiceProbe.arm(deviceID:deviceID, fixture:fixture)
        })
        present(alert, animated:true)
    }

    @objc private func confirmVoiceWakeup() {
        guard let core, let linked = core.linkedDevices(), linked.count == 1,
              let device = linked.first, device.isConnected(), device.bleStateByte() == 9 else {
            log("没有唯一已认证连接，未开启语音唤醒"); return
        }
        let deviceID = device.deviceID()
        let alert = UIAlertController(title: "开启这副眼镜的语音唤醒？", message: "发送官方实测的 Launcher/type16：set_ai_voice_wakeup，mode=1。只改变唤醒开关；不录音、不上传。需要眼镜回传状态和真人唤醒验收。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "开启测试", style: .default) { [weak self] _ in
            guard let current = core.linkedDevices()?.first(where: { $0.deviceID() == deviceID }),
                  current.isConnected(), current.bleStateByte() == 9 else {
                self?.log("连接已变化，取消开启"); return
            }
            do {
                let payload = try LauncherControlPrototype.encode(.enableVoiceWakeup)
                let message = try MessageFactory.make(payload: payload, deviceID: deviceID,
                    business: .launcher, messageID: UUID().uuidString)
                try core.sendMessage(message)
                self?.log("已提交 Launcher/type16 set_ai_voice_wakeup mode=1 bytes=\(payload.count)；等待眼镜回传，非唤醒成功")
            } catch { self?.log("开启语音唤醒发送失败（不记录原始错误）") }
        })
        present(alert, animated: true)
    }

    @objc private func confirmTextTest() {
        guard let core, let linked = core.linkedDevices(), linked.count == 1,
              let device = linked.first, device.isConnected(), device.bleStateByte() == 9 else {
            log("没有唯一已认证连接，未发消息"); return
        }
        let deviceID = device.deviceID()
        let text = "自定义连接测试 1730"
        let alert = UIAlertController(title:"发送固定 ASR 文字？", message:"内容：\(text)\n这是 voiceAssistant/type=5，不是 ANCS 通知。可能需要先唤醒眼镜；实际显示需本人确认。", preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消", style:.cancel))
        alert.addAction(UIAlertAction(title:"发送测试", style:.default) { [weak self] _ in
            guard let current = core.linkedDevices()?.first(where: { $0.deviceID() == deviceID }),
                  current.isConnected(), current.bleStateByte() == 9 else {
                self?.log("连接已变化，取消发送"); return
            }
            do {
                let payload = try AssistantTextPrototype.asrText(text, isFinal:true)
                let message = try MessageFactory.make(payload:payload, deviceID:deviceID,
                                                     business:.voiceAssistant, messageID:UUID().uuidString)
                try core.sendMessage(message)
                self?.log("本 App→眼镜 type=5 bytes=\(payload.count) 调用已返回；等待回调与实际显示")
            } catch { self?.log("文字测试发送失败（未记录错误正文）") }
        })
        present(alert, animated:true)
    }

    @objc private func scan() {
        scanRequested = true
        seen.removeAll()
        parsedAdvertisements.removeAll()
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginScan() }
    }

    private func beginScan() {
        guard central?.state == .poweredOn else { return }
        scanRequested = false
        central?.scanForPeripherals(withServices: [CBUUID(string: "B81D")], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("扫描已验证的 B81D 服务（15 秒，无连接/写入）")
        for p in central!.retrieveConnectedPeripherals(withServices: [CBUUID(string: "B81D")]) {
            devices[p.identifier] = p
            log("系统已连 RayNeo 服务: \(p.name ?? "unnamed")")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.central?.stopScan()
            self?.log("扫描结束")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("CoreBluetooth state=\(central.state.rawValue)")
        #if COMPANION_DEVICE
        if central.state == .poweredOn { deviceConnectionPolicy.resetBudget() }
        deviceConnectionTick()
        if scanRequested { beginScan() }
        if voiceProbe.standby.enabled { standbyTick() }
        #else
        if voiceProbe.standby.enabled { standbyTick() } else { beginScan() }
        #endif
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        devices[peripheral.identifier] = peripheral
        if seen.insert(peripheral.identifier).inserted {
            log("发现: \(peripheral.name ?? "unnamed") RSSI=\(RSSI)")
            log("广播字段: \(advertisementData.keys.sorted().joined(separator: ", "))")
        }
        if !parsedAdvertisements.contains(peripheral.identifier), let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            parsedAdvertisements.insert(peripheral.identifier)
            log("制造商广播长度=\(data.count)，调用 ObjC 解析入口")
            if let id = RNProbeIdentifier(data, (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false) {
                sdkDeviceIDs.insert(id)
                if let sdkPeripheral = RNProbeSDKPeripheral(peripheral.identifier), let modelCatalog {
                    sdkPeripherals[peripheral.identifier] = RNProbePeripheral(data, sdkPeripheral, advertisementData, modelCatalog)
                    log("已由 SDK 自己的 CBCentralManager 解析外设对象")
                } else { log("SDK central 尚未就绪，请加载后重新扫描") }
                log("SDK 广播解析成功，已取得协议设备标识（不显示原值）")
            } else { log("SDK 广播解析未返回设备标识: \(RNProbeDiagnosis())") }
        }
    }

    @objc private func accessories() {
        let matches = EAAccessoryManager.shared().connectedAccessories.filter { $0.name.localizedCaseInsensitiveContains("rayneo") }
        log("本 App 可见 RayNeo MFi 附件: \(matches.count)")
        for a in matches { log("\(a.name) protocols=\(a.protocolStrings.joined(separator: ","))") }
        guard eaSession == nil, let accessory = matches.first,
              accessory.protocolStrings.contains("com.rayneo.venus.pub") else { return }
        eaSession = EASession(accessory: accessory, forProtocol: "com.rayneo.venus.pub")
        guard let session = eaSession else { log("EASession 创建失败"); return }
        log("EASession 已创建；只测打开流，不发送业务消息")
        for stream in [session.inputStream as Stream?, session.outputStream as Stream?].compactMap({$0}) {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .default)
            stream.open()
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+5) { [weak self] in
            guard let self, let session = self.eaSession else { return }
            for stream in [session.inputStream as Stream?, session.outputStream as Stream?].compactMap({$0}) {
                stream.close()
                stream.remove(from: .main, forMode: .default)
                stream.delegate = nil
            }
            self.eaSession = nil
            self.log("MFi 测试流已关闭")
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        let direction = aStream === eaSession?.inputStream ? "input" : "output"
        if eventCode.contains(.openCompleted) { log("MFi \(direction) openCompleted") }
        if eventCode.contains(.errorOccurred) { log("MFi \(direction) error: \(aStream.streamError?.localizedDescription ?? "unknown")") }
    }

    @objc private func sdkDiscovery() {
        if core == nil { loadCore() }
        guard let core else { return }
        do { try core.discover(); log("SDK discoverStart 调用成功（不代表认证成功）") }
        catch { log("SDK discovery error: \(error)") }
    }

    @objc private func connectSDK() {
        guard !voiceProbe.standby.enabled else { log("持续服务管理连接中，请先关闭再手动连接"); return }
        guard let core else { log("先加载通信核心并发现眼镜"); return }
        // findCoreDevice compares CBPeripheral.identifier.uuidString, NOT the
        // 6-byte identifier carried in the manufacturer's advertisement.
        let found = sdkPeripherals.compactMap { uuid, peripheral in
            let id = uuid.uuidString
            return (core.findDevice(id) ?? convertPeripheral(peripheral)).map { (id, $0) }
        }
        guard found.count == 1, let (id, target) = found.first else { log("SDK 缓存匹配设备数=\(found.count)，未连接"); return }
        do {
            // No account/token/key copied from the official app. Normal SDK path.
            try core.connectBLE(target)
            log("SDK BLE 请求已提交，等待设备认证状态")
            for delay in [2.0,5.0,10.0,20.0,30.0,45.0] {
                DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
                    let linked = core.linkedDevices() ?? []
                    let cached = core.findDevice(id)
                    let live = linked.first { $0.deviceID() == target.deviceID() }
                    let fresh = live ?? cached
                    self?.log("\(Int(delay))s SDK linkedCount=\(linked.count), connected=\(fresh?.isConnected() ?? false), BLE状态字节=\(fresh?.bleStateByte() ?? 255)")
                    if let live, let cached, live.bleStateByte() != cached.bleStateByte() {
                        self?.log("SDK 缓存对象状态不一致：linked=\(live.bleStateByte()), findDevice=\(cached.bleStateByte())；以上显示 linked 对象")
                    }
                }
            }
        } catch { log("SDK BLE 连接错误: \(error)") }
    }

    @objc private func confirmUnbind() {
        guard let core, let device = core.linkedDevices()?.first, device.isConnected(), device.bleStateByte() == 9 else {
            log("没有已认证连接，未执行解绑")
            return
        }
        let targetID = device.deviceID()
        let alert = UIAlertController(title: "解除这副测试眼镜的绑定？", message: "用于切换回另一台手机。可能清除眼镜内容；电脑录音副本不受影响。执行后停止本 App，并在系统蓝牙中忽略设备。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认解绑", style: .destructive) { [weak self] _ in
            // The alert can remain open while the glasses disconnect. Re-fetch
            // the target and validate its real CBPeripheral immediately before
            // calling the SDK, which otherwise silently performs local cleanup.
            guard let self, let fresh = core.linkedDevices()?.first(where: { $0.deviceID() == targetID }),
                  fresh.isConnected(), fresh.bleStateByte() == 9 else {
                self?.log("确认时认证连接已失效；拒绝把离线本地清理当作眼镜解绑")
                return
            }
            self.logDeviceState(fresh, prefix: "解绑前复核")
            self.disableStandby()
            let transport = fresh.transport()
            guard transport.rnSDKPeripheral()?.state == .connected,
                  [UInt8(1), UInt8(3)].contains(transport.rnSDKTransportState()) else {
                self.log("底层 BLE 不满足 SDK 在线解绑条件，未执行；保留本 App 绑定以便重试")
                return
            }
            do {
                self.central?.stopScan()
                try core.unbind(fresh)
                self.log("SDK unbound 调用已返回，等待远端证据；本地数量归零不等于远端成功")
                for delay in [2.0,5.0,10.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                        self?.log("解绑 \(Int(delay))s：本 App 绑定数=\(core.bondedDevices()?.count ?? 0)，连接数=\(core.linkedDevices()?.count ?? 0)")
                    }
                }
            } catch { self.log("解绑请求错误: \(error)") }
        })
        present(alert, animated: true)
    }

    private func logDeviceState(_ device: DeviceHandle, prefix: String) {
        let transport = device.transport()
        log("\(prefix)：connected=\(device.isConnected()) / BLE=\(device.bleStateByte()) / transport=\(transport.rnSDKTransportState()) / CB=\(transport.rnSDKPeripheral()?.state.rawValue ?? -1)")
    }

}
