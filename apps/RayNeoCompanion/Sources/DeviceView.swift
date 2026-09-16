import SwiftUI

struct DeviceView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var automaticWeather: AutomaticWeather
    @EnvironmentObject private var qweather: QWeatherDashboard
    @State private var showSettings = false
    @State private var showConnection = false

    var body: some View {
        Screen(title: L10n.text("My Glasses", locale: locale), eyebrow: L10n.text("Norman IO · Your local smart glasses assistant", locale: locale), headerIcon: "gearshape", headerAction: { showSettings = true }) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image("NormanIOMark").resizable().scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    Text("Norman IO").font(.system(size: 25, weight: .semibold))
                    Spacer()
                    if store.demoMode { Badge(text: L10n.text("Demo Interface", locale: locale), active: true) }
                }
                Text(runtime.ready ? L10n.text("Authenticated Connection", locale: locale) : L10n.text("Not Connected Yet", locale: locale)).font(.system(size: 15, weight: .medium))
                GlassesIllustration().padding(.horizontal, 15).padding(.vertical, 28)
                Text(L10n.text("Glasses illustration · Not live device status", locale: locale)).font(.system(size: 9)).foregroundStyle(Palette.mint.opacity(0.5))
            }
            .padding(22).foregroundStyle(.white)
            .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            if runtime.supportsDevice {
                PrimaryButton(title: L10n.text("Discover Glasses in Pairing Mode", locale: locale), icon: "antenna.radiowaves.left.and.right", enabled: !runtime.enabled) { runtime.discover() }
                Button(L10n.text("Connect to the Only Discovered Pair", locale: locale)) { runtime.connect() }.disabled(runtime.enabled)
                Button(L10n.text("Reconnect Glasses Paired with This App", locale: locale)) { runtime.reconnectBonded() }
                    .accessibilityIdentifier("reconnect-bonded")
                Text(runtime.latestEvent).font(.caption).foregroundStyle(Palette.muted)
            } else {
                PrimaryButton(title: L10n.text("The simulator does not connect to glasses", locale: locale), icon: "link", enabled: false) {}
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button { store.selectedTab = 1 } label: { shortcut("mic", title: L10n.text("Voice Assistant", locale: locale), subtitle: L10n.text("Speech recognition and conversation", locale: locale)) }.buttonStyle(.plain)
                Button { store.selectedTab = 2 } label: { shortcut("folder", title: L10n.text("Recording Archive", locale: locale), subtitle: L10n.text("Manage local audio", locale: locale)) }.buttonStyle(.plain)
                NavigationLink { PrompterView() } label: { shortcut("text.alignleft", title: L10n.text("Teleprompter", locale: locale), subtitle: L10n.text("Edit and preview on your phone", locale: locale)) }.buttonStyle(.plain)
                NavigationLink { TodoView() } label: { shortcut("checkmark.circle", title: L10n.text("To-Do List", locale: locale), subtitle: L10n.text("Record and manage tasks", locale: locale)) }.buttonStyle(.plain)
            }
            NavigationLink { QWeatherDashboardView() } label: {
                Label(L10n.qweatherStatus(qweather.status, locale: locale), systemImage: "cloud.sun")
                    .font(.caption).foregroundStyle(Palette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("device-weather-status")
            Button { showConnection = true } label: {
                Label(L10n.text("Local features available; glasses controls await verification", locale: locale), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { runtime.prepare() }
        .sheet(isPresented: $showConnection) { ConnectionBoundaryView() }
    }

    private func shortcut(_ icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(Palette.ink)
                .frame(width: 34, height: 38).background(Palette.mint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line.opacity(0.6), lineWidth: 0.75))
    }
}

struct ConnectionBoundaryView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "link.badge.plus").font(.system(size: 35, weight: .light)).foregroundStyle(Palette.green)
                    Text(L10n.text("Connect with clear boundaries.", locale: locale)).font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text(L10n.text("Turbo IO uses its own bundle and sandbox. The device build integrates the prototype communication core and voice pipeline; the simulator does not load vendor libraries or send Bluetooth commands. Pairing, background behavior, and the glasses display still need testing with the new app on hardware.", locale: locale))
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "iphone", title: L10n.text("Local Phone Features", locale: locale), subtitle: L10n.text("Drafts, imports, configuration, and status demos", locale: locale), status: L10n.text("Available", locale: locale), active: true)
                        FeatureRow(icon: "link", title: L10n.text("Connection, Authentication, and Unpairing", locale: locale), subtitle: L10n.text("Device builds reuse the prototype core; no automatic unpairing or reset", locale: locale))
                        FeatureRow(icon: "eyeglasses", title: L10n.text("Glasses Display and Return Events", locale: locale), subtitle: L10n.text("Each feature must be verified on actual glasses", locale: locale))
                        FeatureRow(icon: "signature", title: L10n.text("Signed, Non-Jailbroken Devices", locale: locale), subtitle: L10n.text("A simulator build does not verify operation on non-jailbroken devices", locale: locale), status: L10n.text("Hardware Test Pending", locale: locale))
                    }
                    Text(L10n.text("Does not modify firmware, unlink official accounts, automatically enable the microphone, or upload recordings.", locale: locale))
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle(L10n.text("Connection Progress", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } }
        }
    }
}
