import Foundation

protocol MarketsServicing: Sendable {
    func fetchMarketOverview(credentials: AlpacaCredentials) async throws -> MarketOverview
    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> [MarketIndexQuote]
    func fetchAssets(assetClass: String?, credentials: AlpacaCredentials) async throws -> [AlpacaAsset]
    func fetchAsset(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaAsset
    func fetchAssetDetail(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AssetDetailSnapshot
    func fetchStockSnapshot(symbol: String, feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> AlpacaStockSnapshot?
    func fetchCurrentStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaResolvedStockSnapshot
    func fetchLatestStockBar(symbol: String, feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> AlpacaMarketBar?
    func fetchHistoricalStockQuotes(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        start: Date,
        end: Date,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockQuotesPage
    func fetchOptionChain(
        symbol: String,
        feed: AlpacaOptionFeed,
        type: AlpacaOptionContractType?,
        expirationDate: String?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionChainPage
    func fetchOptionSnapshots(
        symbols: [String],
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionSnapshotsPage
    func fetchOptionBars(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionBarsPage
    func fetchOptionTrades(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionTradesPage
    func fetchLatestOptionTrades(
        symbols: [String],
        feed: AlpacaOptionFeed,
        credentials: AlpacaCredentials
    ) async throws -> [String: AlpacaOptionTrade]
    func fetchOptionContracts(
        symbol: String,
        expirationDateGTE: String?,
        expirationDateLTE: String?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionContractsPage
    func fetchNews(
        symbols: [String],
        start: Date?,
        end: Date?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaNewsPage
    func fetchMarketSymbols(symbols: [String], credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol]
    func fetchMostActiveMarketSymbols(top: Int, sort: MarketMostActiveSort, credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol]
}

extension MarketsServicing {
    func fetchMarketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await fetchAssets(assetClass: "us_equity", credentials: credentials)
    }
}

struct MarketsService: MarketsServicing {
    private let alpaca: any AlpacaServicing

    init(alpaca: any AlpacaServicing) {
        self.alpaca = alpaca
    }

    func fetchMarketOverview(credentials: AlpacaCredentials) async throws -> MarketOverview {
        try await alpaca.fetchMarketOverview(credentials: credentials)
    }

    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> [MarketIndexQuote] {
        try await alpaca.fetchMarketIndexQuotes(feed: feed, credentials: credentials)
    }

    func fetchAssets(assetClass: String?, credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await alpaca.fetchAssets(assetClass: assetClass, credentials: credentials)
    }

    func fetchAsset(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaAsset {
        try await alpaca.fetchAsset(symbolOrAssetID: symbolOrAssetID, credentials: credentials)
    }

    func fetchAssetDetail(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AssetDetailSnapshot {
        try await alpaca.fetchAssetDetail(symbol: symbol, range: range, feed: feed, credentials: credentials)
    }

    func fetchStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockSnapshot? {
        try await alpaca.fetchStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
    }

    func fetchCurrentStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaResolvedStockSnapshot {
        try await alpaca.fetchCurrentStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
    }

    func fetchLatestStockBar(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaMarketBar? {
        try await alpaca.fetchLatestStockBar(symbol: symbol, feed: feed, credentials: credentials)
    }

    func fetchHistoricalStockQuotes(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        start: Date,
        end: Date,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockQuotesPage {
        try await alpaca.fetchHistoricalStockQuotes(
            symbol: symbol,
            feed: feed,
            start: start,
            end: end,
            limit: limit,
            pageToken: pageToken,
            sort: sort,
            credentials: credentials
        )
    }

    func fetchOptionChain(
        symbol: String,
        feed: AlpacaOptionFeed,
        type: AlpacaOptionContractType?,
        expirationDate: String?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionChainPage {
        try await alpaca.fetchOptionChain(
            symbol: symbol,
            feed: feed,
            type: type,
            expirationDate: expirationDate,
            limit: limit,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchOptionSnapshots(
        symbols: [String],
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionSnapshotsPage {
        try await alpaca.fetchOptionSnapshots(
            symbols: symbols,
            feed: feed,
            limit: limit,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchOptionBars(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionBarsPage {
        try await alpaca.fetchOptionBars(
            symbol: symbol,
            range: range,
            feed: feed,
            limit: limit,
            pageToken: pageToken,
            sort: sort,
            credentials: credentials
        )
    }

    func fetchOptionTrades(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed,
        limit: Int,
        pageToken: String?,
        sort: AlpacaSortDirection,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionTradesPage {
        try await alpaca.fetchOptionTrades(
            symbol: symbol,
            range: range,
            feed: feed,
            limit: limit,
            pageToken: pageToken,
            sort: sort,
            credentials: credentials
        )
    }

    func fetchLatestOptionTrades(
        symbols: [String],
        feed: AlpacaOptionFeed,
        credentials: AlpacaCredentials
    ) async throws -> [String: AlpacaOptionTrade] {
        try await alpaca.fetchLatestOptionTrades(symbols: symbols, feed: feed, credentials: credentials)
    }

    func fetchOptionContracts(
        symbol: String,
        expirationDateGTE: String?,
        expirationDateLTE: String?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionContractsPage {
        try await alpaca.fetchOptionContracts(
            symbol: symbol,
            expirationDateGTE: expirationDateGTE,
            expirationDateLTE: expirationDateLTE,
            limit: limit,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchNews(
        symbols: [String],
        start: Date?,
        end: Date?,
        limit: Int,
        pageToken: String?,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaNewsPage {
        try await alpaca.fetchNews(
            symbols: symbols,
            start: start,
            end: end,
            limit: limit,
            pageToken: pageToken,
            credentials: credentials
        )
    }

    func fetchMarketSymbols(symbols: [String], credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol] {
        try await alpaca.fetchMarketSymbols(symbols: symbols, credentials: credentials)
    }

    func fetchMostActiveMarketSymbols(
        top: Int,
        sort: MarketMostActiveSort,
        credentials: AlpacaCredentials
    ) async throws -> [MarketActiveSymbol] {
        try await alpaca.fetchMostActiveMarketSymbols(top: top, sort: sort, credentials: credentials)
    }
}
