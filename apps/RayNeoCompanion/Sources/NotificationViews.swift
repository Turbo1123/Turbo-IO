import SwiftUI

struct NotificationCenterView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var confirmSources = false
    var body: some View {
        Form {
            Section {
                Text(L10n.text("Notifications, Right Before Your Eyes", locale: locale)).font(.title3.weight(.semibold))
                Text(L10n.text("System notification sharing and custom business notifications use separate paths. This page does not collect notification bodies from other apps.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                Text(voice.ready ? L10n.text("Glasses Connected", locale: locale) : L10n.text("Glasses not connected · Draft editing and preview available", locale: locale))
                    .accessibilityIdentifier("notification-connection")
            }
            Section(L10n.text("System Notification Sharing · ANCS", locale: locale)) {
                Toggle(L10n.text("Allow Glasses Notifications", locale: locale), isOn: Binding(get: { notifications.preferences.enabled }, set: { notifications.setEnabled($0) }))
                    .accessibilityIdentifier("notification-master")
                Text(L10n.text("When connected and idle, the master switch is submitted immediately. Offline changes are saved as drafts only. This does not automatically change iOS notification permissions.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                Button(L10n.text("Apply Master Switch to Current Glasses", locale: locale)) { notifications.applyMaster() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-master")
                NavigationLink { NotificationSourcesView() } label: {
                    LabeledContent(L10n.text("Allowed Apps", locale: locale), value: "\(notifications.preferences.sources.filter(\.allowed).count)/\(notifications.preferences.sources.count)")
                }.accessibilityIdentifier("notification-sources-open")
                Picker(L10n.text("Notification Display Duration", locale: locale), selection: Binding(get: { notifications.preferences.displayTime }, set: { notifications.setDisplayTime($0) })) {
                    ForEach([5,10,15,20,30], id: \.self) { seconds in Text(L10n.format("%@ seconds", locale: locale, String(describing: seconds))).tag(seconds) }
                }.accessibilityIdentifier("notification-display-time")
                Button(L10n.text("Set Draft to 15 Seconds", locale: locale)) { notifications.setDisplayTime(15) }
                    .accessibilityIdentifier("notification-duration-15")
                Text(L10n.text("New durations need timing checks on the glasses. The protocol packages duration and source filters together, so draft edits are not automatically sent. Review sources before applying.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
                Text(notifications.sourcesNeedApply ? L10n.text("Source List: Draft Not Applied", locale: locale) : L10n.text("Source List: Submitted, Effect Unverified", locale: locale))
                    .font(.caption).accessibilityIdentifier("notification-sources-state")
                Button(L10n.text("Apply Source Configuration to Glasses", locale: locale)) { confirmSources = true }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-apply-sources")
                Text(L10n.appStatus(notifications.configurationStatus, locale: locale)).font(.caption).accessibilityIdentifier("notification-settings-status")
                if let enabled = notifications.reportedEnabled {
                    Text(L10n.format("Glasses-reported master switch: %@ (not an acknowledgment for each source)", locale: locale, String(describing: enabled ? L10n.text("On", locale: locale) : L10n.text("Off", locale: locale)))).font(.caption)
                }
            }
            Section(L10n.text("Manual Test · No Server Connection", locale: locale)) {
                NavigationLink { NotificationTestView() } label: {
                    Label(L10n.text("Write and Send a Test Notification", locale: locale), systemImage: "paperplane")
                }.accessibilityIdentifier("notification-test-open")
                Text(L10n.text("Uses the glasses business channel directly, without showing a phone notification. Enter a title and body, then inspect the UID, status, and timeout.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            }
            Section(L10n.text("Shared Notification Check", locale: locale)) {
                Text(L10n.appStatus(notifications.availabilityStatus, locale: locale)).accessibilityIdentifier("notification-ancs-status")
                Button(L10n.text("Query Glasses ANCS Status", locale: locale)) { notifications.queryAvailability() }
                    .disabled(!notifications.canSend).accessibilityIdentifier("notification-query")
                Text(L10n.text("On your iPhone, go to Settings → Bluetooth → Glasses Details and allow system notification sharing. Source apps also need notification permission. Focus mode and preview settings may affect what appears. Turbo IO does not change these settings for you.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            }
            if let error = notifications.error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-error") } }
        }
        .navigationTitle(L10n.text("Notification Center", locale: locale)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onAppear { features.prepare(); notifications.connectionChanged() }
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
        .confirmationDialog(L10n.text("Replace the current glasses' notification source configuration?", locale: locale), isPresented: $confirmSources, titleVisibility: .visible) {
            Button(L10n.text("Confirm Apply Current Configuration", locale: locale)) { notifications.applySources() }
            Button(L10n.text("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(L10n.format("Applies the master switch, each listed app’s switch (including Phone), and the draft duration: displayTime=%@, avoidDuplicate=false, intervalTime=2. This is not the original configuration read from the glasses. Unlisted apps are not guaranteed to be blocked.", locale: locale, String(describing: notifications.preferences.displayTime)))
        }
    }
}

struct NotificationSourcesView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var notifications: CompanionNotifications
    @State private var search = ""
    @State private var adding = false
    private var visible: [NotificationSource] {
        notifications.preferences.sources.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                Text(L10n.text("These are configurable sources, not a list of installed apps. The protocol sends Bundle IDs for disabled sources; unknown apps are not automatically blocked. Applying for the first time replaces the previous source filters.", locale: locale))
                    .font(.caption).accessibilityIdentifier("notification-source-boundary")
                TextField(L10n.text("Search by name or Bundle ID", locale: locale), text: $search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("notification-source-search")
                Button(L10n.text("Add Source App", locale: locale)) { adding = true }.accessibilityIdentifier("notification-source-add")
            }
            Section(L10n.text("On means allowed · Return to apply your changes", locale: locale)) {
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
            Section { Text(L10n.text("An incorrect Bundle ID cannot filter the intended source. This does not read third-party app data or automatically upload notifications. To restore a disabled source, enable it again and apply the configuration.", locale: locale)).font(.caption) }
        }
        .navigationTitle(L10n.text("Allowed Apps", locale: locale)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .sheet(isPresented: $adding) { NotificationSourceEditor() }
    }
}

private struct NotificationSourceEditor: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var notifications: CompanionNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var id = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.text("App name", locale: locale), text: $name).accessibilityIdentifier("notification-source-name")
                TextField(L10n.text("Bundle ID, e.g. com.example.app", locale: locale), text: $id)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("notification-source-id")
                Text(L10n.text("Enter the actual Bundle ID; a display name cannot replace it. New sources are allowed by default. After saving, return and apply the configuration.", locale: locale)).font(.caption)
                if let error = notifications.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(L10n.text("Add Notification Source", locale: locale)).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel", locale: locale)) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Save Source", locale: locale)) { if notifications.addSource(name: name, id: id) { dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !GlassesNotificationProtocol.validAppID(id))
                        .accessibilityIdentifier("notification-source-save")
                }
            }
        }
    }
}

struct NotificationTestView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var notifications: CompanionNotifications
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var title = "Turbo IO通知测试"
    @State private var content = "这是独立 App 的业务通知测试。"
    @FocusState private var focused: Bool
    private var valid: Bool { (try? GlassesNotificationProtocol.notification(uid: "1", title: title, content: content)) != nil }
    var body: some View {
        Form {
            Section(L10n.text("Edit Test Content", locale: locale)) {
                Text(L10n.text("The source is fixed to Turbo IO and does not impersonate other apps. Content stays in this page's memory only and is not saved or uploaded to a server.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                TextField(L10n.text("Title (up to 80 characters)", locale: locale), text: $title, axis: .vertical)
                    .focused($focused).accessibilityIdentifier("notification-test-title")
                TextField(L10n.text("Body (up to 500 characters)", locale: locale), text: $content, axis: .vertical).lineLimit(3...8)
                    .focused($focused).accessibilityIdentifier("notification-test-content")
                Text(L10n.format("Title %@/80 · Body %@/500 · Test limits for this version, not a guarantee of glasses layout", locale: locale, String(describing: title.count), String(describing: content.count))).font(.caption2)
                Button(L10n.text("Insert Random Verification Test Data", locale: locale)) {
                    let code = String(UUID().uuidString.prefix(6))
                    title = "Turbo IO通知测试 \(code)"; content = "第一行：独立业务通知\n第二行：校验码 \(code)\n请核对眼镜文字。"
                    focused = false
                }.accessibilityIdentifier("notification-test-sample")
            }
            Section(L10n.text("Phone Preview · Not a Glasses Screenshot", locale: locale)) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Turbo IO", systemImage: "bell.badge").font(.caption).foregroundStyle(Palette.green)
                    Text(title).font(.headline)
                    Text(content).font(.body)
                }.padding(.vertical, 8).accessibilityIdentifier("notification-test-preview")
            }
            Section {
                Button(L10n.text("Send to Glasses", locale: locale)) {
                    focused = false; _ = notifications.send(title: title, content: content)
                }.disabled(!notifications.canTest || !valid).accessibilityIdentifier("notification-test-send")
                Text(L10n.text("Requires an authenticated connection, glasses notifications allowed, the Turbo IO source enabled, and the master switch already applied. Does not interrupt voice, recording, or teleprompter use. Sends once per tap, without automatic retries.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                if let uid = notifications.lastUID { Text(L10n.format("Latest UID: %@", locale: locale, String(describing: uid))).font(.caption.monospaced()).accessibilityIdentifier("notification-test-uid") }
                Text(L10n.appStatus(notifications.testStatus, locale: locale)).accessibilityIdentifier("notification-test-status")
                if let operation = notifications.operationStatus { Text(operation).font(.caption) }
                if let error = notifications.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("notification-test-error") }
                Text(L10n.text("An SDK call returning, a glasses status report, and actual display on the glasses are different checks. Even with a report, verify the code above visually. Existing voice text display does not count as passing this test.", locale: locale)).font(.caption)
            }
        }
        .navigationTitle(L10n.text("Custom Notification Test", locale: locale)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L10n.text("Finish Editing", locale: locale)) { focused = false } } }
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
        .onChange(of: voice.deviceID) { _ in notifications.connectionChanged() }
    }
}
