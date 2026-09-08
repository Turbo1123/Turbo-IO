import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var showModel = false
    @State private var showLab = false
    var body: some View {
        Screen(title: "工具箱", eyebrow: "本地工具与实验") {
            NavigationLink { DisplayObserverView() } label: {
                Card { FeatureRow(icon: "eyeglasses", title: "显示观察", subtitle: "USB · 页面回报与发送文字 · 非截图", status: "只读") }
            }.buttonStyle(.plain).accessibilityIdentifier("display-observer-entry")
            NavigationLink { AlwaysOnLocalProbeView(probe: store.alwaysOn) } label: {
                Card { FeatureRow(icon: "waveform.path", title: "全天智记", subtitle: "仅音频 · 30秒本地协议测试", status: "实验") }
            }.buttonStyle(.plain).accessibilityIdentifier("always-on-entry")
            NavigationLink { ModelToolsView() } label: {
                Card { FeatureRow(icon: "wrench.and.screwdriver", title: "AI Tools", subtitle: "模型工具 · 参数 · 可用条件", status: "查看") }
            }.buttonStyle(.plain).accessibilityIdentifier("model-tools-entry")
            NavigationLink { CodexCompanionView() } label: {
                Card { FeatureRow(icon: "terminal", title: "Codex 控制台", subtitle: "电脑任务 · 进度 · 单次审批", status: "连接电脑") }
            }.buttonStyle(.plain).accessibilityIdentifier("codex-tool")
            Card {
                NavigationLink { TodoView() } label: {
                    FeatureRow(icon: "checklist", title: "待办清单", subtitle: "记录与管理任务", status: "本地可用", active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("todo-tool")
                Divider().overlay(Palette.line)
                NavigationLink { PrompterView() } label: {
                    FeatureRow(icon: "text.alignleft", title: "提词器", subtitle: "台词编辑与手机预览", status: "本地可用", active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("prompter-tool")
            }
            Card {
                Button { showModel = true } label: { FeatureRow(icon: "gearshape", title: "模型设置", subtitle: "配置本地模型与服务", status: "配置") }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showLab = true } label: { FeatureRow(icon: "flask", title: "协议实验室", subtitle: "探索协议与功能实验", status: "本地模拟") }.buttonStyle(.plain).accessibilityIdentifier("protocol-lab")
            }
            VStack(spacing: 12) {
                SectionLabel(title: "眼镜功能", trailing: "真机接入 · 待复验")
                Card {
                    NavigationLink { NotificationCenterView() } label: { FeatureRow(icon: "bell.badge", title: "通知中心", subtitle: "来源开关与自定义发送测试", status: "真机") }.buttonStyle(.plain).accessibilityIdentifier("notification-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "cloud", title: "天气与设备设置", subtitle: "自定义数据、读取状态与设置", status: "真机") }.buttonStyle(.plain).accessibilityIdentifier("device-settings-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "slider.vertical.3", title: "头控与旋钮", subtitle: "已有协议值域的控制子集", status: "真机") }.buttonStyle(.plain)
                }
            }
            Label("设备效果以实机验收为准", systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            HStack {
                NavigationLink("使用说明") { HelpView() }
                Spacer()
                NavigationLink("能力范围") { ProtocolLabView() }
                Spacer()
                NavigationLink("偏好设置") { SettingsView(embedded: true) }
            }.font(.system(size: 12)).padding(.horizontal, 5)
        }
        .sheet(isPresented: $showModel) { ModelConfigurationView() }
        .sheet(isPresented: $showLab) { SessionSimulationView() }
    }

    private func toolTile(_ icon: String, title: String, description: String, footnote: String, green: Bool) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Image(systemName: icon).font(.system(size: 25, weight: .light)); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(description).font(.system(size: 11)).opacity(0.7)
            }
            Text(footnote).font(.system(size: 10)).opacity(0.7)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 160)
            .foregroundStyle(green ? Palette.mint : Palette.ink)
            .background(green ? Palette.ink : Palette.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ModelToolsView: View {
    @EnvironmentObject private var codex: CodexCompanion
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @State private var refreshing = false
    @State private var expandedTools: Set<String> = []
    private var providedNames: Set<String> {
        Set(codex.toolDefinitions.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("DeepSeek 的工具清单", systemImage: "wrench.and.screwdriver").font(.headline)
                    Text("当前配置将提供 \(providedNames.count) / \(CodexToolDescriptor.all.count) 个工具")
                        .accessibilityIdentifier("model-tools-count")
                    Text("这是下次模型请求可携带的 tools，不代表已经发出请求、工具执行成功或电脑在线。页面只读，不会启动任务。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(codex.configured ? (codex.voiceToolsEnabled ? "工具权限：已允许" : "工具权限：已关闭") : "工具配置：缺少桥接地址或令牌")
                        .font(.caption).accessibilityIdentifier("model-tools-configuration")
                    Text(runtime.supportsDevice ? "语音：\(runtime.phaseLabel) · \(runtime.cloud ? "云对话" : "云对话未运行")" : "模拟器：仅查看清单，不运行眼镜语音")
                        .font(.caption)
                    Text("桥接状态（上次检查 / 配置结果）：\(codex.status)").font(.caption)
                        .accessibilityIdentifier("model-tools-bridge-state")
                    Button(refreshing ? "正在检查…" : "检查桥接连接（不发任务）") {
                        refreshing = true
                        Task { await codex.refresh(); refreshing = false }
                    }.disabled(!codex.configured || refreshing).accessibilityIdentifier("model-tools-refresh")
                    NavigationLink("管理 Codex 工具开关与连接") { CodexCompanionView() }
                        .accessibilityIdentifier("model-tools-configure")
                }
                ForEach(CodexToolDescriptor.all) { tool in
                    Card {
                        Text(tool.title).font(.headline)
                        Text(tool.id).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("model-tool-name-\(tool.id)")
                        Badge(text: providedNames.contains(tool.id) ? "将随模型请求提供" : "未提供给模型")
                        Text(tool.description).font(.subheadline)
                        Text(tool.requiresText ? "参数：text（必填字符串，任务要求）" : "参数：无，使用当前所选任务")
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("你可以说：“\(tool.example)”").font(.caption).foregroundStyle(Palette.green)
                        Button {
                            if expandedTools.contains(tool.id) { expandedTools.remove(tool.id) }
                            else { expandedTools.insert(tool.id) }
                        } label: {
                            HStack {
                                Text(expandedTools.contains(tool.id) ? "收起工具定义（JSON）" : "查看实际工具定义（JSON）")
                                Spacer()
                                Image(systemName: expandedTools.contains(tool.id) ? "chevron.down" : "chevron.right")
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("model-tool-details-\(tool.id)")
                            .accessibilityValue(expandedTools.contains(tool.id) ? "已展开" : "已收起")
                        if expandedTools.contains(tool.id) {
                            Text(tool.schemaJSON).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("model-tool-schema-\(tool.id)")
                        }
                    }
                }
                Text("当前使用 Function Calling，并非 MCP。待办、天气、录音等 App 功能尚未注册为模型工具；权限审批仍须在手机明确确认，没有自动批准工具。")
                    .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("model-tools-boundary")
            }.padding(22)
        }.background(Palette.background).navigationTitle("AI Tools").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct TodoView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var title = ""
    @State private var showCompleted = false
    @State private var editingTodo: LocalTodo?
    @FocusState private var inputFocused: Bool
    private var visibleTodos: [LocalTodo] { store.todos.filter { $0.archivedAt == nil && $0.completed == showCompleted } }
    private var markdown: String {
        "# Turbo IO待办清单\n\n> 本机当前快照；不代表眼镜同步或镜片验收状态。\n\n" + store.todos.filter { $0.archivedAt == nil }.map {
            "- [\($0.completed ? "x" : " ")] \($0.title.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notice("先保存到本机 · 眼镜同步需确认")
                NavigationLink("从系统提醒事项导入") { ReminderImportView() }
                    .accessibilityIdentifier("system-reminders-open")
                Picker("待办筛选", selection: $showCompleted) {
                    Text("进行中").tag(false); Text("已完成").tag(true)
                }.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    TextField("添加一条待办…", text: $title, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("todo-input").focused($inputFocused)
                    Button {
                        store.addTodo(title); title = ""
                        inputFocused = false
                        showCompleted = false
                    } label: { Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(.white).frame(width: 36, height: 36).background(Palette.ink, in: Circle()) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("保存到本机")
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 0.75))
                if visibleTodos.isEmpty {
                    Card { EmptyState(icon: "checkmark.circle", title: showCompleted ? "还没有已完成待办" : "还没有进行中的待办", detail: "从一件可以完成的小事开始。\n这里不会显示或修改官方 App 的待办。") }
                } else {
                    ForEach(visibleTodos) { todo in
                        Button { store.toggleTodo(todo.id) } label: {
                            Card {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 23)).foregroundStyle(Palette.green)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(todo.title).font(.system(size: 15)).strikethrough(todo.completed).foregroundStyle(todo.completed ? Palette.muted : Palette.ink)
                                        Text(todo.deliveryDescription).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        if let day = SystemReminderSnapshot.dateOnlyLabel(todo.reminderDueComponents) {
                                            Text("计划：" + day).font(.caption2).foregroundStyle(Palette.muted)
                                        } else if let due = todo.dueAt { Text("计划：" + due.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Palette.muted) }
                                        if todo.reminderSourceID != nil { Text("系统提醒事项导入 · 独立副本，不回写").font(.caption2).foregroundStyle(Palette.muted) }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(todo.title)，\(todo.completed ? "本机已完成" : "本机未完成")")
                            .contextMenu {
                                Button("编辑内容和计划时间") { editingTodo = todo }
                                Button("移到已移除", role: .destructive) { store.archiveTodo(todo.id, archived: true) }
                            }
                    }
                }
                HStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 7) {
                        GlassesTodoSyncCard()
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
                ShareLink(item: markdown) {
                    Label("导出待办清单（本机）", systemImage: "arrow.down.to.line")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(store.todos.isEmpty)
                Text("仅分享本机 Markdown 文本，不会推送到眼镜。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                NavigationLink("已移除的待办（可恢复）") { RemovedTodosView() }
                NavigationLink("待发送与冲突") { TodoDeliveryView() }
                    .accessibilityIdentifier("todo-delivery-open")
                Text("长按条目可编辑或移除；计划时间仅记录，不自动创建系统提醒。").font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle("待办清单").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .sheet(item: $editingTodo) { TodoEditorView(todo: $0) }
    }
}

struct TodoEditorView: View {
    let todo: LocalTodo
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDate = false
    @State private var due = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("待办内容", text: $title, axis: .vertical).accessibilityIdentifier("todo-edit-title")
                Toggle("计划时间（不自动提醒）", isOn: $hasDate)
                if hasDate { DatePicker("时间", selection: $due) }
                Text("已关联眼镜的任务会尝试在线同步内容/完成状态；计划时间仅本机保存，不生成通知。").font(.caption)
            }.navigationTitle("编辑待办").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    store.editTodo(todo.id, title: title, dueAt: hasDate ? due : nil); dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.onAppear { title = todo.title; hasDate = todo.dueAt != nil; due = todo.dueAt ?? Date() }
        }
    }
}

struct RemovedTodosView: View {
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        List {
            ForEach(store.todos.filter { $0.archivedAt != nil }) { todo in
                HStack { Text(todo.title); Spacer(); Button("恢复") { store.archiveTodo(todo.id, archived: false) } }
            }
        }.navigationTitle("已移除的待办").toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct PrompterView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var text = ""
    @State private var fontSize = 22.0
    @State private var mode = "编辑"
    @State private var page = 0
    @State private var saved = false
    private var pages: [String] { LocalPrompterPager.pages(text) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("提词器模式", selection: $mode) { Text("编辑").tag("编辑"); Text("手机预览").tag("手机预览") }.pickerStyle(.segmented)
                NavigationLink { BookShelfView() } label: {
                    Card { FeatureRow(icon: "books.vertical", title: "书籍导入与匀速阅读", subtitle: "TXT / EPUB · 章节 · 播放速度 · 续读", status: "本地可用", active: true) }
                }.buttonStyle(.plain).accessibilityIdentifier("book-shelf")
                if mode == "编辑" {
                    Card {
                        HStack { Text("我的提词稿").font(.headline).foregroundStyle(Palette.ink); Spacer(); Text("\(text.count) 字").font(.caption).foregroundStyle(Palette.muted) }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty { Text("写下你想说的话……").foregroundStyle(Palette.muted).padding(.top, 8).padding(.leading, 5) }
                            TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 260).accessibilityIdentifier("prompter-input")
                        }.font(.system(size: 16)).padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("手机排版预览").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    VStack {
                        ScrollView {
                            Text(pages.isEmpty ? "还没有提词稿，请先在编辑页输入。" : pages[min(page, pages.count - 1)])
                                .font(.system(size: fontSize, weight: .medium)).foregroundStyle(Palette.mint).lineSpacing(14)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }.frame(height: 210)
                        Text(pages.isEmpty ? "无内容" : "手机页 \(page + 1) / \(pages.count)").font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.6)).padding(.bottom, 16)
                    }.background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                    HStack { Text("字号"); Spacer(); Text("\(Int(fontSize))").monospacedDigit() }.font(.subheadline)
                    HStack { Text("A").font(.caption); Slider(value: $fontSize, in: 16...40, step: 1); Text("A").font(.title3) }
                    HStack {
                        Button { page = max(0, page - 1) } label: { Label("上一页", systemImage: "chevron.left").frame(maxWidth: .infinity) }.disabled(page == 0)
                        Button { page = min(pages.count - 1, page + 1) } label: { Label("下一页", systemImage: "chevron.right").frame(maxWidth: .infinity) }.disabled(page + 1 >= pages.count)
                    }.font(.system(size: 13)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text("每页按 140 个字符切分，仅便于手机阅读，不是眼镜分页规则。")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 12) {
                    Button { store.savePrompter(text); saved = true } label: {
                        Label(saved ? "已保存" : "保存草稿", systemImage: saved ? "checkmark" : "square.and.arrow.down").frame(maxWidth: .infinity)
                    }.accessibilityIdentifier("prompter-save")
                    ShareLink(item: text) { Label("分享稿件", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.disabled(text.isEmpty)
                }.font(.system(size: 13, weight: .medium)).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.green, lineWidth: 0.75))
                GlassesPrompterControls(text:text)
                notice("镜片排版与旋钮操作需实机验证")
            }.padding(24)
        }.background(Palette.background).navigationTitle("提词器").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { text = store.prompterText }.onChange(of: text) { _ in saved = false; page = 0 }
    }
}

enum LocalPrompterPager {
    static func pages(_ text: String, charactersPerPage: Int = 140) -> [String] {
        guard !text.isEmpty, charactersPerPage > 0 else { return [] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: charactersPerPage, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }
}

private func notice(_ text: String) -> some View {
    Label { Text(text).lineSpacing(4) } icon: { Image(systemName: "info.circle") }
        .font(.system(size: 12)).foregroundStyle(Palette.green).padding(14)
        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
}

struct ProtocolLabView: View {
    private let capabilities: [(String, String, String)] = [
        ("连接与认证", "手机 → 眼镜 / 眼镜 → 手机", "真机构建已复用原型通信核心。新 Bundle 的配对、后台与解绑仍需实机复验；模拟器不加载核心。"),
        ("完整语音", "唤醒、音频、识别、回复、退出", "真机构建接入云端 ASR/VAD、Flash 流式和连续插话，先配置密钥并确认开启；新 App 镜片验收待做。"),
        ("待办反向事件", "眼镜完成 → 手机合并", "本地勾选不是反向协议证据。需保留 ID、修改时间与重复事件防护。"),
        ("提词与显示", "手机发送 / 眼镜旋钮、翻页", "手机预览不替代镜片验收；分页、排版、头控与退出需要实际操作。"),
        ("录音与离线同步", "眼镜文件 → 手机归档", "已接在线控制、offset 接收、Ogg/WAV 与归档；离线列表导入、冷启动自动续传和新 App 真机闭环仍待。"),
        ("天气与通知", "手机内容 → 眼镜展示", "发送成功与镜片显示分开记录，不将系统通知镜像当作自定义协议实现。")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                notice("本页面是集成边界说明，不会发送实验指令或读取官方 App。")
                ForEach(capabilities, id: \.0) { item in
                    Card {
                        HStack { Text(item.0).font(.headline).foregroundStyle(Palette.ink); Spacer(); Badge(text: "待接入 / 验收") }
                        Text(item.1).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green)
                        Text(item.2).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("协议实验室").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var body: some View {
        if embedded { settingsContent } else {
            NavigationStack { settingsContent.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
        }
    }
    private var settingsContent: some View {
        Form {
            Section {
                Toggle("启用界面演示", isOn: $store.demoMode).disabled(store.voice.supportsDevice)
                Text("仅当前启动有效。演示内容会明确标注，不创建音频、不触发模型、不更改真实设备状态。")
                    .font(.footnote).foregroundStyle(Palette.muted)
            } header: { Text("演示模式") }
            Section("隐私与安全") {
                Label("不会自动启用麦克风", systemImage: "mic.slash")
                Label("不会自动上传音频或草稿", systemImage: "network.slash")
                Label("模型密钥仅保存到系统钥匙串", systemImage: "key")
                Label("不接管官方登录和绑定", systemImage: "lock.shield")
            }.font(.subheadline)
            Section("当前构建") {
                LabeledContent("版本", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0") + " · 研究版")
                LabeledContent("设备通道", value: store.voice.supportsDevice ? "厂商核心适配 · 待真机复验" : "模拟器禁用")
                LabeledContent("最低系统", value: "iOS 16")
                Text("模拟器与编译通过不代表非越狱实机、配对或镜片效果已验证。")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
        }.navigationTitle("偏好设置").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: embedded)
    }
}

struct HelpView: View {
    private let sections: [(String, String)] = [
        ("现在可以使用什么？", "本机待办与提词稿；手选录音副本并校验、手工文字生成不可覆盖的 Markdown 修订与系统分享；模型配置草稿和隔离的 Keychain 密钥。"),
        ("哪些还不是正式能力？", "真实蓝牙连接、独立认证、语音采集与识别、模型调用、TTS、镜片显示、反向事件、NAS 自动归档。界面不会将这些显示为成功。"),
        ("我的录音保存在哪里？", "新归档在Turbo IO自己沙盒的 Documents/VerifiedRecordingArchiveV1。旧 ImportedRecordings 保留原位，只有逐条确认才复制进新档。来源不修改，不自动播放、识别或上传。"),
        ("演示会改变眼镜吗？", "不会。演示只是手机侧的可视化与纯逻辑实验；顶部持续显示演示标识。退出应用后默认回到真实未连接状态。"),
        ("怎么接入自己的模型？", "真机语音页使用已验收的阿里云 ASR 与 DeepSeek Flash，在语音服务密钥页配置后明确开启待命。其他模型设置仍是独立草稿，不会改变实际语音服务。"),
        ("为什么没有重置或升级按钮？", "研究版不会为了界面完整加入危险操作。必须等协议、恢复路径和目标设备被核实后，才会开放有确认步骤的控制。"),
        ("如何判断真正打通？", "代码测试、手机运行、眼镜实际显示与反向操作分别验收。最终还要在使用自有签名的非越狱 iPhone 上完整验证。")
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(sections, id: \.0) { item in
                    Card {
                        Text(item.0).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(item.1).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
