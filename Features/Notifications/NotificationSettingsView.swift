import ActivityKit
import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var liveActivitiesAvailable = true

    var body: some View {
        @Bindable var app = app

        BasicLayout(L10n.NotificationSettings.title, titleDisplayMode: .inline, style: .form) {
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

            Section {
                Toggle(isOn: $app.liveActivitySettings.isEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.LiveActivity.settingsEnabled,
                        systemImage: "lock.rectangle.stack.fill"
                    )
                }

                Toggle(isOn: $app.liveActivitySettings.orderCardEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.LiveActivity.settingsOrderCard,
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .disabled(!app.liveActivitySettings.isEnabled)
                .opacity(app.liveActivitySettings.isEnabled ? 1 : 0.55)

                Toggle(isOn: $app.liveActivitySettings.sessionCardEnabled) {
                    NotificationSettingsLabel(
                        title: L10n.LiveActivity.settingsSessionCard,
                        systemImage: "clock.badge.checkmark"
                    )
                }
                .disabled(!app.liveActivitySettings.isEnabled)
                .opacity(app.liveActivitySettings.isEnabled ? 1 : 0.55)

                #if DEBUG
                NavigationLink {
                    LiveActivityPreviewView()
                } label: {
                    Text(L10n.LiveActivity.settingsPreview)
                }
                #endif
            } header: {
                Text(L10n.LiveActivity.settingsTitle)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.LiveActivity.settingsFooter)

                    if !liveActivitiesAvailable {
                        Label {
                            Text(L10n.LiveActivity.settingsSystemDisabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(AppTheme.ColorToken.warning)
                    }
                }
            }
        }
        .tint(AppTheme.ColorToken.brand)
        .task {
            liveActivitiesAvailable = ActivityAuthorizationInfo().areActivitiesEnabled
        }
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
