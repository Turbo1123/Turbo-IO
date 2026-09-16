import SwiftUI

struct CodexCompanionView: View {
    @Environment(\.locale) private var locale
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
    @State private var abandoningPending = false
    @State private var answers: [String: String] = [:]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label(L10n.text("Your Computer, Codex in Your Glasses", locale: locale), systemImage: "terminal").font(.headline)
                    Text(L10n.text("Send tasks, check progress, and continue conversations. The computer runs independently, so glasses voice sessions do not have to wait. Approvals require your explicit confirmation on this page; the model cannot approve for you.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(L10n.appStatus(codex.status, locale: locale)).font(.caption).accessibilityIdentifier("codex-status")
                    if let state = codex.state {
                        Text(state.workspace).font(.caption2).textSelection(.enabled)
                        Badge(text: state.readOnly ? L10n.text("Read-Only Test", locale: locale) : L10n.text("Workspace Write Access", locale: locale))
                    }
                }
                Card {
                    Text(L10n.text("Computer Bridge", locale: locale)).font(.headline)
                    TextField(L10n.text("HTTPS address", locale: locale), text: $endpoint).accessibilityIdentifier("codex-endpoint")
                    if !codex.endpoint.isEmpty {
                        Text(L10n.format("Saved address: %@", locale: locale, String(describing: codex.endpoint))).font(.caption2).textSelection(.enabled)
                    }
                    SecureField(L10n.text("Separate access token (leave blank to keep)", locale: locale), text: $token).privacySensitive().accessibilityIdentifier("codex-token")
                    Toggle(L10n.text("Allow DeepSeek to Call Codex Tools", locale: locale), isOn: $voiceTools).accessibilityIdentifier("codex-voice-tools")
                    Text(L10n.text("When enabled, task text from voice conversations may be sent to this computer and Codex. Raw microphone audio is not uploaded, and existing desktop tasks are not taken over.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button(L10n.text("Save Configuration Without Starting a Task", locale: locale)) {
                        do { try codex.save(endpoint: endpoint, token: token, voiceTools: voiceTools); token = "" }
                        catch { self.error = error.localizedDescription; token = "" }
                    }.disabled(codex.busy).accessibilityIdentifier("codex-save")
                    Button(L10n.text("Connect / Refresh Status", locale: locale)) { Task { await codex.refresh() } }
                        .disabled(!codex.configured).accessibilityIdentifier("codex-refresh")
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Card {
                    Toggle(L10n.text("Notify When Codex Finishes or Needs Confirmation", locale: locale), isOn: Binding(get: { push.enabled }, set: { push.setEnabled($0) }))
                        .accessibilityIdentifier("codex-push-enabled")
                    Text(push.status).font(.caption).accessibilityIdentifier("codex-push-status")
                    Text(L10n.appStatus(notifications.testStatus, locale: locale)).font(.caption2).accessibilityIdentifier("codex-push-delivery")
                    NavigationLink(L10n.text("Glasses Notification Settings and Send Test", locale: locale)) { NotificationCenterView() }
                    Text(L10n.text("Only new events trigger alerts. Completed tasks show a summary; full results stay on this page. Alerts wait while voice, recording, or teleprompter features are using the display. A notification is not an approval.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(L10n.text("If glasses notifications were already allowed, this master switch is restored after connecting. Other apps' source filters stay unchanged.", locale: locale))
                        .font(.caption2).foregroundStyle(Palette.muted)
                    Text(L10n.text("Checks roughly every two seconds while iOS allows the app to run. APNs is not integrated, so timely alerts are not guaranteed after suspension or force quit. The computer bridge keeps up to 128 events in memory and retains completion events for one hour; restarting clears them.", locale: locale))
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if codex.hasUnknownDelivery {
                    Card {
                        Label(L10n.text("Previous Submission Needs Verification", locale: locale), systemImage: "exclamationmark.triangle").foregroundStyle(Palette.amber)
                        Text(L10n.text("Keeps the original request without automatically creating a second task. If the token is wrong, save a corrected token for the current address, then verify. The address cannot change until verification finishes. Pending verification data is stored temporarily on this device and cleared after confirmation.", locale: locale))
                            .font(.caption)
                        Button(L10n.text("Verify Previous Submission", locale: locale)) { Task { await codex.retryPending() } }.disabled(codex.busy)
                        Button(L10n.text("Discard Old Submission and Reconfigure", locale: locale), role: .destructive) { abandoningPending = true }
                            .disabled(codex.busy).accessibilityIdentifier("codex-abandon-pending")
                    }
                }
                Card {
                    HStack {
                        Text(L10n.text("Current Task", locale: locale)).font(.headline); Spacer()
                        Button(L10n.text("Start a New Task Instead", locale: locale)) { codex.select(nil) }.disabled(codex.busy || codex.hasUnknownDelivery)
                    }
                    Text(codex.selectedTaskID.map { L10n.text("Task ", locale: locale) + String($0.prefix(8)) } ?? L10n.text("The next message will create a new task", locale: locale)).font(.caption)
                    TextField(L10n.text("Instructions for Codex…", locale: locale), text: $prompt, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("codex-prompt")
                    Button(L10n.text("Insert Random Verification Test", locale: locale)) {
                        prompt = "这是Turbo IO连接测试。不要读写文件或运行工具，只回复：Turbo IOCodex校验 " + String(UUID().uuidString.prefix(6))
                    }.accessibilityIdentifier("codex-fixture")
                    HStack {
                        Button(L10n.text("Send to Computer", locale: locale)) { Task { do { _ = try await codex.message(prompt); prompt = "" } catch { self.error = error.localizedDescription } } }
                            .disabled(!codex.configured || codex.busy || codex.hasUnknownDelivery || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("codex-send")
                        Spacer()
                        Button(L10n.text("Stop Task", locale: locale), role: .destructive) { Task { do { try await codex.stop() } catch { self.error = error.localizedDescription } } }
                            .disabled(codex.selected?.turnId == nil || codex.busy || codex.hasUnknownDelivery)
                    }
                }
                if let task = codex.selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(task.status).font(.headline)
                        Text(task.answer.isEmpty ? L10n.text("No Codex Output Yet", locale: locale) : task.answer).textSelection(.enabled).privacySensitive()
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.mint)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("codex-output")
                    ForEach(task.pending) { request in
                        Card {
                            Label(request.kind == "question" ? L10n.text("Codex Needs Your Answer", locale: locale) : L10n.text("Codex Requests One-Time Approval", locale: locale), systemImage: "hand.raised").font(.headline)
                            Text(request.summary).font(.caption).textSelection(.enabled)
                            Text(L10n.format("Request %@ · Valid for two minutes", locale: locale, String(describing: request.id.prefix(8)))).font(.caption2)
                            if request.kind == "question" {
                                ForEach(request.questions) { q in
                                    Text(q.question).font(.subheadline)
                                    ForEach(q.options, id: \.self) { option in Button(option) { answers[q.id] = option } }
                                    TextField(L10n.text("Your answer", locale: locale), text: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 }))
                                }
                                Button(L10n.text("Submit These Answers", locale: locale)) { decide(request, accept: false) }
                                    .disabled(codex.busy || request.questions.contains(where: { answers[$0.id, default: ""].isEmpty }))
                            } else {
                                HStack {
                                    Button(L10n.text("Approve Once", locale: locale)) { approval = request }
                                    Button(L10n.text("Deny", locale: locale), role: .destructive) { decide(request, accept: false) }
                                }.disabled(codex.busy || codex.hasUnknownDelivery)
                            }
                        }
                    }
                }
                if let tasks = codex.state?.tasks, !tasks.isEmpty {
                    Card {
                        Text(L10n.text("Tasks Managed by the Bridge", locale: locale)).font(.headline)
                        ForEach(tasks) { task in
                            Button("\(task.id.prefix(8)) · \(task.status)") { codex.select(task.id) }
                                .disabled(codex.busy || codex.hasUnknownDelivery)
                        }
                    }
                }
                Text(L10n.text("Refreshes every two seconds while this page is in the foreground. Closing the page does not stop computer tasks. This version does not guarantee real-time iOS background notifications. You can ask “How is Codex progressing?” by voice.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(22)
        }.background(Palette.background).navigationTitle(L10n.text("Codex Console", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { endpoint = codex.endpoint; voiceTools = codex.voiceToolsEnabled }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await codex.refresh() }
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                }
            }
            .confirmationDialog(L10n.text("Approves only this request, without granting permission for the whole session.", locale: locale), isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } })) {
                Button(L10n.text("Confirm One-Time Approval", locale: locale)) { if let request = approval { decide(request, accept: true) }; approval = nil }
            } message: { Text(approval?.summary ?? "") }
            .confirmationDialog(L10n.text("Discard this pending verification record?", locale: locale), isPresented: $abandoningPending, titleVisibility: .visible) {
                Button(L10n.text("Confirm Discard Old Submission", locale: locale), role: .destructive) {
                    do { try codex.abandonPending() }
                    catch { self.error = error.localizedDescription }
                }
            } message: {
                Text(L10n.text("Only removes the local pending verification record. It does not stop the computer task or automatically resend it. If the old request already ran, submitting again may repeat the action.", locale: locale))
            }
            .alert(L10n.text("Codex Bridge", locale: locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.text("Got It", locale: locale), role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private func decide(_ request: CodexApproval, accept: Bool) {
        Task { do { try await codex.decide(request, approve: accept, answers: answers); answers = [:] } catch { self.error = error.localizedDescription } }
    }
}
