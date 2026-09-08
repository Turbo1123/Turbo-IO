import SwiftUI

struct CodexCompanionView: View {
    @EnvironmentObject private var codex: CodexCompanion
    @EnvironmentObject private var push: CodexPush
    @EnvironmentObject private var notifications: CompanionNotifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var endpoint = ""
    @State private var token = ""
    @State private var voiceTools = false
    @State private var prompt = ""
    @State private var error: String?
    @State private var approval: CodexApproval?
    @State private var answers: [String: String] = [:]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("你的电脑，眼镜里的 Codex", systemImage: "terminal").font(.headline)
                    Text("发任务、查进度、继续对话；电脑独立执行，眼镜语音不必一直等待。审批仅在本页明确确认，不接受模型代批。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(codex.status).font(.caption).accessibilityIdentifier("codex-status")
                    if let state = codex.state {
                        Text(state.workspace).font(.caption2).textSelection(.enabled)
                        Badge(text: state.readOnly ? "只读测试" : "工作区可写")
                    }
                }
                Card {
                    Text("电脑桥接").font(.headline)
                    TextField("HTTPS 地址", text: $endpoint).accessibilityIdentifier("codex-endpoint")
                    SecureField("独立访问令牌（留空保留）", text: $token).privacySensitive().accessibilityIdentifier("codex-token")
                    Toggle("允许 DeepSeek 调用 Codex 工具", isOn: $voiceTools).accessibilityIdentifier("codex-voice-tools")
                    Text("开启后，语音中的任务文字可能发送到此电脑及 Codex。不会上传麦克风原始音频；不接管已有桌面任务。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button("保存配置，不启动任务") {
                        do { try codex.save(endpoint: endpoint, token: token, voiceTools: voiceTools); token = "" }
                        catch { self.error = error.localizedDescription; token = "" }
                    }.disabled(codex.busy || codex.hasUnknownDelivery).accessibilityIdentifier("codex-save")
                    Button("连接／刷新状态") { Task { await codex.refresh() } }
                        .disabled(!codex.configured).accessibilityIdentifier("codex-refresh")
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Card {
                    Toggle("Codex 完成和待确认时主动提醒", isOn: Binding(get: { push.enabled }, set: { push.setEnabled($0) }))
                        .accessibilityIdentifier("codex-push-enabled")
                    Text(push.status).font(.caption).accessibilityIdentifier("codex-push-status")
                    Text(notifications.testStatus).font(.caption2).accessibilityIdentifier("codex-push-delivery")
                    NavigationLink("眼镜通知开关与发送测试") { NotificationCenterView() }
                    Text("开启后只提醒新事件；完成结果显示摘要，完整内容在本页。语音、录音或提词占用时等待空闲，不抢屏。提醒不是批准。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("已允许眼镜通知时，连接后会恢复此总开关；不会替换其他 App 来源过滤设置。")
                        .font(.caption2).foregroundStyle(Palette.muted)
                    Text("当前是 App 获准运行时约每两秒检查；未接 APNs，系统挂起或强退后不能保证及时提醒。电脑桥接内存最多保留128条、完成事件一小时，重启会清空。")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if codex.hasUnknownDelivery {
                    Card {
                        Label("上次提交结果待核对", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.amber)
                        Text("保留同一请求编号，不自动创建第二个任务。网络恢复后先核对。待核对内容临时保存在本机，确认后清除。")
                            .font(.caption)
                        Button("核对上次提交") { Task { await codex.retryPending() } }.disabled(codex.busy)
                    }
                }
                Card {
                    HStack {
                        Text("当前任务").font(.headline); Spacer()
                        Button("改为新任务") { codex.select(nil) }.disabled(codex.busy || codex.hasUnknownDelivery)
                    }
                    Text(codex.selectedTaskID.map { "任务 " + String($0.prefix(8)) } ?? "下一条将新建任务").font(.caption)
                    TextField("交给 Codex 的要求…", text: $prompt, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("codex-prompt")
                    Button("填入随机校验测试") {
                        prompt = "这是Turbo IO连接测试。不要读写文件或运行工具，只回复：Turbo IOCodex校验 " + String(UUID().uuidString.prefix(6))
                    }.accessibilityIdentifier("codex-fixture")
                    HStack {
                        Button("发送到电脑") { Task { do { _ = try await codex.message(prompt); prompt = "" } catch { self.error = error.localizedDescription } } }
                            .disabled(!codex.configured || codex.busy || codex.hasUnknownDelivery || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("codex-send")
                        Spacer()
                        Button("停止任务", role: .destructive) { Task { do { try await codex.stop() } catch { self.error = error.localizedDescription } } }
                            .disabled(codex.selected?.turnId == nil || codex.busy || codex.hasUnknownDelivery)
                    }
                }
                if let task = codex.selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.status).font(.headline)
                        Text(task.answer.isEmpty ? "还没有收到 Codex 输出" : task.answer).textSelection(.enabled).privacySensitive()
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.mint)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("codex-output")
                    ForEach(task.pending) { request in
                        Card {
                            Label(request.kind == "question" ? "Codex 需要你的回答" : "Codex 请求单次批准", systemImage: "hand.raised").font(.headline)
                            Text(request.summary).font(.caption).textSelection(.enabled)
                            Text("请求 \(request.id.prefix(8)) · 两分钟内有效").font(.caption2)
                            if request.kind == "question" {
                                ForEach(request.questions) { q in
                                    Text(q.question).font(.subheadline)
                                    ForEach(q.options, id: \.self) { option in Button(option) { answers[q.id] = option } }
                                    TextField("你的回答", text: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 }))
                                }
                                Button("提交这些回答") { decide(request, accept: false) }
                                    .disabled(codex.busy || request.questions.contains(where: { answers[$0.id, default: ""].isEmpty }))
                            } else {
                                HStack {
                                    Button("批准这一次") { approval = request }
                                    Button("拒绝", role: .destructive) { decide(request, accept: false) }
                                }.disabled(codex.busy || codex.hasUnknownDelivery)
                            }
                        }
                    }
                }
                if let tasks = codex.state?.tasks, !tasks.isEmpty {
                    Card {
                        Text("桥接管理的任务").font(.headline)
                        ForEach(tasks) { task in
                            Button("\(task.id.prefix(8)) · \(task.status)") { codex.select(task.id) }
                                .disabled(codex.busy || codex.hasUnknownDelivery)
                        }
                    }
                }
                Text("页面前台每两秒刷新。关闭页面不停止电脑任务；本版不承诺 iOS 后台实时通知。语音可问“Codex 进度如何”。")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22)
        }.background(Palette.background).navigationTitle("Codex 控制台").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { endpoint = codex.endpoint; voiceTools = codex.voiceToolsEnabled }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await codex.refresh() }
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
            .confirmationDialog("仅批准这个请求，不授予整场会话权限。", isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } })) {
                Button("确认批准这一次") { if let request = approval { decide(request, accept: true) }; approval = nil }
            } message: { Text(approval?.summary ?? "") }
            .alert("Codex 桥接", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private func decide(_ request: CodexApproval, accept: Bool) {
        Task { do { try await codex.decide(request, approve: accept, answers: answers); answers = [:] } catch { self.error = error.localizedDescription } }
    }
}
