import Foundation

protocol AlpacaServicing: Sendable {
    func testConnection(credentials: AlpacaCredentials) async throws
    func fetchAccount(credentials: AlpacaCredentials) async throws -> AlpacaAccount
    func fetchAccountActivities(pageSize: Int, pageToken: String?, credentials: AlpacaCredentials) async throws -> AlpacaAccountActivitiesPage
    func fetchPositions(credentials: AlpacaCredentials) async throws -> [AlpacaPosition]
    func fetchOpenPosition(symbolOrAssetID: String, credentials: AlpacaCredentials) async throws -> AlpacaPosition?
    func fetchRecentOrders(credentials: AlpacaCredentials) async throws -> [AlpacaOrder]
    func fetchOrder(id: String, nested: Bool, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func cancelOrder(id: String, credentials: AlpacaCredentials) async throws
    func replaceOrder(id: String, request: AlpacaReplaceOrderRequest, credentials: AlpacaCredentials) async throws -> AlpacaOrder
    func fetchMarketOverview(credentials: AlpacaCredentials) async throws -> MarketOverview
    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) async throws -> [MarketIndexQuote]
    func fetchMarketCalendar(market: String, start: String, end: String, credentials: AlpacaCredentials) async throws -> [AlpacaCalendarDay]
    func fetchMarketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset]
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

struct AlpacaClient: AlpacaServicing {
    private static let marketDataBaseURL = URL(string: "https://data.alpaca.markets")!
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

    private let apiClient: any APIClient

    init(apiClient: any APIClient = URLSessionAPIClient()) {
        self.apiClient = apiClient
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

    func fetchMarketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        try await request(.assets, credentials: credentials)
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
        async let assetRequest = fetchAsset(symbolOrAssetID: normalizedSymbol, credentials: credentials)
        let chartContext = try await assetChartDataContext(range: range, feed: feed, credentials: credentials)
        async let barsResultRequest = fetchStockBarsResult(
            symbol: normalizedSymbol,
            range: range,
            context: chartContext,
            credentials: credentials
        )
        async let chartBaselineRequest = fetchChartBaselineClose(
            symbol: normalizedSymbol,
            range: range,
            feed: chartContext.barsFeed,
            credentials: credentials
        )
        async let snapshotRequest = fetchAssetDetailSnapshot(
            symbol: normalizedSymbol,
            feed: chartContext.feed,
            credentials: credentials
        )
        async let latestBarRequest = try? fetchLatestStockBar(
            symbol: normalizedSymbol,
            feed: chartContext.feed,
            credentials: credentials
        )

        let barsResult = try await barsResultRequest
        return try await AssetDetailSnapshot(
            asset: assetRequest,
            stockSnapshot: snapshotRequest,
            bars: barsResult.bars,
            chartBaseline: chartBaselineRequest,
            range: range,
            feed: chartContext.feed,
            sessionProgress: barsResult.context.sessionProgress,
            latestBar: latestBarRequest
        )
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

        let response: AlpacaOptionBarsResponse = try await marketDataRequest(
            .optionBars(
                symbol: normalizedSymbol,
                range: range,
                feed: feed,
                interval: Self.optionDataInterval(for: range),
                limit: min(max(limit, 1), 10_000),
                pageToken: pageToken,
                sort: sort
            ),
            credentials: credentials
        )

        return AlpacaOptionBarsPage(
            bars: response.bars[normalizedSymbol] ?? [],
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
        let bars = try await fetchStockBars(
            symbol: symbol,
            range: range,
            feed: context.barsFeed,
            interval: context.interval,
            credentials: credentials
        )
        if range == .oneDay,
           bars.count < 2,
           let fallbackInterval = context.emptyBarsFallbackInterval {
            let fallbackBars = try await fetchStockBars(
                symbol: symbol,
                range: range,
                feed: context.barsFeed,
                interval: fallbackInterval,
                credentials: credentials
            )
            if !fallbackBars.isEmpty {
                return (fallbackBars + bars, context)
            }
        }
        return (bars, context)
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
        return try await apiClient.send(
            APIRequest(
                baseURL: credentials.environment.baseURL,
                path: endpoint.path,
                method: endpoint.method,
                queryItems: endpoint.queryItems,
                body: body,
                requestInterceptors: [
                    AlpacaAuthenticationInterceptor(credentials: credentials)
                ],
                responseInterceptors: [
                    AlpacaErrorResponseInterceptor()
                ]
            )
        )
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
        return try await apiClient.send(
            APIRequest(
                baseURL: Self.marketDataBaseURL,
                path: endpoint.path,
                method: .get,
                queryItems: endpoint.queryItems,
                requestInterceptors: [
                    AlpacaAuthenticationInterceptor(credentials: credentials)
                ],
                responseInterceptors: [
                    AlpacaErrorResponseInterceptor()
                ]
            )
        )
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
        allowsActiveSession: Bool = true
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

        let clockResponse: AlpacaMarketClockResponse = try await request(.marketClock, credentials: credentials)
        let clock = try clockResponse.clock(market: "NYSE")
        let referenceDate = AlpacaDateParser.date(clock.timestamp) ?? Date()
        let calendarStart = Self.marketCalendarDateString(daysAfter: -14, from: clock.timestamp)
        let calendarEnd = Self.marketCalendarDateString(daysAfter: 7, from: clock.timestamp)
        let calendarResponse: AlpacaMarketCalendarResponse = try await request(
            .marketCalendar(
                market: "NYSE",
                start: calendarStart,
                end: calendarEnd
            ),
            credentials: credentials
        )
        let overnightCalendar = await fetchOvernightMarketCalendar(
            start: calendarStart,
            end: calendarEnd,
            credentials: credentials
        )
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()

        if allowsActiveSession,
           let activeInterval = MarketSessionSchedule.activeInterval(
            at: referenceDate,
            in: calendarResponse.calendar,
            overnightDays: overnightCalendar
           ) {
            if activeInterval.session == .overnight {
                guard let latestSession = MarketSessionSchedule.latestRegularInterval(
                    before: referenceDate,
                    in: calendarResponse.calendar,
                    overnightDays: overnightCalendar
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
                        in: calendarResponse.calendar,
                        overnightDays: overnightCalendar,
                        at: referenceDate
                    )
                )
            }

            let emptyBarsFallbackInterval: StockDataInterval?
            if activeInterval.session == .preMarket,
               let latestSession = MarketSessionSchedule.latestRegularInterval(
                before: referenceDate,
                in: calendarResponse.calendar,
                overnightDays: overnightCalendar
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
                    in: calendarResponse.calendar,
                    overnightDays: overnightCalendar,
                    at: referenceDate
                )
            )
        }

        guard let latestSession = MarketSessionSchedule.latestRegularInterval(
            before: referenceDate,
            in: calendarResponse.calendar,
            overnightDays: overnightCalendar
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
            sessionProgress: nil
        )
    }

    private func currentStockDataContext(
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) async throws -> CurrentStockDataContext {
        let defaultFeed = Self.defaultMarketHoursFeed(from: feed)
        let clockResponse: AlpacaMarketClockResponse = try await request(.marketClock, credentials: credentials)
        let clock = try clockResponse.clock(market: "NYSE")
        let referenceDate = AlpacaDateParser.date(clock.timestamp) ?? Date()
        let calendarStart = Self.marketCalendarDateString(daysAfter: -14, from: clock.timestamp)
        let calendarEnd = Self.marketCalendarDateString(daysAfter: 7, from: clock.timestamp)
        let calendarResponse: AlpacaMarketCalendarResponse = try await request(
            .marketCalendar(
                market: "NYSE",
                start: calendarStart,
                end: calendarEnd
            ),
            credentials: credentials
        )
        let overnightCalendar = await fetchOvernightMarketCalendar(
            start: calendarStart,
            end: calendarEnd,
            credentials: credentials
        )

        guard let activeInterval = MarketSessionSchedule.activeInterval(
            at: referenceDate,
            in: calendarResponse.calendar,
            overnightDays: overnightCalendar
        ) else {
            return CurrentStockDataContext(feed: defaultFeed, activeSession: nil)
        }

        return CurrentStockDataContext(
            feed: activeInterval.session == .overnight ? .overnight : defaultFeed,
            activeSession: activeInterval.session
        )
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
        let earliest = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1)) ?? now
        let requestedStart = range.startDate(now: now)
        let start = max(requestedStart, earliest)
        let formatter = AlpacaMarketDataEndpoint.makeStockDataDateFormatter()

        return StockDataInterval(
            start: formatter.string(from: start),
            end: formatter.string(from: now)
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

private enum AlpacaEndpoint: Sendable {
    case account
    case accountActivities(pageSize: Int, pageToken: String?)
    case assets
    case asset(symbolOrAssetID: String)
    case marketClock
    case marketCalendar(market: String, start: String, end: String)
    case optionContracts(underlyingSymbol: String, expirationDateGTE: String?, expirationDateLTE: String?, limit: Int, pageToken: String?)
    case positions
    case position(symbolOrAssetID: String)
    case recentOrders
    case order(id: String, nested: Bool)
    case cancelOrder(id: String)
    case replaceOrder(id: String)
    case watchlists
    case createWatchlist
    case watchlist(id: String)
    case updateWatchlist(id: String)
    case deleteWatchlist(id: String)
    case addSymbolToWatchlist(id: String)
    case watchlistSymbol(id: String, symbol: String)
    case portfolioHistory(range: PortfolioHistoryRange, accountCreatedAt: String?)
    case submitOrder

    var path: String {
        switch self {
        case .account:
            "v2/account"
        case .accountActivities:
            "v2/account/activities"
        case .assets:
            "v2/assets"
        case .asset(let symbolOrAssetID):
            "v2/assets/\(Self.encodedPathSegment(symbolOrAssetID))"
        case .marketClock:
            "v3/clock"
        case .marketCalendar(let market, _, _):
            "v3/calendar/\(Self.encodedPathSegment(market))"
        case .optionContracts:
            "v2/options/contracts"
        case .positions:
            "v2/positions"
        case .position(let symbolOrAssetID):
            "v2/positions/\(Self.encodedPathSegment(symbolOrAssetID))"
        case .recentOrders, .submitOrder:
            "v2/orders"
        case .order(let id, _), .cancelOrder(let id), .replaceOrder(let id):
            "v2/orders/\(Self.encodedPathSegment(id))"
        case .watchlists, .createWatchlist:
            "v2/watchlists"
        case .watchlist(let id), .updateWatchlist(let id), .deleteWatchlist(let id), .addSymbolToWatchlist(let id):
            "v2/watchlists/\(id)"
        case .watchlistSymbol(let id, let symbol):
            "v2/watchlists/\(id)/\(symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
        case .portfolioHistory:
            "v2/account/portfolio/history"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .submitOrder, .createWatchlist, .addSymbolToWatchlist:
            .post
        case .replaceOrder:
            .patch
        case .updateWatchlist:
            .put
        case .deleteWatchlist, .watchlistSymbol, .cancelOrder:
            .delete
        default:
            .get
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .accountActivities(let pageSize, let pageToken):
            var items = [
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "page_size", value: String(pageSize))
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .assets:
            return [
                URLQueryItem(name: "status", value: "active"),
                URLQueryItem(name: "asset_class", value: "us_equity")
            ]
        case .marketClock:
            return [
                URLQueryItem(name: "markets", value: "NYSE,NASDAQ")
            ]
        case .marketCalendar(_, let start, let end):
            return [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end)
            ]
        case .optionContracts(let underlyingSymbol, let expirationDateGTE, let expirationDateLTE, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "underlying_symbols", value: underlyingSymbol),
                URLQueryItem(name: "status", value: "active"),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let expirationDateGTE, !expirationDateGTE.isEmpty {
                items.append(URLQueryItem(name: "expiration_date_gte", value: expirationDateGTE))
            }

            if let expirationDateLTE, !expirationDateLTE.isEmpty {
                items.append(URLQueryItem(name: "expiration_date_lte", value: expirationDateLTE))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .recentOrders:
            return [
                URLQueryItem(name: "status", value: "all"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "direction", value: "desc")
            ]
        case .order(_, let nested):
            return nested ? [URLQueryItem(name: "nested", value: "true")] : []
        case .portfolioHistory(let range, let accountCreatedAt):
            return range.queryItems(accountCreatedAt: accountCreatedAt)
        default:
            return []
        }
    }

    private static func encodedPathSegment(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? trimmedValue
    }
}

private enum AlpacaMarketDataEndpoint: Sendable {
    case stockSnapshots(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockLatestTrade(symbol: String, feed: AlpacaMarketDataFeed)
    case stockLatestQuotes(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockLatestBars(symbols: [String], feed: AlpacaMarketDataFeed)
    case stockQuotes(symbol: String, feed: AlpacaMarketDataFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case stockBars(symbol: String, range: AssetChartRange, feed: AlpacaMarketDataFeed, interval: StockDataInterval?)
    case optionChain(underlyingSymbol: String, feed: AlpacaOptionFeed, type: AlpacaOptionContractType?, expirationDate: String?, limit: Int, pageToken: String?)
    case optionSnapshots(symbols: [String], feed: AlpacaOptionFeed, limit: Int, pageToken: String?)
    case optionBars(symbol: String, range: AssetChartRange, feed: AlpacaOptionFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case optionTrades(symbol: String, feed: AlpacaOptionFeed, interval: StockDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection)
    case optionLatestTrades(symbols: [String], feed: AlpacaOptionFeed)
    case news(symbols: [String], interval: NewsDataInterval, limit: Int, pageToken: String?, sort: AlpacaSortDirection, includeContent: Bool)
    case stockMovers(top: Int)
    case mostActiveStocks(top: Int, sort: MarketMostActiveSort)

    var path: String {
        switch self {
        case .stockSnapshots:
            "v2/stocks/snapshots"
        case .stockLatestTrade(let symbol, _):
            "v2/stocks/\(Self.encodedPathSegment(symbol))/trades/latest"
        case .stockLatestQuotes:
            "v2/stocks/quotes/latest"
        case .stockLatestBars:
            "v2/stocks/bars/latest"
        case .stockQuotes:
            "v2/stocks/quotes"
        case .stockBars:
            "v2/stocks/bars"
        case .optionChain(let underlyingSymbol, _, _, _, _, _):
            "v1beta1/options/snapshots/\(Self.encodedPathSegment(underlyingSymbol))"
        case .optionSnapshots:
            "v1beta1/options/snapshots"
        case .optionBars:
            "v1beta1/options/bars"
        case .optionTrades:
            "v1beta1/options/trades"
        case .optionLatestTrades:
            "v1beta1/options/trades/latest"
        case .news:
            "v1beta1/news"
        case .stockMovers:
            "v1beta1/screener/stocks/movers"
        case .mostActiveStocks:
            "v1beta1/screener/stocks/most-actives"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .stockSnapshots(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestTrade(_, let feed):
            return [
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestQuotes(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockLatestBars(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "currency", value: "USD")
            ]
        case .stockQuotes(let symbol, let feed, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "feed", value: Self.quotesFeedValue(feed)),
                URLQueryItem(name: "currency", value: "USD"),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .stockBars(let symbol, let range, let feed, let intervalOverride):
            let interval = intervalOverride ?? Self.dateInterval(for: range)
            return [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "timeframe", value: range.timeframe),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(range.requestLimit)),
                URLQueryItem(name: "adjustment", value: "all"),
                URLQueryItem(name: "feed", value: Self.barsFeedValue(feed)),
                URLQueryItem(name: "currency", value: "USD"),
                URLQueryItem(name: "sort", value: "asc")
            ]
        case .optionChain(_, let feed, let type, let expirationDate, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let type {
                items.append(URLQueryItem(name: "type", value: type.rawValue))
            }

            if let expirationDate, !expirationDate.isEmpty {
                items.append(URLQueryItem(name: "expiration_date", value: expirationDate))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionSnapshots(let symbols, let feed, let limit, let pageToken):
            var items = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionBars(let symbol, let range, let feed, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "timeframe", value: range.timeframe),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionTrades(let symbol, let feed, let interval, let limit, let pageToken, let sort):
            var items = [
                URLQueryItem(name: "symbols", value: symbol),
                URLQueryItem(name: "start", value: interval.start),
                URLQueryItem(name: "end", value: interval.end),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "feed", value: feed.rawValue),
                URLQueryItem(name: "sort", value: sort.rawValue)
            ]

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .optionLatestTrades(let symbols, let feed):
            return [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "feed", value: feed.rawValue)
            ]
        case .news(let symbols, let interval, let limit, let pageToken, let sort, let includeContent):
            var items = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort.rawValue),
                URLQueryItem(name: "include_content", value: includeContent ? "true" : "false")
            ]

            if let start = interval.start, !start.isEmpty {
                items.append(URLQueryItem(name: "start", value: start))
            }

            if let end = interval.end, !end.isEmpty {
                items.append(URLQueryItem(name: "end", value: end))
            }

            if let pageToken, !pageToken.isEmpty {
                items.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            return items
        case .stockMovers(let top):
            return [
                URLQueryItem(name: "top", value: String(top))
            ]
        case .mostActiveStocks(let top, let sort):
            return [
                URLQueryItem(name: "by", value: sort.rawValue),
                URLQueryItem(name: "top", value: String(top))
            ]
        }
    }

    private static func barsFeedValue(_ feed: AlpacaMarketDataFeed) -> String {
        switch feed {
        case .delayedSIP:
            "sip"
        case .overnight:
            "boats"
        default:
            feed.rawValue
        }
    }

    private static func quotesFeedValue(_ feed: AlpacaMarketDataFeed) -> String {
        switch feed {
        case .delayedSIP:
            "sip"
        case .overnight:
            "iex"
        default:
            feed.rawValue
        }
    }

    private static func encodedPathSegment(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? trimmedValue
    }

    private static func dateInterval(for range: AssetChartRange, now: Date = Date()) -> StockDataInterval {
        let startDate = range.startDate(now: now)
        let formatter = makeStockDataDateFormatter()
        return StockDataInterval(
            start: formatter.string(from: startDate),
            end: formatter.string(from: now)
        )
    }

    static func makeStockDataDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private struct StockDataInterval: Sendable {
    let start: String
    let end: String
}

private struct NewsDataInterval: Sendable {
    let start: String?
    let end: String?
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

private struct AlpacaAuthenticationInterceptor: APIRequestInterceptor {
    let credentials: AlpacaCredentials

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue(credentials.keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }
}

private struct AlpacaErrorResponseInterceptor: APIResponseInterceptor {
    func intercept(_ context: APIResponseContext) async throws -> APIResponseContext {
        guard !(200..<300).contains(context.response.statusCode) else {
            return context
        }

        if let alpacaError = try? JSONDecoder().decode(AlpacaErrorResponse.self, from: context.data),
           let message = alpacaError.resolvedMessage {
            throw APIClientError.requestFailed(statusCode: context.response.statusCode, message: message)
        }

        return context
    }
}

private struct AlpacaErrorResponse: Decodable {
    let code: String?
    let message: String?

    var resolvedMessage: String? {
        APIErrorMessageSanitizer.displayMessage(message ?? code)
    }
}
