import UIKit
import XCTest
@testable import vicu

final class MarketSearchEngineTests: XCTestCase {
    private func makeAsset(
        symbol: String,
        name: String? = nil,
        exchange: String? = "NASDAQ",
        tradable: Bool = true,
        fractionable: Bool = true
    ) -> AlpacaAsset {
        AlpacaAsset(
            id: "id-\(symbol)",
            assetClass: "us_equity",
            exchange: exchange,
            symbol: symbol,
            name: name,
            status: "active",
            tradable: tradable,
            marginable: true,
            maintenanceMarginRequirement: nil,
            marginRequirementLong: nil,
            marginRequirementShort: nil,
            shortable: true,
            easyToBorrow: true,
            borrowStatus: nil,
            fractionable: fractionable,
            attributes: nil
        )
    }

    func testExactTickerMatchRanksFirstAbovePrefixesAndNameMatches() {
        let assets = [
            makeAsset(symbol: "AAPLX", name: "Apple Extended ETF", exchange: "ARCA"),
            makeAsset(symbol: "APLE", name: "Apple Hospitality REIT"),
            makeAsset(symbol: "AAPL", name: "Apple Inc."),
            makeAsset(symbol: "A", name: "Agilent Technologies Inc.", exchange: "NYSE")
        ]
        let index = MarketSearchIndex(assets: assets)

        let results = index.search(query: "aapl")

        XCTAssertEqual(results.first?.symbol, "AAPL")
        XCTAssertEqual(results.map(\.symbol), ["AAPL", "AAPLX"])
    }

    func testOwnedAndFavoritedSymbolsReceiveRelevanceBoost() {
        let assets = [
            makeAsset(symbol: "AMAT", name: "Applied Materials Inc."),
            makeAsset(symbol: "AMD", name: "Advanced Micro Devices Inc."),
            makeAsset(symbol: "AMZN", name: "Amazon.com Inc."),
            makeAsset(symbol: "AAL", name: "American Airlines Group Inc.")
        ]
        let index = MarketSearchIndex(assets: assets)

        let results = index.search(
            query: "AM",
            ownedSymbols: ["AMZN"],
            favoriteSymbols: ["AMD"]
        )

        XCTAssertEqual(results.prefix(2).map(\.symbol), ["AMZN", "AMD"])
    }

    func testScopeFilteringSeparatesSavedETFAndFractional() {
        let assets = [
            makeAsset(symbol: "SPY", name: "SPDR S&P 500 ETF Trust", exchange: "ARCA", fractionable: true),
            makeAsset(symbol: "NVDA", name: "NVIDIA Corporation", exchange: "NASDAQ", fractionable: true),
            makeAsset(symbol: "BRK.A", name: "Berkshire Hathaway Inc.", exchange: "NYSE", fractionable: false)
        ]
        let index = MarketSearchIndex(assets: assets)

        let etfMatches = index.search(query: "S", scope: .etf)
        XCTAssertEqual(etfMatches.map(\.symbol), ["SPY"])

        let savedMatches = index.search(query: "N", scope: .saved, ownedSymbols: ["NVDA"])
        XCTAssertEqual(savedMatches.map(\.symbol), ["NVDA"])

        let fractionalMatches = index.search(query: "BRK", scope: .fractional)
        XCTAssertTrue(fractionalMatches.isEmpty)
    }

    func testCompanyNameLookupResolvesInConstantTime() {
        let index = MarketSearchIndex(assets: [
            makeAsset(symbol: "NVDA", name: "NVIDIA Corporation"),
            makeAsset(symbol: "TSLA", name: "Tesla, Inc.")
        ])

        XCTAssertEqual(index.companyName(forSymbol: "nvda"), "NVIDIA Corporation")
        XCTAssertEqual(index.companyName(forSymbol: " TSLA "), "Tesla, Inc.")
        XCTAssertNil(index.companyName(forSymbol: "UNKNOWN"))
    }

    func testMajorExchangeTradableRanksAheadOfOTCAndNonTradable() {
        let assets = [
            makeAsset(symbol: "NVDAX", name: "OTC NVDA Tracker", exchange: "OTC", tradable: false),
            makeAsset(symbol: "NVDAW", name: "OTC Warrant", exchange: "OTC", tradable: true),
            makeAsset(symbol: "NVDL", name: "GraniteShares 2x Long NVDA Daily ETF", exchange: "NASDAQ", tradable: true)
        ]
        let index = MarketSearchIndex(assets: assets)

        let results = index.search(query: "NVD")

        XCTAssertEqual(results.first?.symbol, "NVDL")
        XCTAssertEqual(results.last?.symbol, "NVDAX")
    }

    func testLargeCatalogSearchCompletesInMilliseconds() {
        var records: [SearchableAssetRecord] = []
        records.reserveCapacity(12_000)
        records.append(SearchableAssetRecord(id: "nvda", symbol: "NVDA", name: "NVIDIA Corporation", exchange: "NASDAQ", tradable: true, fractionable: true))
        for i in 0..<11_999 {
            let prefix = Character(UnicodeScalar(65 + (i % 26))!)
            records.append(
                SearchableAssetRecord(
                    id: "id-\(i)",
                    symbol: "\(prefix)SYM\(i)",
                    name: "Sample Holdings Corporation \(i)",
                    exchange: i % 2 == 0 ? "NASDAQ" : "NYSE",
                    tradable: true,
                    fractionable: i % 3 == 0
                )
            )
        }

        let index = MarketSearchIndex(records: records)
        let startedAt = CFAbsoluteTimeGetCurrent()
        let results = index.search(query: "NV", limit: 24)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000

        XCTAssertEqual(results.first?.symbol, "NVDA")
        XCTAssertLessThan(elapsedMs, 50.0, "Indexed search across 12,000 assets should complete well under 50ms, took \(elapsedMs)ms")
    }

    @MainActor
    func testRecentSearchSymbolsPersistDeduplicateAndClear() {
        let configStore = MemoryAppConfigurationStore()
        let services = AppServices(
            alpaca: AlpacaClient(),
            credentialStore: KeychainCredentialStore(),
            configurationStore: configStore,
            pageCache: MemoryPageCacheStore()
        )
        let app = AppModel(services: services)
        app.credentials = AlpacaCredentials(keyID: "k1", secretKey: "s1", environment: .paper)

        app.recordRecentSearchSymbol("nvda")
        app.recordRecentSearchSymbol("AAPL")
        app.recordRecentSearchSymbol("NVDA")

        XCTAssertEqual(app.recentSearchSymbols(), ["NVDA", "AAPL"])

        app.removeRecentSearchSymbol("AAPL")
        XCTAssertEqual(app.recentSearchSymbols(), ["NVDA"])

        app.clearRecentSearchSymbols()
        XCTAssertTrue(app.recentSearchSymbols().isEmpty)
    }

    @MainActor
    func testStoreResetsLoadingStatesOnDisappearAndContextSwitch() {
        let store = MarketSearchStore()
        store.scope = .etf
        store.showsAllPopular = true
        store.isSearching = true
        store.isLoadingPopular = true
        store.recentSymbols = ["NVDA"]
        store.popularSymbols = [
            MarketActiveSymbol(symbol: "NVDA", companyName: "NVIDIA", price: 140, change: 1, percentChange: 0.01, volume: nil, tradeCount: nil)
        ]

        store.onDisappear()
        XCTAssertFalse(store.isSearching)
        XCTAssertFalse(store.isLoadingPopular)

        store.resetForContextChange()
        XCTAssertEqual(store.scope, .all)
        XCTAssertFalse(store.showsAllPopular)
        XCTAssertTrue(store.recentSymbols.isEmpty)
        XCTAssertTrue(store.popularSymbols.isEmpty)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertTrue(store.shouldShowPopularSkeleton)
        XCTAssertTrue(store.shouldShowTrendingSection)

        store.hasLoadedPopularOnce = true
        XCTAssertFalse(store.shouldShowPopularSkeleton)
        XCTAssertFalse(store.shouldShowTrendingSection)
    }

    @MainActor
    func testStoreColdStartCatalogFailureClearsSearchingStateAndReportsError() async {
        struct FailingAPIClient: APIClient {
            func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
                throw APIClientError.underlying("Network offline")
            }
        }

        let services = AppServices(
            alpaca: AlpacaClient(apiClient: FailingAPIClient()),
            credentialStore: KeychainCredentialStore(),
            configurationStore: MemoryAppConfigurationStore(),
            pageCache: MemoryPageCacheStore()
        )
        let app = AppModel(services: services)
        app.credentials = AlpacaCredentials(keyID: "k1", secretKey: "s1", environment: .paper)
        app.hasCredentials = true

        let store = MarketSearchStore()
        store.updateQuery("ZZZUNKNOWN", app: app, immediate: true)

        // Wait briefly for the failing catalog warmup task to finish
        for _ in 0..<40 where store.isCatalogSyncing || store.isSearching {
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertFalse(store.isCatalogSyncing)
        XCTAssertFalse(store.isSearching)
        XCTAssertNotNil(store.consumeCatalogErrorMessage())
    }

    @MainActor
    func testStoreSyncRecentSymbolsPicksUpExternalUpdates() {
        let services = AppServices(
            alpaca: AlpacaClient(),
            credentialStore: KeychainCredentialStore(),
            configurationStore: MemoryAppConfigurationStore(),
            pageCache: MemoryPageCacheStore()
        )
        let app = AppModel(services: services)
        app.credentials = AlpacaCredentials(keyID: "k1", secretKey: "s1", environment: .paper)

        let store = MarketSearchStore()
        XCTAssertTrue(store.recentSymbols.isEmpty)

        app.recordRecentSearchSymbol("TSLA")
        store.syncRecentSymbols(app: app)
        XCTAssertEqual(store.recentSymbols, ["TSLA"])
    }

    func testTabBarDualStateAssetsAndUnifiedOrder() {
        XCTAssertEqual(AppTab.allCases, [.home, .markets, .orders, .more])
        XCTAssertNotNil(UIImage(named: AppIcon.Account.avatar))

        for tab in AppTab.allCases {
            let unselectedName = AppIcon.Tab.assetName(for: tab, isSelected: false)
            let selectedName = AppIcon.Tab.assetName(for: tab, isSelected: true)
            XCTAssertNotEqual(unselectedName, selectedName)
            XCTAssertNotNil(UIImage(named: unselectedName), "Missing unselected tab asset: \(unselectedName)")
            XCTAssertNotNil(UIImage(named: selectedName), "Missing selected tab asset: \(selectedName)")
        }
    }
}
