import SwiftUI
import RayNeoSession

struct LegacyConversationView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @State private var showConfiguration = false
    @State private var showSimulation = false

    var body: some View {
        Screen(title: L10n.text("Voice Conversation", locale: locale), eyebrow: L10n.text("Local Recognition and Conversation", locale: locale)) {
            HStack {
                Label(L10n.text("Waiting for Connection", locale: locale), systemImage: "clock").font(.system(size: 16, weight: .semibold))
                Spacer(); Badge(text: L10n.text("No Audio Captured Yet", locale: locale), active: true)
            }.foregroundStyle(Palette.ink).padding(16).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))

            VStack(spacing: 13) {
                Text(L10n.text("Your Voice, Your Model", locale: locale)).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                Text(L10n.text("Recognize · Converse · Respond", locale: locale)).font(.system(size: 13)).foregroundStyle(Palette.mint.opacity(0.7))
                HStack(spacing: 4) {
                    ForEach(0..<39) { index in
                        let height = Double([5, 8, 14, 25, 38, 27, 17, 9, 20, 30, 42, 24, 16][index % 13])
                        Capsule().fill(Palette.mint.opacity(0.35 + Double(index % 4) * 0.1)).frame(width: 3, height: height)
                    }
                }.frame(height: 65).padding(.top, 21).accessibilityLabel(L10n.text("Static voice illustration; no audio captured", locale: locale))
                Text(L10n.text("Microphone off · No audio is being transmitted", locale: locale)).font(.system(size: 10)).foregroundStyle(Palette.mint.opacity(0.55))
            }.padding(.vertical, 35).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            Card {
                Button { showConfiguration = true } label: {
                    HStack {
                        Label(L10n.text("Recognition Source", locale: locale), systemImage: "waveform").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text(L10n.text("To Be Determined by Testing", locale: locale)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
                Divider().overlay(Palette.line)
                Button { showConfiguration = true } label: {
                    HStack {
                        Label(L10n.text("Model Service", locale: locale), systemImage: "server.rack").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer(); Text(store.configuration.endpoint.isEmpty ? L10n.text("Not Configured", locale: locale) : L10n.text("Saved on This Device", locale: locale)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.buttonStyle(.plain)
            }
            PrimaryButton(title: L10n.text("Model Settings", locale: locale), icon: "gearshape") { showConfiguration = true }.accessibilityIdentifier("model-settings")
            Button { showSimulation = true } label: {
                Label(L10n.text("Local Workflow Demo", locale: locale), systemImage: "play")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.green, lineWidth: 1))
            }.accessibilityIdentifier("open-session-lab")
        }
        .sheet(isPresented: $showConfiguration) { ModelConfigurationView() }
        .sheet(isPresented: $showSimulation) { SessionSimulationView() }
    }

}

struct ModelConfigurationView: View {
    @Environment(\.locale) private var locale
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
                    Label(L10n.text("Saves settings only; does not connect to the service", locale: locale), systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    Card {
                        Text(L10n.text("Service Address", locale: locale)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField(L10n.text("HTTPS base URL (optional)", locale: locale), text: $draft.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-endpoint")
                        Text(L10n.text("Model Name", locale: locale)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        TextField(L10n.text("Enter model name", locale: locale), text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("model-name")
                        Text(L10n.text("API Key", locale: locale)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                        SecureField(hasKey ? L10n.text("New key (leave blank to keep this address's key)", locale: locale) : L10n.text("Store securely in Keychain (optional)", locale: locale), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).privacySensitive()
                        Text(hasKey ? L10n.text("A key is saved for this service address. Its stored value is not displayed.", locale: locale) : L10n.text("Keys are saved separately for each full service address and are not reused across addresses.", locale: locale))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    Card {
                        HStack {
                        Text(L10n.text("Speech Recognition Strategy", locale: locale)).foregroundStyle(Palette.ink).accessibilityIdentifier("recognition-strategy-label")
                        Spacer()
                        Picker(L10n.text("Speech Recognition Strategy", locale: locale), selection: $draft.recognition) {
                            Text(L10n.text("To Be Determined by Testing", locale: locale)).tag("待实测决定")
                            Text(L10n.text("Local Sherpa (not integrated yet)", locale: locale)).tag("本地 Sherpa")
                            Text(L10n.text("Your Cloud Service (not integrated yet)", locale: locale)).tag("自有云端")
                        }.labelsHidden().accessibilityLabel(L10n.text("Speech Recognition Strategy", locale: locale))
                        }
                        Divider().overlay(Palette.line)
                        HStack {
                        Text(L10n.text("Speech Output", locale: locale)).foregroundStyle(Palette.ink).accessibilityIdentifier("speech-output-label")
                        Spacer()
                        Picker(L10n.text("Speech Output", locale: locale), selection: $draft.speech) {
                            Text(L10n.text("Not Integrated Yet", locale: locale)).tag("待接入")
                            Text(L10n.text("System Speech (not integrated yet)", locale: locale)).tag("系统语音")
                            Text(L10n.text("Your TTS Service (not integrated yet)", locale: locale)).tag("自有 TTS")
                        }.labelsHidden().accessibilityLabel(L10n.text("Speech Output", locale: locale))
                        }
                    }.font(.system(size: 14))
                    PrimaryButton(title: L10n.text("Save Configuration", locale: locale), icon: "square.and.arrow.down") { save() }.accessibilityIdentifier("save-model")
                    Label(L10n.text("No official account or cloud credentials used", locale: locale), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber).padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                    Text(L10n.text("Keys are available only on this device after unlock and are not written to logs or configuration files. Recognition and speech options are draft preferences only; they do not run models or change glasses settings.", locale: locale))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    if hasKey { Button(L10n.text("Remove This Service's Locally Saved Key", locale: locale), role: .destructive) { confirmRemoval = true }.font(.footnote) }
                }.padding(24)
            }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.text("Model Settings", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel", locale: locale)) { dismiss() } }
            }
            .onAppear { draft = store.configuration; hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .onChange(of: draft.endpoint) { _ in hasKey = CredentialVault.hasKey(for: draft.endpoint) }
            .confirmationDialog(L10n.text("Deletes only the model key saved by Turbo IO. The official app is unaffected.", locale: locale), isPresented: $confirmRemoval) {
                Button(L10n.text("Delete Local Key", locale: locale), role: .destructive) {
                    do { try CredentialVault.remove(for: draft.endpoint); hasKey = false } catch { self.error = error.localizedDescription }
                }
            }
            .alert(L10n.text("Configuration Not Saved", locale: locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L10n.text("Got It", locale: locale), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do { try store.saveConfiguration(draft, key: key); key = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
