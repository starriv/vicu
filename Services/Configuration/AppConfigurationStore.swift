import Foundation

struct AppConfigurationKey<Value: Codable & Sendable>: Sendable {
    let namespace: String
    let name: String
    let defaultValue: Value
    let allowsCloudOverride: Bool

    init(
        namespace: String,
        name: String,
        defaultValue: Value,
        allowsCloudOverride: Bool = false
    ) {
        self.namespace = namespace
        self.name = name
        self.defaultValue = defaultValue
        self.allowsCloudOverride = allowsCloudOverride
    }
}

protocol AppConfigurationStoring: Sendable {
    func value<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value
    func optionalValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value?
    func setValue<Value: Codable & Sendable>(_ value: Value, for key: AppConfigurationKey<Value>)
    func removeValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>)
    // Returns true only when a value has been explicitly written to the local store.
    // Cloud overrides are intentionally excluded — this is used to gate migration
    // (has the user ever set a value?) not to reflect the effective resolved value.
    func hasValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Bool
}

protocol CloudConfigurationStoring: Sendable {
    func cloudValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value?
    func setCloudValue<Value: Codable & Sendable>(_ value: Value?, for key: AppConfigurationKey<Value>)
    func clearCloudValues()
}

enum AppConfigurationKeys {
    enum App {
        static let tradeEnvironment = AppConfigurationKey<TradeEnvironment>(
            namespace: "app",
            name: TradeEnvironment.storageKey,
            defaultValue: .paper
        )

        static let appearanceMode = AppConfigurationKey<AppearanceMode>(
            namespace: "app",
            name: AppearanceMode.storageKey,
            defaultValue: .system
        )

        static let appLanguage = AppConfigurationKey<AppLanguage>(
            namespace: "app",
            name: AppLanguage.storageKey,
            defaultValue: .system
        )
    }

    enum Integrations {
        static let logoDevAPIKey = AppConfigurationKey<String>(
            namespace: "integrations.logo_dev",
            name: "api_key",
            defaultValue: ""
        )

        static let isLogoDevEnabled = AppConfigurationKey<Bool>(
            namespace: "integrations.logo_dev",
            name: "enabled",
            defaultValue: false
        )
    }

    enum Notifications {
        static let preferences = AppConfigurationKey<AppNotificationPreferences>(
            namespace: "notifications",
            name: AppNotificationPreferences.storageKey,
            defaultValue: .default
        )
    }

    enum Realtime {
        static func activityLastEventID(credentials: AlpacaCredentials) -> AppConfigurationKey<String> {
            AppConfigurationKey(
                namespace: "runtime",
                name: legacyRealtimeKey(prefix: "alpaca.activity", name: "last_event_id", credentials: credentials),
                defaultValue: ""
            )
        }

        static func recentActivityRefIDs(credentials: AlpacaCredentials) -> AppConfigurationKey<[String]> {
            AppConfigurationKey(
                namespace: "runtime",
                name: legacyRealtimeKey(prefix: "alpaca.activity", name: "recent_ref_ids", credentials: credentials),
                defaultValue: []
            )
        }

        static func tradeLastEventID(credentials: AlpacaCredentials) -> AppConfigurationKey<String> {
            AppConfigurationKey(
                namespace: "runtime",
                name: legacyRealtimeKey(prefix: "alpaca.trade_event", name: "last_event_id", credentials: credentials),
                defaultValue: ""
            )
        }

        static func recentTradeEventIDs(credentials: AlpacaCredentials) -> AppConfigurationKey<[String]> {
            AppConfigurationKey(
                namespace: "runtime",
                name: legacyRealtimeKey(prefix: "alpaca.trade_event", name: "recent_event_ids", credentials: credentials),
                defaultValue: []
            )
        }

        static func legacyKey<Value: Codable & Sendable>(
            _ name: String,
            defaultValue: Value
        ) -> AppConfigurationKey<Value> {
            AppConfigurationKey(namespace: "runtime", name: name, defaultValue: defaultValue)
        }

        private static func legacyRealtimeKey(
            prefix: String,
            name: String,
            credentials: AlpacaCredentials
        ) -> String {
            [
                prefix,
                name,
                credentials.environment.rawValue,
                credentials.keyID
            ].joined(separator: ".")
        }
    }

    enum Migration {
        static let userDefaultsV1 = AppConfigurationKey<Bool>(
            namespace: "migration",
            name: "user_defaults_configuration_v1",
            defaultValue: false
        )
    }
}

final class CloudControlledConfigurationStore: AppConfigurationStoring {
    private let localStore: any AppConfigurationStoring
    private let cloudStore: any CloudConfigurationStoring

    init(
        localStore: any AppConfigurationStoring,
        cloudStore: any CloudConfigurationStoring
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
    }

    func value<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value {
        if key.allowsCloudOverride, let cloudValue = cloudStore.cloudValue(for: key) {
            return cloudValue
        }

        return localStore.value(for: key)
    }

    func optionalValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value? {
        if key.allowsCloudOverride, let cloudValue = cloudStore.cloudValue(for: key) {
            return cloudValue
        }

        return localStore.optionalValue(for: key)
    }

    func setValue<Value: Codable & Sendable>(_ value: Value, for key: AppConfigurationKey<Value>) {
        localStore.setValue(value, for: key)
    }

    func removeValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) {
        localStore.removeValue(for: key)
    }

    // Delegates to the local store only. See AppConfigurationStoring.hasValue.
    func hasValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Bool {
        localStore.hasValue(for: key)
    }

    func setCloudOverride<Value: Codable & Sendable>(_ value: Value?, for key: AppConfigurationKey<Value>) {
        cloudStore.setCloudValue(value, for: key)
    }

    func clearCloudOverrides() {
        cloudStore.clearCloudValues()
    }
}

final class SQLiteAppConfigurationStore: AppConfigurationStoring {
    private let database: SQLiteDatabase
    private let scope: AppConfigurationScope
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: SQLiteDatabase, scope: AppConfigurationScope = .local) throws {
        self.database = database
        self.scope = scope
        try Self.prepareSchema(in: database)
    }

    func value<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value {
        optionalValue(for: key) ?? key.defaultValue
    }

    func optionalValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value? {
        do {
            guard let data = try data(for: key) else {
                return nil
            }

            return try decoder.decode(Value.self, from: data)
        } catch {
            reportFailure(error)
            return nil
        }
    }

    func setValue<Value: Codable & Sendable>(_ value: Value, for key: AppConfigurationKey<Value>) {
        do {
            let data = try encoder.encode(value)
            try database.execute(
                """
                INSERT INTO configuration_values (scope, namespace, key, encoded_value, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(scope, namespace, key) DO UPDATE SET
                    encoded_value = excluded.encoded_value,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(scope.rawValue),
                    .text(key.namespace),
                    .text(key.name),
                    .blob(data),
                    .real(Date().timeIntervalSince1970)
                ]
            )
        } catch {
            reportFailure(error)
        }
    }

    func removeValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) {
        do {
            try database.execute(
                """
                DELETE FROM configuration_values
                WHERE scope = ? AND namespace = ? AND key = ?
                """,
                bindings: [.text(scope.rawValue), .text(key.namespace), .text(key.name)]
            )
        } catch {
            reportFailure(error)
        }
    }

    func hasValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Bool {
        do {
            let rows = try database.query(
                """
                SELECT 1
                FROM configuration_values
                WHERE scope = ? AND namespace = ? AND key = ?
                LIMIT 1
                """,
                bindings: [.text(scope.rawValue), .text(key.namespace), .text(key.name)]
            )
            return !rows.isEmpty
        } catch {
            reportFailure(error)
            return false
        }
    }

    func clearValues() {
        do {
            try database.execute(
                "DELETE FROM configuration_values WHERE scope = ?",
                bindings: [.text(scope.rawValue)]
            )
        } catch {
            reportFailure(error)
        }
    }

    private func data<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) throws -> Data? {
        try database.query(
            """
            SELECT encoded_value
            FROM configuration_values
            WHERE scope = ? AND namespace = ? AND key = ?
            LIMIT 1
            """,
            bindings: [.text(scope.rawValue), .text(key.namespace), .text(key.name)]
        ).first?.data("encoded_value")
    }

    private static func prepareSchema(in database: SQLiteDatabase) throws {
        try database.executeRaw(
            """
            CREATE TABLE IF NOT EXISTS configuration_values (
                scope TEXT NOT NULL,
                namespace TEXT NOT NULL,
                key TEXT NOT NULL,
                encoded_value BLOB NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(scope, namespace, key)
            );
            CREATE INDEX IF NOT EXISTS configuration_values_namespace_idx
                ON configuration_values(scope, namespace);
            """
        )
    }

    private func reportFailure(_ error: Error) {
        #if DEBUG
        print("Configuration store error: \(error.localizedDescription)")
        #endif
    }
}

final class SQLiteCloudConfigurationStore: CloudConfigurationStoring {
    private let store: SQLiteAppConfigurationStore

    init(database: SQLiteDatabase) throws {
        self.store = try SQLiteAppConfigurationStore(database: database, scope: .cloud)
    }

    func cloudValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value? {
        guard key.allowsCloudOverride else {
            return nil
        }

        return store.optionalValue(for: key)
    }

    func setCloudValue<Value: Codable & Sendable>(_ value: Value?, for key: AppConfigurationKey<Value>) {
        guard key.allowsCloudOverride else {
            return
        }

        if let value {
            store.setValue(value, for: key)
        } else {
            store.removeValue(for: key)
        }
    }

    func clearCloudValues() {
        store.clearValues()
    }
}

final class MemoryAppConfigurationStore: AppConfigurationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AppConfigurationStorageID: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func value<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value {
        optionalValue(for: key) ?? key.defaultValue
    }

    func optionalValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value? {
        let storageID = AppConfigurationStorageID(key)
        lock.lock()
        let data = values[storageID]
        lock.unlock()

        guard let data else {
            return nil
        }

        return try? decoder.decode(Value.self, from: data)
    }

    func setValue<Value: Codable & Sendable>(_ value: Value, for key: AppConfigurationKey<Value>) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        let storageID = AppConfigurationStorageID(key)
        lock.lock()
        values[storageID] = data
        lock.unlock()
    }

    func removeValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) {
        let storageID = AppConfigurationStorageID(key)
        lock.lock()
        values.removeValue(forKey: storageID)
        lock.unlock()
    }

    func hasValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Bool {
        let storageID = AppConfigurationStorageID(key)
        lock.lock()
        let exists = values[storageID] != nil
        lock.unlock()
        return exists
    }

    func clearValues() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }
}

final class MemoryCloudConfigurationStore: CloudConfigurationStoring {
    private let store = MemoryAppConfigurationStore()

    func cloudValue<Value: Codable & Sendable>(for key: AppConfigurationKey<Value>) -> Value? {
        guard key.allowsCloudOverride else {
            return nil
        }

        return store.optionalValue(for: key)
    }

    func setCloudValue<Value: Codable & Sendable>(_ value: Value?, for key: AppConfigurationKey<Value>) {
        guard key.allowsCloudOverride else {
            return
        }

        if let value {
            store.setValue(value, for: key)
        } else {
            store.removeValue(for: key)
        }
    }

    func clearCloudValues() {
        store.clearValues()
    }
}

enum AppConfigurationStoreFactory {
    static func live() -> any AppConfigurationStoring {
        let store: any AppConfigurationStoring

        do {
            let database = try SQLiteDatabase()
            let localStore = try SQLiteAppConfigurationStore(database: database)
            let cloudStore = try SQLiteCloudConfigurationStore(database: database)
            store = CloudControlledConfigurationStore(localStore: localStore, cloudStore: cloudStore)
        } catch {
            #if DEBUG
            print("Falling back to in-memory configuration store: \(error.localizedDescription)")
            #endif
            store = CloudControlledConfigurationStore(
                localStore: MemoryAppConfigurationStore(),
                cloudStore: MemoryCloudConfigurationStore()
            )
        }

        UserDefaultsConfigurationMigrator.migrateIfNeeded(to: store)
        return store
    }
}

enum AppConfigurationScope: String, Sendable {
    case local
    case cloud
}

private struct AppConfigurationStorageID: Hashable {
    let namespace: String
    let name: String

    init<Value>(_ key: AppConfigurationKey<Value>) {
        self.namespace = key.namespace
        self.name = key.name
    }
}
