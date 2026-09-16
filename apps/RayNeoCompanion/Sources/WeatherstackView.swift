import SwiftUI

struct WeatherstackView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var automatic: AutomaticWeather
    @StateObject private var weather = WeatherstackController()
    @State private var city = "Beijing, China"
    @State private var key = ""
    @State private var rawIcon = ""
    @State private var acknowledgedIcon = false
    @State private var confirmQuery = false
    @State private var confirmSend = false
    @State private var lookup: Task<Void,Never>?

    var body: some View {
        Form {
            Section(L10n.text("Sync Automatically After Authenticated Connection", locale: locale)) {
                Text(L10n.text("QWeather dashboard weather has replaced the legacy automatic configuration. Connection events no longer trigger this service. Queries and retries on this page are manual.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("Sync Home Weather After Connecting / Reconnecting", locale: locale), isOn: Binding(
                    get: { automatic.configuration.enabled },
                    set: { automatic.configure(city: automatic.configuration.city, enabled: $0) }))
                    .accessibilityIdentifier("weather-auto-enabled")
                Text(L10n.format("Selected city: %@", locale: locale, String(describing: automatic.configuration.city))).font(.caption)
                Text(automatic.status).font(.caption).accessibilityIdentifier("weather-auto-status")
                Text(L10n.text("Fetches and sends only after an authenticated connection. Fresh results can be reused on reconnect. The dashboard layout stays unchanged. Updates wait during recording, conversation, or teleprompter use. Requires a weather-specific key and verified icon mapping.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Retry Automatic Sync", locale: locale)) { automatic.retry() }.disabled(automatic.busy)
                    .accessibilityIdentifier("weather-auto-retry")
                if let result = automatic.snapshot {
                    Text(L10n.format("Automatic query: %@ %@°C · %@ · Weather code %@", locale: locale, String(describing: result.city), String(describing: result.lensTemperature), String(describing: result.description), String(describing: result.providerCode))).font(.caption)
                }
            }
            Section(L10n.text("Weatherstack · Live Weather", locale: locale)) {
                Text(L10n.text("Queries send only the city you enter to Weatherstack and may use your quota. Does not access phone location or send chats, recordings, or glasses identity.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(weather.hasKey ? L10n.text("New key (leave blank to keep the existing key)", locale: locale) : "Weatherstack API Key",text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("weather-key")
                HStack {
                    Button(L10n.text("Save Key Securely", locale: locale)) { weather.saveKey(key); key = ""; automatic.retry() }.disabled(key.isEmpty || weather.busy)
                    Spacer()
                    Button(L10n.text("Remove Key", locale: locale),role:.destructive) { weather.removeKey(); automatic.retry() }.disabled(!weather.hasKey || weather.busy)
                }
                TextField(L10n.text("City and Country", locale: locale),text:$city).autocorrectionDisabled().accessibilityIdentifier("weather-city")
                Button(L10n.text("Save as Automatic Sync City", locale: locale)) {
                    automatic.configure(city:city, enabled:automatic.configuration.enabled)
                }.accessibilityIdentifier("weather-auto-city-save")
                Button(weather.busy ? L10n.text("Fetching…", locale: locale) : L10n.text("Fetch and Preview Without Sending", locale: locale)) { confirmQuery = true }
                    .disabled(weather.busy || !weather.hasKey || city.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("weather-query")
                Button(L10n.text("View Your Provided 2019 Example", locale: locale)) { weather.previewSample() }
                    .disabled(weather.busy).accessibilityIdentifier("weather-sample")
                Text(weather.message).font(.caption).accessibilityIdentifier("weather-status")
            }
            if let result = automatic.snapshot, !result.isSample {
                Section(L10n.text("Verify Automatic Weather Icon", locale: locale)) {
                    Text(L10n.format("Save the verified firmware icon for Weatherstack code %@. If the weather type changes, updates pause until the new code is verified.", locale: locale, String(describing: result.providerCode)))
                        .font(.caption)
                    TextField(L10n.text("Firmware Icon ID", locale: locale), text:$rawIcon).keyboardType(.numberPad)
                    Toggle(L10n.text("I Have Verified This Icon Mapping", locale: locale), isOn:$acknowledgedIcon)
                    Button(L10n.text("Save Icon Mapping and Retry", locale: locale)) {
                        guard acknowledgedIcon, let icon = validIcon else { return }
                        automatic.confirmIcon(providerCode:result.providerCode, firmwareCode:icon)
                    }.disabled(!acknowledgedIcon || validIcon == nil || automatic.busy)
                }
            }
            if let snapshot = weather.snapshot {
                Section(snapshot.isSample ? L10n.text("Historical Example · Cannot Be Sent", locale: locale) : L10n.text("Query Results · Not Synced Yet", locale: locale)) {
                    LabeledContent(snapshot.city,value:snapshot.celsius.formatted(.number.locale(locale)) + " °C")
                        .accessibilityIdentifier("weather-preview")
                    Text(snapshot.description)
                    Text(L10n.format("Local time: %@", locale: locale, String(describing: snapshot.sourceLocalTime.isEmpty ? L10n.text("Missing", locale: locale) : snapshot.sourceLocalTime))).font(.caption)
                    Text(L10n.format("Weatherstack code: %@ (not a glasses icon ID)", locale: locale, String(describing: snapshot.providerCode))).font(.caption)
                    if snapshot.usedLegacyTemperatureKey {
                        Text(L10n.text("Supports the sample's “temparature” spelling; the standard “temperature” field takes precedence.", locale: locale)).font(.caption2)
                    }
                    Text(L10n.text("The home screen protocol carries only the location, integer temperature, and firmware icon. Wind speed, air quality, moon phase, and other fields are not currently sent.", locale: locale)).font(.caption)
                }
                Section(L10n.text("Sync Home Screen Weather", locale: locale)) {
                    TextField(L10n.text("Verified raw firmware icon ID", locale: locale),text:$rawIcon).keyboardType(.numberPad)
                    Toggle(L10n.text("I Have Verified This Firmware Icon Code", locale: locale),isOn:$acknowledgedIcon)
                    Text(L10n.text("No verified automatic mapping exists for provider codes. Do not guess the glasses icon using 122. Temperatures are rounded to integers. The current dashboard layout stays unchanged.", locale: locale)).font(.caption)
                    Button(L10n.text("Sync Query Results to Glasses", locale: locale)) { confirmSend = true }
                        .disabled(!voice.ready || !snapshot.canSend(at:Date()) || !acknowledgedIcon || validIcon == nil || weather.busy)
                        .accessibilityIdentifier("weather-send")
                    Text(features.status).font(.caption)
                    if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                }
            }
        }.navigationTitle(L10n.text("Weatherstack Weather", locale: locale))
        .confirmationDialog(L10n.text("Send the entered city to Weatherstack for one query? This may use your plan's quota.", locale: locale),isPresented:$confirmQuery) {
            Button(L10n.text("Fetch Once", locale: locale)) { lookup = Task { await weather.refresh(city:city) } }
        }
        .confirmationDialog(L10n.text("Send the previewed temperature and specified firmware icon to the glasses home screen?", locale: locale),isPresented:$confirmSend) {
            Button(L10n.text("Confirm Sync", locale: locale)) {
                guard let snapshot = weather.snapshot, acknowledgedIcon, let icon = validIcon else { return }
                features.sendWeatherstack(snapshot,icon:icon)
            }
        }
        .onChange(of:rawIcon) { _ in acknowledgedIcon = false }
        .onAppear { city = automatic.configuration.city }
        .onDisappear { lookup?.cancel(); key = "" }
    }
    private var validIcon: Int? { guard let n = Int(rawIcon), (0...999).contains(n) else { return nil }; return n }
}
