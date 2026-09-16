import SwiftUI
import RayNeoSession

struct ConversationView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var showKeys = false
    @State private var showConfiguration = false
    @State private var showSimulation = false
    @State private var showDiagnostics = false
    @State private var useCloud = true
    @State private var continuous = true
    @State private var confirmStart = false
    @State private var showBackendSettings = false
    @State private var typedText = ""
    var body: some View {
        Screen(title: L10n.text("Voice Conversation", locale: locale), eyebrow: L10n.text("Cloud speech segmentation · Streaming conversation", locale: locale)) {
            HStack {
                Label(runtime.textBusy ? L10n.text("Processing Text Question", locale: locale) : localizedPhaseLabel, systemImage: runtime.textBusy ? "text.bubble" : (runtime.enabled ? "waveform" : "moon"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: runtime.supportsDevice ? (runtime.ready ? L10n.text("Authenticated", locale: locale) : L10n.text("Not Connected", locale: locale)) : L10n.text("Simulator Preview", locale: locale))
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .monospacedDigit().accessibilityLabel(L10n.text("Current Time", locale: locale))
                }.accessibilityIdentifier("voice-current-time")
                Spacer()
                if let seconds = runtime.initialSpeechSeconds {
                    Text(L10n.format("Listening · Speak now; exits after %@ seconds without speech", locale: locale, seconds.formatted(.number.locale(locale))))
                        .monospacedDigit().accessibilityIdentifier("voice-initial-countdown")
                }
            }.font(.caption).foregroundStyle(Palette.muted)
            Picker(L10n.text("Response Backend", locale: locale), selection: Binding(get: { runtime.selectedBackend }, set: { runtime.selectBackend($0) })) {
                ForEach(ConversationBackend.allCases, id: \.self) { backend in Text(backend.label).tag(backend) }
            }.pickerStyle(.segmented).disabled(!runtime.canConfigureConversation).accessibilityIdentifier("conversation-backend")
            Text(L10n.text("Choose the response backend manually. Turn off standby and end the current task before switching. Connection failures will not automatically switch models.", locale: locale))
                .font(.caption).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.text("What You Said", locale: locale), systemImage: "mic").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.transcript.isEmpty ? (runtime.phase == "recording" ? L10n.text("Listening. Say your task now; no need to wait for the welcome text to disappear.", locale: locale) : L10n.text("Recognized speech will appear here after wake-up", locale: locale)) : runtime.transcript)
                    .font(.system(size: 18)).foregroundStyle(.white).privacySensitive()
                Divider().overlay(Palette.mint.opacity(0.3))
                Label((runtime.answerBackend ?? runtime.selectedBackend).label, systemImage: "sparkles").font(.caption).foregroundStyle(Palette.mint.opacity(0.7))
                Text(runtime.answer.isEmpty ? (runtime.selectedBackend == .hermes ? L10n.text("A receipt appears when your task is accepted. See the task card below for results.", locale: locale) : L10n.text("Responses appear as they stream. Speak to interrupt.", locale: locale)) : runtime.answer)
                    .font(.system(size: 16)).foregroundStyle(Palette.mint).lineSpacing(6).privacySensitive()
                if runtime.modelComplete { Text(runtime.selectedBackend == .hermes ? L10n.text("Display submission complete · See the task card for computer execution status", locale: locale) : L10n.text("Model output complete · Glasses rendering may still be in progress", locale: locale)).font(.caption2).foregroundStyle(Palette.mint.opacity(0.6)) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("live-voice-content")
            if !runtime.enabled {
                Text(L10n.text("Microphone off · No audio is being transmitted", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text(runtime.phase == "idle" || runtime.phase == "waitingForConnection" ? L10n.text("Standing by for the glasses to wake the service; this is not all-day recording.", locale: locale) : L10n.text("Processing this turn's audio. Turn off standby to stop this turn and future automatic responses.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            HStack {
                Button(L10n.text("Model Settings", locale: locale)) { showBackendSettings = true }.accessibilityIdentifier("model-settings")
                Spacer()
                Button(L10n.text("Local Workflow Demo", locale: locale)) { showSimulation = true }.accessibilityIdentifier("open-session-lab")
            }.font(.subheadline)
            Card {
                Label(L10n.text("Text Question", locale: locale), systemImage: "text.bubble").font(.headline)
                TextField(L10n.text("Type your question", locale: locale), text: $typedText, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder).privacySensitive().accessibilityIdentifier("conversation-typed-input")
                Text(L10n.text("Sends only text to the selected backend and leaves the microphone off. Hermes can run tasks on your computer; check progress and results below after submitting.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
                if runtime.textBusy {
                    Button(L10n.text("Stop Text Question", locale: locale)) { runtime.stopText() }.accessibilityIdentifier("conversation-typed-stop")
                } else {
                    Button(L10n.format("Send to %@", locale: locale, runtime.selectedBackend.label)) {
                        runtime.sendText(typedText)
                        if runtime.textBusy { typedText = "" }
                    }.disabled(!runtime.canConfigureConversation || !runtime.modelConfigured || typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("conversation-typed-send")
                }
            }
            if runtime.selectedBackend == .hermes || runtime.hermesTaskUnresolved || runtime.hermesTask != nil {
                HermesTaskCard()
            }
            NavigationLink { CodexCompanionView() } label: {
                Label(L10n.text("Codex Tasks and Approvals", locale: locale), systemImage: "terminal")
            }.accessibilityIdentifier("codex-conversation-entry")
            NavigationLink { ModelToolsView() } label: {
                Label(L10n.text("AI Tools · View tools available to the model", locale: locale), systemImage: "wrench.and.screwdriver")
            }.accessibilityIdentifier("model-tools-conversation-entry")
            if let error = timeline.storageError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.amber)
            }
            NavigationLink { ConversationTimelineView() } label: {
                Card { FeatureRow(icon: "clock.arrow.circlepath", title: L10n.text("Conversation Timeline", locale: locale), subtitle: L10n.text("Automatically save conversations locally · Export and share", locale: locale), status: L10n.text("Saved Locally", locale: locale), active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("conversation-timeline")
            Card {
                Text(L10n.text("Current Voice Pipeline", locale: locale)).font(.headline).foregroundStyle(Palette.ink)
                FeatureRow(icon: "waveform", title: L10n.text("Alibaba Cloud Streaming ASR", locale: locale), subtitle: L10n.text("Cloud VAD segmentation, without additional local silence cutoff", locale: locale), status: L10n.text("Prototype Verified", locale: locale))
                Divider().overlay(Palette.line)
                FeatureRow(icon: "bolt", title: runtime.selectedBackend.label,
                           subtitle: runtime.selectedBackend == .hermes ? L10n.text("Live Hermes · Separate IO session · Computer tasks", locale: locale) : L10n.text("Thinking off · Streaming text · Web search off by default", locale: locale),
                           status: runtime.selectedBackend == .hermes ? L10n.text("Configuration and Verification Required", locale: locale) : L10n.text("Prototype Verified", locale: locale))
                Divider().overlay(Palette.line)
                Text(L10n.text("After continuous ASR wakes, it exits if no valid speech is recognized within 8 seconds. Recognition cancels that countdown; a 120-second session limit remains. Hermes computer tasks run independently and continue when audio capture ends; use the task card to stop them. DeepSeek voice tools need separate configuration. TTS is not currently available.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            if runtime.supportsDevice {
                Card {
                    Toggle(L10n.text("Use Live Cloud Conversation", locale: locale), isOn: $useCloud).disabled(runtime.enabled)
                    Toggle(L10n.text("Continuous ASR · Allow Interruptions", locale: locale), isOn: $continuous).disabled(runtime.enabled || !useCloud).accessibilityIdentifier("voice-continuous-draft")
                    Text(runtime.enabled ? (runtime.cloud && runtime.continuous ? L10n.text("Running: continuous ASR · A newly recognized sentence interrupts the response", locale: locale) : L10n.text("Running: non-continuous mode · Interruptions during output are not guaranteed", locale: locale)) : L10n.text("The switch above configures the next session; it is not running yet", locale: locale))
                        .font(.caption).foregroundStyle(Palette.amber).accessibilityIdentifier("voice-effective-policy")
                    Text(useCloud ? L10n.format("After waking, audio goes to the configured Alibaba Cloud ASR and recognized text goes to %@. Charges may apply.", locale: locale, runtime.selectedBackend.label) : L10n.text("Local WebRTC VAD only. Each turn returns a random test string; no speech recognition or uploads.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button(runtime.hasCredentials ? L10n.text("Manage Voice Service Keys", locale: locale) : L10n.text("Configure ASR and model keys", locale: locale)) { showKeys = true }
                        .disabled(runtime.enabled)
                }
                if runtime.enabled {
                    PrimaryButton(title: L10n.text("Turn Off Standby", locale: locale), icon: "stop.circle") { runtime.stop() }
                    Button(L10n.text("End This Turn, Keep Standby On", locale: locale)) { runtime.endRound() }
                } else {
                    PrimaryButton(title: L10n.text("Enable Glasses Voice Standby", locale: locale), icon: "waveform", enabled: runtime.canStartStandby && runtime.ready && (!useCloud || runtime.hasCredentials)) { confirmStart = true }
                }
                Button(L10n.text("Manage Connection and Unpairing", locale: locale)) { showDiagnostics = true }
                Text(runtime.latestEvent).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                DisclosureGroup(L10n.text("Wake Diagnostics · Last Six Events", locale: locale)) {
                    Text(L10n.text("Oldest to newest. Records structure and limited source identifiers only, without speech content. Identifier meanings are unverified. Cleared when the app restarts.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    if runtime.wakeDiagnostics.isEmpty { Text(L10n.text("No Wake Events Received Yet", locale: locale)) }
                    ForEach(Array(runtime.wakeDiagnostics.enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)").font(.system(size: 11, design: .monospaced))
                    }
                }.accessibilityIdentifier("wake-diagnostics")
                DisclosureGroup(L10n.text("Wake Word Settings · Read-Only Diagnostics", locale: locale)) {
                    Text(L10n.text("Reads wake settings returned by the glasses without changing the wake word. Missing fields do not prove that customization is unsupported; values still need verification.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Button(L10n.text("Read Glasses Wake Settings", locale: locale)) { runtime.queryWakeSettings() }
                        .disabled(!runtime.ready || runtime.queryingWakeSettings)
                    Text(runtime.wakeSettingsStatus).font(.caption)
                    ForEach(Array(runtime.wakeSettingsDiagnostics.enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)").font(.system(size: 11, design: .monospaced))
                    }
                }.accessibilityIdentifier("wake-settings-diagnostics")
                DisclosureGroup(L10n.text("Hey Norman · One-Time Write Test", locale: locale)) {
                    Text(L10n.text("Writes one candidate parameter, then submits the original parameters after 120 seconds. Keep the app in the foreground. A successful submission does not prove that the wake word works.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(runtime.wakeWordTrialStatus).font(.caption)
                    Button(L10n.text("Test Writing Hey Norman Once", locale: locale)) { runtime.beginWakeWordTrial() }
                        .disabled(!runtime.ready || runtime.wakeWordTrial.attempted)
                    if runtime.wakeWordTrial.target != nil {
                        Button(L10n.text("Restore Original Parameters", locale: locale)) { runtime.restoreOriginalWakeParameters() }.disabled(!runtime.ready)
                        Button(L10n.text("Confirmed that “小雷小雷” wakes the glasses", locale: locale)) { runtime.confirmOriginalWakeRestored() }
                            .disabled(!runtime.ready || runtime.wakeWordTrial.phase != .restoreSubmitted)
                    }
                }.accessibilityIdentifier("wake-word-data-trial")
            } else {
                Text(L10n.text("This build does not load the glasses communication library. Configure the settings above to use live text questions. The local workflow demo remains offline and does not represent actual audio capture.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Text(L10n.text("After all response chunks and the completion message are submitted, the session exits if no valid new sentence arrives for 10 seconds. Speaking again cancels the old timer. Timing does not start at the first character, and submission does not prove the glasses finished rendering.", locale: locale))
                .font(.caption).foregroundStyle(Palette.amber)
            Button(L10n.text("Clear This Turn's Screen Text", locale: locale)) { runtime.clearText() }.font(.caption)
        }
        .onAppear { runtime.prepare(); reflectRunningPolicy() }
        .onChange(of: scenePhase) { phase in if phase == .active { runtime.resumeHermesTask() } }
        .onChange(of: runtime.enabled) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.cloud) { _ in reflectRunningPolicy() }
        .onChange(of: runtime.continuous) { _ in reflectRunningPolicy() }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
        .sheet(isPresented: $showKeys) { LiveVoiceKeysView() }
        .sheet(isPresented: $showBackendSettings) { ConversationBackendSettingsView() }
        #if COMPANION_DEVICE
        .sheet(isPresented: $showDiagnostics, onDismiss: { runtime.refresh() }) {
            NavigationStack { VoiceDiagnosticsView(runtime: runtime).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { showDiagnostics = false } } } }
        }
        #endif
        .confirmationDialog(useCloud ? L10n.format("Enable standby? Waking the glasses sends audio to Alibaba Cloud and text to %@. Charges may apply.", locale: locale, runtime.selectedBackend.label) : L10n.text("Start the local random-response test without uploading speech.", locale: locale), isPresented: $confirmStart) {
            Button(L10n.text("Confirm Enable Standby", locale: locale)) { runtime.start(cloud: useCloud, continuous: continuous) }
        }
        .alert(L10n.text("Voice Service", locale: locale), isPresented: Binding(get: { runtime.error != nil }, set: { if !$0 { runtime.error = nil } })) {
            Button(L10n.text("Got It", locale: locale), role: .cancel) {}
        } message: { Text(runtime.error ?? "") }
    }
    private var localizedPhaseLabel: String {
        switch runtime.phase {
        case "disabled": return L10n.text("Standby Off", locale: locale)
        case "waitingForConnection": return L10n.text("Waiting for Authentication", locale: locale)
        case "idle": return L10n.text("Waiting for Glasses Wake-Up", locale: locale)
        case "recording": return L10n.text("Listening", locale: locale)
        case "processing": return L10n.text("Generating Response", locale: locale)
        case "displaying": return L10n.text("Response Sent · You Can Keep Speaking", locale: locale)
        default: return L10n.text("Waiting for Status", locale: locale)
        }
    }
    private func reflectRunningPolicy() {
        guard runtime.enabled else { return }
        useCloud = runtime.cloud; continuous = runtime.continuous
    }
}

struct HermesTaskCard: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var push: HermesPush
    @State private var clarification = ""
    @State private var confirmReconciled = false
    var body: some View {
        Card {
            Label(L10n.text("Hermes · Computer Tasks", locale: locale), systemImage: "desktopcomputer").font(.headline)
            Toggle(L10n.text("Notify on Glasses When Hermes Needs Attention", locale: locale),
                   isOn: Binding(get: { push.enabled }, set: { push.setEnabled($0) }))
                .accessibilityIdentifier("hermes-push-enabled")
            Text(L10n.text(push.status, locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("hermes-push-status")
            Text(L10n.text("Only short, generic reminders appear on the glasses while iOS can run. Review task details and approve only on this phone.", locale: locale))
                .font(.caption2).foregroundStyle(Palette.muted)
            NavigationLink(L10n.text("Glasses Notification Settings and Send Test", locale: locale)) { NotificationCenterView() }
            Text(runtime.hermesTask?.summary ?? (runtime.hermesTaskUnresolved ? L10n.text("Previous Submission Needs Verification", locale: locale) : L10n.text("Submit text or wake the glasses and speak a task. Hermes will run it on your Mac.", locale: locale)))
                .font(.subheadline).accessibilityIdentifier("hermes-task-status")
            if let state = runtime.hermesTask, !state.answer.isEmpty {
                Text(state.answer).font(.system(size: 15)).textSelection(.enabled).privacySensitive()
                    .accessibilityIdentifier("hermes-task-answer")
            }
            if let prompt = runtime.hermesTask?.prompt {
                Divider()
                Text(prompt.kind == .approval ? L10n.text("Your Confirmation Is Needed", locale: locale) : prompt.kind == .clarify ? L10n.text("Hermes Needs More Details", locale: locale) : L10n.text("Handle This on Your Computer", locale: locale)).font(.headline)
                Text(prompt.title).font(.subheadline).textSelection(.enabled).privacySensitive()
                if prompt.kind == .approval {
                    HStack {
                        Button(L10n.text("Allow Once", locale: locale)) { runtime.decideHermesTask(promptID: prompt.id, choice: "once") }.accessibilityIdentifier("hermes-approve-once")
                        Button(L10n.text("Deny", locale: locale), role: .destructive) { runtime.decideHermesTask(promptID: prompt.id, choice: "deny") }
                    }.disabled(runtime.hermesTaskBusy || runtime.hermesDecisionUnconfirmed)
                } else if prompt.kind == .clarify {
                    ForEach(prompt.options, id: \.self) { option in Button(option) { clarification = option } }
                    TextField(L10n.text("Answer this follow-up", locale: locale), text: $clarification, axis: .vertical).textFieldStyle(.roundedBorder).privacySensitive()
                    Button(L10n.text("Reply to Hermes", locale: locale)) { runtime.decideHermesTask(promptID: prompt.id, text: clarification); clarification = "" }
                        .disabled(runtime.hermesTaskBusy || runtime.hermesDecisionUnconfirmed || clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("hermes-clarify-send")
                } else {
                    Text(L10n.text("Return to your Mac for passwords, login, or system permissions. This field does not accept passwords. You can also stop the current task.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                }
                if runtime.hermesDecisionUnconfirmed { Text(L10n.text("The confirmation result needs verification and will not be sent again automatically. Refresh the status or stop the task.", locale: locale)).font(.caption).foregroundStyle(Palette.amber) }
            }
            if let problem = runtime.hermesTaskProblem { Text(problem).font(.caption).foregroundStyle(Palette.amber) }
            HStack {
                Button(L10n.text("Verify Task / Reconnect", locale: locale)) { runtime.resumeHermesTask() }.disabled(runtime.hermesTaskBusy).accessibilityIdentifier("hermes-task-refresh")
                if runtime.hermesTaskUnresolved {
                    Button(runtime.hermesTask?.status == .stopping ? L10n.text("Request Stop Again", locale: locale) : L10n.text("Stop Computer Task", locale: locale), role: .destructive) { runtime.stopHermesTask() }
                        .disabled(runtime.hermesTaskBusy).accessibilityIdentifier("hermes-task-stop")
                }
            }
            if runtime.hermesTask?.status == .unknown {
                Button(L10n.text("Verified on Computer; Start a New Task", locale: locale)) { confirmReconciled = true }.disabled(runtime.hermesTaskBusy)
            }
            Text(L10n.text("Mac tasks can continue after the phone screen turns off or audio capture ends. Stopping a task does not undo completed actions.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
        }.accessibilityIdentifier("hermes-task-card")
            .onChange(of: runtime.hermesTask?.prompt?.id) { _ in clarification = "" }
            .confirmationDialog(L10n.text("Have you verified the original task on your computer?", locale: locale), isPresented: $confirmReconciled) {
                Button(L10n.text("Verified; Clear the Old Task Lock", locale: locale)) { runtime.acknowledgeHermesUnknown() }
            } message: { Text(L10n.text("This only clears the local task lock left after a restart. It does not undo or rerun the original action. Verify the result before submitting a new task to avoid duplicate execution.", locale: locale)) }
    }
}

struct ConversationBackendSettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var token = ""
    @State private var deepSeekKey = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Manual Selection", locale: locale)) {
                    Picker(L10n.text("Response Backend", locale: locale), selection: Binding(get: { runtime.selectedBackend }, set: { runtime.selectBackend($0) })) {
                        ForEach(ConversationBackend.allCases, id: \.self) { backend in Text(backend.label).tag(backend) }
                    }.disabled(!runtime.canConfigureConversation)
                    Text(L10n.text("Settings can be changed only with standby off and no task running. Wake words and errors will not automatically switch the backend.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Hermes · Computer Bridge", locale: locale)) {
                    TextField(L10n.text("HTTPS bridge base URL", locale: locale), text: $endpoint).keyboardType(.URL).accessibilityIdentifier("hermes-endpoint")
                    SecureField(L10n.text("Separate bridge token (leave blank to keep)", locale: locale), text: $token).accessibilityIdentifier("hermes-token")
                    Text(L10n.text("The token is stored only in this app's separate Keychain and is tied to this address. Server credentials stay on the computer. Do not enter Hermes's model API key here.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("Save Hermes Configuration", locale: locale)) {
                        _ = runtime.saveHermes(endpoint: endpoint, token: token); token = ""
                    }.disabled(!runtime.canEditHermesConfiguration).accessibilityIdentifier("hermes-save")
                    Button(L10n.text("Check Saved Bridge", locale: locale)) { Task { await runtime.checkHermes() } }
                        .disabled(!runtime.canEditHermesConfiguration || runtime.hermesEndpoint.isEmpty).accessibilityIdentifier("hermes-check")
                    Text(L10n.appStatus(runtime.hermesStatus, locale: locale)).font(.caption)
                    Text(L10n.text("Hermes can run tasks using tools configured on your computer. IO sessions are separate from WhatsApp and share your existing persona and memory configuration. While a task is unfinished, only the token for the original address can be corrected; the task ID is retained.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("DeepSeek · Shared by Text and Voice", locale: locale)) {
                    SecureField("DeepSeek API Key", text: $deepSeekKey)
                    Button(L10n.text("Save DeepSeek Key", locale: locale)) {
                        _ = runtime.saveTextDeepSeekKey(deepSeekKey); deepSeekKey = ""
                    }.disabled(!runtime.canConfigureConversation || deepSeekKey.isEmpty)
                    Text(L10n.text("Text questions do not need an ASR key. Configure glasses ASR under “Manage Voice Service Keys” on the Conversation page.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = runtime.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .navigationTitle(L10n.text("Response Backend", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .onAppear { endpoint = runtime.hermesEndpoint }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } }
        }
    }
}

struct LiveVoiceKeysView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var asr = ""
    @State private var host = CloudASRHostSettings.current()
    @State private var llm = ""
    @State private var enableDefault = true
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Current Voice Service", locale: locale)) {
                    Text(L10n.format("Alibaba Cloud qwen-audio-3.0-asr-flash-streaming\nResponse backend: %@", locale: locale, runtime.selectedBackend.label))
                    Text(L10n.text("Enter your own Alibaba Cloud ASR host. It must support the model and the DashScope streaming task protocol. DeepSeek uses its fixed official endpoint. Set the Hermes address and token in Model Settings.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("This App's Separate Keychain", locale: locale)) {
                    TextField(L10n.text("Your ASR host (without https://)", locale: locale), text: $host)
                        .accessibilityIdentifier("live-asr-host").keyboardType(.URL)
                    Text(L10n.text("Changing hosts will not reuse a key from another host. The source code contains no developer tenant addresses or keys.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField(L10n.text("Alibaba Cloud API key (leave blank to keep)", locale: locale), text: $asr)
                        .accessibilityIdentifier("live-asr-key")
                    SecureField(runtime.selectedBackend == .hermes ? L10n.text("DeepSeek API key (not needed for Hermes)", locale: locale) : L10n.text("DeepSeek API key (leave blank to keep)", locale: locale), text: $llm)
                        .accessibilityIdentifier("live-llm-key")
                    Text(L10n.text("Does not read keys from the official app or test apps. After the first device unlock, keys are available for local background voice use. They are not synced, and stored values are never displayed.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }.textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Toggle(L10n.text("Enable Cloud Conversation and Continuous Interruptions After Saving", locale: locale), isOn: $enableDefault).accessibilityIdentifier("live-default-voice")
                Text(L10n.text("Default standby waits for wake-up after connecting; it does not continuously record. If you turn standby off, it will not turn itself back on.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Button(enableDefault ? L10n.text("Save and Enable Default Standby", locale: locale) : L10n.text("Save Keys Only, Without Starting Conversation", locale: locale)) {
                    let saved = runtime.saveKeys(asr: asr, llm: llm, host: host, enableDefault: enableDefault)
                    asr = ""; llm = ""
                    if saved { dismiss() }
                }.accessibilityIdentifier("live-save-keys")
                if let error = runtime.error { Text(error).foregroundStyle(.red).font(.caption) }
            }.navigationTitle(L10n.text("Voice Service Keys", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel", locale: locale)) { dismiss() } } }
        }
    }
}
