import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        BasicLayout(L10n.NotificationSettings.title, style: .form) {
            Section {
                Toggle(isOn: $app.notificationPreferences.isEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.NotificationSettings.allowNotifications,
                        systemImage: AppIcon.Settings.notifications
                    )
                }

                Toggle(isOn: $app.notificationPreferences.tradeOrderSubmittedNotificationsEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.NotificationSettings.tradeOrderSubmitted,
                        systemImage: AppIcon.Settings.tradeNotifications
                    )
                }
                .disabled(!app.notificationPreferences.isEnabled)
                .opacity(app.notificationPreferences.isEnabled ? 1 : 0.55)

                Toggle(isOn: $app.notificationPreferences.tradeOrderStatusNotificationsEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.NotificationSettings.tradeOrderStatus,
                        systemImage: AppIcon.Settings.orderStatusNotifications
                    )
                }
                .disabled(!app.notificationPreferences.isEnabled)
                .opacity(app.notificationPreferences.isEnabled ? 1 : 0.55)

                Toggle(isOn: $app.notificationPreferences.accountActivityNotificationsEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.NotificationSettings.accountActivity,
                        systemImage: AppIcon.Settings.accountActivityNotifications
                    )
                }
                .disabled(!app.notificationPreferences.isEnabled)
                .opacity(app.notificationPreferences.isEnabled ? 1 : 0.55)
            } footer: {
                Text(L10n.NotificationSettings.footer)
            }
        }
        .tint(AppTheme.ColorToken.brand)
    }
}

private struct NotificationSettingsLabel: View {
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
        NotificationSettingsView()
            .environment(AppModel())
    }
}
