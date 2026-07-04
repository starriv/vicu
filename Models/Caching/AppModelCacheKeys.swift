import CryptoKit
import Foundation
import os.log

struct TimedCacheEntry<Value> {
    let value: Value
    let cachedAt: Date
}

struct SearchResultCacheKey: Hashable {
    let query: String
    let limit: Int
}

struct NewsPageCacheKey: Hashable {
    let symbol: String
    let startDay: String
    let limit: Int
    let pageToken: String?
}

struct OptionChainPageCacheKey: Hashable {
    let symbol: String
    let type: AlpacaOptionContractType?
    let expirationDate: String?
    let limit: Int
    let pageToken: String?
}

struct OptionExpirationCacheKey: Hashable {
    let symbol: String
    let startDate: String
    let endDate: String
}

struct OptionSnapshotCacheKey: Hashable {
    let symbol: String
}

struct OptionLatestTradeCacheKey: Hashable {
    let symbol: String
}

struct OptionBarsPageCacheKey: Hashable {
    let symbol: String
    let range: AssetChartRange
    let limit: Int
    let pageToken: String?
}

struct OptionTradesPageCacheKey: Hashable {
    let symbol: String
    let range: AssetChartRange
    let limit: Int
    let pageToken: String?
}

enum PageCacheNamespace: String, CaseIterable, Identifiable, Codable, Sendable {
    case homePortfolio = "home.portfolio"
    case marketOverview = "markets.overview"
    case marketFavorites = "markets.favorites"
    case assetDetail = "asset.detail"
    case assetPosition = "asset.position"

    var id: String { rawValue }
}

struct PageCacheKey: Hashable, Sendable {
    let scope: String
    let namespace: PageCacheNamespace
    let key: String
}

struct PageCachePolicy: Sendable {
    let freshTimeToLive: TimeInterval
    let maximumAge: TimeInterval
    let schemaVersion: Int

    init(
        freshTimeToLive: TimeInterval,
        maximumAge: TimeInterval,
        schemaVersion: Int = 1
    ) {
        self.freshTimeToLive = freshTimeToLive
        self.maximumAge = max(maximumAge, freshTimeToLive)
        self.schemaVersion = schemaVersion
    }

    static let homePortfolio = PageCachePolicy(freshTimeToLive: 30, maximumAge: 24 * 60 * 60, schemaVersion: 2)
    static let marketOverview = PageCachePolicy(freshTimeToLive: 60, maximumAge: 24 * 60 * 60)
    static let marketFavorites = PageCachePolicy(freshTimeToLive: 45, maximumAge: 24 * 60 * 60)
    static let assetDetail = PageCachePolicy(freshTimeToLive: 30, maximumAge: 6 * 60 * 60, schemaVersion: 2)
    static let assetPosition = PageCachePolicy(freshTimeToLive: 20, maximumAge: 24 * 60 * 60)

    static func expectedSchemaVersion(for namespace: PageCacheNamespace) -> Int {
        switch namespace {
        case .homePortfolio: return homePortfolio.schemaVersion
        case .marketOverview: return marketOverview.schemaVersion
        case .marketFavorites: return marketFavorites.schemaVersion
        case .assetDetail: return assetDetail.schemaVersion
        case .assetPosition: return assetPosition.schemaVersion
        }
    }
}

enum PageCacheFreshness: Sendable {
    case fresh
    case stale
}

struct PageCacheLookup<Value: Sendable>: Sendable {
    let value: Value
    let cachedAt: Date
    let freshness: PageCacheFreshness

    var isFresh: Bool {
        freshness == .fresh
    }
}

struct PageCacheNamespaceStatistics: Identifiable, Sendable {
    var id: PageCacheNamespace { namespace }
    let namespace: PageCacheNamespace
    let entryCount: Int
    let byteSize: Int
    let lastUpdatedAt: Date?
}

struct PageCacheStatistics: Sendable {
    let namespaces: [PageCacheNamespaceStatistics]

    var totalEntryCount: Int {
        namespaces.reduce(0) { $0 + $1.entryCount }
    }

    var totalByteSize: Int {
        namespaces.reduce(0) { $0 + $1.byteSize }
    }

    static let empty = PageCacheStatistics(namespaces: [])
}

private enum PageCacheLimits {
    static let maximumEntryCount = 600
    static let maximumTotalByteSize = 50 * 1024 * 1024
}

protocol PageCacheStoring: Sendable {
    func value<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: PageCacheKey,
        allowStale: Bool
    ) -> PageCacheLookup<Value>?
    func setValue<Value: Codable & Sendable>(
        _ value: Value,
        for key: PageCacheKey,
        policy: PageCachePolicy
    )
    func removeValue(for key: PageCacheKey)
    func clear(scope: String?)
    func clear(namespace: PageCacheNamespace, scope: String?)
    func clearExpired()
    func statistics(scope: String?) -> PageCacheStatistics
}

extension PageCacheStoring {
    func value<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: PageCacheKey
    ) -> PageCacheLookup<Value>? {
        value(type, for: key, allowStale: true)
    }

    func valueAsync<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: PageCacheKey,
        allowStale: Bool
    ) async -> PageCacheLookup<Value>? {
        await Task.detached(priority: .userInitiated) {
            self.value(type, for: key, allowStale: allowStale)
        }.value
    }

    func setValueAsync<Value: Codable & Sendable>(
        _ value: Value,
        for key: PageCacheKey,
        policy: PageCachePolicy
    ) async {
        await Task.detached(priority: .utility) {
            self.setValue(value, for: key, policy: policy)
        }.value
    }
}

// @unchecked Sendable: immutable let fields; all DB access delegated to SQLiteDatabase (NSLock + SQLITE_OPEN_FULLMUTEX)
final class SQLitePageCacheStore: PageCacheStoring, @unchecked Sendable {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: SQLiteDatabase) throws {
        self.database = database
        try Self.prepareSchema(in: database)
    }

    func value<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: PageCacheKey,
        allowStale: Bool
    ) -> PageCacheLookup<Value>? {
        do {
            guard let row = try database.query(
                """
                SELECT encoded_value, cached_at, stale_at, expires_at, schema_version
                FROM page_cache_entries
                WHERE scope = ? AND namespace = ? AND key = ?
                LIMIT 1
                """,
                bindings: [.text(key.scope), .text(key.namespace.rawValue), .text(key.key)]
            ).first else {
                return nil
            }

            guard let data = row.data("encoded_value"),
                  let cachedAtValue = row.double("cached_at"),
                  let staleAtValue = row.double("stale_at"),
                  let expiresAtValue = row.double("expires_at"),
                  let storedSchemaVersion = row.int("schema_version") else {
                removeValue(for: key)
                return nil
            }

            guard storedSchemaVersion == PageCachePolicy.expectedSchemaVersion(for: key.namespace) else {
                removeValue(for: key)
                return nil
            }

            let now = Date().timeIntervalSince1970
            if expiresAtValue < now {
                removeValue(for: key)
                return nil
            }
            guard allowStale || staleAtValue >= now else {
                return nil
            }

            let value = try decoder.decode(Value.self, from: data)
            updateLastAccessedAt(for: key, timestamp: now)
            return PageCacheLookup(
                value: value,
                cachedAt: Date(timeIntervalSince1970: cachedAtValue),
                freshness: staleAtValue >= now ? .fresh : .stale
            )
        } catch {
            if error is DecodingError {
                removeValue(for: key)
            }
            reportFailure(error)
            return nil
        }
    }

    func setValue<Value: Codable & Sendable>(
        _ value: Value,
        for key: PageCacheKey,
        policy: PageCachePolicy
    ) {
        do {
            let data = try encoder.encode(value)
            let now = Date().timeIntervalSince1970
            try database.execute(
                """
                INSERT INTO page_cache_entries (
                    scope, namespace, key, schema_version, encoded_value,
                    cached_at, stale_at, expires_at, last_accessed_at, byte_size
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(scope, namespace, key) DO UPDATE SET
                    schema_version = excluded.schema_version,
                    encoded_value = excluded.encoded_value,
                    cached_at = excluded.cached_at,
                    stale_at = excluded.stale_at,
                    expires_at = excluded.expires_at,
                    last_accessed_at = excluded.last_accessed_at,
                    byte_size = excluded.byte_size
                """,
                bindings: [
                    .text(key.scope),
                    .text(key.namespace.rawValue),
                    .text(key.key),
                    .integer(Int64(policy.schemaVersion)),
                    .blob(data),
                    .real(now),
                    .real(now + policy.freshTimeToLive),
                    .real(now + policy.maximumAge),
                    .real(now),
                    .integer(Int64(data.count))
                ]
            )
            trimIfNeeded()
        } catch {
            reportFailure(error)
        }
    }

    func removeValue(for key: PageCacheKey) {
        do {
            try database.execute(
                """
                DELETE FROM page_cache_entries
                WHERE scope = ? AND namespace = ? AND key = ?
                """,
                bindings: [.text(key.scope), .text(key.namespace.rawValue), .text(key.key)]
            )
        } catch {
            reportFailure(error)
        }
    }

    func clear(scope: String?) {
        do {
            if let scope {
                try database.execute("DELETE FROM page_cache_entries WHERE scope = ?", bindings: [.text(scope)])
            } else {
                try database.execute("DELETE FROM page_cache_entries")
            }
        } catch {
            reportFailure(error)
        }
    }

    func clear(namespace: PageCacheNamespace, scope: String?) {
        do {
            if let scope {
                try database.execute(
                    "DELETE FROM page_cache_entries WHERE namespace = ? AND scope = ?",
                    bindings: [.text(namespace.rawValue), .text(scope)]
                )
            } else {
                try database.execute(
                    "DELETE FROM page_cache_entries WHERE namespace = ?",
                    bindings: [.text(namespace.rawValue)]
                )
            }
        } catch {
            reportFailure(error)
        }
    }

    func clearExpired() {
        do {
            try database.execute(
                "DELETE FROM page_cache_entries WHERE expires_at < ?",
                bindings: [.real(Date().timeIntervalSince1970)]
            )
        } catch {
            reportFailure(error)
        }
    }

    func statistics(scope: String?) -> PageCacheStatistics {
        do {
            let rows: [SQLiteRow]
            if let scope {
                rows = try database.query(
                    """
                    SELECT namespace, COUNT(*) AS entry_count, COALESCE(SUM(byte_size), 0) AS byte_size, MAX(cached_at) AS last_updated_at
                    FROM page_cache_entries
                    WHERE scope = ?
                    GROUP BY namespace
                    """,
                    bindings: [.text(scope)]
                )
            } else {
                rows = try database.query(
                    """
                    SELECT namespace, COUNT(*) AS entry_count, COALESCE(SUM(byte_size), 0) AS byte_size, MAX(cached_at) AS last_updated_at
                    FROM page_cache_entries
                    GROUP BY namespace
                    """
                )
            }

            let namespaceStats = rows.compactMap { row -> PageCacheNamespaceStatistics? in
                guard let namespaceText = row.string("namespace"),
                      let namespace = PageCacheNamespace(rawValue: namespaceText) else {
                    return nil
                }

                return PageCacheNamespaceStatistics(
                    namespace: namespace,
                    entryCount: row.int("entry_count") ?? 0,
                    byteSize: row.int("byte_size") ?? 0,
                    lastUpdatedAt: row.double("last_updated_at").map(Date.init(timeIntervalSince1970:))
                )
            }

            return PageCacheStatistics(
                namespaces: namespaceStats.sorted { $0.namespace.rawValue < $1.namespace.rawValue }
            )
        } catch {
            reportFailure(error)
            return .empty
        }
    }

    private static func prepareSchema(in database: SQLiteDatabase) throws {
        try database.executeRaw(
            """
            CREATE TABLE IF NOT EXISTS page_cache_entries (
                scope TEXT NOT NULL,
                namespace TEXT NOT NULL,
                key TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                encoded_value BLOB NOT NULL,
                cached_at REAL NOT NULL,
                stale_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL,
                byte_size INTEGER NOT NULL,
                PRIMARY KEY(scope, namespace, key)
            );
            CREATE INDEX IF NOT EXISTS page_cache_entries_scope_namespace_idx
                ON page_cache_entries(scope, namespace);
            CREATE INDEX IF NOT EXISTS page_cache_entries_expires_at_idx
                ON page_cache_entries(expires_at);
            """
        )
        try migrateSchemaIfNeeded(in: database)
    }

    private func trimIfNeeded() {
        do {
            let rows = try database.query(
                """
                SELECT scope, namespace, key, byte_size
                FROM page_cache_entries
                ORDER BY last_accessed_at ASC
                """
            )
            var totalEntryCount = rows.count
            var totalByteSize = rows.reduce(0) { total, row in
                total + (row.int("byte_size") ?? 0)
            }

            guard totalEntryCount > PageCacheLimits.maximumEntryCount ||
                  totalByteSize > PageCacheLimits.maximumTotalByteSize else {
                return
            }

            for row in rows {
                guard totalEntryCount > PageCacheLimits.maximumEntryCount ||
                      totalByteSize > PageCacheLimits.maximumTotalByteSize else {
                    break
                }

                guard let scope = row.string("scope"),
                      let namespace = row.string("namespace"),
                      let key = row.string("key") else {
                    continue
                }

                let byteSize = row.int("byte_size") ?? 0
                try database.execute(
                    """
                    DELETE FROM page_cache_entries
                    WHERE scope = ? AND namespace = ? AND key = ?
                    """,
                    bindings: [.text(scope), .text(namespace), .text(key)]
                )
                totalEntryCount -= 1
                totalByteSize -= byteSize
            }
        } catch {
            reportFailure(error)
        }
    }

    private static func migrateSchemaIfNeeded(in database: SQLiteDatabase) throws {
        let rows = try database.query("PRAGMA table_info(page_cache_entries)")
        let columnNames = Set(rows.compactMap { $0.string("name") })

        if !columnNames.contains("last_accessed_at") {
            try database.executeRaw("ALTER TABLE page_cache_entries ADD COLUMN last_accessed_at REAL;")
            try database.executeRaw("UPDATE page_cache_entries SET last_accessed_at = cached_at WHERE last_accessed_at IS NULL;")
        }
    }

    private func updateLastAccessedAt(for key: PageCacheKey, timestamp: TimeInterval) {
        do {
            try database.execute(
                """
                UPDATE page_cache_entries
                SET last_accessed_at = ?
                WHERE scope = ? AND namespace = ? AND key = ?
                """,
                bindings: [.real(timestamp), .text(key.scope), .text(key.namespace.rawValue), .text(key.key)]
            )
        } catch {
            reportFailure(error)
        }
    }

    private func reportFailure(_ error: Error) {
        #if DEBUG
        print("Page cache store error: \(error.localizedDescription)")
        #endif
    }
}

// @unchecked Sendable: mutable entries dict guarded by NSLock
final class MemoryPageCacheStore: PageCacheStoring, @unchecked Sendable {
    private struct StoredEntry {
        let data: Data
        let schemaVersion: Int
        let cachedAt: Date
        let staleAt: Date
        let expiresAt: Date
        var lastAccessedAt: Date
        let byteSize: Int
    }

    private let lock = NSLock()
    private var entries: [PageCacheKey: StoredEntry] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func value<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: PageCacheKey,
        allowStale: Bool
    ) -> PageCacheLookup<Value>? {
        lock.lock()
        let entry = entries[key]
        lock.unlock()

        guard let entry else {
            return nil
        }

        let now = Date()
        guard entry.expiresAt >= now else {
            removeValue(for: key)
            return nil
        }

        guard allowStale || entry.staleAt >= now else {
            return nil
        }

        guard entry.schemaVersion == PageCachePolicy.expectedSchemaVersion(for: key.namespace) else {
            removeValue(for: key)
            return nil
        }

        do {
            let decoded = try decoder.decode(Value.self, from: entry.data)
            updateLastAccessedAt(for: key, at: now)
            return PageCacheLookup(
                value: decoded,
                cachedAt: entry.cachedAt,
                freshness: entry.staleAt >= now ? .fresh : .stale
            )
        } catch {
            removeValue(for: key)
            return nil
        }
    }

    func setValue<Value: Codable & Sendable>(
        _ value: Value,
        for key: PageCacheKey,
        policy: PageCachePolicy
    ) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        let now = Date()
        let entry = StoredEntry(
            data: data,
            schemaVersion: policy.schemaVersion,
            cachedAt: now,
            staleAt: now.addingTimeInterval(policy.freshTimeToLive),
            expiresAt: now.addingTimeInterval(policy.maximumAge),
            lastAccessedAt: now,
            byteSize: data.count
        )
        lock.lock()
        entries[key] = entry
        trimIfNeededLocked()
        lock.unlock()
    }

    func removeValue(for key: PageCacheKey) {
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }

    func clear(scope: String?) {
        lock.lock()
        if let scope {
            entries = entries.filter { $0.key.scope != scope }
        } else {
            entries.removeAll()
        }
        lock.unlock()
    }

    func clear(namespace: PageCacheNamespace, scope: String?) {
        lock.lock()
        entries = entries.filter { item in
            if let scope {
                return item.key.namespace != namespace || item.key.scope != scope
            }

            return item.key.namespace != namespace
        }
        lock.unlock()
    }

    func clearExpired() {
        let now = Date()
        lock.lock()
        entries = entries.filter { $0.value.expiresAt >= now }
        lock.unlock()
    }

    func statistics(scope: String?) -> PageCacheStatistics {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        let filtered = snapshot.filter { item in
            scope.map { item.key.scope == $0 } ?? true
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.key.namespace })
        let namespaceStats = grouped.map { namespace, items in
            PageCacheNamespaceStatistics(
                namespace: namespace,
                entryCount: items.count,
                byteSize: items.reduce(0) { $0 + $1.value.byteSize },
                lastUpdatedAt: items.map(\.value.cachedAt).max()
            )
        }

        return PageCacheStatistics(
            namespaces: namespaceStats.sorted { $0.namespace.rawValue < $1.namespace.rawValue }
        )
    }

    private func trimIfNeededLocked() {
        var totalEntryCount = entries.count
        var totalByteSize = entries.values.reduce(0) { $0 + $1.byteSize }
        guard totalEntryCount > PageCacheLimits.maximumEntryCount ||
              totalByteSize > PageCacheLimits.maximumTotalByteSize else {
            return
        }

        let keysByAge = entries.sorted { lhs, rhs in
            lhs.value.lastAccessedAt < rhs.value.lastAccessedAt
        }.map(\.key)

        for key in keysByAge {
            guard totalEntryCount > PageCacheLimits.maximumEntryCount ||
                  totalByteSize > PageCacheLimits.maximumTotalByteSize else {
                break
            }

            guard let removed = entries.removeValue(forKey: key) else {
                continue
            }
            totalEntryCount -= 1
            totalByteSize -= removed.byteSize
        }
    }

    private func updateLastAccessedAt(for key: PageCacheKey, at date: Date) {
        lock.lock()
        if var entry = entries[key] {
            entry.lastAccessedAt = date
            entries[key] = entry
        }
        lock.unlock()
    }
}

private let pageCacheLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "PageCache")

enum PageCacheStoreFactory {
    static func live() -> any PageCacheStoring {
        do {
            return try SQLitePageCacheStore(database: SQLiteDatabase())
        } catch {
            pageCacheLogger.error("Page cache SQLite open failed, using in-memory fallback: \(error)")
            return MemoryPageCacheStore()
        }
    }
}

enum AppPageCacheKeys {
    static func scope(credentials: AlpacaCredentials) -> String {
        let rawValue = "\(credentials.environment.rawValue):\(credentials.keyID)"
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return "\(credentials.environment.rawValue).\(fingerprint)"
    }

    static func homePortfolio(credentials: AlpacaCredentials) -> PageCacheKey {
        PageCacheKey(scope: scope(credentials: credentials), namespace: .homePortfolio, key: "summary")
    }

    static func marketOverview(credentials: AlpacaCredentials) -> PageCacheKey {
        PageCacheKey(scope: scope(credentials: credentials), namespace: .marketOverview, key: "overview")
    }

    static func marketFavorites(credentials: AlpacaCredentials) -> PageCacheKey {
        PageCacheKey(scope: scope(credentials: credentials), namespace: .marketFavorites, key: "favorites")
    }

    static func assetDetail(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) -> PageCacheKey {
        PageCacheKey(
            scope: scope(credentials: credentials),
            namespace: .assetDetail,
            key: [
                normalizedSymbol(symbol),
                range.rawValue,
                feed.rawValue
            ].joined(separator: ".")
        )
    }

    static func assetPosition(symbol: String, credentials: AlpacaCredentials) -> PageCacheKey {
        PageCacheKey(
            scope: scope(credentials: credentials),
            namespace: .assetPosition,
            key: normalizedSymbol(symbol)
        )
    }

    private static func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct HomePortfolioCacheSegment<Value: Codable & Sendable>: Codable, Sendable {
    let value: Value
    let cachedAt: Date

    func isUsable(now: Date = Date(), maximumAge: TimeInterval) -> Bool {
        cachedAt.addingTimeInterval(maximumAge) >= now
    }
}

struct HomePortfolioHistoryCacheSegment: Codable, Sendable {
    let range: PortfolioHistoryRange
    let value: [PortfolioHistoryPoint]
    let cachedAt: Date

    func isUsable(
        for requestedRange: PortfolioHistoryRange,
        now: Date = Date(),
        maximumAge: TimeInterval
    ) -> Bool {
        range == requestedRange && cachedAt.addingTimeInterval(maximumAge) >= now
    }

    func isUsable(now: Date = Date(), maximumAge: TimeInterval) -> Bool {
        cachedAt.addingTimeInterval(maximumAge) >= now
    }
}

struct HomePortfolioCacheSnapshot: Codable, Sendable {
    var account: HomePortfolioCacheSegment<AlpacaAccount>? = nil
    var positions: HomePortfolioCacheSegment<[AlpacaPosition]>? = nil
    var orders: HomePortfolioCacheSegment<[AlpacaOrder]>? = nil
    var history: HomePortfolioHistoryCacheSegment? = nil

    var isEmpty: Bool {
        account == nil && positions == nil && orders == nil && history == nil
    }

    func pruned(now: Date = Date(), policy: PageCachePolicy = .homePortfolio) -> Self {
        Self(
            account: account?.isUsable(now: now, maximumAge: policy.maximumAge) == true ? account : nil,
            positions: positions?.isUsable(now: now, maximumAge: policy.maximumAge) == true ? positions : nil,
            orders: orders?.isUsable(now: now, maximumAge: policy.maximumAge) == true ? orders : nil,
            history: history?.isUsable(now: now, maximumAge: policy.maximumAge) == true ? history : nil
        )
    }
}

struct MarketFavoritesCacheSnapshot: Codable, Sendable {
    let symbols: [String]
    let assetsBySymbol: [String: AlpacaAsset]
    let quotesBySymbol: [String: MarketActiveSymbol]
}

struct AssetPositionCacheSnapshot: Codable, Sendable {
    let position: AlpacaPosition?
}

enum AssetDetailCacheFeedPolicy {
    static func lookupFeeds(requestedFeed: AlpacaMarketDataFeed) -> [AlpacaMarketDataFeed] {
        switch requestedFeed {
        case .iex:
            [.iex, .overnight]
        case .overnight:
            [.overnight, .iex]
        case .boats:
            [.boats, .iex]
        case .sip, .delayedSIP:
            [requestedFeed]
        }
    }

    static func shouldStoreResolvedKey(
        requestedFeed: AlpacaMarketDataFeed,
        resolvedFeed: AlpacaMarketDataFeed
    ) -> Bool {
        guard requestedFeed != resolvedFeed else {
            return false
        }

        return lookupFeeds(requestedFeed: requestedFeed).contains(resolvedFeed)
    }
}
