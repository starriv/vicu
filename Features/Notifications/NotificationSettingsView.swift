import ActivityKit
import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var notificationAuthStatus: UNAuthorizationStatus = .authorized
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

                #if DEBUG
                NavigationLink {
                    NotificationPreviewView()
                } label: {
                    Text(app.appLanguage.locale.identifier.hasPrefix("zh") ? "通知样式预览" : "Notification Preview")
                }
                #endif
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.NotificationSettings.footer)

                    if notificationAuthStatus == .denied {
                        Label {
                            Text(
                                app.appLanguage.locale.identifier.hasPrefix("zh")
                                    ? "系统通知权限已关闭，请前往「设置」开启。"
                                    : "Notifications are turned off in iOS Settings."
                            )
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(AppTheme.ColorToken.warning)
                    }
                }
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
            notificationAuthStatus = await app.services.appNotifier.authorizationStatus()
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
