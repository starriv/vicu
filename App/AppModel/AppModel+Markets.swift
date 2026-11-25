import Foundation

enum MarketSearchLoadEvent {
    case cached(String, [MarketSearchResult], isFresh: Bool)
    case partial(String, [MarketSearchResult])
    case enriched(String, [MarketSearchResult])

    var query: String {
        switch self {
        case .cached(let query, _, _), .partial(let query, _), .enriched(let query, _):
            query
        }
    }

    var results: [MarketSearchResult] {
        switch self {
        case .cached(_, let results, _), .partial(_, let results), .enriched(_, let results):
            results
        }
    }
}

extension AppModel {
    func hydrateCachedMarketsFromDisk() async {
        guard let activeCredentials = credentials else {
            return
        }

        let overviewKey = AppPageCacheKeys.marketOverview(credentials: activeCredentials)
        let favoritesKey = AppPageCacheKeys.marketFavorites(credentials: activeCredentials)

        let pageCache = services.pageCache
        let revision = favoriteCacheRevision
        let (cachedOverview, cachedFavorites) = await withCheckedContinuation { continuation in
            marketCacheQueue.async {
                let overview = pageCache.value(MarketOverview.self, for: overviewKey, allowStale: true)
                let favorites = pageCache.value(MarketFavoritesCacheSnapshot.self, for: favoritesKey, allowStale: true)
                continuation.resume(returning: (overview, favorites))
            }
        }
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if cachedMarketOverview == nil, let cachedOverview {
            cachedMarketOverview = cachedOverview.value
            cachedMarketOverviewAt = cachedOverview.cachedAt
            isMarketOverviewFromStaleCache = !cachedOverview.isFresh
        }

        if revision == favoriteCacheRevision, !hasLoadedFavoriteMarketSymbols, let cachedFavorites {
            favoriteMarketSymbols = Self.normalizedMarketSymbols(cachedFavorites.value.symbols)
            favoriteMarketAssetBySymbol = cachedFavorites.value.assetsBySymbol
            favoriteMarketQuotesBySymbol = cachedFavorites.value.quotesBySymbol
            favoriteMarketSymbolsUpdatedAt = cachedFavorites.cachedAt
            hasLoadedFavoriteMarketSymbols = true
        }
    }

    func prewarmMarketsIfNeeded() {
        guard let activeCredentials = credentials else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.hydrateCachedMarketsFromDisk()
            guard self.isCurrentCredentialContext(activeCredentials) else {
                return
            }

            async let overviewWarmup: Void = {
                _ = try? await self.fetchMarketOverview(forceRefresh: false)
            }()
            async let favoritesWarmup: Void = self.refreshFavoriteMarketSymbols(forceReload: false)
            _ = await (overviewWarmup, favoritesWarmup)
        }
    }

    func cachedPopularMarketSymbols(sort: MarketMostActiveSort, limit: Int = 12) -> [MarketActiveSymbol]? {
        if let cached = searchCache.popularSymbolsCache[sort], !cached.isEmpty {
            return Array(cached.prefix(limit))
        }
        return nil
    }

    func refreshFavoriteMarketSymbols(forceReload: Bool = false) async {
        guard let activeCredentials = credentials else {
            resetFavoriteMarketSymbols()
            return
        }

        if !hasLoadedFavoriteMarketSymbols {
            await hydrateCachedMarketsFromDisk()
            guard isCurrentCredentialContext(activeCredentials) else {
                return
            }
        }

        if !forceReload,
           hasLoadedFavoriteMarketSymbols,
           let updatedAt = favoriteMarketSymbolsUpdatedAt,
           Date().timeIntervalSince(updatedAt) < PageCachePolicy.marketFavorites.freshTimeToLive {
            return
        }

        if let existingTask = inFlightFavoriteSymbolsTask {
            await existingTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFavoriteMarketSymbolsRefresh(
                credentials: activeCredentials
            )
        }
        inFlightFavoriteSymbolsTask = task
        await task.value
        if inFlightFavoriteSymbolsTask == task {
            inFlightFavoriteSymbolsTask = nil
        }
    }

    private func performFavoriteMarketSymbolsRefresh(
        credentials activeCredentials: AlpacaCredentials
    ) async {
        let revision = favoriteCacheRevision
        let mutationGeneration = favoriteMutationGeneration
        let shouldShowInitialLoading = !hasLoadedFavoriteMarketSymbols && favoriteMarketSymbols.isEmpty
        if shouldShowInitialLoading {
            isLoadingFavoriteMarketSymbols = true
        }
        defer {
            if revision == favoriteCacheRevision { isLoadingFavoriteMarketSymbols = false }
        }

        do {
            let watchlist = try await ensureFavoritesWatchlist(credentials: activeCredentials, reload: true)
            try Task.checkCancellation()
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else { return }
            // A favorite toggle finished or started while this fetch was in flight;
            // its result is newer than this snapshot, so do not apply or persist it.
            guard mutationGeneration == favoriteMutationGeneration else { return }
            updateFavoriteMarketSymbols(from: watchlist)
            hasLoadedFavoriteMarketSymbols = true
            favoriteMarketSymbolsUpdatedAt = Date()
            favoriteMarketSymbolsError = nil

            async let assetHydration: Void = hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: activeCredentials)
            async let quoteRefresh: Void = refreshFavoriteMarketQuotes(credentials: activeCredentials)
            _ = await (assetHydration, quoteRefresh)

            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else {
                return
            }

            guard !Task.isCancelled, mutationGeneration == favoriteMutationGeneration else { return }
            favoriteMarketSymbolsUpdatedAt = Date()
            persistFavoriteMarketSymbolsCache(credentials: activeCredentials)
        } catch where error.isRequestCancellation {
            return
        } catch {
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else { return }
            favoriteMarketSymbolsError = APIErrorDisplayMessage.message(for: error, locale: appLanguage.locale)
        }
    }

    func toggleFavoriteMarketSymbol(_ symbol: String) async {
        guard let activeCredentials = credentials else {
            lastError = L10n.Credentials.apiKeyRequired(locale: appLanguage.locale)
            return
        }

        let normalizedSymbol = normalizedMarketSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return
        }

        let revision = favoriteCacheRevision
        favoriteMutationGeneration += 1
        let previousSymbols = favoriteMarketSymbols
        let previousAssetsBySymbol = favoriteMarketAssetBySymbol
        let previousQuotesBySymbol = favoriteMarketQuotesBySymbol
        let isRemoving = favoriteMarketSymbols.contains(normalizedSymbol)

        // Optimistic UI update immediately before awaiting network round-trips.
        if let index = favoriteMarketSymbols.firstIndex(of: normalizedSymbol) {
            favoriteMarketSymbols.remove(at: index)
            favoriteMarketAssetBySymbol.removeValue(forKey: normalizedSymbol)
            favoriteMarketQuotesBySymbol.removeValue(forKey: normalizedSymbol)
        } else {
            favoriteMarketSymbols.append(normalizedSymbol)
        }
        hasLoadedFavoriteMarketSymbols = true

        do {
            let watchlist = try await ensureFavoritesWatchlist(credentials: activeCredentials)
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else { return }
            let updatedWatchlist: AlpacaWatchlist

            if isRemoving {
                updatedWatchlist = try await services.watchlists.removeSymbol(normalizedSymbol, fromWatchlist: watchlist.id, credentials: activeCredentials)
            } else {
                updatedWatchlist = try await services.watchlists.addSymbol(normalizedSymbol, toWatchlist: watchlist.id, credentials: activeCredentials)
            }

            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else {
                return
            }

            favoriteMutationGeneration += 1
            favoritesWatchlist = updatedWatchlist
            updateFavoriteMarketSymbols(from: updatedWatchlist)
            favoriteMarketSymbolsUpdatedAt = Date()
            favoriteMarketSymbolsError = nil
            lastError = nil

            async let assetHydration: Void = hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: activeCredentials)
            async let quoteRefresh: Void = refreshFavoriteMarketQuotes(credentials: activeCredentials)
            _ = await (assetHydration, quoteRefresh)

            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else {
                return
            }

            persistFavoriteMarketSymbolsCache(credentials: activeCredentials)
        } catch where error.isRequestCancellation {
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else { return }
            favoriteMarketSymbols = previousSymbols
            favoriteMarketAssetBySymbol = previousAssetsBySymbol
            favoriteMarketQuotesBySymbol = previousQuotesBySymbol
            favoriteMarketSymbolsError = nil
        } catch {
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(activeCredentials) else { return }
            favoriteMarketSymbols = previousSymbols
            favoriteMarketAssetBySymbol = previousAssetsBySymbol
            favoriteMarketQuotesBySymbol = previousQuotesBySymbol
            let message = APIErrorDisplayMessage.message(for: error, locale: appLanguage.locale)
            favoriteMarketSymbolsError = message
            lastError = message
        }
    }

    func fetchMarketOverview(forceRefresh: Bool = false) async throws -> MarketOverview {
        guard let activeCredentials = credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        if !forceRefresh, cachedMarketOverview == nil {
            await hydrateCachedMarketsFromDisk()
            guard isCurrentCredentialContext(activeCredentials) else {
                throw CancellationError()
            }
        }

        if !forceRefresh,
           !isMarketOverviewFromStaleCache, let cachedMarketOverview,
           let cachedAt = cachedMarketOverviewAt,
           Date().timeIntervalSince(cachedAt) < PageCachePolicy.marketOverview.freshTimeToLive {
            return cachedMarketOverview
        }

        if !forceRefresh, let existingTask = inFlightMarketOverviewTask {
            return try await existingTask.value
        }

        inFlightMarketOverviewTask?.cancel()
        let task = Task<MarketOverview, Error> { @MainActor in
            defer {
                if !Task.isCancelled { inFlightMarketOverviewTask = nil }
            }
            do {
                let overview = try await services.markets.fetchMarketOverview(credentials: activeCredentials)
                try Task.checkCancellation()
                guard isCurrentCredentialContext(activeCredentials) else { throw CancellationError() }

                cachedMarketOverview = overview
                cachedMarketOverviewAt = Date()
                isMarketOverviewFromStaleCache = false
                let cacheKey = AppPageCacheKeys.marketOverview(credentials: activeCredentials)
                let pageCache = services.pageCache
                marketCacheQueue.async {
                    pageCache.setValue(overview, for: cacheKey, policy: .marketOverview)
                }
                return overview
            } catch {
                try Task.checkCancellation()
                guard isCurrentCredentialContext(activeCredentials) else { throw CancellationError() }
                isMarketOverviewFromStaleCache = cachedMarketOverview != nil
                throw error
            }
        }
        inFlightMarketOverviewTask = task
        return try await task.value
    }

    func persistFavoriteMarketSymbolsCache(credentials activeCredentials: AlpacaCredentials) {
        let snapshot = MarketFavoritesCacheSnapshot(
            symbols: favoriteMarketSymbols,
            assetsBySymbol: favoriteMarketAssetBySymbol,
            quotesBySymbol: favoriteMarketQuotesBySymbol
        )
        let cacheKey = AppPageCacheKeys.marketFavorites(credentials: activeCredentials)
        let pageCache = services.pageCache
        marketCacheQueue.async {
            pageCache.setValue(snapshot, for: cacheKey, policy: .marketFavorites)
        }
    }

    func fetchMarketIndexQuotes(feed: AlpacaMarketDataFeed = .iex) async throws -> [MarketIndexQuote] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.markets.fetchMarketIndexQuotes(feed: feed, credentials: credentials)
    }

    func fetchAssetDetailSnapshot(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed = .iex
    ) async throws -> AssetDetailSnapshot {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.markets.fetchAssetDetail(
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

        return try await services.markets.fetchStockSnapshot(symbol: symbol, feed: feed, credentials: credentials)
    }

    func fetchResolvedAssetSnapshot(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex
    ) async throws -> AlpacaResolvedStockSnapshot {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return try await services.markets.fetchCurrentStockSnapshot(
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

        return try await services.markets.fetchLatestStockBar(
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

        return try await services.markets.fetchHistoricalStockQuotes(
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
           let cachedEntry = optionCache.chainPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.chainPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.markets.fetchOptionChain(
            symbol: normalizedSymbol,
            feed: .indicative,
            type: type,
            expirationDate: expirationDate,
            limit: resolvedLimit,
            pageToken: pageToken,
            credentials: credentials
        )
        optionCache.chainPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
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
           let cachedEntry = optionCache.expirationCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.expirationCacheTTL {
            return cachedEntry.value
        }

        var expirations = Set<String>()
        var pageToken: String?

        repeat {
            let page = try await services.markets.fetchOptionContracts(
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
        optionCache.expirationCache[cacheKey] = TimedCacheEntry(
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
           let cachedEntry = optionCache.snapshotCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.snapshotCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.markets.fetchOptionSnapshots(
            symbols: [normalizedSymbol],
            feed: .indicative,
            limit: 1,
            pageToken: nil,
            credentials: credentials
        )
        let snapshot = page.snapshots.first { $0.contractSymbol == normalizedSymbol } ?? page.snapshots.first
        optionCache.snapshotCache[cacheKey] = TimedCacheEntry(value: snapshot, cachedAt: Date())
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
           let cachedEntry = optionCache.latestTradeCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.latestTradeCacheTTL {
            return cachedEntry.value
        }

        let trades = try await services.markets.fetchLatestOptionTrades(
            symbols: [normalizedSymbol],
            feed: .indicative,
            credentials: credentials
        )
        let trade = trades[normalizedSymbol] ?? trades.values.first
        optionCache.latestTradeCache[cacheKey] = TimedCacheEntry(value: trade, cachedAt: Date())
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
           let cachedEntry = optionCache.barsPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.barsPageCacheTTL {
            #if DEBUG
            print(
                "[OptionChart][AppModel] cache-hit symbol=\(normalizedSymbol) range=\(range.title) bars=\(cachedEntry.value.bars.count) nextPageToken=\(cachedEntry.value.nextPageToken ?? "nil") first={\(cachedEntry.value.bars.first?.debugSummary ?? "nil")} last={\(cachedEntry.value.bars.last?.debugSummary ?? "nil")}"
            )
            #endif
            return cachedEntry.value
        }

        #if DEBUG
        print(
            "[OptionChart][AppModel] fetch symbol=\(normalizedSymbol) range=\(range.title) limit=\(resolvedLimit) pageToken=\(pageToken ?? "nil") forceReload=\(forceReload)"
        )
        #endif

        let page = try await services.markets.fetchOptionBars(
            symbol: normalizedSymbol,
            range: range,
            feed: .indicative,
            limit: resolvedLimit,
            pageToken: pageToken,
            sort: .asc,
            credentials: credentials
        )
        #if DEBUG
        print(
            "[OptionChart][AppModel] fetched symbol=\(normalizedSymbol) range=\(range.title) bars=\(page.bars.count) nextPageToken=\(page.nextPageToken ?? "nil") first={\(page.bars.first?.debugSummary ?? "nil")} last={\(page.bars.last?.debugSummary ?? "nil")}"
        )
        #endif
        optionCache.barsPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
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
           let cachedEntry = optionCache.tradesPageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < optionCache.tradesPageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.markets.fetchOptionTrades(
            symbol: normalizedSymbol,
            range: range,
            feed: .indicative,
            limit: resolvedLimit,
            pageToken: pageToken,
            sort: .desc,
            credentials: credentials
        )
        optionCache.tradesPageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
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
           let cachedEntry = newsCache.pageCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < newsCache.pageCacheTTL {
            return cachedEntry.value
        }

        let page = try await services.markets.fetchNews(
            symbols: [normalizedSymbol],
            start: start,
            end: nil,
            limit: resolvedLimit,
            pageToken: pageToken,
            credentials: credentials
        )
        newsCache.pageCache[cacheKey] = TimedCacheEntry(value: page, cachedAt: Date())
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

        return try await services.trade.fetchOpenPosition(
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

        async let accountRequest = services.trade.fetchAccount(credentials: credentials)
        async let positionRequest = services.trade.fetchOpenPosition(
            symbolOrAssetID: normalizedSymbol,
            credentials: credentials
        )
        async let assetRequest = services.markets.fetchAsset(symbolOrAssetID: normalizedSymbol, credentials: credentials)

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

        return try await services.markets.fetchCurrentStockSnapshot(
            symbol: normalizedSymbol,
            feed: feed,
            credentials: credentials
        )
    }

    func searchMarketSymbols(_ query: String, limit: Int = 20) async throws -> [MarketSearchResult] {
        var latestResults: [MarketSearchResult] = []
        try await searchMarketSymbolsProgressively(query, limit: limit) { event in
            latestResults = event.results
        }
        return latestResults
    }

    func searchMarketSymbolsProgressively(
        _ query: String,
        limit: Int = 20,
        forceRefresh: Bool = false,
        emit: @MainActor (MarketSearchLoadEvent) -> Void
    ) async throws {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return
        }

        let startedAt = Date()
        Self.debugMarketSearchLatency("start", query: normalizedQuery, startedAt: startedAt)
        let cacheKey = SearchResultCacheKey(query: normalizedQuery.uppercased(), limit: limit)
        let cachedEntry = searchCache.resultCache[cacheKey]
        let cachedResults = cachedEntry?.value
        if let cachedEntry = searchCache.resultCache[cacheKey],
           Date().timeIntervalSince(cachedEntry.cachedAt) < searchCache.resultCacheTTL {
            Self.debugMarketSearchLatency(
                "cache.fresh",
                query: normalizedQuery,
                startedAt: startedAt,
                resultCount: cachedEntry.value.count
            )
            emit(.cached(normalizedQuery, cachedEntry.value, isFresh: true))
            if !forceRefresh {
                return
            }
        } else if let cachedEntry {
            Self.debugMarketSearchLatency(
                "cache.stale",
                query: normalizedQuery,
                startedAt: startedAt,
                resultCount: cachedEntry.value.count
            )
            emit(.cached(normalizedQuery, cachedEntry.value, isFresh: false))
        }

        let assets = try await marketAssets(credentials: credentials)
        try Task.checkCancellation()
        Self.debugMarketSearchLatency(
            "assets.ready",
            query: normalizedQuery,
            startedAt: startedAt,
            resultCount: assets.count
        )
        let matchedAssets = await Task.detached(priority: .userInitiated) {
            Self.rankMarketAssets(assets, query: normalizedQuery, limit: limit)
        }.value
        try Task.checkCancellation()
        Self.debugMarketSearchLatency(
            "rank.done",
            query: normalizedQuery,
            startedAt: startedAt,
            resultCount: matchedAssets.count
        )
        let symbols = matchedAssets.map(\.symbol)

        guard !symbols.isEmpty else {
            searchCache.resultCache[cacheKey] = TimedCacheEntry(value: [], cachedAt: Date())
            emit(.enriched(normalizedQuery, []))
            return
        }

        let cachedQuotesBySymbol: [String: MarketActiveSymbol] = (cachedResults ?? []).reduce(into: [:]) { quotesBySymbol, result in
            guard let quote = result.quote else {
                return
            }

            quotesBySymbol[normalizedMarketSymbol(result.symbol)] = quote
        }
        let partialResults = matchedAssets.map { asset in
            MarketSearchResult(asset: asset, quote: cachedQuotesBySymbol[normalizedMarketSymbol(asset.symbol)])
        }
        Self.debugMarketSearchLatency(
            "partial.emit",
            query: normalizedQuery,
            startedAt: startedAt,
            resultCount: partialResults.count
        )
        emit(.partial(normalizedQuery, partialResults))

        let quotes = (try? await services.markets.fetchMarketSymbols(symbols: symbols, credentials: credentials)) ?? []
        try Task.checkCancellation()
        let quotesBySymbol: [String: MarketActiveSymbol] = quotes.reduce(into: [:]) { quotesBySymbol, quote in
            quotesBySymbol[normalizedMarketSymbol(quote.symbol)] = quote
        }

        let results = matchedAssets.map { asset in
            let normalizedSymbol = normalizedMarketSymbol(asset.symbol)
            return MarketSearchResult(
                asset: asset,
                quote: quotesBySymbol[normalizedSymbol] ?? cachedQuotesBySymbol[normalizedSymbol]
            )
        }
        searchCache.resultCache[cacheKey] = TimedCacheEntry(value: results, cachedAt: Date())
        Self.debugMarketSearchLatency(
            "enriched.done",
            query: normalizedQuery,
            startedAt: startedAt,
            resultCount: results.count
        )
        emit(.enriched(normalizedQuery, results))
    }

    func fetchSearchPopularMarketSymbols(limit: Int = 12, sort: MarketMostActiveSort = .volume) async throws -> [MarketActiveSymbol] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        if let searchPopularSymbolsCache = searchCache.popularSymbolsCache[sort],
           let searchPopularSymbolsCacheDate = searchCache.popularSymbolsCacheDate[sort],
           Date().timeIntervalSince(searchPopularSymbolsCacheDate) < searchCache.popularSymbolsCacheTTL {
            return Array(searchPopularSymbolsCache.prefix(limit))
        }

        let rankedSymbols = try await services.markets.fetchMostActiveMarketSymbols(top: limit, sort: sort, credentials: credentials)
        try Task.checkCancellation()
        guard isCurrentCredentialContext(credentials) else { throw CancellationError() }
        let symbols = Self.normalizedMarketSymbols(rankedSymbols.map(\.symbol))
        guard !symbols.isEmpty else {
            searchCache.popularSymbolsCache[sort] = []
            searchCache.popularSymbolsCacheDate[sort] = Date()
            return []
        }

        async let quotesRequest = services.markets.fetchMarketSymbols(symbols: symbols, credentials: credentials)

        let quotes = (try? await quotesRequest) ?? []
        let quotesBySymbol = quotes.reduce(into: [:]) { result, quote in
            result[normalizedMarketSymbol(quote.symbol)] = quote
        }
        let rankedBySymbol = rankedSymbols.reduce(into: [:]) { result, symbol in
            result[normalizedMarketSymbol(symbol.symbol)] = symbol
        }

        let popularSymbols = symbols.map { symbol in
            let rankedSymbol = rankedBySymbol[symbol]
            let quote = quotesBySymbol[symbol]
            return MarketActiveSymbol(
                symbol: symbol,
                companyName: rankedSymbol?.companyName,
                price: quote?.price ?? rankedSymbol?.price,
                change: quote?.change ?? rankedSymbol?.change,
                percentChange: quote?.percentChange ?? rankedSymbol?.percentChange,
                volume: rankedSymbol?.volume ?? quote?.volume,
                tradeCount: rankedSymbol?.tradeCount ?? quote?.tradeCount
            )
        }

        try Task.checkCancellation()
        guard isCurrentCredentialContext(credentials) else { throw CancellationError() }
        searchCache.popularSymbolsCache[sort] = popularSymbols
        searchCache.popularSymbolsCacheDate[sort] = Date()
        return popularSymbols
    }

    func fetchSearchPlaceholderSymbol(sort: MarketMostActiveSort = .trades) async -> String {
        guard let credentials else {
            return Self.searchPlaceholderFallbackSymbol
        }

        if let searchPopularSymbolsCache = searchCache.popularSymbolsCache[sort],
           let searchPopularSymbolsCacheDate = searchCache.popularSymbolsCacheDate[sort],
           Date().timeIntervalSince(searchPopularSymbolsCacheDate) < searchCache.popularSymbolsCacheTTL {
            return Self.searchPlaceholderSymbol(from: searchPopularSymbolsCache)
        }

        do {
            let mostActiveSymbols = try await services.markets.fetchMostActiveMarketSymbols(
                top: 12,
                sort: sort,
                credentials: credentials
            )
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
        if let cached = assetCache.marketAssets,
           let cacheDate = assetCache.marketAssetsDate,
           Date().timeIntervalSince(cacheDate) < assetCache.marketAssetsTTL {
            return cached
        }

        let fetchedAssets = try await services.markets.fetchMarketAssets(credentials: credentials)
        let assets = fetchedAssets.filter { asset in
            asset.symbol.isEmpty == false && asset.status?.lowercased() == "active"
        }

        assetCache.marketAssets = assets
        assetCache.marketAssetsDate = Date()
        return assets
    }

    private func ensureFavoritesWatchlist(credentials: AlpacaCredentials, reload: Bool = false) async throws -> AlpacaWatchlist {
        if !reload, let favoritesWatchlist {
            return favoritesWatchlist
        }

        // Share one lookup/create across concurrent callers (refresh + toggle) so a
        // new account never ends up with two favorites watchlists.
        if let existingTask = inFlightFavoritesWatchlistTask {
            return try await existingTask.value
        }

        let revision = favoriteCacheRevision
        let task = Task<AlpacaWatchlist, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            let watchlist = try await self.loadOrCreateFavoritesWatchlist(credentials: credentials, revision: revision)
            if revision == self.favoriteCacheRevision, self.isCurrentCredentialContext(credentials) {
                self.favoritesWatchlist = watchlist
            }
            return watchlist
        }
        inFlightFavoritesWatchlistTask = task
        defer {
            if inFlightFavoritesWatchlistTask == task {
                inFlightFavoritesWatchlistTask = nil
            }
        }
        return try await task.value
    }

    private func loadOrCreateFavoritesWatchlist(credentials: AlpacaCredentials, revision: Int) async throws -> AlpacaWatchlist {
        let watchlists = try await services.watchlists.fetchWatchlists(credentials: credentials)
        try Task.checkCancellation()
        guard revision == favoriteCacheRevision, isCurrentCredentialContext(credentials) else { throw CancellationError() }
        if let existing = watchlists.first(where: { $0.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame }) {
            let watchlist = try await services.watchlists.fetchWatchlist(id: existing.id, credentials: credentials)
            try Task.checkCancellation()
            guard revision == favoriteCacheRevision, isCurrentCredentialContext(credentials),
                  watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame else { throw CancellationError() }
            return watchlist
        }

        return try await services.watchlists.createWatchlist(
            name: Self.favoritesWatchlistName,
            symbols: [],
            credentials: credentials
        )
    }

    nonisolated static func rankMarketAssets(_ assets: [AlpacaAsset], query: String, limit: Int) -> [AlpacaAsset] {
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

    private nonisolated static func debugMarketSearchLatency(
        _ stage: String,
        query: String,
        startedAt: Date,
        resultCount: Int? = nil
    ) {
        #if DEBUG
        let latency = max(0, Int((Date().timeIntervalSince(startedAt) * 1_000).rounded()))
        let count = resultCount.map { " count=\($0)" } ?? ""
        print("[MarketSearch] \(stage) query=\(query) latency=\(latency)ms\(count)")
        #endif
    }

    func invalidateFavoritesWatchlist(credentials: AlpacaCredentials) {
        let cacheKey = AppPageCacheKeys.marketFavorites(credentials: credentials)
        let pageCache = services.pageCache
        marketCacheQueue.async { pageCache.removeValue(for: cacheKey) }
        if isCurrentCredentialContext(credentials) {
            resetFavoriteMarketSymbols()
        }
    }

    func resetFavoriteMarketSymbols() {
        favoriteCacheRevision += 1
        inFlightFavoriteSymbolsTask?.cancel()
        inFlightFavoriteSymbolsTask = nil
        inFlightFavoritesWatchlistTask?.cancel()
        inFlightFavoritesWatchlistTask = nil
        favoritesWatchlist = nil
        favoriteMarketSymbols = []
        favoriteMarketAssetBySymbol = [:]
        favoriteMarketQuotesBySymbol = [:]
        favoriteMarketSymbolsUpdatedAt = nil
        hasLoadedFavoriteMarketSymbols = false
        isLoadingFavoriteMarketSymbols = false
        favoriteMarketSymbolsError = nil
    }

    func resetMarketOverviewCache() {
        inFlightMarketOverviewTask?.cancel()
        inFlightMarketOverviewTask = nil
        cachedMarketOverview = nil
        cachedMarketOverviewAt = nil
        isMarketOverviewFromStaleCache = false
    }

    func resetMarketSearchCaches() {
        assetCache.marketAssets = nil
        assetCache.marketAssetsDate = nil
        assetCache.watchlistAssets = nil
        assetCache.watchlistAssetsDate = nil
        searchCache.popularSymbolsCache = [:]
        searchCache.popularSymbolsCacheDate = [:]
        searchCache.resultCache = [:]
        newsCache.pageCache = [:]
        optionCache.chainPageCache = [:]
        optionCache.expirationCache = [:]
        optionCache.snapshotCache = [:]
        optionCache.latestTradeCache = [:]
        optionCache.barsPageCache = [:]
        optionCache.tradesPageCache = [:]
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

    func updateFavoriteMarketSymbols(from watchlist: AlpacaWatchlist) {
        favoriteMarketSymbols = Self.normalizedMarketSymbols(watchlist.symbols)
        let allowed = Set(favoriteMarketSymbols)
        var mergedAssets = favoriteMarketAssetBySymbol.filter { allowed.contains($0.key) }
        for asset in watchlist.assets ?? [] {
            let normalizedSymbol = normalizedMarketSymbol(asset.symbol)
            guard !normalizedSymbol.isEmpty, allowed.contains(normalizedSymbol) else {
                continue
            }
            mergedAssets[normalizedSymbol] = asset
        }
        favoriteMarketAssetBySymbol = mergedAssets
        favoriteMarketQuotesBySymbol = favoriteMarketQuotesBySymbol.filter { allowed.contains($0.key) }
    }

    private static let favoriteAssetHydrationConcurrency = 4

    private func hydrateFavoriteMarketAssetDetailsIfNeeded(credentials: AlpacaCredentials) async {
        let revision = favoriteCacheRevision
        let missingSymbols = favoriteMarketSymbols.filter { symbol in
            let assetName = favoriteMarketAssetBySymbol[symbol]?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return assetName?.isEmpty ?? true
        }

        guard !missingSymbols.isEmpty else {
            return
        }

        let marketsService = services.markets
        let maxConcurrentRequests = Self.favoriteAssetHydrationConcurrency
        let fetchedAssets = await withTaskGroup(of: AlpacaAsset?.self) { group in
            var assets: [AlpacaAsset] = []
            var pendingSymbols = missingSymbols[...]

            func enqueueNext() {
                guard let symbol = pendingSymbols.popFirst() else { return }
                group.addTask {
                    try? await marketsService.fetchAsset(symbolOrAssetID: symbol, credentials: credentials)
                }
            }

            // Sliding window keeps the asset lookups under Alpaca's rate limit
            // even for large favorites lists.
            for _ in 0..<maxConcurrentRequests {
                enqueueNext()
            }

            while let asset = await group.next() {
                if let asset {
                    assets.append(asset)
                }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                enqueueNext()
            }
            return assets
        }

        guard !Task.isCancelled, revision == favoriteCacheRevision, isCurrentCredentialContext(credentials) else { return }

        for asset in fetchedAssets {
            let normalizedSymbol = normalizedMarketSymbol(asset.symbol)
            guard favoriteMarketSymbols.contains(normalizedSymbol) else {
                continue
            }

            favoriteMarketAssetBySymbol[normalizedSymbol] = asset
        }
    }

    private func refreshFavoriteMarketQuotes(credentials: AlpacaCredentials) async {
        let revision = favoriteCacheRevision
        guard !favoriteMarketSymbols.isEmpty else {
            favoriteMarketQuotesBySymbol = [:]
            return
        }

        do {
            let quotes = try await services.markets.fetchMarketSymbols(
                symbols: favoriteMarketSymbols,
                credentials: credentials
            )
            guard !Task.isCancelled, revision == favoriteCacheRevision, isCurrentCredentialContext(credentials) else { return }
            favoriteMarketQuotesBySymbol = quotes.reduce(into: [:]) { quotesBySymbol, quote in
                let normalizedSymbol = normalizedMarketSymbol(quote.symbol)
                guard favoriteMarketSymbols.contains(normalizedSymbol) else { return }
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
