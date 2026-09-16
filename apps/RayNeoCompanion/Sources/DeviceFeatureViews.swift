import SwiftUI

struct GlassesRecordingCard: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmStart = false
    @State private var expanded = false
    var body: some View {
        Card {
            DisclosureGroup(isExpanded:$expanded) {
              VStack(alignment:.leading,spacing:12) {
                Text(L10n.deviceFeatureStatus(features.recordingStatus, locale: locale)).font(.caption).foregroundStyle(Palette.muted)
                if features.recordingBytes > 0 { Text(L10n.format("Received %@", locale: locale, String(describing: ByteCountFormatter.string(fromByteCount:Int64(features.recordingBytes),countStyle:.file)))).font(.caption.monospacedDigit()) }
                Toggle(L10n.text("Allow Glasses-Initiated Recordings to Be Saved Locally", locale: locale),isOn:Binding(get:{features.acceptsEyeRecording},set:{features.enableEyeRecording($0)}))
                    .font(.caption).disabled(features.recordingID != nil || !voice.ready)
                if features.recordingID == nil {
                    Button(L10n.text("Start Recording on Glasses", locale: locale)) { confirmStart = true }.disabled(!voice.ready)
                } else {
                    HStack {
                        Button(L10n.text("Pause", locale: locale)) { features.recordingControl(8) }
                        Button(L10n.text("Restore", locale: locale)) { features.recordingControl(9) }
                        Button(L10n.text("Mark", locale: locale)) { features.recordingControl(11) }
                        Button(L10n.text("Stop", locale: locale)) { features.recordingControl(4) }
                    }.disabled(!voice.ready)
                }
                Text(L10n.text("Voice standby is paused during recording. Saves audio only, without automatic ASR, uploads, or deletion of glasses files. Re-enable standby on the Conversation page when finished. Offline backlog imports need separate verification.", locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
                if let file = features.completedRecording {
                    HStack { ShareLink(item:file) { Label(L10n.text("Share WAV", locale: locale),systemImage:"square.and.arrow.up") }; Button(L10n.text("Retry Archive", locale: locale)) { Task { await features.archiveReceivedRecording() } } }.font(.caption)
                } else if features.recordingID != nil {
                    Button(L10n.text("Reverify After Completion Message", locale: locale)) { features.retryRecordingFinish() }.font(.caption)
                }
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
              }.padding(.top,12)
            } label: {
                VStack(alignment:.leading,spacing:6) {
                    Label(L10n.text("Glasses Recording", locale: locale),systemImage:"mic.badge.plus").font(.headline)
                    Text(features.recordingID == nil ? L10n.text("Expand Recording Controls · Audio Capture Off by Default", locale: locale) : L10n.deviceFeatureStatus(features.recordingStatus, locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
                }
            }.accessibilityIdentifier("recording-controls").padding(18)
            NavigationLink(L10n.text("Find Local Received Files from Before Restart", locale: locale)) { RecordingRecoveryView() }
                .font(.caption).padding(.horizontal,18).padding(.bottom,14).accessibilityIdentifier("recording-recovery")
        }
        .confirmationDialog(L10n.text("Start recording on the glasses and save to Turbo IO? AI voice standby will pause. Nothing will be uploaded automatically.", locale: locale),isPresented:$confirmStart) {
            Button(L10n.text("Start Recording", locale: locale)) { features.startRecording() }
        }
        .onAppear { features.prepare() }
        .onChange(of:features.recordingID) { if $0 != nil { expanded = true } }
    }
}

struct GlassesTodoSyncCard: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button(L10n.text("Sync Local To-Dos to Glasses", locale: locale)) { confirm = true }.disabled(!voice.ready)
            Text(L10n.deviceFeatureStatus(features.todoStatus, locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            Text(L10n.text("First sync requires confirmation. Edits to linked items are sent when online; offline edits wait for a retry. Status conflicts do not overwrite phone edits; resolve them under Pending Sends and Conflicts. Removal is local only and does not delete old items on the glasses.", locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }
        .confirmationDialog(L10n.text("Send local to-dos that have not been removed to the current glasses? Other official tasks will not be overwritten.", locale: locale),isPresented:$confirm) {
            Button(L10n.text("Send Local To-Dos", locale: locale)) { features.syncTodos() }
        }.onAppear { features.prepare() }
    }
}

struct GlassesPrompterControls: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    let text: String
    @State private var speed = 120.0
    @State private var selectedMode: GlassesPrompterMode = .constantSpeed
    @State private var confirm = false
    private var displayedMode: GlassesPrompterMode { features.teleprompterMode ?? selectedMode }
    private var modeLabel: String {
        L10n.text(displayedMode == .constantSpeed ? "Constant Speed" : "Native Follow Trial", locale: locale)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L10n.text("Glasses Teleprompter", locale: locale)).font(.headline)
            Text(L10n.deviceFeatureStatus(features.teleprompterStatus, locale: locale)).font(.caption).foregroundStyle(Palette.muted)
            Picker(L10n.text("Glasses Scroll Mode", locale: locale), selection: Binding(
                get: { displayedMode }, set: { selectedMode = $0 }
            )) {
                Text(L10n.text("Constant Speed", locale: locale)).tag(GlassesPrompterMode.constantSpeed)
                Text(L10n.text("Native Follow Trial", locale: locale)).tag(GlassesPrompterMode.nativeFollowTrial)
            }.pickerStyle(.segmented).disabled(features.teleprompterID != nil)
            if features.teleprompterID != nil {
                Text(L10n.format("Requested mode: %@", locale: locale, modeLabel)).font(.caption2).foregroundStyle(Palette.muted)
            }
            if displayedMode.canAdjustSpeed {
                HStack { Text(L10n.text("Scroll Speed", locale: locale)); Spacer(); Text(L10n.format("%@ characters/minute candidate", locale: locale, String(describing: Int(speed)))).monospacedDigit() }.font(.caption)
                Slider(value:$speed,in:60...240,step:10)
            }
            if features.teleprompterID == nil {
                Button(L10n.text("Prepare and Transfer Current Script", locale: locale)) { confirm = true }.disabled(!voice.ready || text.isEmpty)
            } else {
                HStack {
                    Button(L10n.text("Start", locale: locale)) { features.teleprompterControl(3) }
                    Button(L10n.text("Pause", locale: locale)) { features.teleprompterControl(4) }
                    Button(L10n.text("Resume", locale: locale)) { features.teleprompterControl(5) }
                    Button(L10n.text("Exit", locale: locale)) { features.teleprompterControl(6) }
                }.disabled(!voice.ready)
                if displayedMode.canAdjustSpeed {
                    Button(L10n.text("Apply Scroll Speed", locale: locale)) { features.teleprompterControl(7,speed:Int(speed)) }.disabled(!voice.ready)
                }
            }
            Text(L10n.text("Only the current segment (up to 12,000 characters) is sent. A receipt or progress offset does not prove speech tracking on the lenses.", locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
            if displayedMode == .nativeFollowTrial {
                Text(L10n.text("This mode asks the glasses to try an unverified native follow setting. The glasses may use its microphone; firmware network use and charges are unknown. Norman IO does not record or transcribe this audio. Test with a short script; exit before changing modes.", locale: locale)).font(.caption2).foregroundStyle(Palette.amber)
            }
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:16))
        .confirmationDialog(displayedMode == .nativeFollowTrial
            ? L10n.text("Try native following on the glasses? AI standby will pause. The glasses firmware controls microphone and network use; verify with a short script.", locale: locale)
            : L10n.text("Send the current text to the glasses? AI standby will pause. Text is transferred only over the local connection.", locale: locale),isPresented:$confirm) {
            Button(L10n.text("Prepare Current Script", locale: locale)) { features.prepareTeleprompter(text,speed:Int(speed),mode:selectedMode) }
        }.onAppear { features.prepare() }
    }
}

struct GlassesSettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var location = "协议测试城市"
    @State private var temperature = 27
    @State private var icon = "100"
    @State private var description = "自定义测试天气"
    @State private var confirmWeather = false
    var body: some View {
        Form {
            Section(L10n.text("Connection and Actual Status", locale: locale)) {
                Text(voice.ready ? L10n.text("Authenticated Connection", locale: locale) : L10n.text("Not connected (simulator sends no packets)", locale: locale))
                LabeledContent(L10n.text("Battery", locale: locale),value:features.battery.map { "\($0)%" } ?? L10n.text("Not Read Yet", locale: locale))
                LabeledContent(L10n.text("Brightness", locale: locale),value:features.brightness.map(String.init) ?? L10n.text("Not Read Yet", locale: locale))
                Button(L10n.text("Read Status and Settings from Glasses", locale: locale)) { features.refreshSettings() }.disabled(!voice.ready)
                Text(L10n.deviceFeatureStatus(features.status, locale: locale)).font(.caption)
            }
            Section(L10n.text("Weather Service", locale: locale)) {
                NavigationLink(L10n.text("Live Dashboard Weather · QWeather", locale: locale)) { QWeatherDashboardView() }.accessibilityIdentifier("qweather-entry")
                NavigationLink(L10n.text("Legacy Weatherstack Manual Query", locale: locale)) { WeatherstackView() }.accessibilityIdentifier("weatherstack-entry")
                Text(L10n.text("Dedicated key · Manual query · Confirm after previewing to sync. No location permission needed.", locale: locale)).font(.caption)
            }
            Section(L10n.text("Verified Settings Controls", locale: locale)) {
                HStack { Button(L10n.text("Brightness 7", locale: locale)) { features.setBrightness(7) }; Spacer(); Button(L10n.text("Brightness 8", locale: locale)) { features.setBrightness(8) } }
                HStack { Button(L10n.text("Sleep After 15 Seconds", locale: locale)) { features.setSleep(15) }; Spacer(); Button(L10n.text("Sleep After 25 Seconds", locale: locale)) { features.setSleep(25) } }
                Button(L10n.text("Head Gestures On · Mode 0", locale: locale)) { features.setHeadControl(true,mode:0) }
                Button(L10n.text("Head Gestures Off", locale: locale)) { features.setHeadControl(false,mode:0) }
                Button(L10n.text("Double-Tap to Open To-Dos", locale: locale)) { features.setDoubleTapTodo(true) }
                Button(L10n.text("Double-Tap to Restore AI", locale: locale)) { features.setDoubleTapTodo(false) }
                Button(L10n.text("Display Height Level 1", locale: locale)) { features.setDisplay(height:1) }
                Button(L10n.text("Display Height Level 3", locale: locale)) { features.setDisplay(height:3) }
                Button(L10n.text("Display Distance Level 1", locale: locale)) { features.setDisplay(distance:1) }
                Button(L10n.text("Display Distance Level 2", locale: locale)) { features.setDisplay(distance:2) }
                Text(L10n.text("Only controls with evidence for their value ranges are available. Unknown privacy fields stay unchanged. Submitting a button action does not verify its physical effect on the glasses.", locale: locale)).font(.caption)
            }.disabled(!voice.ready)
            Section(L10n.text("Custom Weather · Not a Live Weather Service", locale: locale)) {
                TextField(L10n.text("City label", locale: locale),text:$location)
                Stepper(L10n.format("Temperature: %@", locale: locale, temperature.formatted(.number.locale(locale))),value:$temperature,in:-80...60)
                TextField(L10n.text("Raw firmware icon ID", locale: locale),text:$icon).keyboardType(.numberPad)
                TextField(L10n.text("Weather text", locale: locale),text:$description)
                Button(L10n.text("Send Home Screen Test Weather", locale: locale)) { confirmWeather = true }.disabled(!voice.ready || Int(icon) == nil)
                Text(L10n.text("Sends content only, preserving the dashboard layout. The small home weather display and city cards use separate channels. Icon IDs and glasses display behavior need hardware reverification. This does not automatically access location, fetch online weather, or refresh in the background.", locale: locale)).font(.caption)
            }
            if let error = features.error { Section(L10n.text("Action Details", locale: locale)) { Text(error).foregroundStyle(Palette.amber) } }
        }.navigationTitle(L10n.text("Weather and Device Settings", locale: locale))
        .confirmationDialog(L10n.text("Send this explicitly labeled test weather to the glasses?", locale: locale),isPresented:$confirmWeather) {
            Button(L10n.text("Send Custom Data", locale: locale)) { features.sendWeather(location:location,temperature:temperature,icon:Int(icon) ?? 100,description:description) }
        }.onAppear { features.prepare() }
    }
}
