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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lab = SessionLabModel()
    private var phaseName: String {
        switch lab.snapshot.phase {
        case .disconnected: return "尚未开始"
        case .idle: return "模拟连接就绪"
        case .listening: return "模拟聆听中"
        case .awaitingTranscript: return "等待示例识别结果"
        case .generating: return "等待示例模型结果"
        case .speaking: return "模拟 TTS 回复中"
        case .awaitingNextRound: return "等待下一轮"
        case .awaitingToolApproval: return "等待工具确认（仅状态）"
        case .closed: return "会话已收尾"
        }
    }
    private var isActive: Bool { ![.disconnected, .idle, .closed].contains(lab.snapshot.phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("纯逻辑模拟 · 不采音、不联网、不操作眼镜", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.98, green: 0.92, blue: 0.77), in: RoundedRectangle(cornerRadius: 14))
                    Card {
                        HStack { Text("语音会话流程").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink); Spacer(); Badge(text: phaseName, active: true) }
                        VStack(spacing: 0) {
                            timelineRow("唤醒", active: [.idle, .listening].contains(lab.snapshot.phase), complete: [.awaitingTranscript, .generating, .speaking, .awaitingNextRound, .closed].contains(lab.snapshot.phase), last: false)
                            timelineRow("识别", active: [.listening, .awaitingTranscript].contains(lab.snapshot.phase), complete: [.generating, .speaking, .awaitingNextRound].contains(lab.snapshot.phase), last: false)
                            timelineRow("模型回复", active: [.generating, .speaking].contains(lab.snapshot.phase), complete: lab.snapshot.phase == .awaitingNextRound, last: false)
                            timelineRow("收尾", active: lab.snapshot.phase == .awaitingNextRound, complete: lab.snapshot.phase == .closed, last: true)
                        }
                        HStack {
                            Text("轮次 \(lab.snapshot.currentRound.map { $0.index + 1 } ?? 0)")
                            Spacer()
                            Text("已完成 \(lab.snapshot.completedRoundCount) 轮")
                        }.font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                        Toggle("模拟网络可用", isOn: Binding(get: { lab.snapshot.networkAvailable }, set: { lab.network($0) }))
                            .font(.subheadline).disabled(isActive)
                        Text("这是本应用的云端优先 / 本地回退策略实验，不是官方 App 的识别结论。切换不改变手机网络。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                        if let source = lab.snapshot.asrSource {
                            Label(source == .local ? "策略选择：本地识别" : "策略选择：云端识别", systemImage: source == .local ? "iphone" : "cloud")
                                .font(.caption).foregroundStyle(Palette.green)
                        }
                        if !lab.snapshot.transcript.isEmpty {
                            Text("示例提问：\(lab.snapshot.transcript)").font(.subheadline).foregroundStyle(Palette.ink)
                        }
                        if !lab.snapshot.response.isEmpty {
                            Text("示例回答：\(lab.snapshot.response)").font(.subheadline).foregroundStyle(Palette.green)
                        }
                        mainAction
                        if isActive {
                            HStack {
                                Button("模拟打断") { lab.interrupt() }.accessibilityIdentifier("lab-interrupt")
                                Spacer()
                                Button("模拟退出") { lab.exit() }.accessibilityIdentifier("lab-exit")
                            }.font(.system(size: 13, weight: .medium))
                        }
                        if lab.canTestStale {
                            Button("注入上轮迟到回调") { lab.staleCallback() }.font(.caption).accessibilityIdentifier("lab-stale")
                        }
                        if let result = lab.staleCallbackResult { Text(result).font(.caption).foregroundStyle(Palette.green) }
                    }
                    Card {
                        DisclosureGroup("意图轨迹（没有执行副作用）") {
                            if lab.events.isEmpty {
                                Text("手动开始模拟后展示核心返回的意图。不会执行音频、模型、工具或蓝牙操作。")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(5).padding(.top, 10)
                            } else {
                                ForEach(Array(lab.events.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                            }
                        }.font(.system(size: 13, weight: .medium))
                    }
                    Card {
                        Text("工具批准保护").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.green)
                        FeatureRow(icon: "link", title: "请求绑定", subtitle: "未连接真实工具请求", status: "未执行")
                        FeatureRow(icon: "checkmark.shield", title: "有效期检查", subtitle: "未签发或消费授权", status: "未执行")
                        FeatureRow(icon: "square.on.square", title: "重复保护", subtitle: "只展示事件，不执行工具", status: "未执行")
                    }
                }.padding(24)
            }.background(Palette.background).navigationTitle("协议实验室").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
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
            Text(complete ? "模拟完成" : active ? "当前步骤" : "等待中").font(.system(size: 11)).foregroundStyle(active || complete ? Palette.green : Palette.muted)
        }
    }

    @ViewBuilder private var mainAction: some View {
        switch lab.snapshot.phase {
        case .disconnected: PrimaryButton(title: "手动开启模拟连接") { lab.connect() }.accessibilityIdentifier("lab-connect")
        case .idle, .closed: PrimaryButton(title: "模拟唤醒") { lab.wake() }.accessibilityIdentifier("lab-wake")
        case .listening, .awaitingTranscript: PrimaryButton(title: "注入示例识别结果") { lab.transcript() }.accessibilityIdentifier("lab-asr")
        case .generating: PrimaryButton(title: "注入示例回答 + TTS 开始") { lab.answer() }.accessibilityIdentifier("lab-answer")
        case .speaking: PrimaryButton(title: "模拟 TTS 输入结束 + 播放耗尽") { lab.finishSpeech() }.accessibilityIdentifier("lab-tts-finish")
        case .awaitingNextRound: PrimaryButton(title: "模拟眼镜开启下一轮") { lab.nextRound() }.accessibilityIdentifier("lab-next")
        case .awaitingToolApproval:
            Text("等待工具确认 · 仅状态展示，未接入授权执行器")
                .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("lab-tool-approval-pending")
        }
    }
}
