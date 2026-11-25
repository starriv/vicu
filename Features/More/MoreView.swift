import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    private var connectionTint: Color {
        switch app.credentialsStatus {
        case .connected, .verified:
            AppTheme.ColorToken.positive
        case .failed:
            AppTheme.ColorToken.negative
        case .testing:
            .blue
        case .missing, .untested:
            AppTheme.ColorToken.warning
        }
    }

    private var notificationsEnabledSummary: String {
        let prefs = app.notificationPreferences
        let hasActiveChannel = prefs.isEnabled && (
            prefs.tradeOrderSubmittedNotificationsEnabled ||
            prefs.tradeOrderStatusNotificationsEnabled ||
            prefs.accountActivityNotificationsEnabled
        )
        return hasActiveChannel
            ? L10n.More.notificationsOn(locale: locale)
            : L10n.More.notificationsOff(locale: locale)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountView()
                } label: {
                    MoreAccountProfileRow(
                        accountNumber: app.portfolio.account?.accountNumber,
                        environment: app.environment,
                        statusText: app.credentialsStatus.title(locale: locale),
                        statusTint: connectionTint
                    )
                }
                .accessibilityHint(L10n.More.accountHint)
            }

            Section {
                NavigationLink {
                    AlpacaView()
                } label: {
                    AppSettingsRow(
                        title: L10n.More.alpacaRowTitle,
                        detail: app.environment.titleText(locale: locale),
                        detailDotColor: connectionTint,
                        systemImage: AppIcon.More.alpaca,
                        badgeColor: .teal
                    )
                }

                NavigationLink {
                    AccountActivityView()
                } label: {
                    AppSettingsRow(
                        title: L10n.AccountActivity.title,
                        systemImage: AppIcon.More.activity,
                        badgeColor: .blue
                    )
                }
            } header: {
                Text(L10n.More.brokerageSection)
            }

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    AppSettingsRow(
                        title: L10n.More.notificationsRowTitle,
                        detail: notificationsEnabledSummary,
                        systemImage: AppIcon.More.notifications,
                        badgeColor: .red
                    )
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    AppSettingsRow(
                        title: L10n.More.settingsRowTitle,
                        detail: app.appearanceMode.titleText(locale: locale),
                        systemImage: AppIcon.More.settings,
                        badgeColor: .gray
                    )
                }
            } header: {
                Text(L10n.More.preferencesSection)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.More.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct MoreAccountProfileRow: View {
    let accountNumber: String?
    let environment: TradeEnvironment
    let statusText: String
    let statusTint: Color

    private var cleanAccountNumber: String? {
        guard let accountNumber else { return nil }
        let trimmed = accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(spacing: 14) {
            AppAccountAvatar(size: 54, iconSize: 52)
                .modifier(MoreAvatarGlassRingModifier())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let cleanAccountNumber {
                        Text(cleanAccountNumber)
                            .font(.headline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text(L10n.More.accountDefaultTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    MoreEnvironmentPill(environment: environment)
                }

                HStack(spacing: 6) {
                    AppSettingsStatusDot(color: statusTint, size: 7)

                    Text(statusText)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct MoreEnvironmentPill: View {
    let environment: TradeEnvironment

    private var foregroundColor: Color {
        environment == .paper ? AppTheme.ColorToken.brandForeground : AppTheme.ColorToken.positive
    }

    private var backgroundColor: Color {
        environment == .paper ? AppTheme.ColorToken.brand : AppTheme.ColorToken.positive.opacity(0.16)
    }

    var body: some View {
        Text(environment.title)
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
    }
}

private struct MoreAvatarGlassRingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(2)
                .glassEffect(.regular, in: .circle)
        } else {
            content
                .overlay {
                    Circle()
                        .strokeBorder(Color(.separator).opacity(0.2), lineWidth: 0.75)
                }
        }
    }
}

#Preview {
    NavigationStack {
        MoreView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
