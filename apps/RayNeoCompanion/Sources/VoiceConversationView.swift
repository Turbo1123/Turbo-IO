import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var showKeys = false
    @State private var showConfiguration = false
    @State private var showSimulation = false
    @State private var showDiagnostics = false
    @State private var useCloud = true
    @State private var continuous = true
    @State private var confirmStart = false
    var body: some View {
        Screen(title: "语音会话", eyebrow: "云端断句 · 流式对话") {
            HStack {
                Label(runtime.phaseLabel, systemImage: runtime.enabled ? "waveform" : "moon")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: runtime.supportsDevice ? (runtime.ready ? "已认证" : "未连接") : "模拟器预览")
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 18) {
                Label("你说的话", systemImage: "mic").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.transcript.isEmpty ? "唤醒后，识别文字会显示在这里" : runtime.transcript)
                    .font(.system(size: 18)).foregroundStyle(.white).privacySensitive()
                Divider().overlay(Palette.mint.opacity(0.3))
                Label("DeepSeek Flash", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.answer.isEmpty ? "回答逐字显示，开口可以打断" : runtime.answer)
                    .font(.system(size: 16)).foregroundStyle(Palette.mint).lineSpacing(6).privacySensitive()
                if runtime.modelComplete { Text("模型输出已完成 · 不等于镜片渲染完成").font(.caption2).foregroundStyle(Palette.mint.opacity(0.6)) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("live-voice-content")
            if !runtime.enabled {
                Text("麦克风未启用 · 没有音频正在传输").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text(runtime.phase == "idle" || runtime.phase == "waitingForConnection" ? "服务待命，不是全天录音；等眼镜主动唤醒。" : "本轮音频处理中；关闭待命可停止本轮与后续自动响应。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            HStack {
                Button("模型设置") { if runtime.supportsDevice { showKeys = true } else { showConfiguration = true } }.accessibilityIdentifier("model-settings")
                Spacer()
                Button("本地流程演示") { showSimulation = true }.accessibilityIdentifier("open-session-lab")
            }.font(.subheadline)
            NavigationLink { CodexCompanionView() } label: {
                Label("Codex 任务与审批", systemImage: "terminal")
            }.accessibilityIdentifier("codex-conversation-entry")
            NavigationLink { ModelToolsView() } label: {
                Label("AI Tools · 查看模型可用工具", systemImage: "wrench.and.screwdriver")
            }.accessibilityIdentifier("model-tools-conversation-entry")
            if let error = timeline.storageError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.amber)
            }
            NavigationLink { ConversationTimelineView() } label: {
                Card { FeatureRow(icon: "clock.arrow.circlepath", title: "对话时间轴", subtitle: "自动记录本机对话 · 导出与分享", status: "本地保存", active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("conversation-timeline")
            Card {
                Text("已跑通的语音方案").font(.headline).foregroundStyle(Palette.ink)
                FeatureRow(icon: "waveform", title: "阿里云流式 ASR", subtitle: "云端 VAD 断句，不叠加本地静音截断", status: "原型已验")
                Divider().overlay(Palette.line)
                FeatureRow(icon: "bolt", title: "DeepSeek V4 Flash", subtitle: "关闭思考 · 流式文字 · 不默认联网搜索", status: "原型已验")
                Divider().overlay(Palette.line)
                Text("持续 ASR 在唤醒会话内保持，云端出现有效新句才打断旧回答；空句不打断。单次会话保留 120 秒保护。Codex 工具需单独配置和允许；当前无 TTS。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            if runtime.supportsDevice {
                Card {
                    Toggle("使用真实云对话", isOn: $useCloud).disabled(runtime.enabled)
                    Toggle("持续 ASR · 允许插话", isOn: $continuous).disabled(runtime.enabled || !useCloud).accessibilityIdentifier("voice-continuous-draft")
                    Text(runtime.enabled ? (runtime.cloud && runtime.continuous ? "实际运行：持续 ASR · 有效识别新句打断" : "实际运行：非持续模式 · 输出时不保证插话") : "上方开关是下次启动配置，尚未运行")
                        .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("voice-effective-policy")
                    Text(useCloud ? "唤醒后的音频送往已指定阿里云 ASR，识别文字送往 DeepSeek；可能计费。" : "仅本机 WebRTC VAD 检测；回复每轮随机测试串，不识别、不上传。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button(runtime.hasCredentials ? "管理语音服务密钥" : "配置 ASR 和模型密钥") { showKeys = true }
                        .disabled(runtime.enabled)
                }
                if runtime.enabled {
                    PrimaryButton(title: "关闭待命", icon: "stop.circle") { runtime.stop() }
                    Button("结束本轮，保留待命") { runtime.endRound() }
                } else {
                    PrimaryButton(title: "开启眼镜语音待命", icon: "waveform", enabled: runtime.ready && (!useCloud || runtime.hasCredentials)) { confirmStart = true }
                }
                Button("连接与解绑管理") { showDiagnostics = true }
                Text(runtime.latestEvent).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            } else {
                Text("此构建不加载眼镜通信库，也不会调用云服务。真机请使用 RayNeoCompanionDevice 构建；下面的演示不代表实际收音。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Text("回答全部分片及完成消息提交后，10 秒无有效新句自动退出；继续说话会取消旧计时。不是从第一个字计时，提交完成也不等于镜片渲染完成。")
                .font(.caption).foregroundStyle(Palette.amber)
            Button("清除本次屏幕文字") { runtime.clearText() }.font(.caption)
        }
        .onAppear { runtime.prepare(); reflectRunningPolicy() }
        .onChange(of: runtime.enabled) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.cloud) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.continuous) { _ in reflectRunningPolicy() }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
        .sheet(isPresented: $showKeys) { LiveVoiceKeysView() }
        #if COMPANION_DEVICE
        .sheet(isPresented: $showDiagnostics, onDismiss: { runtime.refresh() }) {
            NavigationStack { VoiceDiagnosticsView(runtime: runtime).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showDiagnostics = false } } } }
        }
        #endif
        .confirmationDialog(useCloud ? "开启后，主动唤醒会将音频发送给阿里云，文字发送给 DeepSeek；服务可能计费。" : "开启本地随机回复测试，不上传语音。", isPresented: $confirmStart) {
            Button("确认开启待命") { runtime.start(cloud: useCloud, continuous: continuous) }
        }
        .alert("语音服务", isPresented: Binding(get: { runtime.error != nil }, set: { if !$0 { runtime.error = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(runtime.error ?? "") }
    }
    private func reflectRunningPolicy() {
        guard runtime.enabled else { return }
        useCloud = runtime.cloud; continuous = runtime.continuous
    }
}

struct LiveVoiceKeysView: View {
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var asr = ""
    @State private var host = CloudASRHostSettings.current()
    @State private var llm = ""
    @State private var enableDefault = true
    var body: some View {
        NavigationStack {
            Form {
                Section("已验收的服务组合") {
                    Text("阿里云 qwen-audio-3.0-asr-flash-streaming\nDeepSeek V4 Flash · 关闭思考 · 流式")
                    Text("填写自己的阿里云 ASR Host；需要服务支持此模型及 DashScope 流式任务协议。DeepSeek 使用官方固定端点，其他模型设置页仍是草稿。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("本 App 独立钥匙串") {
                    TextField("你的 ASR Host（不含 https://）", text: $host)
                        .accessibilityIdentifier("live-asr-host").keyboardType(.URL)
                    Text("更换 Host 不沿用其他主机的 Key。源码不包含开发者的租户地址或密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("阿里云 API Key（留空保留）", text: $asr)
                        .accessibilityIdentifier("live-asr-key")
                    SecureField("DeepSeek API Key（留空保留）", text: $llm)
                        .accessibilityIdentifier("live-llm-key")
                    Text("不会读取官方 App 或测试 App 的密钥。首次解锁后可供本机后台语音使用，不同步、不显示原值。")
                        .font(.caption).foregroundStyle(.secondary)
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Toggle("保存后默认开启云对话和持续插话", isOn: $enableDefault).accessibilityIdentifier("live-default-voice")
                Text("默认待命只在连接后等待唤醒，不是持续录音。主动关闭待命后不会自动再开。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(enableDefault ? "保存并开启默认待命" : "仅保存密钥，不启动对话") {
                    let saved = runtime.saveKeys(asr: asr, llm: llm, host: host, enableDefault: enableDefault)
                    asr = ""; llm = ""
                    if saved { dismiss() }
                }.accessibilityIdentifier("live-save-keys")
                if let error = runtime.error { Text(error).foregroundStyle(.red).font(.caption) }
            }.navigationTitle("语音服务密钥").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
