import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    var body: some View {
        BasicLayout(L10n.More.title, style: .list) {
            List {
                Section {
                    NavigationLink {
                        AlpacaView()
                    } label: {
                        MoreRow(
                            title: L10n.More.alpacaTitle(locale: locale),
                            subtitle: app.credentialsStatus.title(locale: locale),
                            systemImage: AppIcon.More.alpaca,
                            tint: AppTheme.ColorToken.icon
                        )
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        MoreRow(
                            title: L10n.More.settingsTitle(locale: locale),
                            subtitle: L10n.More.settingsSubtitle(
                                theme: app.appearanceMode.titleText(locale: locale),
                                locale: locale
                            ),
                            systemImage: AppIcon.More.settings,
                            tint: AppTheme.ColorToken.icon
                        )
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        MoreRow(
                            title: L10n.More.notificationsTitle(locale: locale),
                            subtitle: L10n.More.notificationsSubtitle(locale: locale),
                            systemImage: AppIcon.More.notifications,
                            tint: AppTheme.ColorToken.icon
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private struct MoreRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppTypography.detail)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    NavigationStack {
        MoreView()
            .environment(AppModel())
    }
}
