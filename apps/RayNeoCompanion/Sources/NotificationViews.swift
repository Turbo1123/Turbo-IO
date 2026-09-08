import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var confirmSources = false
    var body: some View {
        Form {
            Section {
                Text("通知，让消息抵达眼前").font(.title3.weight(.semibold))
                Text("系统通知共享与自定义业务通知是两条独立通路；此页不采集其他 App 的通知正文。").font(.caption).foregroundStyle(Palette.muted)
                Text(voice.ready ? "眼镜已连接" : "未连接眼镜 · 可编辑草稿和预览")
                    .accessibilityIdentifier("notification-connection")
            }
            Section("系统通知共享 · ANCS") {
                Toggle("允许眼镜通知", isOn: Binding(get: { notifications.preferences.enabled }, set: { notifications.setEnabled($0) }))
                    .accessibilityIdentifier("notification-master")
                Text("在线且空闲时，总开关立即提交；离线只存草稿。不会自动改变 iOS 的通知授权。").font(.caption).foregroundStyle(Palette.muted)
                Button("向当前眼镜应用总开关") { notifications.applyMaster() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-master")
                NavigationLink { NotificationSourcesView() } label: {
                    LabeledContent("允许哪些 App", value: "\(notifications.preferences.sources.filter(\.allowed).count)/\(notifications.preferences.sources.count)")
                }.accessibilityIdentifier("notification-sources-open")
                Picker("通知停留时间", selection: Binding(get: { notifications.preferences.displayTime }, set: { notifications.setDisplayTime($0) })) {
                    ForEach([5,10,15,20,30], id: \.self) { seconds in Text("\(seconds) 秒").tag(seconds) }
                }.accessibilityIdentifier("notification-display-time")
                Button("设为 15 秒草稿") { notifications.setDisplayTime(15) }
                    .accessibilityIdentifier("notification-duration-15")
                Text("新时长需镜片计时验收。协议把时长与来源过滤放在同一包，改草稿不会自动下发；应用前请核对来源。")
                    .font(.caption).foregroundStyle(Palette.muted)
                Text(notifications.sourcesNeedApply ? "来源列表：草稿待应用" : "来源列表：已提交，效果待验")
                    .font(.caption).accessibilityIdentifier("notification-sources-state")
                Button("应用来源配置到眼镜") { confirmSources = true }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-sources")
                Text(notifications.configurationStatus).font(.caption).accessibilityIdentifier("notification-settings-status")
                if let enabled = notifications.reportedEnabled {
                    Text("眼镜报告总开关：\(enabled ? "开" : "关")（不是来源逐项回执）").font(.caption)
                }
            }
            Section("手动测试 · 不接服务器") {
                NavigationLink { NotificationTestView() } label: {
                    Label("编写并发送测试通知", systemImage: "paperplane")
                }.accessibilityIdentifier("notification-test-open")
                Text("直接走眼镜业务通道，不弹手机通知。支持填写标题、正文，查看 UID、状态和超时。").font(.caption).foregroundStyle(Palette.muted)
            }
            Section("共享通知检查") {
                Text(notifications.availabilityStatus).accessibilityIdentifier("notification-ancs-status")
                Button("查询眼镜 ANCS 状态") { notifications.queryAvailability() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-query")
                Text("请在 iPhone 设置 → 蓝牙 → 眼镜详情中允许共享系统通知。来源 App 也需要系统通知权限；专注模式、预览设置等可能影响实际显示。Turbo IO不会替你更改这些设置。").font(.caption).foregroundStyle(Palette.muted)
            }
            if let error = notifications.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-error") } }
        }
        .navigationTitle("通知中心").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onAppear { features.prepare(); notifications.connectionChanged() }
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
        .confirmationDialog("替换当前眼镜的通知来源配置？", isPresented: $confirmSources, titleVisibility: .visible) {
            Button("确认应用当前配置") { notifications.applySources() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将应用总开关、列表中各 App（含电话）的开关和停留时间草稿：displayTime=\(notifications.preferences.displayTime)、avoidDuplicate=false、intervalTime=2。不是从眼镜读回的原配置；未列出的 App 不保证被拦截。")
        }
    }
}

struct NotificationSourcesView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @State private var search = ""
    @State private var adding = false
    private var visible: [NotificationSource] {
        notifications.preferences.sources.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                Text("这些是可配置的来源，不是手机已安装 App 清单。协议发送关闭项的 Bundle ID；未知 App 不会自动被拒绝。首次应用会替换原来源过滤配置。")
                    .font(.caption).accessibilityIdentifier("notification-source-boundary")
                TextField("搜索名称或 Bundle ID", text: $search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("notification-source-search")
                Button("添加来源 App") { adding = true }.accessibilityIdentifier("notification-source-add")
            }
            Section("打开为允许 · 修改后返回应用") {
                ForEach(visible) { source in
                    Toggle(isOn: Binding(get: { notifications.preferences.sources.first(where: { $0.id == source.id })?.allowed ?? false },
                                         set: { notifications.setAllowed(source.id, $0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                            Text(source.id).font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }.accessibilityIdentifier("notification-source-\(source.id)")
                }
            }
            Section { Text("填错 Bundle ID 将无法过滤对应来源。当前不读取第三方 App 数据，也不自动上传通知。要恢复一个关闭项，请重新打开并应用配置。").font(.caption) }
        }
        .navigationTitle("允许哪些 App").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .sheet(isPresented: $adding) { NotificationSourceEditor() }
    }
}

private struct NotificationSourceEditor: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var id = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("App 名称", text: $name).accessibilityIdentifier("notification-source-name")
                TextField("Bundle ID，例如 com.example.app", text: $id)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("notification-source-id")
                Text("请填写真实 Bundle ID；显示名称无法替代标识。新增项默认允许，保存后仍需返回应用配置。").font(.caption)
                if let error = notifications.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("添加通知来源").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存来源") { if notifications.addSource(name: name, id: id) { dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !GlassesNotificationProtocol.validAppID(id))
                        .accessibilityIdentifier("notification-source-save")
                }
            }
        }
    }
}

struct NotificationTestView: View {
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var title = "Turbo IO通知测试"
    @State private var content = "这是独立 App 的业务通知测试。"
    @FocusState private var focused: Bool
    private var valid: Bool { (try? GlassesNotificationProtocol.notification(uid: "1", title: title, content: content)) != nil }
    var body: some View {
        Form {
            Section("编辑测试内容") {
                Text("来源固定为Turbo IO，不冒充其他 App；内容只在本次页面内存中，不保存或上传服务器。").font(.caption).foregroundStyle(Palette.muted)
                TextField("标题（最多 80 字）", text: $title, axis: .vertical)
                    .focused($focused).accessibilityIdentifier("notification-test-title")
                TextField("正文（最多 500 字）", text: $content, axis: .vertical).lineLimit(3...8)
                    .focused($focused).accessibilityIdentifier("notification-test-content")
                Text("标题 \(title.count)/80 · 正文 \(content.count)/500 · 这是本版测试上限，不是镜片排版保证").font(.caption2)
                Button("填入随机校验测试数据") {
                    let code = String(UUID().uuidString.prefix(6))
                    title = "Turbo IO通知测试 \(code)"; content = "第一行：独立业务通知\n第二行：校验码 \(code)\n请核对眼镜文字。"
                    focused = false
                }.accessibilityIdentifier("notification-test-sample")
            }
            Section("手机预览 · 不是镜片截图") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Turbo IO", systemImage: "bell.badge").font(.caption).foregroundStyle(Palette.green)
                    Text(title).font(.headline)
                    Text(content).font(.body)
                }.padding(.vertical, 8).accessibilityIdentifier("notification-test-preview")
            }
            Section {
                Button("发送到眼镜") {
                    focused = false; _ = notifications.send(title: title, content: content)
                }.disabled(!notifications.canTest || !valid).accessibilityIdentifier("notification-test-send")
                Text("需要已认证连接、允许眼镜通知、Turbo IO来源开启，且先应用总开关；语音、录音或提词进行时不抢占。按钮只发一次，不自动重试。").font(.caption).foregroundStyle(Palette.muted)
                if let uid = notifications.lastUID { Text("最近一次 UID：\(uid)").font(.caption.monospaced()).accessibilityIdentifier("notification-test-uid") }
                Text(notifications.testStatus).accessibilityIdentifier("notification-test-status")
                if let operation = notifications.operationStatus { Text(operation).font(.caption) }
                if let error = notifications.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-test-error") }
                Text("SDK 调用返回、眼镜状态回报、实际镜片显示是不同判据。即使收到回报，也请核对上方校验码；原有语音文字显示不算这项通过。").font(.caption)
            }
        }
        .navigationTitle("自定义通知测试").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成编辑") { focused = false } } }
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
    }
}
