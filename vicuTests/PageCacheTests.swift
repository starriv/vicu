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

extension PageCacheTests {
    @MainActor
    private func marketApp(api: any APIClient, cache: MemoryPageCacheStore) -> AppModel {
        let services = AppServices(alpaca: AlpacaClient(apiClient: api), credentialStore: KeychainCredentialStore(),
                                   configurationStore: MemoryAppConfigurationStore(), pageCache: cache)
        let app = AppModel(services: services)
        app.credentials = AlpacaCredentials(keyID: "fixture", secretKey: "fixture", environment: .paper)
        app.hasCredentials = true
        return app
    }

    @MainActor
    func testSubmitRequiresConfirmationForCurrentEnvironment() async {
        let app = marketApp(api: MarketCacheFixtureAPI(), cache: MemoryPageCacheStore())
        let result = await app.submit(OrderDraft(), clientOrderID: nil, confirmedEnvironment: .live)
        guard case .failure(let message) = result else { return XCTFail("Wrong environment accepted") }
        XCTAssertEqual(message, L10n.string("trade.confirm.environment_changed", locale: app.appLanguage.locale))
        XCTAssertTrue(app.portfolio.orders.isEmpty)
    }

    @MainActor
    func testForceRefreshKeepsNewestOverviewInMemoryAndDisk() async throws {
        let firstClockStarted = expectation(description: "First overview clock is suspended")
        let api = MarketCacheFixtureAPI(firstClockStarted: firstClockStarted)
        let cache = MemoryPageCacheStore()
        let app = marketApp(api: api, cache: cache)
        let first = Task { try await app.fetchMarketOverview(forceRefresh: true) }
        await fulfillment(of: [firstClockStarted], timeout: 3)

        let latest = try await app.fetchMarketOverview(forceRefresh: true)
        await api.releaseFirstClock()
        do {
            _ = try await first.value
            XCTFail("Superseded overview returned a result")
        } catch is CancellationError {}
        XCTAssertEqual(latest.clock.timestamp, "2026-11-25T15:00:00Z")
        XCTAssertEqual(app.cachedMarketOverview?.clock.timestamp, latest.clock.timestamp)
        app.resetMarketOverviewCache()
        await app.hydrateCachedMarketsFromDisk()
        XCTAssertEqual(app.cachedMarketOverview?.clock.timestamp, latest.clock.timestamp)
        XCTAssertNil(app.cachedPopularMarketSymbols(sort: .trades))
        XCTAssertNil(app.cachedPopularMarketSymbols(sort: .volume))
        XCTAssertFalse(latest.mostActive.isEmpty)
    }

    @MainActor
    func testExpiredFavoritesReloadAndRemovalSurviveHydration() async throws {
        let api = MarketCacheFixtureAPI()
        let app = marketApp(api: api, cache: MemoryPageCacheStore())

        await app.refreshFavoriteMarketSymbols()
        XCTAssertEqual(app.favoriteMarketSymbols, ["AAA"])
        await api.changeSymbol(to: "BBB")
        app.favoriteMarketSymbolsUpdatedAt = Date().addingTimeInterval(-PageCachePolicy.marketFavorites.freshTimeToLive - 1)
        await app.refreshFavoriteMarketSymbols()
        XCTAssertEqual(app.favoriteMarketSymbols, ["BBB"])

        let favorites = try XCTUnwrap(app.favoritesWatchlist)
        try await app.deleteWatchlist(favorites)
        await app.hydrateCachedMarketsFromDisk()
        XCTAssertTrue(app.favoriteMarketSymbols.isEmpty)
        XCTAssertFalse(app.hasLoadedFavoriteMarketSymbols)
    }

    @MainActor
    func testRenameInvalidatesDiskOnlyFavorites() async throws {
        let api = MarketCacheFixtureAPI()
        let app = marketApp(api: api, cache: MemoryPageCacheStore())
        await app.refreshFavoriteMarketSymbols()
        app.resetFavoriteMarketSymbols()
        await app.hydrateCachedMarketsFromDisk()
        XCTAssertEqual(app.favoriteMarketSymbols, ["AAA"])
        XCTAssertNil(app.favoritesWatchlist)
        _ = try await app.updateWatchlist(id: "f", name: "research", symbols: ["AAA"], previousName: "Favorites")
        await app.hydrateCachedMarketsFromDisk()
        XCTAssertFalse(app.hasLoadedFavoriteMarketSymbols)
        XCTAssertTrue(app.favoriteMarketSymbols.isEmpty)
    }

    func testSessionUsesCurrentCalendarTimeEvenWithOldOpenClock() throws {
        let clock = AlpacaMarketClock(timestamp: "2026-11-24T15:00:00Z", isMarketDay: true, isOpen: true,
                                      nextOpen: nil, nextClose: "2026-11-24T21:00:00Z", phase: "open", phaseUntil: nil)
        let day = AlpacaCalendarDay(date: "2026-11-25", coreStart: "2026-11-25T14:30:00Z", coreEnd: "2026-11-25T21:00:00Z",
                                    preStart: nil, preEnd: nil, postStart: nil, postEnd: nil, settlementDate: nil)
        let overview = MarketOverview(clock: clock, calendar: [day], overnightCalendar: [], indexQuotes: [], gainers: [], losers: [], mostActive: [])
        let beforeOpen = try XCTUnwrap(AlpacaDateParser.date("2026-11-25T13:00:00Z"))
        let open = try XCTUnwrap(AlpacaDateParser.date(day.coreStart))
        let closed = MarketSessionSnapshot.current(for: overview, now: beforeOpen)
        XCTAssertEqual(closed.session, .closed)
        XCTAssertEqual(closed.nextBoundary, open)
        XCTAssertEqual(MarketSessionSnapshot.current(for: overview, now: open).session, .regular)
        let expired = MarketSessionSnapshot.current(for: overview, now: open.addingTimeInterval(86400))
        XCTAssertEqual(expired.session, .unknown)
        XCTAssertNil(expired.nextBoundary)
    }
}

private actor MarketCacheFixtureAPI: APIClient {
    private var symbol = "AAA"
    private var firstClockStarted: XCTestExpectation?
    private var firstClock: CheckedContinuation<Void, Never>?

    init(firstClockStarted: XCTestExpectation? = nil) {
        self.firstClockStarted = firstClockStarted
    }

    func changeSymbol(to symbol: String) { self.symbol = symbol }

    func releaseFirstClock() {
        firstClock?.resume()
        firstClock = nil
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        let json: String
        let favorites = #"{"id":"f","name":"favorites","assets":[{"id":"a","symbol":"\#(symbol)","name":"Fixture"}]}"#
        switch request.path {
        case APIPaths.AlpacaTrading.marketClock:
            let time: String
            if let expectation = firstClockStarted {
                firstClockStarted = nil
                await withCheckedContinuation { continuation in
                    firstClock = continuation
                    expectation.fulfill()
                }
                time = "2026-11-24T15:00:00Z"
            } else {
                time = "2026-11-25T15:00:00Z"
            }
            json = #"{"clocks":[{"market":{"acronym":"NYSE"},"is_market_day":true,"timestamp":"\#(time)","phase":"open"}]}"#
        case let path where path.hasPrefix("v3/calendar/"):
            json = #"{"calendar":[]}"#
        case APIPaths.AlpacaTrading.watchlists:
            json = "[\(favorites)]"
        case APIPaths.AlpacaTrading.watchlist("f"):
            switch request.method {
            case .put: json = #"{"id":"f","name":"research","assets":[]}"#
            case .delete: json = "{}"
            default: json = favorites
            }
        default:
            json = "{}"
        }
        return try JSONDecoder().decode(Response.self, from: Data(json.utf8))
    }
}
