import UIKit

@available(iOS 26.0, *)
@objc(TIOCaptionLocalPanel)
@MainActor final class LocalTranslationPanel: UITableViewController {
    private let router = CaptionTranslationRouter()
    private let preferences = UserDefaults(suiteName: "org.turboio.caption.local")!
    private var provider: CaptionTranslationRouter.Provider = .apple
    private var englishToChinese = true
    private var input = "Please turn left at the next intersection."
    private var output = "译文会显示在这里。"
    private var status = "尚未运行 · 本机文字测试"
    private var busy = false
    private var task: Task<Void, Never>?
    private let editor = UITextView()
    private let resultView = UITextView()
    @objc static func makeController() -> UIViewController { LocalTranslationPanel(style: .insetGrouped) }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "字幕 · 本地翻译"
        provider = CaptionTranslationRouter.Provider(rawValue: preferences.string(forKey: "provider") ?? "apple") ?? .apple
        if provider == .originalOnly { provider = .apple }
        router.select(provider)
        let savedThreads = preferences.integer(forKey: "hymtThreads")
        router.hymtThreads = [2, 3, 4, 6, 8].contains(savedThreads) ? savedThreads : min(6, ProcessInfo.processInfo.activeProcessorCount)
        view.backgroundColor = .systemGroupedBackground
        editor.font = .preferredFont(forTextStyle: .body)
        editor.text = input; editor.accessibilityIdentifier = "turbo.localtranslation.input"
        editor.backgroundColor = .clear
        tableView.keyboardDismissMode = .interactive
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "停止", style: .plain, target: self, action: #selector(stop))
        navigationItem.rightBarButtonItems = [UIBarButtonItem(image: UIImage(systemName: "mic.fill"), style: .plain, target: self, action: #selector(openOffline)), UIBarButtonItem(title: "停止", style: .plain, target: self, action: #selector(stop))]
        tableView.accessibilityIdentifier = "turbo.localtranslation.phone01"
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { stop() }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 6 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [3, 2, 1, 1, 3, 1][section]
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["翻译引擎", "本机资源", "输入文字", "译文", "运行测试", "英语实时收音"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "LOCAL-TRANSLATION-SOURCE-01\n右上角麦克风或页面底部进入英语离线字幕；本页保留文字翻译测试。" }
        if section == 1 { return "Hy-MT2 需按开源文档下载并随自己的构建打包，加载前校验完整 SHA；无需 Key。Apple 语言包需你明确下载。翻译失败不会自动上传到云端。" }
        if section == 4 { return status + "\n只在页面显示输入与译文，不保存你的测试正文。退出页面释放模型；连续字幕的延迟与耗电仍待实测。" }
        return nil
    }
    override func tableView(_ tableView: UITableView, heightForRowAt path: IndexPath) -> CGFloat {
        if path.section == 2 { return 138 }
        if path.section == 3 { return 160 }
        return 62
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.selectionStyle = .default
        switch path.section {
        case 0:
            cell.textLabel?.text = ["翻译引擎", "翻译方向", "Hy-MT2 性能"][path.row]
            cell.detailTextLabel?.text = path.row == 0 ? (provider == .hymt ? "Hy-MT2 · 本机 CPU" : "Apple · 本机翻译") : path.row == 1 ? (englishToChinese ? "英语 → 中文" : "中文 → 英语") : "\(router.hymtThreads) 线程 · 不超过本机可用核心"
            cell.imageView?.image = UIImage(systemName: path.row == 0 ? "cpu" : "arrow.left.arrow.right")
            cell.accessoryType = .disclosureIndicator
        case 1:
            cell.textLabel?.text = path.row == 0 ? "Hy-MT2 模型" : "准备 Apple 语言包"
            cell.detailTextLabel?.text = path.row == 0 ? (router.localModelReady ? "已加载 · 点击释放内存" : "内置约 440 MiB · 首次翻译时校验加载") : "仅在你确认后下载系统语言资源"
            cell.imageView?.image = UIImage(systemName: path.row == 0 ? "internaldrive" : "character.book.closed")
        case 2:
            cell.selectionStyle = .none
            editor.removeFromSuperview(); editor.frame = CGRect(x: 12, y: 4, width: tableView.bounds.width - 64, height: 130)
            editor.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cell.contentView.addSubview(editor)
        case 3:
            cell.selectionStyle = .none
            let result = resultView
            result.removeFromSuperview(); result.frame = CGRect(x: 12, y: 4, width: tableView.bounds.width - 64, height: 152)
            result.isEditable = false; result.text = output; result.backgroundColor = .clear
            result.font = .preferredFont(forTextStyle: .body); result.accessibilityIdentifier = "turbo.localtranslation.result"
            result.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cell.contentView.addSubview(result)
        case 5:
            cell.textLabel?.text = "英语离线字幕 · Parakeet"
            cell.detailTextLabel?.text = "手机 / 蓝牙麦克风 → 本机识别翻译 → 眼镜"
            cell.imageView?.image = UIImage(systemName: "mic.fill"); cell.accessoryType = .disclosureIndicator
        default:
            cell.textLabel?.text = path.row == 0 ? (busy ? "正在本机翻译…" : "翻译输入文字") : path.row == 1 ? "载入固定测试句" : "载入《哈姆雷特》长文"
            cell.imageView?.image = UIImage(systemName: path.row == 0 ? "play.circle.fill" : "text.quote")
            cell.textLabel?.textColor = .systemIndigo
            cell.accessibilityIdentifier = path.row == 0 ? "turbo.localtranslation.translate" : "turbo.localtranslation.fixture"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard !busy else { return }
        if path.section == 5 { openOffline(); return }
        if path.section == 0 && path.row == 0 {
            let sheet = UIAlertController(title: "选择本机翻译引擎", message: "本页为验收入口，不改变官方字幕。", preferredStyle: .actionSheet)
            for (value, title) in [(CaptionTranslationRouter.Provider.apple, "Apple 本机翻译"), (.hymt, "Hy-MT2 本机翻译")] {
                sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    guard let self else { return }; self.provider = value; self.router.select(value)
                    self.preferences.set(value.rawValue, forKey: "provider"); self.status = "已选择，尚未运行"; self.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: path)
            present(sheet, animated: true)
        } else if path.section == 0 && path.row == 2 {
            let sheet = UIAlertController(title: "Hy-MT2 性能", message: "更多线程不一定更快。保留收音与蓝牙所需资源；热保护始终开启。", preferredStyle: .actionSheet)
            for threads in [2, 3, 4, 6, 8] where threads <= ProcessInfo.processInfo.activeProcessorCount {
                sheet.addAction(UIAlertAction(title: "\(threads) 线程", style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.router.hymtThreads = threads; self.preferences.set(threads, forKey: "hymtThreads"); self.tableView.reloadData()
                })
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: path)
            present(sheet, animated: true)
        } else if path.section == 0 {
            englishToChinese.toggle(); tableView.reloadData()
        } else if path.section == 1 && path.row == 0 {
            router.stop(); status = "模型已释放，下一次翻译时重新加载"; tableView.reloadData()
        } else if path.section == 1 {
            navigationController?.pushViewController(CaptionLocalTranslation.preparationController(source: "en", target: "zh"), animated: true)
        } else if path.section == 4 && path.row == 0 { translate() }
        else if path.section == 4 {
            if path.row == 2 { englishToChinese = true; editor.text = HyMTPerformanceProbe.hamlet; tableView.reloadData() }
            else { editor.text = englishToChinese ? "Please turn left at the next intersection." : "请问最近的地铁站在哪里？" }
        }
    }
    @objc private func stop() {
        task?.cancel(); router.stop(); status = "已停止并释放模型"; tableView.reloadData()
    }
    @objc private func openOffline() {
        guard !busy else { return }; router.stop()
        navigationController?.pushViewController(OfflineCaptionPanel(style: .insetGrouped), animated: true)
    }
    private func translate() {
        input = editor.text ?? ""; view.endEditing(true)
        guard !input.isEmpty, input.utf8.count <= 4096 else { status = "请输入不超过 4096 字节的短句"; tableView.reloadData(); return }
        busy = true; status = "校验并准备本机引擎…"; output = ""; tableView.reloadData()
        let text = input, from = englishToChinese ? "en" : "zh", to = englishToChinese ? "zh" : "en"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.task = nil; self.tableView.reloadData() }
            do {
                let start = ContinuousClock.now
                if self.provider == .hymt && !self.router.localModelReady { try await self.router.loadHyMT(TIOCaptionPhoneProbe.modelURL()) }
                try Task.checkCancellation()
                let result = try await self.router.translateStable(text, source: from, target: to) { [weak self] partial in
                    guard let self else { return }
                    self.output = partial; self.resultView.text = partial
                }
                try Task.checkCancellation()
                self.output = result; self.status = "本机完成 · 含准备耗时 \(start.duration(to: .now))"
                if self.provider == .hymt, let timing = self.router.lastTiming {
                    self.status += String(format: "\n%d 线程 · 首 token %.0f ms · 推理 %.0f ms · 输出 %d tokens", timing.threads, timing.firstTokenMS, timing.totalMS, timing.outputTokens)
                }
            } catch is CancellationError { self.output = ""; self.status = "已取消，旧译文已丢弃" }
            catch { self.output = ""; self.status = "未完成：\(TIOCaptionPhoneProbe.safeError(error))" }
        }
    }
}

@available(iOS 26.0, *)
@objc(TIOCaptionPhoneProbe)
@MainActor final class TIOCaptionPhoneProbe: NSObject {
    private static var running = false
    static func modelURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "Hy-MT2-1.8B-STQ43", withExtension: "gguf", subdirectory: "TurboCaptionModels") else { throw HyMTFailure.invalidModel }
        return url
    }
    static func safeError(_ error: Error) -> String {
        switch error {
        case HyMTFailure.invalidModel: return "model_missing_or_hash_mismatch"
        case HyMTFailure.native(let status): return "native_\(status)"
        case HyMTFailure.busy: return "busy"
        case CaptionFailure.unavailable: return "apple_language_not_installed"
        case is CancellationError: return "cancelled"
        default: return "local_translation_failed"
        }
    }
    @objc static func runFixedProbe() {
        guard !running, ProcessInfo.processInfo.environment["TIO_LOCAL_TRANSLATION_PROBE"] == "HYMT_PHONE_01" else { return }
        if ProcessInfo.processInfo.environment["TIO_HYMT_PERF_PROBE"] == "PERF_02" { HyMTPerformanceProbe.run(); return }
        running = true
        Task {
            let engine = CaptionHyMTTranslation()
            var report: [String: Any] = ["build": "LOCAL-TRANSLATION-PHONE-01", "syntheticOnly": true, "pid": ProcessInfo.processInfo.processIdentifier, "startedAt": ISO8601DateFormatter().string(from: Date()), "os": UIDevice.current.systemVersion, "networkUsed": false, "microphoneUsed": false, "glassesWrites": false]
            func save(_ phase: String) {
                report["phase"] = phase
                do {
                    var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TurboCaptionTests", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
                    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("phone01.json"), options: .atomic)
                } catch { /* Never print paths, account data, or a raw system error. */ }
            }
            defer { engine.unload(); running = false }
            save("loading")
            do {
                let loadStart = Date()
                try await engine.load(url: modelURL())
                report["load_ms"] = Date().timeIntervalSince(loadStart) * 1000
                report["model_sha256"] = CaptionHyMTTranslation.modelSHA256
                save("loaded")
                var results: [[String: Any]] = []
                for (text, source, target) in [("Please turn left at the next intersection.", "en", "zh"), ("请问最近的地铁站在哪里？", "zh", "en"), ("Could you speak more slowly? I am using live captions.", "en", "zh")] {
                    let start = Date(); let result = try await engine.translate(text, source: source, target: target)
                    results.append(["fixture": results.count, "source": source, "target": target, "output": result, "elapsed_ms": Date().timeIntervalSince(start) * 1000])
                    report["results"] = results; save("translating")
                }
                engine.unload(); report["passed"] = true; save("completed")
            } catch { report["passed"] = false; report["error"] = safeError(error); save("failed") }
        }
    }
}
