import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        BasicLayout(L10n.Settings.title, style: .form) {
            Section {
                Picker(selection: $app.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                } label: {
                    Label {
                        Text(L10n.Settings.themeMode)
                    } icon: {
                        Image(systemName: AppIcon.Settings.appearance)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.icon)
                            .frame(width: 30)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text(L10n.Settings.appearance)
            } footer: {
                Text(L10n.Settings.themeModeFooter)
            }

            Section {
                Picker(selection: $app.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title)
                            .tag(language)
                    }
                } label: {
                    Label {
                        Text(L10n.Settings.appLanguage)
                    } icon: {
                        Image(systemName: AppIcon.Settings.language)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.icon)
                            .frame(width: 30)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text(L10n.Settings.language)
            } footer: {
                Text(L10n.Settings.languageFooter)
            }

            Section {
                Toggle(isOn: $app.isLogoDevEnabled) {
                    SettingsLabel(title: L10n.Settings.logoDevEnabled, systemImage: AppIcon.Settings.logoDev)
                }

                Label {
                    TextField(L10n.Settings.logoDevAPIKeyPlaceholder, text: $app.logoDevAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } icon: {
                    Image(systemName: AppIcon.Settings.logoDev)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.icon)
                        .frame(width: 30)
                }
                .disabled(!app.isLogoDevEnabled)
                .opacity(app.isLogoDevEnabled ? 1 : 0.55)

                if !app.trimmedLogoDevAPIKey.isEmpty {
                    Button(role: .destructive) {
                        app.logoDevAPIKey = ""
                    } label: {
                        Text(L10n.Settings.clearLogoDevAPIKey)
                    }
                }
            } header: {
                Text(L10n.Settings.logoDev)
            } footer: {
                Text(L10n.Settings.logoDevFooter)
            }
        }
        .tint(AppTheme.ColorToken.brand)
    }
}

private struct SettingsLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.icon)
                .frame(width: 30)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppModel())
    }
}
