import SwiftUI
import RayNeoSession

@MainActor
final class SessionLabModel: ObservableObject {
    @Published private var machine = VoiceSessionMachine(configuration: .init(asrPolicy: .preferCloudWithLocalFallback, ttsMode: .enabled))
    @Published private(set) var events: [String] = []
    @Published private(set) var staleCallbackResult: String?
    private var previousRound: RoundToken?
    var snapshot: SessionSnapshot { machine.snapshot }

    func send(_ event: VoiceSessionEvent, label: String) {
        let effects = machine.handle(event)
        events.insert("\(label) → \(effects.count) 个意图", at: 0)
        for effect in effects.reversed() {
            events.insert("  \(effectName(effect))", at: 1)
        }
        events = Array(events.prefix(60))
    }

    func connect() { send(.connected, label: "模拟连接") }
    func wake() { send(.wake, label: "模拟唤醒") }
    func network(_ available: Bool) { send(.networkChanged(isAvailable: available), label: available ? "模拟网络可用" : "模拟断网") }
    func transcript() {
        guard let round = snapshot.currentRound, let source = snapshot.asrSource else { return }
        send(.audioEnded(round: round), label: "模拟语音结束")
        send(.asrResult(round: round, source: source, result: .init(revision: 1, text: "三加四等于几？", isFinal: true)), label: "注入示例识别文字")
    }
    func answer() {
        guard let round = snapshot.currentRound else { return }
        send(.modelText(round: round, update: .init(revision: 1, text: "三加四等于七。")), label: "注入示例模型回答")
        send(.modelFinished(round: round), label: "模拟模型完成")
        send(.ttsStarted(round: round), label: "模拟 TTS 开始")
    }
    func finishSpeech() {
        guard let round = snapshot.currentRound else { return }
        send(.ttsInputFinished(round: round), label: "模拟 TTS 输入完毕")
        send(.ttsPlaybackDrained(round: round), label: "模拟播放缓冲耗尽")
    }
    func nextRound() {
        guard let round = snapshot.currentRound else { return }
        previousRound = round
        send(.nextRound(round: round), label: "模拟眼镜下一轮")
    }
    func interrupt() {
        guard let round = snapshot.currentRound else { return }
        previousRound = round
        send(.interrupt(round: round), label: "模拟打断并开启下一轮")
    }
    func staleCallback() {
        guard let round = previousRound else { return }
        let before = snapshot
        let effects = machine.handle(.modelText(round: round, update: .init(revision: 99, text: "已失效的示例回答")))
        staleCallbackResult = effects.isEmpty && before == snapshot ? "旧轮回调被忽略，当前会话未改变" : "旧轮回调改变了状态，请检查核心"
        events.insert(staleCallbackResult ?? "", at: 0)
    }
    func exit() { send(.exitRequested(reason: .normal), label: "模拟退出") }
    var canTestStale: Bool { previousRound != nil }

    private func effectName(_ effect: VoiceSessionEffect) -> String {
        switch effect {
        case .startRecognition: return "启动识别（未执行）"
        case .feedRecognition: return "提供音频（未执行）"
        case .finishRecognition: return "结束识别输入（未执行）"
        case .cancelRecognition: return "取消识别（未执行）"
        case .startCapture: return "开启采集（未执行）"
        case .stopCapture: return "停止采集（未执行）"
        case .requestModel: return "请求模型（未执行）"
        case .synthesizeAndPlay: return "合成并播放（未执行）"
        case .cancelWork: return "取消当前轮工作（未执行）"
        case .invalidateToolApprovals: return "使当前轮工具授权失效（未执行）"
        case .displayTranscript: return "显示识别文字（未发送）"
        case .displayResponse: return "显示回答（未发送）"
        case .reportTTSStatus: return "同步 TTS 状态（未发送）"
        case .responseComplete: return "回复完成意图（未发送，不是退出）"
        case .requestExit: return "退出页面意图（未发送）"
        case .scheduleTimeout: return "安排超时（实验中不运行定时器）"
        case .cancelTimeout: return "取消超时（实验中不运行定时器）"
        case .reportFailure: return "报告错误（仅本地意图）"
        }
    }
}

struct SessionSimulationView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lab = SessionLabModel()
    private var phaseName: String {
        switch lab.snapshot.phase {
        case .disconnected: return L10n.text("Not Started", locale: locale)
        case .idle: return L10n.text("Simulated Connection Ready", locale: locale)
        case .listening: return L10n.text("Simulated Listening", locale: locale)
        case .awaitingTranscript: return L10n.text("Waiting for Sample Recognition Result", locale: locale)
        case .generating: return L10n.text("Waiting for Sample Model Result", locale: locale)
        case .speaking: return L10n.text("Simulated TTS Response", locale: locale)
        case .awaitingNextRound: return L10n.text("Waiting for Next Turn", locale: locale)
        case .awaitingToolApproval: return L10n.text("Waiting for Tool Confirmation (Status Only)", locale: locale)
        case .closed: return L10n.text("Session Finished", locale: locale)
        }
    }
    private var isActive: Bool { ![.disconnected, .idle, .closed].contains(lab.snapshot.phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.text("Logic Simulation Only · No Audio Capture, Network, or Glasses Actions", locale: locale), systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.98, green: 0.92, blue: 0.77), in: RoundedRectangle(cornerRadius: 14))
                    Card {
                        HStack { Text(L10n.text("Voice Session Workflow", locale: locale)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink); Spacer(); Badge(text: phaseName, active: true) }
                        VStack(spacing: 0) {
                            timelineRow(L10n.text("Wake", locale: locale), active: [.idle, .listening].contains(lab.snapshot.phase), complete: [.awaitingTranscript, .generating, .speaking, .awaitingNextRound, .closed].contains(lab.snapshot.phase), last: false)
                            timelineRow(L10n.text("Recognize", locale: locale), active: [.listening, .awaitingTranscript].contains(lab.snapshot.phase), complete: [.generating, .speaking, .awaitingNextRound].contains(lab.snapshot.phase), last: false)
                            timelineRow(L10n.text("Model Response", locale: locale), active: [.generating, .speaking].contains(lab.snapshot.phase), complete: lab.snapshot.phase == .awaitingNextRound, last: false)
                            timelineRow(L10n.text("Finish", locale: locale), active: lab.snapshot.phase == .awaitingNextRound, complete: lab.snapshot.phase == .closed, last: true)
                        }
                        HStack {
                            Text(L10n.format("Turn %@", locale: locale, String(describing: lab.snapshot.currentRound.map { $0.index + 1 } ?? 0)))
                            Spacer()
                            Text(L10n.format("%@ turns completed", locale: locale, String(describing: lab.snapshot.completedRoundCount)))
                        }.font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                        Toggle(L10n.text("Simulate Network Availability", locale: locale), isOn: Binding(get: { lab.snapshot.networkAvailable }, set: { lab.network($0) }))
                            .font(.subheadline).disabled(isActive)
                        Text(L10n.text("This tests the app's cloud-first, local-fallback strategy. It is not a recognition result from the official app. Toggling does not change your phone's network.", locale: locale))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                        if let source = lab.snapshot.asrSource {
                            Label(source == .local ? L10n.text("Selected Strategy: Local Recognition", locale: locale) : L10n.text("Selected Strategy: Cloud Recognition", locale: locale), systemImage: source == .local ? "iphone" : "cloud")
                                .font(.caption).foregroundStyle(Palette.green)
                        }
                        if !lab.snapshot.transcript.isEmpty {
                            Text(L10n.format("Sample question: %@", locale: locale, String(describing: lab.snapshot.transcript))).font(.subheadline).foregroundStyle(Palette.ink)
                        }
                        if !lab.snapshot.response.isEmpty {
                            Text(L10n.format("Sample response: %@", locale: locale, String(describing: lab.snapshot.response))).font(.subheadline).foregroundStyle(Palette.green)
                        }
                        mainAction
                        if isActive {
                            HStack {
                                Button(L10n.text("Simulate Interruption", locale: locale)) { lab.interrupt() }.accessibilityIdentifier("lab-interrupt")
                                Spacer()
                                Button(L10n.text("Simulate Exit", locale: locale)) { lab.exit() }.accessibilityIdentifier("lab-exit")
                            }.font(.system(size: 13, weight: .medium))
                        }
                        if lab.canTestStale {
                            Button(L10n.text("Inject Late Callback from Previous Turn", locale: locale)) { lab.staleCallback() }.font(.caption).accessibilityIdentifier("lab-stale")
                        }
                        if let result = lab.staleCallbackResult { Text(result).font(.caption).foregroundStyle(Palette.green) }
                    }
                    Card {
                        DisclosureGroup(L10n.text("Intent Trace (No Side Effects Executed)", locale: locale)) {
                            if lab.events.isEmpty {
                                Text(L10n.text("After you manually start the simulation, this shows intents returned by the core. No audio, model, tool, or Bluetooth operations are executed.", locale: locale))
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5).padding(.top, 10)
                            } else {
                                ForEach(Array(lab.events.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                            }
                        }.font(.system(size: 13, weight: .medium))
                    }
                    Card {
                        Text(L10n.text("Tool Approval Protection", locale: locale)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.green)
                        FeatureRow(icon: "link", title: L10n.text("Request Binding", locale: locale), subtitle: L10n.text("No Real Tool Request Connected", locale: locale), status: L10n.text("Not Executed", locale: locale))
                        FeatureRow(icon: "checkmark.shield", title: L10n.text("Expiration Check", locale: locale), subtitle: L10n.text("No Authorization Issued or Consumed", locale: locale), status: L10n.text("Not Executed", locale: locale))
                        FeatureRow(icon: "square.on.square", title: L10n.text("Duplicate Protection", locale: locale), subtitle: L10n.text("Displays Events Only; Does Not Run Tools", locale: locale), status: L10n.text("Not Executed", locale: locale))
                    }
                }.padding(24)
            }.background(Palette.background).navigationTitle(L10n.text("Protocol Lab", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } }
        }
    }

    private func timelineRow(_ title: String, active: Bool, complete: Bool, last: Bool) -> some View {
        HStack(spacing: 15) {
            VStack(spacing: 0) {
                Image(systemName: complete ? "checkmark.circle.fill" : active ? "play.circle.fill" : "circle")
                    .font(.system(size: 21)).foregroundStyle(active || complete ? Palette.green : Palette.muted.opacity(0.5))
                    .frame(height: 27)
                if !last { Rectangle().fill(Palette.line).frame(width: 1, height: 16) }
            }
            Text(title).font(.system(size: 14)).foregroundStyle(active || complete ? Palette.ink : Palette.muted)
            Spacer()
            Text(complete ? L10n.text("Simulation Complete", locale: locale) : active ? L10n.text("Current Step", locale: locale) : L10n.text("Waiting", locale: locale)).font(.system(size: 11)).foregroundStyle(active || complete ? Palette.green : Palette.muted)
        }
    }

    @ViewBuilder private var mainAction: some View {
        switch lab.snapshot.phase {
        case .disconnected: PrimaryButton(title: L10n.text("Start Simulated Connection Manually", locale: locale)) { lab.connect() }.accessibilityIdentifier("lab-connect")
        case .idle, .closed: PrimaryButton(title: L10n.text("Simulate Wake", locale: locale)) { lab.wake() }.accessibilityIdentifier("lab-wake")
        case .listening, .awaitingTranscript: PrimaryButton(title: L10n.text("Inject Sample Recognition Result", locale: locale)) { lab.transcript() }.accessibilityIdentifier("lab-asr")
        case .generating: PrimaryButton(title: L10n.text("Inject Sample Response + TTS Start", locale: locale)) { lab.answer() }.accessibilityIdentifier("lab-answer")
        case .speaking: PrimaryButton(title: L10n.text("Simulate End of TTS Input + Playback Drained", locale: locale)) { lab.finishSpeech() }.accessibilityIdentifier("lab-tts-finish")
        case .awaitingNextRound: PrimaryButton(title: L10n.text("Simulate Glasses Starting Next Turn", locale: locale)) { lab.nextRound() }.accessibilityIdentifier("lab-next")
        case .awaitingToolApproval:
            Text(L10n.text("Waiting for tool confirmation · Status display only, no authorization executor connected", locale: locale))
                .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("lab-tool-approval-pending")
        }
    }
}
