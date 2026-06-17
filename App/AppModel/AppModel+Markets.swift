import Foundation

extension AppModel {
    func refreshFavoriteMarketSymbols(forceReload: Bool = true) async {
        guard let credentials else {
            resetFavoriteMarketSymbols()
            return
        }

        isLoadingFavoriteMarketSymbols = true
        defer { isLoadingFavoriteMarketSymbols = false }

        do {
            if forceReload {
                favoritesWatchlist = nil
            }

            let watchlist = try await ensureFavoritesWatchlist(credentials: credentials)
            updateFavoriteMarketSymbols(from: watchlist)
            await hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: credentials)
            await refreshFavoriteMarketQuotes(credentials: credentials)
            favoriteMarketSymbolsError = nil
        } catch where error.isRequestCancellation {
            favoriteMarketSymbolsError = nil
            return
        } catch {
            favoriteMarketSymbolsError = APIErrorDisplayMessage.message(for: error, locale: appLanguage.locale)
        }
    }

    func toggleFavoriteMarketSymbol(_ symbol: String) async {
        guard let credentials else {
            lastError = L10n.Credentials.apiKeyRequired(locale: appLanguage.locale)
            return
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return
        }

        let previousSymbols = favoriteMarketSymbols
        let previousAssetsBySymbol = favoriteMarketAssetBySymbol
        let previousQuotesBySymbol = favoriteMarketQuotesBySymbol

        do {
            let watchlist = try await ensureFavoritesWatchlist(credentials: credentials)
            let updatedWatchlist: AlpacaWatchlist

            if let index = favoriteMarketSymbols.firstIndex(of: normalizedSymbol) {
                favoriteMarketSymbols.remove(at: index)
                favoriteMarketAssetBySymbol.removeValue(forKey: normalizedSymbol)
                favoriteMarketQuotesBySymbol.removeValue(forKey: normalizedSymbol)
                updatedWatchlist = try await services.alpaca.removeSymbol(normalizedSymbol, fromWatchlist: watchlist.id, credentials: credentials)
            } else {
                favoriteMarketSymbols.append(normalizedSymbol)
                updatedWatchlist = try await services.alpaca.addSymbol(normalizedSymbol, toWatchlist: watchlist.id, credentials: credentials)
            }

            favoritesWatchlist = updatedWatchlist
            updateFavoriteMarketSymbols(from: updatedWatchlist)
            await hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: credentials)
            await refreshFavoriteMarketQuotes(credentials: credentials)
            favoriteMarketSymbolsError = nil
            lastError = nil
        } catch where error.isRequestCancellation {
            favoriteMarketSymbols = previousSymbols
            favoriteMarketAssetBySymbol = previousAssetsBySymbol
            favoriteMarketQuotesBySymbol = previousQuotesBySymbol
            favoriteMarketSymbolsError = nil
        } catch {
            favoriteMarketSymbols = previousSymbols
            favoriteMarketAssetBySymbol = previousAssetsBySymbol
            favoriteMarketQuotesBySymbol = previousQuotesBySymbol
            let message = APIErrorDisplayMessage.message(for: error, locale: appLanguage.locale)
            favoriteMarketSymbolsError = message
            lastError = message
        }
    }

    func fetchMarketOverview() async throws -> MarketOverview {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let overview = try await services.alpaca.fetchMarketOverview(credentials: credentials)
        cachedMarketOverview = overview
        return overview
    }

    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed = .iex) async throws -> [MarketIndexQuote] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchMarketIndexQuotes(feed: feed, credentials: credentials)
    }

    func fetchAssetDetailSnapshot(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed = .iex
    ) async throws -> AssetDetailSnapshot {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchAssetDetail(
            symbol: symbol,
            range: range,
            feed: feed,
            credentials: credentials
        )
    }

    func fetchAssetSnapshot(symbol: String, feed: AlpacaMarketDataFeed = .iex) async throws -> AlpacaStockSnapshot? {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        if feed == .overnight {
            return try await fetchResolvedAssetSnapshot(symbol: symbol, feed: feed).snapshot
        }

        return try await services.alpaca.fetchStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
    }

    func fetchResolvedAssetSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex
    ) async throws -> AlpacaResolvedStockSnapshot {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchCurrentStockSnapshot(
            symbol: symbol,
            feed: feed,
            credentials: credentials
        )
    }

    func fetchLatestStockBar(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex
    ) async throws -> AlpacaMarketBar? {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchLatestStockBar(
            symbol: symbol,
            feed: feed,
            credentials: credentials
        )
    }

    func fetchHistoricalStockQuotes(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        start: Date,
        end: Date,
        limit: Int = 500,
        pageToken: String? = nil,
        sort: AlpacaSortDirection = .desc
    ) async throws -> AlpacaStockQuotesPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchHistoricalStockQuotes(
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

    func fetchAssetOptionChain(
        symbol: String,
        type: AlpacaOptionContractType? = nil,
        expirationDate: String? = nil,
        limit: Int = 250,
        pageToken: String? = nil,
        forceReload: Bool = false
    ) async throws -> AlpacaOptionChainPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionChainPage(snapshots: [], nextPageToken: nil)
        }

        let resolvedLimit = min(max(limit, 1), 1000)
        let cacheKey = OptionChainPageCacheKey(
            symbol: normalizedSymbol,
            type: type,
            expirationDate: expirationDate,
            limit: resolvedLimit,
            pageToken: pageToken
        )

        if !forceReload,
           let cachedEntry = optionChainPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionChainPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.alpaca.fetchOptionChain(
            symbol: normalizedSymbol,
            feed: .indicative,
            type: type,
            expirationDate: expirationDate,
            limit: resolvedLimit,
            pageToken: pageToken,
            credentials: credentials
        )
        optionChainPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
        return page
    }

    func fetchAssetOptionExpirations(
        symbol: String,
        forceReload: Bool = false
    ) async throws -> [String] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return []
        }

        let startDate = Self.optionExpirationDateString()
        let endDate = Self.optionExpirationDateString(daysAfter: Self.optionExpirationHorizonDays)
        let cacheKey = OptionExpirationCacheKey(
            symbol: normalizedSymbol,
            startDate: startDate,
            endDate: endDate
        )

        if !forceReload,
           let cachedEntry = optionExpirationCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionExpirationCacheTTL {
            return cachedEntry.value
        }

        var expirations = Set<String>()
        var pageToken: String?

        repeat {
            let page = try await services.alpaca.fetchOptionContracts(
                symbol: normalizedSymbol,
                expirationDateGTE: startDate,
                expirationDateLTE: endDate,
                limit: Self.optionExpirationPageSize,
                pageToken: pageToken,
                credentials: credentials
            )

            for contract in page.contracts {
                if let expirationDate = contract.expirationDate, !expirationDate.isEmpty {
                    expirations.insert(expirationDate)
                }
            }

            pageToken = page.nextPageToken
        } while pageToken != nil

        let sortedExpirations = expirations.sorted()
        optionExpirationCache[cacheKey] = TimedCacheEntry(
            value: sortedExpirations,
            cachedAt: Date()
        )
        return sortedExpirations
    }

    func fetchOptionSnapshot(
        symbol: String,
        forceReload: Bool = false
    ) async throws -> AlpacaOptionSnapshot? {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let cacheKey = OptionSnapshotCacheKey(symbol: normalizedSymbol)
        if !forceReload,
           let cachedEntry = optionSnapshotCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionSnapshotCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.alpaca.fetchOptionSnapshots(
            symbols: [normalizedSymbol],
            feed: .indicative,
            limit: 1,
            pageToken: nil,
            credentials: credentials
        )
        let snapshot = page.snapshots.first { $0.contractSymbol == normalizedSymbol } ?? page.snapshots.first
        optionSnapshotCache[cacheKey] = TimedCacheEntry(value: snapshot, cachedAt: Date())
        return snapshot
    }

    func fetchLatestOptionTrade(
        symbol: String,
        forceReload: Bool = false
    ) async throws -> AlpacaOptionTrade? {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        let cacheKey = OptionLatestTradeCacheKey(symbol: normalizedSymbol)
        if !forceReload,
           let cachedEntry = optionLatestTradeCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionLatestTradeCacheTTL {
            return cachedEntry.value
        }

        let trades = try await services.alpaca.fetchLatestOptionTrades(
            symbols: [normalizedSymbol],
            feed: .indicative,
            credentials: credentials
        )
        let trade = trades[normalizedSymbol] ?? trades.values.first
        optionLatestTradeCache[cacheKey] = TimedCacheEntry(value: trade, cachedAt: Date())
        return trade
    }

    func fetchOptionBars(
        symbol: String,
        range: AssetChartRange,
        limit: Int = 10_000,
        pageToken: String? = nil,
        forceReload: Bool = false
    ) async throws -> AlpacaOptionBarsPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionBarsPage(bars: [], nextPageToken: nil)
        }

        let resolvedLimit = min(max(limit, 1), 10_000)
        let cacheKey = OptionBarsPageCacheKey(
            symbol: normalizedSymbol,
            range: range,
            limit: resolvedLimit,
            pageToken: pageToken
        )

        if !forceReload,
           let cachedEntry = optionBarsPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionBarsPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.alpaca.fetchOptionBars(
            symbol: normalizedSymbol,
            range: range,
            feed: .indicative,
            limit: resolvedLimit,
            pageToken: pageToken,
            sort: .asc,
            credentials: credentials
        )
        optionBarsPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
        return page
    }

    func fetchOptionTrades(
        symbol: String,
        range: AssetChartRange,
        limit: Int = 100,
        pageToken: String? = nil,
        forceReload: Bool = false
    ) async throws -> AlpacaOptionTradesPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaOptionTradesPage(trades: [], nextPageToken: nil)
        }

        let resolvedLimit = min(max(limit, 1), 500)
        let cacheKey = OptionTradesPageCacheKey(
            symbol: normalizedSymbol,
            range: range,
            limit: resolvedLimit,
            pageToken: pageToken
        )

        if !forceReload,
           let cachedEntry = optionTradesPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionTradesPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.alpaca.fetchOptionTrades(
            symbol: normalizedSymbol,
            range: range,
            feed: .indicative,
            limit: resolvedLimit,
            pageToken: pageToken,
            sort: .desc,
            credentials: credentials
        )
        optionTradesPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
        return page
    }

    func fetchAssetNews(
        symbol: String,
        start: Date,
        limit: Int = 50,
        pageToken: String? = nil,
        forceReload: Bool = false
    ) async throws -> AlpacaNewsPage {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return AlpacaNewsPage(articles: [], nextPageToken: nil)
        }

        let resolvedLimit = min(max(limit, 1), 50)
        let cacheKey = NewsPageCacheKey(
            symbol: normalizedSymbol,
            startDay: Self.newsCacheDayKey(start),
            limit: resolvedLimit,
            pageToken: pageToken
        )

        if !forceReload,
           let cachedEntry = newsPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < newsPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.alpaca.fetchNews(
            symbols: [normalizedSymbol],
            start: start,
            end: nil,
            limit: resolvedLimit,
            pageToken: pageToken,
            credentials: credentials
        )
        newsPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
        return page
    }

    func fetchOpenPosition(symbol: String) async throws -> AlpacaPosition? {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        return try await services.alpaca.fetchOpenPosition(
            symbolOrAssetID: normalizedSymbol,
            credentials: credentials
        )
    }

    func fetchTradeContext(symbol: String, feed: AlpacaMarketDataFeed = .iex) async throws -> TradeContext {
        async let coreContextRequest = fetchTradeCoreContext(symbol: symbol, feed: feed)
        async let snapshotRequest: AlpacaResolvedStockSnapshot? = try? fetchTradeSnapshot(symbol: symbol, feed: feed)

        let coreContext = try await coreContextRequest
        let resolvedSnapshot = await snapshotRequest

        return TradeContext(
            account: coreContext.account,
            asset: coreContext.asset,
            position: coreContext.position,
            snapshot: resolvedSnapshot?.snapshot,
            feed: resolvedSnapshot?.feed ?? coreContext.feed,
            activeSession: resolvedSnapshot?.activeSession
        )
    }

    func fetchTradeCoreContext(symbol: String, feed: AlpacaMarketDataFeed = .iex) async throws -> TradeContext {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Order.missingSymbol(locale: appLanguage.locale))
        }

        async let accountRequest = services.alpaca.fetchAccount(credentials: credentials)
        async let positionRequest = services.alpaca.fetchOpenPosition(
            symbolOrAssetID: normalizedSymbol,
            credentials: credentials
        )
        async let assetRequest = services.alpaca.fetchAsset(symbolOrAssetID: normalizedSymbol, credentials: credentials)

        let (account, position, asset) = try await (
            accountRequest,
            positionRequest,
            assetRequest
        )

        return TradeContext(
            account: account,
            asset: asset,
            position: position,
            snapshot: nil,
            feed: feed,
            activeSession: nil
        )
    }

    func fetchTradeSnapshot(symbol: String, feed: AlpacaMarketDataFeed = .iex) async throws -> AlpacaResolvedStockSnapshot {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Order.missingSymbol(locale: appLanguage.locale))
        }

        return try await services.alpaca.fetchCurrentStockSnapshot(
            symbol: normalizedSymbol,
            feed: feed,
            credentials: credentials
        )
    }

    func searchMarketSymbols(_ query: String, limit: Int = 20) async throws -> [MarketSearchResult] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let cacheKey = SearchResultCacheKey(query: normalizedQuery.uppercased(), limit: limit)
        if let cachedEntry = searchResultCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < searchResultCacheTTL {
            return cachedEntry.value
        }

        let assets = try await marketAssets(credentials: credentials)
        let matchedAssets = await Task.detached(priority: .userInitiated) {
            Self.rankMarketAssets(assets, query: normalizedQuery, limit: limit)
        }.value
        let symbols = matchedAssets.map(\.symbol)

        guard !symbols.isEmpty else {
            searchResultCache[cacheKey] = TimedCacheEntry(value: [], cachedAt: Date())
            return []
        }

        let quotes = (try? await services.alpaca.fetchMarketSymbols(symbols: symbols, credentials: credentials)) ?? []
        let quotesBySymbol = Dictionary(uniqueKeysWithValues: quotes.map { ($0.symbol, $0) })

        let results = matchedAssets.map { asset in
            MarketSearchResult(asset: asset, quote: quotesBySymbol[asset.symbol])
        }
        searchResultCache[cacheKey] = TimedCacheEntry(value: results, cachedAt: Date())
        return results
    }

    func fetchSearchPopularMarketSymbols(limit: Int = 12, sort: MarketMostActiveSort = .volume) async throws -> [MarketActiveSymbol] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        if let searchPopularSymbolsCache = searchPopularSymbolsCache[sort],
           let searchPopularSymbolsCacheDate = searchPopularSymbolsCacheDate[sort],
           Date().timeIntervalSince(searchPopularSymbolsCacheDate) < searchPopularSymbolsCacheTTL {
            return Array(searchPopularSymbolsCache.prefix(limit))
        }

        let rankedSymbols = try await services.alpaca.fetchMostActiveMarketSymbols(top: limit, sort: sort, credentials: credentials)
        let symbols = Self.normalizedMarketSymbols(rankedSymbols.map(\.symbol))
        guard !symbols.isEmpty else {
            searchPopularSymbolsCache[sort] = []
            searchPopularSymbolsCacheDate[sort] = Date()
            return []
        }

        async let quotesRequest = services.alpaca.fetchMarketSymbols(symbols: symbols, credentials: credentials)
        async let assetsRequest = marketAssets(credentials: credentials)

        let quotes = (try? await quotesRequest) ?? []
        let assets = try await assetsRequest
        let quotesBySymbol = quotes.reduce(into: [:]) { result, quote in
            result[normalizedMarketSymbol(quote.symbol)] = quote
        }
        let assetsBySymbol = assets.reduce(into: [:]) { result, asset in
            result[normalizedMarketSymbol(asset.symbol)] = asset
        }
        let rankedBySymbol = rankedSymbols.reduce(into: [:]) { result, symbol in
            result[normalizedMarketSymbol(symbol.symbol)] = symbol
        }

        let popularSymbols = symbols.map { symbol in
            let rankedSymbol = rankedBySymbol[symbol]
            let quote = quotesBySymbol[symbol]
            return MarketActiveSymbol(
                symbol: symbol,
                companyName: assetsBySymbol[symbol]?.name ?? rankedSymbol?.companyName,
                price: quote?.price ?? rankedSymbol?.price,
                change: quote?.change ?? rankedSymbol?.change,
                percentChange: quote?.percentChange ?? rankedSymbol?.percentChange,
                volume: rankedSymbol?.volume ?? quote?.volume,
                tradeCount: rankedSymbol?.tradeCount ?? quote?.tradeCount
            )
        }

        searchPopularSymbolsCache[sort] = popularSymbols
        searchPopularSymbolsCacheDate[sort] = Date()
        return popularSymbols
    }

    func fetchSearchPlaceholderSymbol(sort: MarketMostActiveSort = .trades) async -> String {
        do {
            let mostActiveSymbols = try await fetchSearchPopularMarketSymbols(limit: 12, sort: sort)
            return Self.searchPlaceholderSymbol(from: mostActiveSymbols)
        } catch {
            return Self.searchPlaceholderFallbackSymbol
        }
    }

    nonisolated static func searchPlaceholderSymbol(from mostActiveSymbols: [MarketActiveSymbol]) -> String {
        normalizedMarketSymbols(mostActiveSymbols.map(\.symbol)).randomElement()
            ?? searchPlaceholderFallbackSymbol
    }

    private func marketAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        if let marketAssetCache,
           let marketAssetCacheDate,
           Date().timeIntervalSince(marketAssetCacheDate) < marketAssetCacheTTL {
            return marketAssetCache
        }

        let fetchedAssets = try await services.alpaca.fetchMarketAssets(credentials: credentials)
        let assets = fetchedAssets.filter { asset in
            asset.symbol.isEmpty == false && asset.status?.lowercased() == "active"
        }

        marketAssetCache = assets
        marketAssetCacheDate = Date()
        return assets
    }

    private func ensureFavoritesWatchlist(credentials: AlpacaCredentials) async throws -> AlpacaWatchlist {
        if let favoritesWatchlist {
            return favoritesWatchlist
        }

        let watchlists = try await services.alpaca.fetchWatchlists(credentials: credentials)
        if let existingWatchlist = watchlists.first(where: { watchlist in
            watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame
        }) {
            let loadedWatchlist = try await services.alpaca.fetchWatchlist(id: existingWatchlist.id, credentials: credentials)
            let normalizedNameWatchlist = try await normalizeFavoritesWatchlistNameIfNeeded(loadedWatchlist, credentials: credentials)
            favoritesWatchlist = normalizedNameWatchlist
            return normalizedNameWatchlist
        }

        let createdWatchlist = try await services.alpaca.createWatchlist(
            name: Self.favoritesWatchlistName,
            symbols: [],
            credentials: credentials
        )
        favoritesWatchlist = createdWatchlist
        return createdWatchlist
    }

    private func normalizeFavoritesWatchlistNameIfNeeded(
        _ watchlist: AlpacaWatchlist,
        credentials: AlpacaCredentials
    ) async throws -> AlpacaWatchlist {
        guard watchlist.name != Self.favoritesWatchlistName else {
            return watchlist
        }

        return try await services.alpaca.updateWatchlist(
            id: watchlist.id,
            name: Self.favoritesWatchlistName,
            symbols: watchlist.symbols,
            credentials: credentials
        )
    }

    private nonisolated static func rankMarketAssets(_ assets: [AlpacaAsset], query: String, limit: Int) -> [AlpacaAsset] {
        let normalizedQuery = query.uppercased()
        let nameQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return assets
            .compactMap { asset -> (asset: AlpacaAsset, score: Int)? in
                let symbol = asset.symbol.uppercased()
                let name = asset.name ?? ""
                let foldedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

                let score: Int?
                if symbol == normalizedQuery {
                    score = 0
                } else if symbol.hasPrefix(normalizedQuery) {
                    score = 10
                } else if foldedName.hasPrefix(nameQuery) {
                    score = 20
                } else if symbol.contains(normalizedQuery) {
                    score = 30
                } else if foldedName.localizedCaseInsensitiveContains(nameQuery) {
                    score = 40
                } else {
                    score = nil
                }

                guard let score else {
                    return nil
                }

                return (asset, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }

                if lhs.asset.symbol.count != rhs.asset.symbol.count {
                    return lhs.asset.symbol.count < rhs.asset.symbol.count
                }

                return lhs.asset.symbol < rhs.asset.symbol
            }
            .prefix(limit)
            .map(\.asset)
    }

    func resetFavoriteMarketSymbols() {
        favoritesWatchlist = nil
        favoriteMarketSymbols = []
        favoriteMarketAssetBySymbol = [:]
        favoriteMarketQuotesBySymbol = [:]
        isLoadingFavoriteMarketSymbols = false
        favoriteMarketSymbolsError = nil
    }

    func resetMarketSearchCaches() {
        marketAssetCache = nil
        marketAssetCacheDate = nil
        searchPopularSymbolsCache = [:]
        searchPopularSymbolsCacheDate = [:]
        searchResultCache = [:]
        newsPageCache = [:]
        optionChainPageCache = [:]
        optionExpirationCache = [:]
        optionSnapshotCache = [:]
        optionLatestTradeCache = [:]
        optionBarsPageCache = [:]
        optionTradesPageCache = [:]
    }

    private static let optionExpirationPageSize = 10_000
    private static let optionExpirationHorizonDays = 365 * 3

    private nonisolated static func optionExpirationDateString(daysAfter days: Int = 0, from date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let resolvedDate = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: resolvedDate)

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private nonisolated static func newsCacheDayKey(_ date: Date) -> String {
        let day = Calendar(identifier: .gregorian).startOfDay(for: date)
        return String(Int(day.timeIntervalSince1970))
    }

    private func updateFavoriteMarketSymbols(from watchlist: AlpacaWatchlist) {
        favoriteMarketSymbols = Self.normalizedMarketSymbols(watchlist.symbols)
        favoriteMarketAssetBySymbol = (watchlist.assets ?? []).reduce(into: [:]) { assetsBySymbol, asset in
            let normalizedSymbol = normalizedMarketSymbol(asset.symbol)
            guard !normalizedSymbol.isEmpty else {
                return
            }

            assetsBySymbol[normalizedSymbol] = asset
        }
    }

    private func hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: AlpacaCredentials) async {
        let missingSymbols = favoriteMarketSymbols.filter { symbol in
            let assetName = favoriteMarketAssetBySymbol[symbol]?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return assetName?.isEmpty ?? true
        }

        guard !missingSymbols.isEmpty else {
            return
        }

        for symbol in missingSymbols {
            guard let asset = try? await services.alpaca.fetchAsset(symbolOrAssetID: symbol, credentials: credentials) else {
                continue
            }

            let normalizedSymbol = normalizedMarketSymbol(asset.symbol)
            guard favoriteMarketSymbols.contains(normalizedSymbol) else {
                continue
            }

            favoriteMarketAssetBySymbol[normalizedSymbol] = asset
        }
    }

    private func refreshFavoriteMarketQuotes(credentials: AlpacaCredentials) async {
        guard !favoriteMarketSymbols.isEmpty else {
            favoriteMarketQuotesBySymbol = [:]
            return
        }

        do {
            let quotes = try await services.alpaca.fetchMarketSymbols(
                symbols: favoriteMarketSymbols,
                credentials: credentials
            )
            favoriteMarketQuotesBySymbol = quotes.reduce(into: [:]) { quotesBySymbol, quote in
                let normalizedSymbol = normalizedMarketSymbol(quote.symbol)
                guard !normalizedSymbol.isEmpty else {
                    return
                }

                quotesBySymbol[normalizedSymbol] = quote
            }
        } catch where error.isRequestCancellation {
            return
        } catch {
            // Keep stale quotes when market data is temporarily unavailable.
        }
    }

    private nonisolated static func normalizedMarketSymbols(_ symbols: [String]) -> [String] {
        var seenSymbols = Set<String>()
        return symbols.compactMap { symbol in
            let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalizedSymbol.isEmpty, !seenSymbols.contains(normalizedSymbol) else {
                return nil
            }

            seenSymbols.insert(normalizedSymbol)
            return normalizedSymbol
        }
    }
}
