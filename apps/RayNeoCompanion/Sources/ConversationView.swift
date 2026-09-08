import SwiftUI
import RayNeoSession

struct LegacyConversationView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showConfiguration = false
    @State private var showSimulation = false

    var body: some View {
        Screen(title: "语音会话", eyebrow: "本地识别与对话") {
            HStack {
                Label("等待连接", systemImage: "clock").font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: "尚未采音", active: true)
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))

            VStack(spacing: 13) {
                Text("你的声音，连接你的模型").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                Text("识别 · 对话 · 回复").font(.system(size: 13)).foregroundStyle(Palette.mint.opacity(0.7))
                HStack(spacing: 4) {
                    ForEach(0..<39) { index in
                        let height = Double([5, 8, 14, 25, 38, 27, 17, 9, 20, 30, 42, 24, 16][index % 13])
                        Capsule().fill(Palette.mint.opacity(0.35 + Double(index % 4) * 0.1)).frame(width: 3, height: height)
                    }
                }.frame(height: 65).padding(.top, 21).accessibilityLabel("静态语音图示，未采集声音")
                Text("麦克风未启用 · 没有音频正在传输").font(.system(size: 10)).foregroundStyle(Palette.mint.opacity(0.55))
            }.padding(.vertical, 35).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            Card {
                Button { showConfiguration = true } label: {
                    HStack {
                        Label("识别来源", systemImage: "waveform").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text("待实测决定").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showConfiguration = true } label: {
                    HStack {
                        Label("模型服务", systemImage: "server.rack").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text(store.configuration.endpoint.isEmpty ? "未配置" : "本地已保存").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
            }
            PrimaryButton(title: "模型设置", icon: "gearshape") { showConfiguration = true }.accessibilityIdentifier("model-settings")
            Button { showSimulation = true } label: {
                Label("本地流程演示", systemImage: "play")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.green, lineWidth: 1))
            }.accessibilityIdentifier("open-session-lab")
        }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
    }

}

struct ModelConfigurationView: View {
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ModelConfiguration()
    @State private var key = ""
    @State private var hasKey = false
    @State private var error: String?
    @State private var confirmRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("仅保存配置，不连接服务", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    Card {
                        Text("服务地址").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField("HTTPS 基础地址（可留空）", text: $draft.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-endpoint")
                        Text("模型名称").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField("输入模型名称", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-name")
                        Text("API 密钥").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        SecureField(hasKey ? "新密钥（留空保留此地址的密钥）" : "安全存入钥匙串（可留空）", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).privacySensitive()
                        Text(hasKey ? "此服务地址已保存密钥，不会显示原值。" : "密钥按完整服务地址独立保存，不跨地址沿用。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    Card {
                        HStack {
                        Text("语音识别策略").foregroundStyle(Palette.ink).accessibilityIdentifier("recognition-strategy-label")
                        Spacer()
                        Picker("语音识别策略", selection: $draft.recognition) {
                            Text("待实测决定").tag("待实测决定")
                            Text("本地 Sherpa（待接入）").tag("本地 Sherpa")
                            Text("自有云端（待接入）").tag("自有云端")
                        }.labelsHidden().accessibilityLabel("语音识别策略")
                        }
                        Divider().overlay(Palette.line)
                        HStack {
                        Text("语音输出").foregroundStyle(Palette.ink).accessibilityIdentifier("speech-output-label")
                        Spacer()
                        Picker("语音输出", selection: $draft.speech) {
                            Text("待接入").tag("待接入")
                            Text("系统语音（待接入）").tag("系统语音")
                            Text("自有 TTS（待接入）").tag("自有 TTS")
                        }.labelsHidden().accessibilityLabel("语音输出")
                        }
                    }.font(.system(size: 14))
                    PrimaryButton(title: "保存配置", icon: "square.and.arrow.down") { save() }.accessibilityIdentifier("save-model")
                    Label("未使用官方账号或云端凭证", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                    Text("密钥仅当前设备、解锁后可用，不写入日志或配置文件。识别与语音选项只是策略草稿，不会运行模型或更改眼镜设置。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    if hasKey { Button("移除此服务在本机保存的密钥", role: .destructive) { confirmRemoval = true }.font(.footnote) }
                }.padding(24)
            }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("模型设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear { draft = store.configuration; hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .onChange(of: draft.endpoint) { _ in hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .confirmationDialog("仅删除Turbo IO自己保存的模型密钥，不影响官方 App。", isPresented: $confirmRemoval) {
                Button("删除本机密钥", role: .destructive) {
                    do { try CredentialVault.remove(for: draft.endpoint); hasKey = false } catch { self.error = error.localizedDescription }
                }
            }
            .alert("未保存配置", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do { try store.saveConfiguration(draft, key: key); key = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
