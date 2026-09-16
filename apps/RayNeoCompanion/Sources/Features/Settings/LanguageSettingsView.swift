import SwiftUI

struct LanguageSettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    var body: some View {
        Form {
            Picker(L10n.text("App Language", locale: locale), selection: $languageSettings.language) {
                Text(L10n.text("System Default", locale: locale))
                    .tag(AppLanguage.system)
                    .accessibilityIdentifier("language-system")
                Text(verbatim: "English")
                    .tag(AppLanguage.english)
                    .accessibilityIdentifier("language-en")
                Text(verbatim: "简体中文")
                    .tag(AppLanguage.simplifiedChinese)
                    .accessibilityIdentifier("language-zh-Hans")
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("app-language-picker")
        }
        .navigationTitle(L10n.text("Language", locale: locale))
    }
}
