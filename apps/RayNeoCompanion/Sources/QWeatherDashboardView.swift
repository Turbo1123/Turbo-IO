import SwiftUI

struct QWeatherDashboardView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var weather: QWeatherDashboard
    @State private var draft = QWeatherConfiguration()
    @State private var key = ""
    @State private var test = false
    @State private var confirmIcon = false
    var body: some View {
        Form {
            Section(L10n.text("Dashboard Home · Live Weather", locale: locale)) {
                Text(L10n.text("Updates the small weather display on the home screen. Does not change selected-city weather cards or the dashboard layout.", locale: locale))
                    .font(.caption)
                Text(L10n.qweatherStatus(weather.status, locale: locale)).accessibilityIdentifier("qweather-status")
                Text(L10n.qweatherStatus(weather.reply, locale: locale)).font(.caption).accessibilityIdentifier("qweather-reply")
            }
            Section(L10n.text("QWeather Service · Settings Stored Locally", locale: locale)) {
                TextField(L10n.text("Dedicated API host (without https://)", locale: locale),text:$draft.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-host")
                SecureField(L10n.text("API key (leave blank to keep this host's key)", locale: locale),text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-key")
                TextField(L10n.text("Location name", locale: locale),text:$draft.location).accessibilityIdentifier("qweather-location")
                HStack {
                    TextField(L10n.text("Latitude", locale: locale),text:$draft.latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-latitude")
                    TextField(L10n.text("Longitude", locale: locale),text:$draft.longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-longitude")
                }
                Toggle(L10n.text("Update Dashboard Automatically After Authenticated Connection", locale: locale),isOn:$draft.enabled).accessibilityIdentifier("qweather-enabled")
                Button(L10n.text("Save and Apply", locale: locale)) {
                    draft.host = draft.host.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                    weather.save(draft,key:key.trimmingCharacters(in:.whitespacesAndNewlines)); key = ""
                }.disabled(weather.busy).accessibilityIdentifier("qweather-save")
                Text(L10n.text("After saving while connected, the supplied coordinates will be queried and may use your quota. Phone location is not accessed. Keys are stored separately by host in the local Keychain and are available in the background after the first unlock. No recordings or chats are sent.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Fetch and Send", locale: locale)) {
                Button(L10n.text("Fetch Again / Retry Home Screen Update", locale: locale)) { weather.retry() }.disabled(weather.busy).accessibilityIdentifier("qweather-refresh")
                if let s = weather.snapshot {
                    Text(L10n.format("%@ · %@ · %@°C → Glasses %@°C", locale: locale, String(describing: weather.configuration.location), String(describing: s.condition), String(describing: String(format:"%.2f",s.temperature)), String(describing: s.lensTemperature)))
                        .accessibilityIdentifier("qweather-preview")
                    Text(L10n.format("Fetched: %@. Cached locally for up to 10 minutes. The API provides no observation time; the fetch time is not the observation time.", locale: locale, String(describing: s.fetchedAt.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(locale)))))
                        .font(.caption)
                    Text(L10n.text("Source: QWeather", locale: locale)).font(.caption)
                    ForEach(s.attributions,id:\.self) { Text($0).font(.caption2).textSelection(.enabled) }
                    Text(L10n.format("Weather code %@ does not automatically match a firmware icon. Send a candidate test with the same ID and visually verify it before enabling automatic updates for this type.", locale: locale, String(describing: s.code)))
                        .font(.caption)
                    Button(L10n.text("Send Dashboard Candidate Test", locale: locale)) { test = true }.disabled(weather.busy).accessibilityIdentifier("qweather-test-dashboard")
                    Button(L10n.text("Glasses Icon Verified; Save Mapping", locale: locale)) { confirmIcon = true }.disabled(weather.busy).accessibilityIdentifier("qweather-confirm-icon")
                }
            }
        }
        .navigationTitle(L10n.text("Dashboard Weather", locale: locale))
        .preference(key:CompanionTabBarHiddenPreference.self,value:true)
        .onAppear { draft = weather.configuration }
        .onDisappear { key = "" }
        .confirmationDialog(L10n.text("Send the real temperature and the unverified icon with the same numeric ID to the dashboard home screen? Weather cards will stay unchanged.", locale: locale),isPresented:$test) {
            Button(L10n.text("Send One Home Screen Test", locale: locale)) { weather.testCandidate() }
        }
        .confirmationDialog(L10n.text("Confirm only after seeing the correct temperature and weather icon on the glasses home screen. A protocol acknowledgment does not replace visual verification.", locale: locale),isPresented:$confirmIcon) {
            Button(L10n.text("I Visually Confirmed the Icon Is Correct", locale: locale)) { weather.confirmDisplayedIcon(); draft = weather.configuration }
        }
    }
}
