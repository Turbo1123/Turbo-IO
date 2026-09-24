import UIKit
@preconcurrency import AVFAudio

/// Local capture is explicit and foreground-only; leaving this page always closes the owned session.
@available(iOS 26.0, *)
@MainActor final class OfflineCaptionPanel: UITableViewController {
    private let mic = CaptionMicrophoneInput()
    private let speech = CaptionParakeetSpeech()
    private let router = CaptionTranslationRouter()
    private let prefs = UserDefaults(suiteName: "org.turboio.caption.local")!
    private var provider: CaptionTranslationRouter.Provider = .apple
    private var ports: [CaptionMicrophoneInput.Port] = []
    private var port: CaptionMicrophoneInput.Port?
    private var glasses = true, sid = "", original = "", translated = "", translatedSource = ""
    private var state = "离线英语识别 · 点击开始后才收音"
    private var starting = false, recording = false, generation = 0
    private var startTask: Task<Void, Never>?, translateTask: Task<Void, Never>?
    private var timer: Timer?, observer: NSObjectProtocol?
    private var started = Date(), sent = "", lastSend = Date.distantPast
    private var scheduler = CaptionTranslationScheduler()
    private var fastTranslation = true, showingPreview = false
    private var finalLines: [(Int, String)] = []
    private var preparingSource = false
    private let sourceView = UITextView(), targetView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad(); title = "英语离线字幕"
        view.backgroundColor = .systemGroupedBackground
        provider = CaptionTranslationRouter.Provider(rawValue: prefs.string(forKey: "offlineProvider") ?? "apple") ?? .apple
        router.select(provider)
        fastTranslation = prefs.object(forKey: "fastTranslation") == nil ? true : prefs.bool(forKey: "fastTranslation")
        // Leave CPU headroom for capture and CoreML while running both engines.
        router.hymtThreads = min(4, ProcessInfo.processInfo.activeProcessorCount)
        for view in [sourceView, targetView] { view.isEditable = false; view.font = .preferredFont(forTextStyle: .body); view.backgroundColor = .clear }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "停止", style: .plain, target: self, action: #selector(stopTapped))
        speech.onText = { [weak self] text, final in self?.accept(text, final: final) }
        speech.onFailure = { [weak self] code in self?.stop("识别已停止：" + code) }
        mic.onBuffer = { [weak self] buffer in self?.speech.offer(buffer) }
        mic.onFailure = { [weak self] code in self?.stop("收音已停止：" + code) }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in if self?.recording == true { self?.stop("已离开前台，收音和眼镜字幕已停止") } }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            stop("已退出并停止收音")
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [4, 1, 1, 1, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["收音与显示", "会话", "英语 · 实时识别", "中文 · 分段翻译", "资源"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "英语专用，收音可选手机或系统蓝牙麦克风。快速预译：听到约6个词就开始，以后最多每1.2秒发起一次新预译；这是调度间隔，不是总延迟。句末修正，预译可能改写。Hy-MT2 边生成边显示；Apple 每个短块完成后显示。"
        case 1: return state + "\nOFFLINE-ENGLISH-05 · 前台使用，最长 20 分钟。不会上传音频、保存正文或切换云端。眼镜发送成功不等于已肉眼确认。"
        case 3: return translatedSource.isEmpty ? "等待英文；不必等整句结束。" : (showingPreview ? "预译中，后续可能修正：" : "此段已译：") + translatedSource
        case 4: return "ASR 约 214 MiB 已内置并校验。Hy-MT2 已内置；Apple 翻译需预先下载语言包。不朗读译文，避免麦克风再次识别播报。"
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, heightForRowAt path: IndexPath) -> CGFloat { path.section == 2 || path.section == 3 ? 150 : 64 }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.detailTextLabel?.textColor = .secondaryLabel; cell.detailTextLabel?.numberOfLines = 2
        if path.section == 0 {
            cell.textLabel?.text = ["收音来源", "翻译方式", "同步眼镜字幕", "快速预译"][path.row]
            cell.detailTextLabel?.text = path.row == 0 ? (port?.name ?? "默认手机麦克风 · 点击选择") : path.row == 1 ? providerName : path.row == 2 ? (glasses ? "开启 · 仅显示，不启用眼镜录音" : "关闭 · 仅在手机显示") : (fastTranslation ? "开启 · 不等整句，边说边修正" : "关闭 · 等稳定语块后翻译")
            cell.accessoryType = .disclosureIndicator
        } else if path.section == 1 {
            cell.textLabel?.text = recording ? "停止收音与显示" : starting ? "正在准备… 点击取消" : "开始英语离线字幕"
            cell.textLabel?.textColor = recording || starting ? .systemRed : .systemIndigo
            cell.imageView?.image = UIImage(systemName: recording ? "stop.circle.fill" : "mic.circle.fill")
            cell.accessibilityIdentifier = "turbo.offline.start"
        } else if path.section == 2 || path.section == 3 {
            let textView = path.section == 2 ? sourceView : targetView
            textView.text = path.section == 2 ? original : (showingPreview ? "预译 · " : "") + translated
            textView.removeFromSuperview(); textView.frame = CGRect(x: 12, y: 4, width: tableView.bounds.width - 64, height: 142)
            textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cell.contentView.addSubview(textView); cell.selectionStyle = .none
        } else { cell.textLabel?.text = "准备 Apple 英中语言包"; cell.accessoryType = .disclosureIndicator }
        return cell
    }
    private var providerName: String { provider == .apple ? "Apple · 本机英 → 中" : provider == .hymt ? "Hy-MT2 · 本机英 → 中" : "只显示英文，不翻译" }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        if path.section == 1 { if starting || recording { stop("已手动停止") } else { confirmStart() }; return }
        guard !starting, !recording, !preparingSource else { return }
        if path.section == 0 && path.row == 0 { chooseSource() }
        else if path.section == 0 && path.row == 1 {
            let alert = UIAlertController(title: "离线翻译", message: "不启用云端兜底。", preferredStyle: .alert)
            for (value, label) in [(CaptionTranslationRouter.Provider.originalOnly, "仅英文字幕"), (.apple, "Apple 本机翻译"), (.hymt, "Hy-MT2 本机翻译")] {
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    guard let self else { return }; self.provider = value; self.router.select(value); self.prefs.set(value.rawValue, forKey: "offlineProvider"); self.tableView.reloadData()
                })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel)); present(alert, animated: true)
        } else if path.section == 0 && path.row == 2 { glasses.toggle(); tableView.reloadData() }
        else if path.section == 0 && path.row == 3 { fastTranslation.toggle(); prefs.set(fastTranslation, forKey: "fastTranslation"); tableView.reloadData() }
        else if path.section == 4 { navigationController?.pushViewController(CaptionLocalTranslation.preparationController(source: "en", target: "zh"), animated: true) }
    }
    private func chooseSource() {
        preparingSource = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.preparingSource = false }
            do {
                self.ports = try await self.mic.prepare(); self.mic.stop()
                guard self.viewIfLoaded?.window != nil else { return }
                let alert = UIAlertController(title: "收音来源", message: "蓝牙耳机需先连接手机。切换设备会停止当前会话。", preferredStyle: .alert)
                for port in self.ports {
                    alert.addAction(UIAlertAction(title: port.name, style: .default) { [weak self] _ in self?.port = port; self?.tableView.reloadData() })
                }
                alert.addAction(UIAlertAction(title: "取消", style: .cancel)); self.present(alert, animated: true)
            } catch { self.mic.stop(); self.state = "无法准备麦克风，请检查系统权限和音频占用"; self.tableView.reloadData() }
        }
    }
    private func confirmStart() {
        let alert = UIAlertController(title: "开始收音？", message: "请确认没有录音、语音对话、提词或导航，眼镜已回首页。只在本机识别和翻译，不保存音频。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认空闲并开始", style: .default) { [weak self] _ in self?.start() }); present(alert, animated: true)
    }
    private func start() {
        guard !starting, !recording, !preparingSource else { return }
        starting = true; generation += 1; let epoch = generation; state = "正在校验并加载离线模型…"; tableView.reloadData()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.speech.prepare()
                if self.provider == .hymt { try await self.router.loadHyMT(TIOCaptionPhoneProbe.modelURL()) }
                try Task.checkCancellation()
                self.ports = try await self.mic.prepare()
                let selected = self.port.flatMap { old in self.ports.first { $0.uid == old.uid } } ?? (self.port == nil ? self.ports.first { $0.type == AVAudioSession.Port.builtInMic.rawValue } : nil)
                guard let selected else { throw CaptionFailure.routeChanged }; self.port = selected
                if self.glasses {
                    let result = CaptionHost.call("start")
                    guard let sid = result["sid"] as? String, !sid.isEmpty else { throw CaptionFailure.unavailable }
                    self.sid = sid
                    var ready = false
                    for _ in 0..<40 {
                        try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation()
                        let status = CaptionHost.call("status")
                        guard status["sid"] as? String == sid else { throw CaptionFailure.unavailable }
                        if status["phase"] as? String == "ready" { ready = true; break }
                        if ["stopping", "uncertain", "idle"].contains(status["phase"] as? String ?? "") { break }
                    }
                    guard ready else { throw CaptionFailure.unavailable }
                }
                guard self.generation == epoch, UIApplication.shared.applicationState == .active else { throw CancellationError() }
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                try await self.mic.start(uid: selected.uid, format: format)
                try Task.checkCancellation()
                self.starting = false; self.recording = true; self.started = Date(); self.original = ""; self.translated = ""; self.translatedSource = ""; self.sent = ""; self.scheduler = CaptionTranslationScheduler(); self.scheduler.previews = self.fastTranslation; self.finalLines = []; self.showingPreview = false
                self.state = "正在本机收音 · " + selected.name; self.tableView.reloadData()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.pump() } }
            } catch {
                if self.generation == epoch { self.stop(error is CancellationError ? "已取消" : "启动失败：请检查麦克风权限、模型完整性及眼镜连接；可关闭同步眼镜单测收音") }
            }
        }
    }
    private func accept(_ text: String, final: Bool) {
        guard recording else { return }
        original = text; sourceView.text = text
        guard provider != .originalOnly else { return }
        do { try scheduler.offer(text, final: final); translateNext() }
        catch { stop("翻译积压或识别片段变化，已停止以免显示错配。可关闭快速预译或改用仅英文字幕。") }
    }
    private func translateNext() {
        guard translateTask == nil, recording, let request = scheduler.next(now: ProcessInfo.processInfo.systemUptime) else { return }
        let text = request.text, epoch = generation
        translateTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.router.translateStable(text, source: "en", target: "zh") { [weak self] partial in
                    guard let self, self.generation == epoch, self.recording else { return }
                    self.showTranslation(partial, request: request, complete: false)
                }
                guard self.generation == epoch, !Task.isCancelled else { return }
                self.showTranslation(result, request: request, complete: true)
                self.tableView.reloadSections(IndexSet(integer: 3), with: .none)
            } catch {
                guard self.generation == epoch else { return }
                self.state = "翻译失败（无云端兜底），英文识别继续；请检查本地语言包"
                self.tableView.reloadSections(IndexSet(integer: 1), with: .none)
            }
            guard self.generation == epoch else { return }
            self.scheduler.complete(request); self.translateTask = nil; self.translateNext()
        }
    }
    private func showTranslation(_ value: String, request: CaptionTranslationScheduler.Request, complete: Bool) {
        showingPreview = !request.final || !complete
        translatedSource = request.text
        if request.final && complete {
            finalLines.removeAll { $0.0 == request.id }; finalLines.append((request.id, value))
            if finalLines.count > 2 { finalLines.removeFirst(finalLines.count - 2) }
        }
        let previous = finalLines.filter { $0.0 < request.id }.suffix(1).map { $0.1 }
        translated = (previous + [value]).joined(separator: "\n")
        targetView.text = (showingPreview ? "预译 · " : "") + translated
    }
    private func pump() {
        guard recording else { return }
        translateNext()
        if Date().timeIntervalSince(started) >= 1200 { stop("20分钟保护到期，已停止"); return }
        guard !sid.isEmpty else { return }
        let status = CaptionHost.call("status")
        guard status["sid"] as? String == sid, status["phase"] as? String == "ready" else { stop("眼镜会话已结束，收音同步停止"); return }
        let text = CaptionSegmenter.display(original: original, translated: translated, preview: showingPreview)
        guard !text.isEmpty, text != sent, Date().timeIntervalSince(lastSend) >= 0.5, status["pending"] as? Bool != true else { return }
        if CaptionHost.call("text", ["sid": sid, "text": text])["ok"] as? Bool == true { sent = text; lastSend = Date() }
    }
    @objc private func stopTapped() { stop("已手动停止") }
    private func stop(_ reason: String) {
        generation += 1; starting = false; recording = false
        startTask?.cancel(); startTask = nil; timer?.invalidate(); timer = nil
        mic.stop(); speech.stop(); translateTask?.cancel(); translateTask = nil; router.stop(); scheduler = CaptionTranslationScheduler()
        if !sid.isEmpty { _ = CaptionHost.call("stop", ["sid": sid]); sid = "" }
        state = reason; tableView.reloadData()
    }
}
