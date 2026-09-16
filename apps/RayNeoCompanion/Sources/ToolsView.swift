import SwiftUI

struct ToolsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @State private var showModel = false
    @State private var showLab = false
    var body: some View {
        Screen(title: L10n.text("Toolbox", locale: locale), eyebrow: L10n.text("Local Tools and Experiments", locale: locale)) {
            NavigationLink { DisplayObserverView() } label: {
                Card { FeatureRow(icon: "eyeglasses", title: L10n.text("Display Observer", locale: locale), subtitle: L10n.text("USB · Page reports and sent text · Not screenshots", locale: locale), status: L10n.text("Read Only", locale: locale)) }
            }.buttonStyle(.plain).accessibilityIdentifier("display-observer-entry")
            NavigationLink { AlwaysOnLocalProbeView(probe: store.alwaysOn) } label: {
                Card { FeatureRow(icon: "waveform.path", title: L10n.text("All-Day Notes", locale: locale), subtitle: L10n.text("Audio only · 30-second local protocol test", locale: locale), status: L10n.text("Experimental", locale: locale)) }
            }.buttonStyle(.plain).accessibilityIdentifier("always-on-entry")
            NavigationLink { ModelToolsView() } label: {
                Card { FeatureRow(icon: "wrench.and.screwdriver", title: "AI Tools", subtitle: L10n.text("Model tools · Parameters · Availability", locale: locale), status: L10n.text("View", locale: locale)) }
            }.buttonStyle(.plain).accessibilityIdentifier("model-tools-entry")
            NavigationLink { CodexCompanionView() } label: {
                Card { FeatureRow(icon: "terminal", title: L10n.text("Codex Console", locale: locale), subtitle: L10n.text("Computer tasks · Progress · One-time approvals", locale: locale), status: L10n.text("Connect Computer", locale: locale)) }
            }.buttonStyle(.plain).accessibilityIdentifier("codex-tool")
            Card {
                NavigationLink { TodoView() } label: {
                    FeatureRow(icon: "checklist", title: L10n.text("To-Do List", locale: locale), subtitle: L10n.text("Record and manage tasks", locale: locale), status: L10n.text("Available Locally", locale: locale), active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("todo-tool")
                Divider().overlay(Palette.line)
                NavigationLink { PrompterView() } label: {
                    FeatureRow(icon: "text.alignleft", title: L10n.text("Teleprompter", locale: locale), subtitle: L10n.text("Edit scripts and preview on your phone", locale: locale), status: L10n.text("Available Locally", locale: locale), active: true)
                }.buttonStyle(.plain).accessibilityIdentifier("prompter-tool")
            }
            Card {
                Button { showModel = true } label: { FeatureRow(icon: "gearshape", title: L10n.text("Model Settings", locale: locale), subtitle: L10n.text("Configure local models and services", locale: locale), status: L10n.text("Configure", locale: locale)) }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showLab = true } label: { FeatureRow(icon: "flask", title: L10n.text("Protocol Lab", locale: locale), subtitle: L10n.text("Explore protocols and experimental features", locale: locale), status: L10n.text("Local Simulation", locale: locale)) }.buttonStyle(.plain).accessibilityIdentifier("protocol-lab")
            }
            VStack(spacing: 12) {
                SectionLabel(title: L10n.text("Glasses Features", locale: locale), trailing: L10n.text("Hardware integration · Reverification pending", locale: locale))
                Card {
                    NavigationLink { NotificationCenterView() } label: { FeatureRow(icon: "bell.badge", title: L10n.text("Notification Center", locale: locale), subtitle: L10n.text("Source controls and custom send tests", locale: locale), status: L10n.text("Hardware", locale: locale)) }.buttonStyle(.plain).accessibilityIdentifier("notification-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { HeadControlNotificationTestView() } label: { FeatureRow(icon: "person.crop.circle.badge.checkmark", title: L10n.text("Head Gesture Notification Test", locale: locale), subtitle: L10n.text("To-do suggestion card · Nod/shake events return only to this device", locale: locale), status: L10n.text("Hardware", locale: locale)) }.buttonStyle(.plain).accessibilityIdentifier("head-control-test-entry")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "cloud", title: L10n.text("Weather and Device Settings", locale: locale), subtitle: L10n.text("Custom data, status reading, and settings", locale: locale), status: L10n.text("Hardware", locale: locale)) }.buttonStyle(.plain).accessibilityIdentifier("device-settings-tool")
                    Divider().overlay(Palette.line)
                    NavigationLink { GlassesSettingsView() } label: { FeatureRow(icon: "slider.vertical.3", title: L10n.text("Head Gestures and Dial", locale: locale), subtitle: L10n.text("A subset of controls within known protocol value ranges", locale: locale), status: L10n.text("Hardware", locale: locale)) }.buttonStyle(.plain)
                }
            }
            Label(L10n.text("Device behavior must be verified on hardware", locale: locale), systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            HStack {
                NavigationLink(L10n.text("Help", locale: locale)) { HelpView() }
                Spacer()
                NavigationLink(L10n.text("Capabilities", locale: locale)) { ProtocolLabView() }
                Spacer()
                NavigationLink(L10n.text("Preferences", locale: locale)) { SettingsView(embedded: true) }
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
    @Environment(\.locale) private var locale
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
                    Label(L10n.text("DeepSeek Tool List", locale: locale), systemImage: "wrench.and.screwdriver").font(.headline)
                    Text(L10n.format("Current configuration provides %@ / %@ tools", locale: locale, String(describing: providedNames.count), String(describing: CodexToolDescriptor.all.count)))
                        .accessibilityIdentifier("model-tools-count")
                    Text(L10n.text("These tools may accompany the next model request. This does not mean a request was sent, a tool succeeded, or the computer is online. This page is read-only and does not start tasks.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(codex.configured ? (codex.voiceToolsEnabled ? L10n.text("Tool Permission: Allowed", locale: locale) : L10n.text("Tool Permission: Off", locale: locale)) : L10n.text("Tool Configuration: Bridge Address or Token Missing", locale: locale))
                        .font(.caption).accessibilityIdentifier("model-tools-configuration")
                    Text(runtime.supportsDevice ? L10n.format("Voice: %@ · %@", locale: locale, String(describing: runtime.phaseLabel), String(describing: runtime.cloud ? L10n.text("Cloud conversation", locale: locale) : L10n.text("Cloud conversation inactive", locale: locale))) : L10n.text("Simulator: list preview only; glasses voice is unavailable", locale: locale))
                        .font(.caption)
                    Text(L10n.format("Bridge status (last check or saved configuration): %@", locale: locale, String(describing: codex.status))).font(.caption)
                        .accessibilityIdentifier("model-tools-bridge-state")
                    Button(refreshing ? L10n.text("Checking…", locale: locale) : L10n.text("Check Bridge Connection Without Sending a Task", locale: locale)) {
                        refreshing = true
                        Task { await codex.refresh(); refreshing = false }
                    }.disabled(!codex.configured || refreshing).accessibilityIdentifier("model-tools-refresh")
                    NavigationLink(L10n.text("Manage Codex Tool Access and Connection", locale: locale)) { CodexCompanionView() }
                        .accessibilityIdentifier("model-tools-configure")
                }
                ForEach(CodexToolDescriptor.all) { tool in
                    Card {
                        Text(L10n.codexToolTitle(tool, locale: locale)).font(.headline)
                        Text(tool.id).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("model-tool-name-\(tool.id)")
                        Badge(text: providedNames.contains(tool.id) ? L10n.text("Included with Model Requests", locale: locale) : L10n.text("Not Provided to the Model", locale: locale))
                        Text(L10n.codexToolDescription(tool, locale: locale)).font(.subheadline)
                        Text(tool.requiresText ? L10n.text("Parameter: text (required string containing task instructions)", locale: locale) : L10n.text("Parameters: none; uses the currently selected task", locale: locale))
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text(L10n.format("Try saying: “%@”", locale: locale, L10n.codexToolExample(tool, locale: locale))).font(.caption).foregroundStyle(Palette.green)
                        Button {
                            if expandedTools.contains(tool.id) { expandedTools.remove(tool.id) }
                            else { expandedTools.insert(tool.id) }
                        } label: {
                            HStack {
                                Text(expandedTools.contains(tool.id) ? L10n.text("Hide Tool Definition (JSON)", locale: locale) : L10n.text("View Actual Tool Definition (JSON)", locale: locale))
                                Spacer()
                                Image(systemName: expandedTools.contains(tool.id) ? "chevron.down" : "chevron.right")
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("model-tool-details-\(tool.id)")
                            .accessibilityValue(expandedTools.contains(tool.id) ? L10n.text("Expanded", locale: locale) : L10n.text("Collapsed", locale: locale))
                        if expandedTools.contains(tool.id) {
                            Text(tool.schemaJSON).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("model-tool-schema-\(tool.id)")
                        }
                    }
                }
                Text(L10n.text("Currently uses Function Calling, not MCP. App features such as to-dos, weather, and recordings are not registered as model tools. Permission requests still need explicit confirmation on your phone; there is no automatic approval tool.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("model-tools-boundary")
            }.padding(22)
        }.background(Palette.background).navigationTitle("AI Tools").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct TodoView: View {
    @Environment(\.locale) private var locale
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
                notice(L10n.text("Saved locally first · Glasses sync needs confirmation", locale: locale))
                NavigationLink(L10n.text("Import from System Reminders", locale: locale)) { ReminderImportView() }
                    .accessibilityIdentifier("system-reminders-open")
                Picker(L10n.text("To-Do Filter", locale: locale), selection: $showCompleted) {
                    Text(L10n.text("In Progress", locale: locale)).tag(false); Text(L10n.text("Completed", locale: locale)).tag(true)
                }.pickerStyle(.segmented)
                HStack(spacing: 12) {
                    TextField(L10n.text("Add a to-do…", locale: locale), text: $title, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("todo-input").focused($inputFocused)
                    Button {
                        store.addTodo(title); title = ""
                        inputFocused = false
                        showCompleted = false
                    } label: { Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(.white).frame(width: 36, height: 36).background(Palette.ink, in: Circle()) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel(L10n.text("Save Locally", locale: locale))
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 0.75))
                if visibleTodos.isEmpty {
                    Card { EmptyState(icon: "checkmark.circle", title: showCompleted ? L10n.text("No Completed To-Dos Yet", locale: locale) : L10n.text("No Active To-Dos Yet", locale: locale), detail: L10n.text("Start with one small, achievable task.\nThis page does not show or change to-dos in the official app.", locale: locale)) }
                } else {
                    ForEach(visibleTodos) { todo in
                        Button { store.toggleTodo(todo.id) } label: {
                            Card {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 23)).foregroundStyle(Palette.green)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(todo.title).font(.system(size: 15)).strikethrough(todo.completed).foregroundStyle(todo.completed ? Palette.muted : Palette.ink)
                                        Text(L10n.todoDelivery(todo, locale: locale)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        if let day = SystemReminderSnapshot.dateOnlyLabel(todo.reminderDueComponents) {
                                            Text(L10n.text("Scheduled: ", locale: locale) + day).font(.caption2).foregroundStyle(Palette.muted)
                                        } else if let due = todo.dueAt { Text(L10n.text("Scheduled: ", locale: locale) + due.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))).font(.caption2).foregroundStyle(Palette.muted) }
                                        if todo.reminderSourceID != nil { Text(L10n.text("Imported from System Reminders · Independent copy, no changes written back", locale: locale)).font(.caption2).foregroundStyle(Palette.muted) }
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel(L10n.format("%@, %@", locale: locale, String(describing: todo.title), String(describing: todo.completed ? L10n.text("Completed locally", locale: locale) : L10n.text("Incomplete locally", locale: locale))))
                            .contextMenu {
                                Button(L10n.text("Edit Content and Scheduled Time", locale: locale)) { editingTodo = todo }
                                Button(L10n.text("Move to Removed", locale: locale), role: .destructive) { store.archiveTodo(todo.id, archived: true) }
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
                    Label(L10n.text("Export Local To-Do List", locale: locale), systemImage: "arrow.down.to.line")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(store.todos.isEmpty)
                Text(L10n.text("Shares local Markdown text only; does not send it to the glasses.", locale: locale))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                NavigationLink(L10n.text("Removed To-Dos (Recoverable)", locale: locale)) { RemovedTodosView() }
                NavigationLink(L10n.text("Pending Sends and Conflicts", locale: locale)) { TodoDeliveryView() }
                    .accessibilityIdentifier("todo-delivery-open")
                Text(L10n.text("Touch and hold an item to edit or remove it. Scheduled times are recorded only and do not create system reminders automatically.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("To-Do List", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .sheet(item: $editingTodo) { TodoEditorView(todo: $0) }
    }
}

struct TodoEditorView: View {
    @Environment(\.locale) private var locale
    let todo: LocalTodo
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDate = false
    @State private var due = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.text("To-Do Content", locale: locale), text: $title, axis: .vertical).accessibilityIdentifier("todo-edit-title")
                Toggle(L10n.text("Scheduled Time (No Automatic Reminder)", locale: locale), isOn: $hasDate)
                if hasDate { DatePicker(L10n.text("Time", locale: locale), selection: $due) }
                Text(L10n.text("Tasks linked to the glasses will attempt to sync content and completion status while connected. Scheduled times stay on this device and do not generate notifications.", locale: locale)).font(.caption)
            }.navigationTitle(L10n.text("Edit To-Do", locale: locale)).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel", locale: locale)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save", locale: locale)) {
                    store.editTodo(todo.id, title: title, dueAt: hasDate ? due : nil); dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.onAppear { title = todo.title; hasDate = todo.dueAt != nil; due = todo.dueAt ?? Date() }
        }
    }
}

struct RemovedTodosView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    var body: some View {
        List {
            ForEach(store.todos.filter { $0.archivedAt != nil }) { todo in
                HStack { Text(todo.title); Spacer(); Button(L10n.text("Restore", locale: locale)) { store.archiveTodo(todo.id, archived: false) } }
            }
        }.navigationTitle(L10n.text("Removed To-Dos", locale: locale)).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct PrompterView: View {
    @Environment(\.locale) private var locale
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
                Picker(L10n.text("Teleprompter Mode", locale: locale), selection: $mode) { Text(L10n.text("Edit", locale: locale)).tag("编辑"); Text(L10n.text("Phone Preview", locale: locale)).tag("手机预览") }.pickerStyle(.segmented)
                NavigationLink { BookShelfView() } label: {
                    Card { FeatureRow(icon: "books.vertical", title: L10n.text("Book Import and Paced Reading", locale: locale), subtitle: L10n.text("TXT / EPUB · Chapters · Playback speed · Resume reading", locale: locale), status: L10n.text("Available Locally", locale: locale), active: true) }
                }.buttonStyle(.plain).accessibilityIdentifier("book-shelf")
                if mode == "编辑" {
                    Card {
                        HStack { Text(L10n.text("My Script", locale: locale)).font(.headline).foregroundStyle(Palette.ink); Spacer(); Text(L10n.format("%@ characters", locale: locale, String(describing: text.count))).font(.caption).foregroundStyle(Palette.muted) }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty { Text(L10n.text("Write what you want to say…", locale: locale)).foregroundStyle(Palette.muted).padding(.top, 8).padding(.leading, 5) }
                            TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 260).accessibilityIdentifier("prompter-input")
                        }.font(.system(size: 16)).padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text(L10n.text("Phone Layout Preview", locale: locale)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    VStack {
                        ScrollView {
                            Text(pages.isEmpty ? L10n.text("No script yet. Enter text on the Edit page first.", locale: locale) : pages[min(page, pages.count - 1)])
                                .font(.system(size: fontSize, weight: .medium)).foregroundStyle(Palette.mint).lineSpacing(14)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }.frame(height: 210)
                        Text(pages.isEmpty ? L10n.text("No Content", locale: locale) : L10n.format("Phone page %@ / %@", locale: locale, String(describing: page + 1), String(describing: pages.count))).font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.6)).padding(.bottom, 16)
                    }.background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                    HStack { Text(L10n.text("Text Size", locale: locale)); Spacer(); Text("\(Int(fontSize))").monospacedDigit() }.font(.subheadline)
                    HStack { Text("A").font(.caption); Slider(value: $fontSize, in: 16...40, step: 1); Text("A").font(.title3) }
                    HStack {
                        Button { page = max(0, page - 1) } label: { Label(L10n.text("Previous Page", locale: locale), systemImage: "chevron.left").frame(maxWidth: .infinity) }.disabled(page == 0)
                        Button { page = min(pages.count - 1, page + 1) } label: { Label(L10n.text("Next Page", locale: locale), systemImage: "chevron.right").frame(maxWidth: .infinity) }.disabled(page + 1 >= pages.count)
                    }.font(.system(size: 13)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text(L10n.text("Pages are split every 140 characters for phone reading only. This is not the glasses pagination rule.", locale: locale))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 12) {
                    Button { store.savePrompter(text); saved = true } label: {
                        Label(saved ? L10n.text("Saved", locale: locale) : L10n.text("Save Draft", locale: locale), systemImage: saved ? "checkmark" : "square.and.arrow.down").frame(maxWidth: .infinity)
                    }.accessibilityIdentifier("prompter-save")
                    ShareLink(item: text) { Label(L10n.text("Share Script", locale: locale), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.disabled(text.isEmpty)
                }.font(.system(size: 13, weight: .medium)).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.green, lineWidth: 0.75))
                GlassesPrompterControls(text:text)
                notice(L10n.text("Glasses layout and dial controls need hardware testing", locale: locale))
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("Teleprompter", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
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
    @Environment(\.locale) private var locale
    private var capabilities: [(String, String, String)] { [
        (L10n.text("Connection and Authentication", locale: locale), L10n.text("Phone → Glasses / Glasses → Phone", locale: locale), L10n.text("The device build reuses the prototype communication core. Pairing, background behavior, and unpairing with the new bundle still need hardware verification. The simulator does not load the core.", locale: locale)),
        (L10n.text("Full Voice Pipeline", locale: locale), L10n.text("Wake, audio, recognition, response, and exit", locale: locale), L10n.text("The device build integrates cloud ASR/VAD, Flash streaming, and continuous interruptions. Configure keys and confirm activation first. Glasses display verification for the new app is pending.", locale: locale)),
        (L10n.text("To-Do Return Events", locale: locale), L10n.text("Completed on Glasses → Merged on Phone", locale: locale), L10n.text("Checking an item locally does not verify the return protocol. IDs, modification times, and duplicate-event protection must be retained.", locale: locale)),
        (L10n.text("Teleprompter and Display", locale: locale), L10n.text("Phone sends / Glasses dial and page turns", locale: locale), L10n.text("Phone previews do not replace glasses display verification. Pagination, layout, head gestures, and exit behavior need hands-on testing.", locale: locale)),
        (L10n.text("Recording and Offline Sync", locale: locale), L10n.text("Glasses Files → Phone Archive", locale: locale), L10n.text("Online controls, offset-based reception, Ogg/WAV, and archiving are integrated. Offline list imports, automatic resume after a cold start, and end-to-end hardware testing of the new app remain pending.", locale: locale)),
        (L10n.text("Weather and Notifications", locale: locale), L10n.text("Phone Content → Glasses Display", locale: locale), L10n.text("Successful submission and actual glasses display are recorded separately. System notification mirroring is not treated as a custom protocol implementation.", locale: locale))
    ] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                notice(L10n.text("This page explains integration boundaries. It does not send experimental commands or read the official app.", locale: locale))
                ForEach(capabilities, id: \.0) { item in
                    Card {
                        HStack { Text(item.0).font(.headline).foregroundStyle(Palette.ink); Spacer(); Badge(text: L10n.text("Integration / Verification Pending", locale: locale)) }
                        Text(item.1).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green)
                        Text(item.2).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("Protocol Lab", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}

struct SettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var body: some View {
        if embedded { settingsContent } else {
            NavigationStack { settingsContent.toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } } }
        }
    }
    private var settingsContent: some View {
        Form {
            Section {
                NavigationLink(L10n.text("Language", locale: locale)) { LanguageSettingsView() }
                    .accessibilityIdentifier("language-settings")
            }
            Section {
                Toggle(L10n.text("Enable Interface Demo", locale: locale), isOn: $store.demoMode).disabled(store.voice.supportsDevice)
                Text(L10n.text("Applies only to this app launch. Demo content is clearly labeled and does not create audio, call models, or change actual device state.", locale: locale))
                    .font(.footnote).foregroundStyle(Palette.muted)
            } header: { Text(L10n.text("Demo Mode", locale: locale)) }
            Section(L10n.text("Privacy and Security", locale: locale)) {
                Label(L10n.text("Microphone Never Enabled Automatically", locale: locale), systemImage: "mic.slash")
                Label(L10n.text("Audio and Drafts Never Uploaded Automatically", locale: locale), systemImage: "network.slash")
                Label(L10n.text("Model Keys Stored Only in System Keychain", locale: locale), systemImage: "key")
                Label(L10n.text("No Takeover of Official Login or Pairing", locale: locale), systemImage: "lock.shield")
            }.font(.subheadline)
            Section(L10n.text("Current Build", locale: locale)) {
                LabeledContent(L10n.text("Version", locale: locale), value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0") + L10n.text(" · Research Build", locale: locale))
                LabeledContent(L10n.text("Device Connection", locale: locale), value: store.voice.supportsDevice ? L10n.text("Vendor core adapter · Hardware reverification pending", locale: locale) : L10n.text("Disabled in Simulator", locale: locale))
                LabeledContent(L10n.text("Minimum OS", locale: locale), value: "iOS 16")
                Text(L10n.text("Simulator and build success do not verify non-jailbroken hardware, pairing, or the glasses display.", locale: locale))
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
        }.navigationTitle(L10n.text("Preferences", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: embedded)
    }
}

struct HelpView: View {
    @Environment(\.locale) private var locale
    private var sections: [(String, String)] { [
        (L10n.text("What can I use now?", locale: locale), L10n.text("Local to-dos and teleprompter drafts; manually selected and verified recording copies; non-overwriting Markdown revisions from text you provide, with system sharing; draft model settings and isolated Keychain keys.", locale: locale)),
        (L10n.text("Which capabilities are not ready yet?", locale: locale), L10n.text("Live Bluetooth connections, independent authentication, audio capture and recognition, model calls, TTS, glasses display, return events, and automatic NAS archiving. The interface will not report these as successful.", locale: locale)),
        (L10n.text("Where are my recordings saved?", locale: locale), L10n.text("New archives are stored in Documents/VerifiedRecordingArchiveV1 within Turbo IO's own sandbox. Old ImportedRecordings stay in place and are copied into the new archive only after individual confirmation. Sources stay unchanged, with no automatic playback, recognition, or uploads.", locale: locale)),
        (L10n.text("Will the demo change my glasses?", locale: locale), L10n.text("No. The demo is a phone-side visualization and logic experiment, with a persistent demo label at the top. After quitting, the app defaults back to the actual disconnected state.", locale: locale)),
        (L10n.text("How do I connect my own model?", locale: locale), L10n.text("The device voice page uses verified Alibaba Cloud ASR and DeepSeek Flash. Configure Voice Service Keys, then explicitly enable standby. Other model settings remain separate drafts and do not change the actual voice service.", locale: locale)),
        (L10n.text("Why are there no reset or upgrade buttons?", locale: locale), L10n.text("This research build does not add risky operations just to complete the interface. Controls with confirmation steps will become available only after the protocol, recovery path, and target device are verified.", locale: locale)),
        (L10n.text("How can I tell that integration really works?", locale: locale), L10n.text("Code tests, phone operation, actual glasses display, and return controls are verified separately. Full verification must also run on a non-jailbroken iPhone using your own signing identity.", locale: locale))
    ] }
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
        }.background(Palette.background).navigationTitle(L10n.text("Help", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
