import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isLogoDevKeyFocused: Bool

    var body: some View {
        @Bindable var app = app

        Form {
            Section {
                AppearanceModeGrid(selection: $app.appearanceMode)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
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
                    AppSettingsRow(
                        title: L10n.Settings.appLanguage,
                        systemImage: AppIcon.Settings.language,
                        badgeColor: .blue
                    )
                }
                .pickerStyle(.menu)
                .tint(.secondary)
            } header: {
                Text(L10n.Settings.language)
            } footer: {
                Text(L10n.Settings.languageFooter)
            }

            Section {
                Toggle(isOn: $app.showsChartTradeMarkers) {
                    AppSettingsRow(
                        title: L10n.Chart.tradeMarkers,
                        systemImage: AppIcon.Settings.tradeMarkers,
                        badgeColor: .green
                    )
                }
                .tint(.green)
            } header: {
                Text(L10n.Chart.sectionTitle)
            } footer: {
                Text(L10n.Chart.tradeMarkersFooter)
            }

            Section {
                Toggle(isOn: $app.isLogoDevEnabled.animation(.snappy)) {
                    AppSettingsRow(
                        title: L10n.Settings.logoDevEnabled,
                        systemImage: AppIcon.Settings.logoDev,
                        badgeColor: .purple
                    )
                }
                .tint(.green)

                if app.isLogoDevEnabled {
                    HStack(spacing: 12) {
                        AppSettingsIconBadge(
                            systemImage: AppIcon.Settings.apiKey,
                            color: .indigo
                        )

                        TextField(
                            L10n.Settings.logoDevAPIKeyPlaceholder,
                            text: $app.logoDevAPIKey
                        )
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isLogoDevKeyFocused)

                        if !app.logoDevAPIKey.isEmpty {
                            Button {
                                app.logoDevAPIKey = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.Settings.clearLogoDevAPIKey)
                        }
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text(L10n.Settings.logoDev)
            } footer: {
                Text(L10n.Settings.logoDevFooter)
            }

            Section {
                AppSettingsLinkRow(
                    title: L10n.Settings.privacyPolicy,
                    destination: URL(string: "https://gist.github.com/starriv/a9184e0b2752f7a3c73204d5229fde1b")!,
                    systemImage: AppIcon.Settings.privacyPolicy,
                    badgeColor: .blue
                )
                .accessibilityIdentifier("settings.privacyPolicy")

                AppSettingsLinkRow(
                    title: L10n.Settings.support,
                    destination: URL(string: "https://github.com/starriv/vicu/issues")!,
                    systemImage: AppIcon.Settings.support,
                    badgeColor: .orange
                )
            } header: {
                Text(L10n.Settings.privacyAndSupport)
            }

            Section {
                AppSettingsRow(
                    title: L10n.Settings.version,
                    detail: AppVersionInfo.formattedVersion,
                    systemImage: AppIcon.Settings.version,
                    badgeColor: .gray
                )
            } header: {
                Text(L10n.Settings.about)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: app.appearanceMode)
        .sensoryFeedback(.selection, trigger: app.appLanguage)
        .onChange(of: app.isLogoDevEnabled) { _, isEnabled in
            if !isEnabled {
                isLogoDevKeyFocused = false
            }
        }
    }
}

private struct AppearanceModeGrid: View {
    @Binding var selection: AppearanceMode

    private static let displayOrder: [AppearanceMode] = [.system, .light, .dark]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Self.displayOrder) { mode in
                AppearanceModeOption(
                    mode: mode,
                    isSelected: selection == mode
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = mode
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppearanceModeOption: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearancePreviewTile(mode: mode, isSelected: isSelected)

                Text(mode.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Color.blue : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct AppearancePreviewTile: View {
    let mode: AppearanceMode
    let isSelected: Bool

    private let cornerRadius: CGFloat = 13

    var body: some View {
        Group {
            switch mode {
            case .light:
                AppearanceMiniScreen(isDark: false)
            case .dark:
                AppearanceMiniScreen(isDark: true)
            case .system:
                GeometryReader { proxy in
                    ZStack {
                        AppearanceMiniScreen(isDark: false)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: proxy.size.width / 2)
                            }

                        AppearanceMiniScreen(isDark: true)
                            .mask(alignment: .trailing) {
                                Rectangle()
                                    .frame(width: proxy.size.width / 2)
                            }

                        Rectangle()
                            .fill(Color(.separator).opacity(0.45))
                            .frame(width: 0.75)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.blue : Color(.separator).opacity(0.45),
                    lineWidth: isSelected ? 2.2 : 0.75
                )
        }
        .accessibilityHidden(true)
    }
}

private struct AppearanceMiniScreen: View {
    let isDark: Bool

    private var canvasColor: Color {
        isDark ? Color(red: 0.08, green: 0.09, blue: 0.11) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var surfaceColor: Color {
        isDark ? Color(red: 0.16, green: 0.17, blue: 0.20) : Color.white
    }

    private var primaryBarColor: Color {
        isDark ? Color.white.opacity(0.82) : Color.black.opacity(0.72)
    }

    private var secondaryBarColor: Color {
        isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.16)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvasColor

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.ColorToken.brand)
                        .frame(width: 8, height: 8)

                    Capsule()
                        .fill(primaryBarColor)
                        .frame(width: 26, height: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(primaryBarColor)
                        .frame(width: 30, height: 4)

                    Capsule()
                        .fill(secondaryBarColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 3.5)

                    Capsule()
                        .fill(AppTheme.ColorToken.brand.opacity(isDark ? 0.9 : 0.95))
                        .frame(width: 22, height: 3.5)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(surfaceColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surfaceColor)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(surfaceColor)
                        .frame(height: 12)
                }
            }
            .padding(8)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppModel())
    }
}
