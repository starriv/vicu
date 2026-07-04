import XCTest
@testable import vicu

final class PageCacheTests: XCTestCase {
    private struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    func testMemoryPageCacheRejectsSchemaMismatch() {
        let store = MemoryPageCacheStore()
        let key = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "payload")
        let mismatchedPolicy = PageCachePolicy(
            freshTimeToLive: 60,
            maximumAge: 60,
            schemaVersion: PageCachePolicy.expectedSchemaVersion(for: .marketFavorites) + 1
        )

        store.setValue(Payload(value: "old"), for: key, policy: mismatchedPolicy)

        XCTAssertNil(store.value(Payload.self, for: key, allowStale: true))
        XCTAssertEqual(store.statistics(scope: nil).totalEntryCount, 0)
    }

    func testMemoryPageCacheTrimsLeastRecentlyUsedEntries() {
        let store = MemoryPageCacheStore()

        for index in 0..<600 {
            let key = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-\(index)")
            store.setValue(Payload(value: "\(index)"), for: key, policy: .marketFavorites)
        }

        let recentlyUsedOldKey = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-0")
        XCTAssertEqual(
            store.value(Payload.self, for: recentlyUsedOldKey, allowStale: true)?.value,
            Payload(value: "0")
        )

        Thread.sleep(forTimeInterval: 0.01)

        for index in 600..<610 {
            let key = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-\(index)")
            store.setValue(Payload(value: "\(index)"), for: key, policy: .marketFavorites)
        }

        let oldestKey = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-0")
        let leastRecentlyUsedKey = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-1")
        let newestKey = PageCacheKey(scope: "test", namespace: .marketFavorites, key: "item-609")

        XCTAssertLessThanOrEqual(store.statistics(scope: nil).totalEntryCount, 600)
        XCTAssertEqual(store.value(Payload.self, for: oldestKey, allowStale: true)?.value, Payload(value: "0"))
        XCTAssertNil(store.value(Payload.self, for: leastRecentlyUsedKey, allowStale: true))
        XCTAssertEqual(store.value(Payload.self, for: newestKey, allowStale: true)?.value, Payload(value: "609"))
    }

    func testHomePortfolioSnapshotPrunesExpiredSegmentsIndependently() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expired = now.addingTimeInterval(-PageCachePolicy.homePortfolio.maximumAge - 1)
        let recent = now.addingTimeInterval(-60)
        let snapshot = HomePortfolioCacheSnapshot(
            account: nil,
            positions: HomePortfolioCacheSegment(value: [], cachedAt: expired),
            orders: HomePortfolioCacheSegment(value: [], cachedAt: recent),
            history: HomePortfolioHistoryCacheSegment(range: .oneDay, value: [], cachedAt: expired)
        )

        let pruned = snapshot.pruned(now: now)

        XCTAssertNil(pruned.positions)
        XCTAssertNotNil(pruned.orders)
        XCTAssertNil(pruned.history)
    }

    func testAssetDetailFeedPolicyAllowsOnlyExplicitCompatibleFallbacks() {
        XCTAssertEqual(AssetDetailCacheFeedPolicy.lookupFeeds(requestedFeed: .iex), [.iex, .overnight])
        XCTAssertEqual(AssetDetailCacheFeedPolicy.lookupFeeds(requestedFeed: .overnight), [.overnight, .iex])
        XCTAssertEqual(AssetDetailCacheFeedPolicy.lookupFeeds(requestedFeed: .boats), [.boats, .iex])
        XCTAssertEqual(AssetDetailCacheFeedPolicy.lookupFeeds(requestedFeed: .sip), [.sip])
        XCTAssertEqual(AssetDetailCacheFeedPolicy.lookupFeeds(requestedFeed: .delayedSIP), [.delayedSIP])

        XCTAssertTrue(
            AssetDetailCacheFeedPolicy.shouldStoreResolvedKey(requestedFeed: .iex, resolvedFeed: .overnight)
        )
        XCTAssertFalse(
            AssetDetailCacheFeedPolicy.shouldStoreResolvedKey(requestedFeed: .sip, resolvedFeed: .overnight)
        )
        XCTAssertFalse(
            AssetDetailCacheFeedPolicy.shouldStoreResolvedKey(requestedFeed: .iex, resolvedFeed: .iex)
        )
    }
}
