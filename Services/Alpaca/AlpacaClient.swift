import Foundation
import OSLog

protocol AlpacaServicing: Sendable {
    func testConnection(credentials: AlpacaCredentials) async throws
    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount
    func fetchAccountActivities(pageSize: Int, pageToken: String?, credentials: AlpacaCredentials) async throws -> AlpacaAccountActivitiesPage
    func fetchPositions(credentials: AlpacaCredentials) async throws -> [AlpacaPosition]
    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition?
    func closeOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func fetchRecentOrders(credentials: AlpacaCredentials) async throws -> [AlpacaOrder]
    func fetchOrder(id: String, nested: Bool, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func cancelOrder(id: String, credentials: AlpacaCredentials) async throws
    func replaceOrder(id: String, request: AlpacaReplaceOrderRequest, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func fetchMarketOverview(credentials: AlpacaCredentials) async throws -> MarketOverview
    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> [MarketIndexQuote]
    func fetchMarketCalendar(market: String, start: String, end: String, credentials: AlpacaCredentials) async throws -> [AlpacaCalendarDay]
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
    func fetchLatestStockBar(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaMarketBar?
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
    func fetchStockBars(symbol: String, range: AssetChartRange, feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> [AlpacaMarketBar]
    func fetchMarketSymbols(symbols: [String], credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol]
    func fetchMostActiveMarketSymbols(top: Int, sort: MarketMostActiveSort, credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol]
    func fetchWatchlists(credentials: AlpacaCredentials) async throws -> [AlpacaWatchlist]
    func fetchWatchlist(id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func createWatchlist(name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func updateWatchlist(id: String, name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func deleteWatchlist(id: String, credentials: AlpacaCredentials) async throws
    func addSymbol(_ symbol: String, toWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func removeSymbol(_ symbol: String, fromWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist
    func fetchPortfolioHistory(
        range: PortfolioHistoryRange,
        accountCreatedAt: String?,
        credentials: AlpacaCredentials
    ) async throws -> [PortfolioHistoryPoint]
    func submitOrder(_ draft: OrderDraft, clientOrderID: String?, credentials: AlpacaCredentials) async throws -> AlpacaOrder
}

extension AlpacaServicing {
    func fetchMarketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await fetchAssets(assetClass: "us_equity", credentials: credentials)
    }
}

struct AlpacaClient: AlpacaServicing {
    private static let logger = Logger(subsystem: "com.starriv.vicu", category: "AlpacaClient")
    private static let assetChartSessionContextCacheTTL: TimeInterval = 45
    private static let optionHistoricalDataDelay: TimeInterval = 15 * 60
    private static let assetChartSessionContextCache = AssetChartSessionContextCache()
    private static let indexProxies: [(title: String, symbol: String)] = [
        ("S&P 500", "SPY"),
        ("Nasdaq 100", "QQQ"),
        ("Dow", "DIA")
    ]
    private static let marketCapLeaders: [(symbol: String, companyName: String)] = [
        ("NVDA", "NVIDIA Corporation"),
        ("GOOG", "Alphabet Inc."),
        ("AAPL", "Apple Inc."),
        ("MSFT", "Microsoft Corporation"),
        ("AMZN", "Amazon.com, Inc."),
        ("META", "Meta Platforms, Inc."),
        ("AVGO", "Broadcom Inc."),
        ("TSM", "Taiwan Semiconductor Manufacturing Company"),
        ("TSLA", "Tesla, Inc."),
        ("BRK.B", "Berkshire Hathaway Inc.")
    ]

    private let tradingClient: any AlpacaTradingRequesting
    private let marketDataClient: any AlpacaMarketDataRequesting

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.init(
            tradingClient: AlpacaTradingClient(apiClient: apiClient),
            marketDataClient: AlpacaMarketDataClient(apiClient: apiClient)
        )
    }

    init(
        tradingClient: any AlpacaTradingRequesting,
        marketDataClient: any AlpacaMarketDataRequesting
    ) {
        self.tradingClient = tradingClient
        self.marketDataClient = marketDataClient
    }

    func testConnection(credentials: AlpacaCredentials) async throws {
        _ = try await fetchAccount(credentials: credentials)
    }

    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount {
        try await request(.account, credentials: credentials)
    }

    func fetchAccountActivities(
        pageSize: Int = 100,
        pageToken: String? = nil,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaAccountActivitiesPage {
        let resolvedPageSize = min(max(pageSize, 1), 100)
        let activities: [AlpacaAccountActivity] = try await request(
            .accountActivities(pageSize: resolvedPageSize, pageToken: pageToken),
            credentials: credentials
        )
        return AlpacaAccountActivitiesPage(
            activities: activities,
            nextPageToken: activities.count == resolvedPageSize ? activities.last?.id : nil
        )
    }

    func fetchPositions(credentials: AlpacaCredentials) async throws -> [AlpacaPosition] {
        try await request(.positions, credentials: credentials)
    }

    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition? {
        do {
            return try await request(.position(symbolOrAssetID: symbolOrAssetID), credentials: credentials)
        } catch let error as APIClientError where error.statusCode == 404 {
            return nil
        }
    }

    func closeOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        try await request(.closePosition(symbolOrAssetID: symbolOrAssetID), credentials: credentials)
    }

    func fetchRecentOrders(credentials: AlpacaCredentials) async throws -> [AlpacaOrder] {
        try await request(.recentOrders, credentials: credentials)
    }

    func fetchOrder(id: String, nested: Bool = true, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        try await request(.order(id: id, nested: nested), credentials: credentials)
    }

    func cancelOrder(id: String, credentials: AlpacaCredentials) async throws {
        let _: EmptyAPIResponse = try await request(.cancelOrder(id: id), credentials: credentials)
    }

    func replaceOrder(id: String, request payload: AlpacaReplaceOrderRequest, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        let data = try JSONEncoder().encode(payload)
        return try await request(.replaceOrder(id: id), body: data, credentials: credentials)
    }

    func fetchMarketOverview(credentials: AlpacaCredentials) async throws -> MarketOverview {
        let indexSymbols = Self.indexProxies.map(\.symbol)
        let snapshotSymbols = Array(Set(indexSymbols + Self.marketCapLeaders.map(\.symbol)))

        async let clockRequest: AlpacaMarketClockResponse = request(.marketClock, credentials: credentials)
        let clockResponse = try await clockRequest
        let clock = try clockResponse.clock(market: "NYSE")
        let calendarStart = Self.marketCalendarDateString(from: clock.timestamp)
        let calendarEnd = Self.marketCalendarDateString(daysAfter: 14, from: clock.timestamp)
        async let calendarRequest = fetchMarketCalendar(
            market: "NYSE",
            start: calendarStart,
            end: calendarEnd,
            credentials: credentials
        )
        async let overnightCalendarRequest = fetchOvernightMarketCalendar(
            start: calendarStart,
            end: calendarEnd,
            credentials: credentials
        )
        let calendar = try await calendarRequest
        let overnightCalendar = await overnightCalendarRequest
        let snapshots: AlpacaStockSnapshotsResponse = (try? await marketDataRequest(
            .stockSnapshots(symbols: snapshotSymbols, feed: .iex),
            credentials: credentials
        )) ?? AlpacaStockSnapshotsResponse(snapshots: [:])
        let indexQuotes = Self.indexProxies.map { proxy in
            Self.indexQuote(title: proxy.title, symbol: proxy.symbol, snapshot: snapshots.snapshots[proxy.symbol])
        }
        let marketCapLeaders = Self.marketCapLeaders.map { leader in
            Self.marketSymbol(
                symbol: leader.symbol,
                companyName: leader.companyName,
                snapshot: snapshots.snapshots[leader.symbol]
            )
        }

        return MarketOverview(
            clock: clock,
            calendar: calendar,
            overnightCalendar: overnightCalendar,
            indexQuotes: indexQuotes,
            gainers: [],
            losers: [],
            mostActive: marketCapLeaders
        )
    }

    func fetchMarketIndexQuotes(
        feed: AlpacaMarketDataFeed = .iex,
        credentials: AlpacaCredentials
    ) async throws -> [MarketIndexQuote] {
        let indexSymbols = Self.indexProxies.map(\.symbol)
        var lastError: Error?

        let snapshots: AlpacaStockSnapshotsResponse?
        do {
            snapshots = try await marketDataRequest(
                .stockSnapshots(symbols: indexSymbols, feed: feed),
                credentials: credentials
            )
        } catch {
            snapshots = nil
            lastError = error
        }

        let latestBars: AlpacaLatestStockBarsResponse?
        do {
            latestBars = try await marketDataRequest(
                .stockLatestBars(symbols: indexSymbols, feed: feed),
                credentials: credentials
            )
        } catch {
            latestBars = nil
            lastError = error
        }

        if snapshots == nil, latestBars == nil, let lastError {
            throw lastError
        }

        return Self.indexProxies.map { proxy in
            Self.indexQuote(
                title: proxy.title,
                symbol: proxy.symbol,
                snapshot: snapshots?.snapshots[proxy.symbol],
                latestBar: latestBars?.bars[proxy.symbol]
            )
        }
    }

    func fetchMarketCalendar(market: String, start: String, end: String, credentials: AlpacaCredentials) async throws -> [AlpacaCalendarDay] {
        let response: AlpacaMarketCalendarResponse = try await request(
            .marketCalendar(market: market, start: start, end: end),
            credentials: credentials
        )
        return response.calendar
    }

    private func fetchOvernightMarketCalendar(
        start: String,
        end: String,
        credentials: AlpacaCredentials
    ) async -> [AlpacaCalendarDay] {
        if let oceaCalendar = try? await fetchMarketCalendar(
            market: "OCEA",
            start: start,
            end: end,
            credentials: credentials
        ) {
            return oceaCalendar
        }

        return (try? await fetchMarketCalendar(
            market: "BOATS",
            start: start,
            end: end,
            credentials: credentials
        )) ?? []
    }

    func fetchAssets(assetClass: String?, credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await request(.assets(assetClass: assetClass), credentials: credentials)
    }

    func fetchAsset(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaAsset {
        try await request(.asset(symbolOrAssetID: symbolOrAssetID), credentials: credentials)
    }

    func fetchAssetDetail(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed = .iex,
        credentials: AlpacaCredentials
    ) async throws -> AssetDetailSnapshot {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        let loadStartedAt = Date()
        Self.debugAssetDetailLatency(
            "start",
            symbol: normalizedSymbol,
            range: range,
            feed: feed,
            startedAt: loadStartedAt
        )

        async let assetRequest = timedAssetDetailStage(
            "asset",
            symbol: normalizedSymbol,
            range: range,
            feed: feed
        ) {
            try await fetchAsset(symbolOrAssetID: normalizedSymbol, credentials: credentials)
        }
        let chartContext = try await timedAssetDetailStage(
            "context",
            symbol: normalizedSymbol,
            range: range,
            feed: feed
        ) {
            try await assetChartDataContext(
                range: range,
                feed: feed,
                credentials: credentials,
                debugSymbol: normalizedSymbol
            )
        }
        async let barsResultRequest = timedAssetDetailStage(
            "barsResult",
            symbol: normalizedSymbol,
            range: range,
            feed: chartContext.barsFeed
        ) {
            try await fetchStockBarsResult(
                symbol: normalizedSymbol,
                range: range,
                context: chartContext,
                credentials: credentials
            )
        }
        async let chartBaselineRequest = timedAssetDetailStage(
            "chartBaseline",
            symbol: normalizedSymbol,
            range: range,
            feed: chartContext.barsFeed
        ) {
            await fetchChartBaselineClose(
                symbol: normalizedSymbol,
                range: range,
                feed: chartContext.barsFeed,
                credentials: credentials
            )
        }
        async let snapshotRequest = timedAssetDetailStage(
            "snapshot",
            symbol: normalizedSymbol,
            range: range,
            feed: chartContext.feed,
        ) {
            try await fetchAssetDetailSnapshot(
                symbol: normalizedSymbol,
                feed: chartContext.feed,
                credentials: credentials
            )
        }

        let barsResult = try await barsResultRequest
        let snapshot = try await AssetDetailSnapshot(
            asset: assetRequest,
            stockSnapshot: snapshotRequest,
            bars: barsResult.bars,
            chartBaseline: chartBaselineRequest,
            range: range,
            feed: chartContext.feed,
            sessionProgress: barsResult.context.sessionProgress,
            latestBar: nil
        )
        Self.debugAssetDetailLatency(
            "complete",
            symbol: normalizedSymbol,
            range: range,
            feed: chartContext.feed,
            startedAt: loadStartedAt,
            extra: "bars=\(snapshot.bars.count)"
        )
        return snapshot
    }

    func fetchStockSnapshot(symbol: String, feed: AlpacaMarketDataFeed = .iex, credentials: AlpacaCredentials) async throws -> AlpacaStockSnapshot? {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let response: AlpacaStockSnapshotsResponse = try await marketDataRequest(
            .stockSnapshots(symbols: [normalizedSymbol], feed: feed),
            credentials: credentials
        )
        return response.snapshots[normalizedSymbol]
    }

    func fetchCurrentStockSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaResolvedStockSnapshot {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaResolvedStockSnapshot(
                snapshot: nil,
                feed: Self.defaultMarketHoursFeed(from: feed),
                activeSession: nil,
                latestBar: nil
            )
        }

        let context = (try? await currentStockDataContext(feed: feed, credentials: credentials))
            ?? CurrentStockDataContext(feed: Self.defaultMarketHoursFeed(from: feed), activeSession: nil)
        async let snapshotRequest = try? fetchAssetDetailSnapshot(
            symbol: normalizedSymbol,
            feed: context.feed,
            credentials: credentials
        )
        async let latestBarRequest = try? fetchLatestStockBar(
            symbol: normalizedSymbol,
            feed: context.feed,
            credentials: credentials
        )

        return AlpacaResolvedStockSnapshot(
            snapshot: await snapshotRequest,
            feed: context.feed,
            activeSession: context.activeSession,
            latestBar: await latestBarRequest
        )
    }

    private func fetchAssetDetailSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockSnapshot? {
        guard feed == .overnight else {
            return try await fetchStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
        }

        let snapshot = try? await fetchStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
        let latestQuote = try? await fetchLatestStockQuote(symbol: symbol, feed: feed, credentials: credentials)
        do {
            let latestTrade = try await fetchLatestStockTrade(symbol: symbol, feed: feed, credentials: credentials)
            return (snapshot ?? AlpacaStockSnapshot.empty).withLatestTrade(latestTrade).withLatestQuote(latestQuote)
        } catch {
            if let snapshot {
                return snapshot.withLatestQuote(latestQuote)
            }

            throw error
        }
    }

    private func fetchLatestStockTrade(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockTrade? {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let response: AlpacaLatestStockTradeResponse = try await marketDataRequest(
            .stockLatestTrade(symbol: normalizedSymbol, feed: feed),
            credentials: credentials
        )
        return response.trade
    }

    private func fetchLatestStockQuote(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockQuote? {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let response: AlpacaLatestStockQuotesResponse = try await marketDataRequest(
            .stockLatestQuotes(symbols: [normalizedSymbol], feed: feed),
            credentials: credentials
        )
        return response.quotes[normalizedSymbol]
    }

    func fetchLatestStockBar(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaMarketBar? {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let response: AlpacaLatestStockBarsResponse = try await marketDataRequest(
            .stockLatestBars(symbols: [normalizedSymbol], feed: feed),
            credentials: credentials
        )
        return response.bars[normalizedSymbol]
    }

    func fetchHistoricalStockQuotes(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        start: Date,
        end: Date,
        limit: Int = 500,
        pageToken: String? = nil,
        sort: AlpacaSortDirection = .desc,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaStockQuotesPage {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaStockQuotesPage(quotes: [], nextPageToken: nil)
        }

        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()
        let interval = StockDataInterval(
            start: formatter.string(from: start),
            end: formatter.string(from: end)
        )
        let response: AlpacaStockQuotesResponse = try await marketDataRequest(
            .stockQuotes(
                symbol: normalizedSymbol,
                feed: feed,
                interval: interval,
                limit: min(max(limit, 1), 10_000),
                pageToken: pageToken,
                sort: sort
            ),
            credentials: credentials
        )

        return AlpacaStockQuotesPage(
            quotes: response.quotes[normalizedSymbol] ?? [],
            nextPageToken: response.nextPageToken
        )
    }

    func fetchOptionChain(
        symbol: String,
        feed: AlpacaOptionFeed = .indicative,
        type: AlpacaOptionContractType? = nil,
        expirationDate: String? = nil,
        limit: Int = 250,
        pageToken: String? = nil,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionChainPage {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionChainPage(snapshots: [], nextPageToken: nil)
        }

        let response: AlpacaOptionChainResponse = try await marketDataRequest(
            .optionChain(
                underlyingSymbol: normalizedSymbol,
                feed: feed,
                type: type,
                expirationDate: expirationDate,
                limit: min(max(limit, 1), 1000),
                pageToken: pageToken
            ),
            credentials: credentials
        )

        return AlpacaOptionChainPage(
            snapshots: response.snapshots
                .map { symbol, payload in
                    AlpacaOptionSnapshot(contractSymbol: symbol, payload: payload)
                },
            nextPageToken: response.nextPageToken
        )
    }

    func fetchOptionSnapshots(
        symbols: [String],
        feed: AlpacaOptionFeed = .indicative,
        limit: Int = 1000,
        pageToken: String? = nil,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionSnapshotsPage {
        let normalizedSymbols = normalizedSymbols(symbols)
        guard !normalizedSymbols.isEmpty else {
            return AlpacaOptionSnapshotsPage(snapshots: [], nextPageToken: nil)
        }

        let response: AlpacaOptionSnapshotsResponse = try await marketDataRequest(
            .optionSnapshots(
                symbols: normalizedSymbols,
                feed: feed,
                limit: min(max(limit, 1), 1000),
                pageToken: pageToken
            ),
            credentials: credentials
        )

        return AlpacaOptionSnapshotsPage(
            snapshots: response.snapshots.map { symbol, payload in
                AlpacaOptionSnapshot(contractSymbol: symbol, payload: payload)
            },
            nextPageToken: response.nextPageToken
        )
    }

    func fetchOptionBars(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed = .indicative,
        limit: Int = 10_000,
        pageToken: String? = nil,
        sort: AlpacaSortDirection = .asc,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionBarsPage {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionBarsPage(bars: [], nextPageToken: nil)
        }

        let interval = Self.optionDataInterval(for: range)
        #if DEBUG
        print(
            "[OptionChart][Client] request symbol=\(normalizedSymbol) range=\(range.title) timeframe=\(range.timeframe) start=\(interval.start) end=\(interval.end) limit=\(min(max(limit, 1), 10_000)) pageToken=\(pageToken ?? "nil") sort=\(sort.rawValue)"
        )
        #endif

        let response: AlpacaOptionBarsResponse = try await marketDataRequest(
            .optionBars(
                symbol: normalizedSymbol,
                range: range,
                feed: feed,
                interval: interval,
                limit: min(max(limit, 1), 10_000),
                pageToken: pageToken,
                sort: sort
            ),
            credentials: credentials
        )

        let bars = response.bars[normalizedSymbol] ?? []
        #if DEBUG
        let responseKeys = response.bars.keys.sorted().joined(separator: ",")
        print(
            "[OptionChart][Client] response symbol=\(normalizedSymbol) bars=\(bars.count) nextPageToken=\(response.nextPageToken ?? "nil") keys=[\(responseKeys)] first={\(bars.first?.debugSummary ?? "nil")} last={\(bars.last?.debugSummary ?? "nil")}"
        )
        #endif

        return AlpacaOptionBarsPage(
            bars: bars,
            nextPageToken: response.nextPageToken
        )
    }

    func fetchOptionTrades(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaOptionFeed = .indicative,
        limit: Int = 100,
        pageToken: String? = nil,
        sort: AlpacaSortDirection = .desc,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionTradesPage {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionTradesPage(trades: [], nextPageToken: nil)
        }

        let response: AlpacaOptionTradesResponse = try await marketDataRequest(
            .optionTrades(
                symbol: normalizedSymbol,
                feed: feed,
                interval: Self.optionDataInterval(for: range),
                limit: min(max(limit, 1), 10_000),
                pageToken: pageToken,
                sort: sort
            ),
            credentials: credentials
        )

        return AlpacaOptionTradesPage(
            trades: response.trades[normalizedSymbol] ?? [],
            nextPageToken: response.nextPageToken
        )
    }

    func fetchLatestOptionTrades(
        symbols: [String],
        feed: AlpacaOptionFeed = .indicative,
        credentials: AlpacaCredentials
    ) async throws -> [String: AlpacaOptionTrade] {
        let normalizedSymbols = normalizedSymbols(symbols)
        guard !normalizedSymbols.isEmpty else {
            return [:]
        }

        let response: AlpacaLatestOptionTradesResponse = try await marketDataRequest(
            .optionLatestTrades(symbols: normalizedSymbols, feed: feed),
            credentials: credentials
        )
        return response.trades
    }

    func fetchOptionContracts(
        symbol: String,
        expirationDateGTE: String? = nil,
        expirationDateLTE: String? = nil,
        limit: Int = 10_000,
        pageToken: String? = nil,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaOptionContractsPage {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionContractsPage(contracts: [], nextPageToken: nil)
        }

        let response: AlpacaOptionContractsResponse = try await request(
            .optionContracts(
                underlyingSymbol: normalizedSymbol,
                expirationDateGTE: expirationDateGTE,
                expirationDateLTE: expirationDateLTE,
                limit: min(max(limit, 1), 10_000),
                pageToken: pageToken
            ),
            credentials: credentials
        )

        return AlpacaOptionContractsPage(
            contracts: response.contracts,
            nextPageToken: response.nextPageToken
        )
    }

    func fetchNews(
        symbols: [String],
        start: Date? = nil,
        end: Date? = nil,
        limit: Int = 50,
        pageToken: String? = nil,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaNewsPage {
        let normalizedSymbols = normalizedSymbols(symbols)
        guard !normalizedSymbols.isEmpty else {
            return AlpacaNewsPage(articles: [], nextPageToken: nil)
        }

        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()
        let interval = NewsDataInterval(
            start: start.map { formatter.string(from: $0) },
            end: end.map { formatter.string(from: $0) }
        )
        let response: AlpacaNewsResponse = try await marketDataRequest(
            .news(
                symbols: normalizedSymbols,
                interval: interval,
                limit: min(max(limit, 1), 50),
                pageToken: pageToken,
                sort: .desc,
                includeContent: false
            ),
            credentials: credentials
        )

        return AlpacaNewsPage(
            articles: response.news,
            nextPageToken: response.nextPageToken
        )
    }

    func fetchStockBars(symbol: String, range: AssetChartRange, feed: AlpacaMarketDataFeed = .iex, credentials: AlpacaCredentials) async throws -> [AlpacaMarketBar] {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return []
        }

        let chartContext = try await assetChartDataContext(range: range, feed: feed, credentials: credentials)
        let barsResult = try await fetchStockBarsResult(
            symbol: normalizedSymbol,
            range: range,
            context: chartContext,
            credentials: credentials
        )
        return barsResult.bars
    }

    private func fetchStockBarsResult(
        symbol: String,
        range: AssetChartRange,
        context: AssetChartDataContext,
        credentials: AlpacaCredentials
    ) async throws -> (bars: [AlpacaMarketBar], context: AssetChartDataContext) {
        if range == .oneDay, let fallbackInterval = context.emptyBarsFallbackInterval {
            let fallbackBarsTask = Task {
                await fetchStockBarsIfAvailable(
                    stage: "fallbackBars",
                    symbol: symbol,
                    range: range,
                    feed: context.barsFeed,
                    interval: fallbackInterval,
                    credentials: credentials
                )
            }
            let bars = try await timedAssetDetailStage(
                "primaryBars",
                symbol: symbol,
                range: range,
                feed: context.barsFeed
            ) {
                try await fetchStockBars(
                    symbol: symbol,
                    range: range,
                    feed: context.barsFeed,
                    interval: context.interval,
                    credentials: credentials
                )
            }

            let fallbackBars = await fallbackBarsTask.value ?? []
            guard !fallbackBars.isEmpty else {
                return (bars, context)
            }
            return (fallbackBars + bars, context)
        }

        let bars = try await timedAssetDetailStage(
            "bars",
            symbol: symbol,
            range: range,
            feed: context.barsFeed
        ) {
            try await fetchStockBars(
                symbol: symbol,
                range: range,
                feed: context.barsFeed,
                interval: context.interval,
                credentials: credentials
            )
        }
        return (bars, context)
    }

    private func fetchStockBarsIfAvailable(
        stage: String,
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        interval: StockDataInterval,
        credentials: AlpacaCredentials
    ) async -> [AlpacaMarketBar]? {
        do {
            return try await timedAssetDetailStage(
                stage,
                symbol: symbol,
                range: range,
                feed: feed
            ) {
                try await fetchStockBars(
                    symbol: symbol,
                    range: range,
                    feed: feed,
                    interval: interval,
                    credentials: credentials
                )
            }
        } catch {
            return nil
        }
    }

    private func fetchStockBars(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        interval: StockDataInterval,
        credentials: AlpacaCredentials
    ) async throws -> [AlpacaMarketBar] {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return []
        }

        let response: AlpacaStockBarsResponse = try await marketDataRequest(
            .stockBars(symbol: normalizedSymbol, range: range, feed: feed, interval: interval),
            credentials: credentials
        )
        return response.bars[normalizedSymbol] ?? []
    }

    private func fetchChartBaselineClose(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async -> Double? {
        guard range == .yearToDate else {
            return nil
        }

        do {
            return try await fetchYearToDateBaselineClose(
                symbol: symbol,
                feed: feed,
                credentials: credentials
            )
        } catch {
            return nil
        }
    }

    private func fetchYearToDateBaselineClose(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> Double? {
        let normalizedSymbol = Self.normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let bars = try await fetchStockBars(
            symbol: normalizedSymbol,
            range: .yearToDate,
            feed: feed,
            interval: Self.yearToDateBaselineInterval(),
            credentials: credentials
        )

        return bars.compactMap(\.close).last
    }

    func fetchMarketSymbols(symbols: [String], credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol] {
        let normalizedSymbols = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }

        guard !normalizedSymbols.isEmpty else {
            return []
        }

        let snapshots: AlpacaStockSnapshotsResponse = try await marketDataRequest(
            .stockSnapshots(symbols: normalizedSymbols, feed: .iex),
            credentials: credentials
        )

        return normalizedSymbols.map { symbol in
            Self.marketSymbol(symbol: symbol, companyName: nil, snapshot: snapshots.snapshots[symbol])
        }
    }

    func fetchMostActiveMarketSymbols(top: Int, sort: MarketMostActiveSort, credentials: AlpacaCredentials) async throws -> [MarketActiveSymbol] {
        let response: AlpacaMostActivesResponse = try await marketDataRequest(
            .mostActiveStocks(top: top, sort: sort),
            credentials: credentials
        )
        return response.mostActives
    }

    func fetchWatchlists(credentials: AlpacaCredentials) async throws -> [AlpacaWatchlist] {
        try await request(.watchlists, credentials: credentials)
    }

    func fetchWatchlist(id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        try await request(.watchlist(id: id), credentials: credentials)
    }

    func createWatchlist(name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        let payload = AlpacaWatchlistRequest(name: name, symbols: normalizedSymbols(symbols))
        let data = try JSONEncoder().encode(payload)
        return try await request(.createWatchlist, body: data, credentials: credentials)
    }

    func updateWatchlist(id: String, name: String, symbols: [String], credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        let payload = AlpacaWatchlistRequest(name: name, symbols: normalizedSymbols(symbols))
        let data = try JSONEncoder().encode(payload)
        return try await request(.updateWatchlist(id: id), body: data, credentials: credentials)
    }

    func deleteWatchlist(id: String, credentials: AlpacaCredentials) async throws {
        let _: EmptyAPIResponse = try await request(.deleteWatchlist(id: id), credentials: credentials)
    }

    func addSymbol(_ symbol: String, toWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        let payload = AlpacaWatchlistAssetRequest(symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        let data = try JSONEncoder().encode(payload)
        return try await request(.addSymbolToWatchlist(id: id), body: data, credentials: credentials)
    }

    func removeSymbol(_ symbol: String, fromWatchlist id: String, credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        try await request(.watchlistSymbol(id: id, symbol: symbol), credentials: credentials)
    }

    func fetchPortfolioHistory(
        range: PortfolioHistoryRange,
        accountCreatedAt: String?,
        credentials: AlpacaCredentials
    ) async throws -> [PortfolioHistoryPoint] {
        let history: AlpacaPortfolioHistory = try await request(
            .portfolioHistory(range: range, accountCreatedAt: accountCreatedAt),
            credentials: credentials
        )
        return history.points()
    }

    func submitOrder(_ draft: OrderDraft, clientOrderID: String? = nil, credentials: AlpacaCredentials) async throws -> AlpacaOrder {
        let payload = try draft.requestPayload(clientOrderID: clientOrderID)
        let data = try JSONEncoder().encode(payload)
        return try await request(.submitOrder, body: data, credentials: credentials)
    }

    private func request<Response: Decodable & Sendable>(
        _ endpoint: AlpacaEndpoint,
        body: Data? = nil,
        credentials: AlpacaCredentials
    ) async throws -> Response {
        try await tradingClient.send(endpoint, body: body, credentials: credentials)
    }

    private func normalizedSymbols(_ symbols: [String]) -> [String] {
        var seenSymbols = Set<String>()
        return symbols.compactMap { symbol in
            let normalizedSymbol = Self.normalizedSymbol(symbol)
            guard !normalizedSymbol.isEmpty, !seenSymbols.contains(normalizedSymbol) else {
                return nil
            }

            seenSymbols.insert(normalizedSymbol)
            return normalizedSymbol
        }
    }

    private static func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func marketDataRequest<Response: Decodable & Sendable>(
        _ endpoint: AlpacaMarketDataEndpoint,
        credentials: AlpacaCredentials
    ) async throws -> Response {
        try await marketDataClient.send(endpoint, credentials: credentials)
    }

    private static func indexQuote(
        title: String,
        symbol: String,
        snapshot: AlpacaStockSnapshot?,
        latestBar: AlpacaMarketBar? = nil
    ) -> MarketIndexQuote {
        let price = validMarketPrice(
            latestBar?.close,
            snapshot?.latestTrade?.price,
            snapshot?.dailyBar?.close,
            snapshot?.minuteBar?.close
        )
        let previousClose = validMarketPrice(snapshot?.previousDailyBar?.close)
        let change: Double?
        let percentChange: Double?

        if let price, let previousClose {
            change = price - previousClose
            percentChange = previousClose == 0 ? nil : (price - previousClose) / previousClose
        } else {
            change = nil
            percentChange = nil
        }

        return MarketIndexQuote(
            id: symbol,
            title: title,
            symbol: symbol,
            price: price,
            change: change,
            percentChange: percentChange
        )
    }

    private static func validMarketPrice(_ values: Double?...) -> Double? {
        values.lazy.compactMap { value -> Double? in
            guard let value, value.isFinite, value > 0 else {
                return nil
            }
            return value
        }.first
    }

    private static func marketSymbol(
        symbol: String,
        companyName: String?,
        snapshot: AlpacaStockSnapshot?
    ) -> MarketActiveSymbol {
        let price = validMarketPrice(
            snapshot?.latestTrade?.price,
            snapshot?.dailyBar?.close,
            snapshot?.minuteBar?.close
        )
        let previousClose = validMarketPrice(snapshot?.previousDailyBar?.close)
        let change: Double?
        let percentChange: Double?

        if let price, let previousClose {
            change = price - previousClose
            percentChange = previousClose == 0 ? nil : (price - previousClose) / previousClose
        } else {
            change = nil
            percentChange = nil
        }

        return MarketActiveSymbol(
            symbol: symbol,
            companyName: companyName,
            price: price,
            change: change,
            percentChange: percentChange,
            volume: snapshot?.dailyBar?.volume,
            tradeCount: nil
        )
    }

    private static func marketCalendarDateString(daysAfter days: Int = 0, from timestamp: String?) -> String {
        let baseDate = AlpacaDateParser.date(timestamp) ?? Date()
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .day, value: days, to: baseDate) ?? baseDate
        return marketCalendarDateFormatter.string(from: date)
    }

    private func assetChartDataContext(
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials,
        allowsActiveSession: Bool = true,
        debugSymbol: String? = nil
    ) async throws -> AssetChartDataContext {
        let defaultFeed = Self.defaultMarketHoursFeed(from: feed)
        guard range == .oneDay else {
            return AssetChartDataContext(
                feed: defaultFeed,
                barsFeed: defaultFeed,
                interval: Self.stockDataInterval(for: range),
                emptyBarsFallbackInterval: nil,
                sessionProgress: nil
            )
        }

        let sessionContext = try await assetChartSessionContext(
            credentials: credentials,
            debugSymbol: debugSymbol ?? "session"
        )
        let referenceDate = sessionContext.referenceDate
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()

        if allowsActiveSession,
           let activeSession = sessionContext.activeSession,
           let activeInterval = MarketSessionSchedule.activeInterval(
            at: referenceDate,
            in: sessionContext.calendar,
            overnightDays: sessionContext.overnightCalendar
           ),
           activeInterval.session == activeSession {
            if activeInterval.session == .overnight {
                guard let latestSession = MarketSessionSchedule.latestRegularInterval(
                    before: referenceDate,
                    in: sessionContext.calendar,
                    overnightDays: sessionContext.overnightCalendar
                ) else {
                    throw APIClientError.invalidResponse
                }

                return AssetChartDataContext(
                    feed: .overnight,
                    barsFeed: defaultFeed,
                    interval: StockDataInterval(
                        start: formatter.string(from: latestSession.start),
                        end: formatter.string(from: latestSession.end)
                    ),
                    emptyBarsFallbackInterval: nil,
                    sessionProgress: MarketSessionSchedule.progress(
                        for: activeInterval,
                        in: sessionContext.calendar,
                        overnightDays: sessionContext.overnightCalendar,
                        at: referenceDate
                    )
                )
            }

            let emptyBarsFallbackInterval: StockDataInterval?
            if activeInterval.session.usesLatestRegularBarsFallback,
               let latestSession = MarketSessionSchedule.latestRegularInterval(
                before: referenceDate,
                in: sessionContext.calendar,
                overnightDays: sessionContext.overnightCalendar
               ) {
                emptyBarsFallbackInterval = StockDataInterval(
                    start: formatter.string(from: latestSession.start),
                    end: formatter.string(from: latestSession.end)
                )
            } else {
                emptyBarsFallbackInterval = nil
            }

            return AssetChartDataContext(
                feed: defaultFeed,
                barsFeed: defaultFeed,
                interval: StockDataInterval(
                    start: formatter.string(from: activeInterval.start),
                    end: formatter.string(from: referenceDate)
                ),
                emptyBarsFallbackInterval: emptyBarsFallbackInterval,
                sessionProgress: MarketSessionSchedule.progress(
                    for: activeInterval,
                    in: sessionContext.calendar,
                    overnightDays: sessionContext.overnightCalendar,
                    at: referenceDate
                )
            )
        }

        guard let latestSession = MarketSessionSchedule.latestRegularInterval(
            before: referenceDate,
            in: sessionContext.calendar,
            overnightDays: sessionContext.overnightCalendar
        ) else {
            throw APIClientError.invalidResponse
        }

        return AssetChartDataContext(
            feed: defaultFeed,
            barsFeed: defaultFeed,
            interval: StockDataInterval(
                start: formatter.string(from: latestSession.start),
                end: formatter.string(from: latestSession.end)
            ),
            emptyBarsFallbackInterval: nil,
            sessionProgress: MarketSessionSchedule.progress(
                for: latestSession,
                in: sessionContext.calendar,
                overnightDays: sessionContext.overnightCalendar,
                at: referenceDate
            )
        )
    }

    private func currentStockDataContext(
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> CurrentStockDataContext {
        let defaultFeed = Self.defaultMarketHoursFeed(from: feed)
        let sessionContext = try await assetChartSessionContext(
            credentials: credentials,
            debugSymbol: "current"
        )
        guard let activeSession = sessionContext.activeSession else {
            return CurrentStockDataContext(feed: defaultFeed, activeSession: nil)
        }

        guard let activeInterval = MarketSessionSchedule.activeInterval(
            at: sessionContext.referenceDate,
            in: sessionContext.calendar,
            overnightDays: sessionContext.overnightCalendar
        ),
              activeInterval.session == activeSession else {
            return CurrentStockDataContext(feed: defaultFeed, activeSession: nil)
        }

        return CurrentStockDataContext(
            feed: activeInterval.session == .overnight ? .overnight : defaultFeed,
            activeSession: activeInterval.session
        )
    }

    private func assetChartSessionContext(
        credentials: AlpacaCredentials,
        debugSymbol: String
    ) async throws -> AssetChartSessionContext {
        let cacheKey = AssetChartSessionContextCacheKey(environment: credentials.environment.rawValue)
        if let cachedContext = await Self.assetChartSessionContextCache.value(
            for: cacheKey,
            maxAge: Self.assetChartSessionContextCacheTTL
        ) {
            Self.debugAssetDetailLatency(
                "sessionContext.cacheHit",
                symbol: debugSymbol,
                range: .oneDay,
                feed: .iex,
                startedAt: cachedContext.cachedAt
            )
            return cachedContext.context
        }

        let clockResponse: AlpacaMarketClockResponse = try await timedAssetDetailStage(
            "clock",
            symbol: debugSymbol,
            range: .oneDay,
            feed: .iex
        ) {
            try await request(.marketClock, credentials: credentials)
        }
        let clock = try clockResponse.clock(market: "NYSE")
        let referenceDate = AlpacaDateParser.date(clock.timestamp) ?? Date()
        let calendarStart = Self.marketCalendarDateString(daysAfter: -14, from: clock.timestamp)
        let calendarEnd = Self.marketCalendarDateString(daysAfter: 7, from: clock.timestamp)

        async let calendarResponseRequest: AlpacaMarketCalendarResponse = timedAssetDetailStage(
            "calendar",
            symbol: debugSymbol,
            range: .oneDay,
            feed: .iex
        ) {
            try await request(
                .marketCalendar(
                    market: "NYSE",
                    start: calendarStart,
                    end: calendarEnd
                ),
                credentials: credentials
            )
        }
        async let overnightCalendarRequest = timedAssetDetailStage(
            "overnightCalendar",
            symbol: debugSymbol,
            range: .oneDay,
            feed: .overnight
        ) {
            await fetchOvernightMarketCalendar(
                start: calendarStart,
                end: calendarEnd,
                credentials: credentials
            )
        }

        let calendarResponse = try await calendarResponseRequest
        let sessionContext = AssetChartSessionContext(
            referenceDate: referenceDate,
            activeSession: clock.activeSession,
            calendar: calendarResponse.calendar,
            overnightCalendar: await overnightCalendarRequest
        )
        await Self.assetChartSessionContextCache.store(sessionContext, for: cacheKey)
        return sessionContext
    }

    private func timedAssetDetailStage<Value: Sendable>(
        _ stage: String,
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        operation: () async throws -> Value
    ) async throws -> Value {
        let startedAt = Date()
        do {
            let value = try await operation()
            Self.debugAssetDetailLatency(
                stage,
                symbol: symbol,
                range: range,
                feed: feed,
                startedAt: startedAt
            )
            return value
        } catch {
            Self.debugAssetDetailLatency(
                "\(stage).failed",
                symbol: symbol,
                range: range,
                feed: feed,
                startedAt: startedAt,
                extra: error.localizedDescription
            )
            throw error
        }
    }

    private func timedAssetDetailStage<Value: Sendable>(
        _ stage: String,
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        operation: () async -> Value
    ) async -> Value {
        let startedAt = Date()
        let value = await operation()
        Self.debugAssetDetailLatency(
            stage,
            symbol: symbol,
            range: range,
            feed: feed,
            startedAt: startedAt
        )
        return value
    }

    private static func debugAssetDetailLatency(
        _ stage: String,
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed,
        startedAt: Date,
        extra: String? = nil
    ) {
        #if DEBUG
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        let suffix = extra.map { " \($0)" } ?? ""
        logger.debug("asset detail load symbol=\(symbol, privacy: .public) range=\(range.title, privacy: .public) feed=\(feed.rawValue, privacy: .public) stage=\(stage, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)\(suffix, privacy: .public)")
        #endif
    }

    private static func defaultMarketHoursFeed(from feed: AlpacaMarketDataFeed) -> AlpacaMarketDataFeed {
        switch feed {
        case .boats, .overnight:
            .iex
        default:
            feed
        }
    }

    private static func stockDataInterval(for range: AssetChartRange, now: Date = Date()) -> StockDataInterval {
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()
        return StockDataInterval(
            start: formatter.string(from: range.startDate(now: now)),
            end: formatter.string(from: now)
        )
    }

    private static func optionDataInterval(for range: AssetChartRange, now: Date = Date()) -> StockDataInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let delayedEnd = now.addingTimeInterval(-Self.optionHistoricalDataDelay)
        let earliest = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1)) ?? delayedEnd
        let requestedStart = range.startDate(now: delayedEnd)
        let start = max(requestedStart, earliest)
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()

        return StockDataInterval(
            start: formatter.string(from: start),
            end: formatter.string(from: delayedEnd)
        )
    }

    private static func yearToDateBaselineInterval(now: Date = Date()) -> StockDataInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        let year = calendar.component(.year, from: now)
        let yearStart = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: 1,
                day: 1
            )
        ) ?? now
        let start = calendar.date(byAdding: .day, value: -31, to: yearStart) ?? yearStart
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()

        return StockDataInterval(
            start: formatter.string(from: start),
            end: formatter.string(from: yearStart)
        )
    }

    private static let marketCalendarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}


private struct AssetChartDataContext: Sendable {
    let feed: AlpacaMarketDataFeed
    let barsFeed: AlpacaMarketDataFeed
    let interval: StockDataInterval
    let emptyBarsFallbackInterval: StockDataInterval?
    let sessionProgress: MarketSessionProgress?
}

private struct CurrentStockDataContext: Sendable {
    let feed: AlpacaMarketDataFeed
    let activeSession: MarketSessionKind?
}

private struct AssetChartSessionContext: Sendable {
    let referenceDate: Date
    let activeSession: MarketSessionKind?
    let calendar: [AlpacaCalendarDay]
    let overnightCalendar: [AlpacaCalendarDay]
}

private struct AssetChartSessionContextCacheKey: Hashable, Sendable {
    let environment: String
}

private struct AssetChartSessionContextCacheEntry: Sendable {
    let context: AssetChartSessionContext
    let cachedAt: Date
}

private actor AssetChartSessionContextCache {
    private var entries: [AssetChartSessionContextCacheKey: AssetChartSessionContextCacheEntry] = [:]

    func value(
        for key: AssetChartSessionContextCacheKey,
        maxAge: TimeInterval
    ) -> AssetChartSessionContextCacheEntry? {
        guard let entry = entries[key] else {
            return nil
        }

        guard Date().timeIntervalSince(entry.cachedAt) <= maxAge else {
            entries.removeValue(forKey: key)
            return nil
        }

        return entry
    }

    func store(_ context: AssetChartSessionContext, for key: AssetChartSessionContextCacheKey) {
        entries[key] = AssetChartSessionContextCacheEntry(context: context, cachedAt: Date())
    }
}
