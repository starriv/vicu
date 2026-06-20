import Foundation

enum UserDefaultsConfigurationMigrator {
    static func migrateIfNeeded(
        to store: any AppConfigurationStoring,
        userDefaults: UserDefaults = .standard
    ) {
        guard !store.value(for: AppConfigurationKeys.Migration.userDefaultsV1) else {
            return
        }

        migrateAppSettings(to: store, userDefaults: userDefaults)
        migrateIntegrationSettings(to: store, userDefaults: userDefaults)
        migrateNotificationPreferences(to: store, userDefaults: userDefaults)
        migrateRealtimeState(to: store, userDefaults: userDefaults)
        store.setValue(true, for: AppConfigurationKeys.Migration.userDefaultsV1)
    }

    private static func migrateAppSettings(
        to store: any AppConfigurationStoring,
        userDefaults: UserDefaults
    ) {
        if !store.hasValue(for: AppConfigurationKeys.App.tradeEnvironment),
           let rawValue = userDefaults.string(forKey: TradeEnvironment.storageKey),
           let value = TradeEnvironment(rawValue: rawValue) {
            store.setValue(value, for: AppConfigurationKeys.App.tradeEnvironment)
        }

        if !store.hasValue(for: AppConfigurationKeys.App.appearanceMode),
           let rawValue = userDefaults.string(forKey: AppearanceMode.storageKey),
           let value = AppearanceMode(rawValue: rawValue) {
            store.setValue(value, for: AppConfigurationKeys.App.appearanceMode)
        }

        if !store.hasValue(for: AppConfigurationKeys.App.appLanguage),
           let rawValue = userDefaults.string(forKey: AppLanguage.storageKey),
           let value = AppLanguage(rawValue: rawValue) {
            store.setValue(value, for: AppConfigurationKeys.App.appLanguage)
        }
    }

    private static func migrateIntegrationSettings(
        to store: any AppConfigurationStoring,
        userDefaults: UserDefaults
    ) {
        let legacyAPIKeyKey = "logoDevAPIKey"
        if !store.hasValue(for: AppConfigurationKeys.Integrations.logoDevAPIKey),
           let value = userDefaults.string(forKey: legacyAPIKeyKey) {
            store.setValue(value, for: AppConfigurationKeys.Integrations.logoDevAPIKey)
        }

        let legacyEnabledKey = "logoDevEnabled"
        if !store.hasValue(for: AppConfigurationKeys.Integrations.isLogoDevEnabled),
           userDefaults.object(forKey: legacyEnabledKey) != nil {
            store.setValue(
                userDefaults.bool(forKey: legacyEnabledKey),
                for: AppConfigurationKeys.Integrations.isLogoDevEnabled
            )
        }
    }

    private static func migrateNotificationPreferences(
        to store: any AppConfigurationStoring,
        userDefaults: UserDefaults
    ) {
        guard !store.hasValue(for: AppConfigurationKeys.Notifications.preferences),
              let data = userDefaults.data(forKey: AppNotificationPreferences.storageKey),
              let preferences = try? JSONDecoder().decode(AppNotificationPreferences.self, from: data) else {
            return
        }

        store.setValue(preferences, for: AppConfigurationKeys.Notifications.preferences)
    }

    private static func migrateRealtimeState(
        to store: any AppConfigurationStoring,
        userDefaults: UserDefaults
    ) {
        for (key, value) in userDefaults.dictionaryRepresentation() {
            guard key.hasPrefix("alpaca.activity.") || key.hasPrefix("alpaca.trade_event.") else {
                continue
            }

            if let stringValue = value as? String {
                let configKey = AppConfigurationKeys.Realtime.legacyKey(key, defaultValue: "")
                if !store.hasValue(for: configKey) {
                    store.setValue(stringValue, for: configKey)
                }
            } else if let stringValues = value as? [String] {
                let configKey = AppConfigurationKeys.Realtime.legacyKey(key, defaultValue: [String]())
                if !store.hasValue(for: configKey) {
                    store.setValue(stringValues, for: configKey)
                }
            }
        }
    }
}
