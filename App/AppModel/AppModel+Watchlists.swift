import Foundation

extension AppModel {
    func fetchWatchlists() async throws -> [AlpacaWatchlist] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let summaries = try await services.watchlists.fetchWatchlists(credentials: credentials)
        guard !summaries.isEmpty else {
            return []
        }

        let watchlists = services.watchlists
        return try await withThrowingTaskGroup(of: (Int, AlpacaWatchlist).self) { group in
            for (index, summary) in summaries.enumerated() {
                group.addTask {
                    let detail = try await watchlists.fetchWatchlist(id: summary.id, credentials: credentials)
                    return (index, detail)
                }
            }

            var detailedWatchlists = Array<AlpacaWatchlist?>(repeating: nil, count: summaries.count)
            for try await (index, watchlist) in group {
                detailedWatchlists[index] = watchlist
            }

            return detailedWatchlists.compactMap(\.self)
        }
    }

    func createWatchlist(name: String, symbols: [String]) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.nameRequired(locale: appLanguage.locale))
        }

        let watchlist = try await services.watchlists.createWatchlist(
            name: resolvedName,
            symbols: symbols,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(watchlist, credentials: credentials)
        return watchlist
    }

    func updateWatchlist(id: String, name: String, symbols: [String], previousName: String? = nil) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.nameRequired(locale: appLanguage.locale))
        }

        let watchlist = try await services.watchlists.updateWatchlist(
            id: id,
            name: resolvedName,
            symbols: symbols,
            credentials: credentials
        )
        if previousName?.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame,
           watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) != .orderedSame {
            invalidateFavoritesWatchlist(credentials: credentials)
        } else {
            synchronizeFavoritesWatchlistAfterUpsert(watchlist, credentials: credentials)
        }
        return watchlist
    }

    func deleteWatchlist(_ watchlist: AlpacaWatchlist) async throws {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        try await services.watchlists.deleteWatchlist(id: watchlist.id, credentials: credentials)
        if isFavoritesWatchlist(watchlist) {
            invalidateFavoritesWatchlist(credentials: credentials)
        }
    }

    func addSymbol(_ symbol: String, to watchlist: AlpacaWatchlist) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = Self.normalizedWatchlistSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.invalidSymbol(locale: appLanguage.locale))
        }

        let updatedWatchlist = try await services.watchlists.addSymbol(
            normalizedSymbol,
            toWatchlist: watchlist.id,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(updatedWatchlist, credentials: credentials)
        return updatedWatchlist
    }

    func removeSymbol(_ symbol: String, from watchlist: AlpacaWatchlist) async throws -> AlpacaWatchlist {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedSymbol = Self.normalizedWatchlistSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            throw APIClientError.underlying(L10n.Watchlists.invalidSymbol(locale: appLanguage.locale))
        }

        let updatedWatchlist = try await services.watchlists.removeSymbol(
            normalizedSymbol,
            fromWatchlist: watchlist.id,
            credentials: credentials
        )
        synchronizeFavoritesWatchlistAfterUpsert(updatedWatchlist, credentials: credentials)
        return updatedWatchlist
    }

    func searchWatchlistAssets(query: String, limit: Int = 16) async throws -> [AlpacaAsset] {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let assets = try await watchlistAssets(credentials: credentials)
        return await Task.detached(priority: .userInitiated) {
            Self.rankMarketAssets(assets, query: normalizedQuery, limit: limit)
        }.value
    }

    private func synchronizeFavoritesWatchlistAfterUpsert(_ watchlist: AlpacaWatchlist, credentials: AlpacaCredentials) {
        guard isCurrentCredentialContext(credentials) else { return }
        let wasFavorites = favoritesWatchlist?.id == watchlist.id
        let isFavoritesName = watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame
        guard wasFavorites || isFavoritesName else {
            return
        }

        guard isFavoritesName else {
            invalidateFavoritesWatchlist(credentials: credentials)
            return
        }

        inFlightFavoriteSymbolsTask?.cancel()
        inFlightFavoriteSymbolsTask = nil
        favoriteCacheRevision += 1
        hasLoadedFavoriteMarketSymbols = true
        favoriteMarketSymbolsUpdatedAt = Date()
        favoritesWatchlist = watchlist
        isLoadingFavoriteMarketSymbols = false
        favoriteMarketSymbolsError = nil
        updateFavoriteMarketSymbols(from: watchlist)
        persistFavoriteMarketSymbolsCache(credentials: credentials)
    }

    private func isFavoritesWatchlist(_ watchlist: AlpacaWatchlist) -> Bool {
        favoritesWatchlist?.id == watchlist.id
            || watchlist.name.caseInsensitiveCompare(Self.favoritesWatchlistName) == .orderedSame
    }

    private func watchlistAssets(credentials: AlpacaCredentials) async throws -> [AlpacaAsset] {
        if let cached = assetCache.watchlistAssets,
           let cacheDate = assetCache.watchlistAssetsDate,
           Date().timeIntervalSince(cacheDate) < assetCache.watchlistAssetsTTL {
            return cached
        }

        let fetchedAssets = try await services.watchlists.fetchAssets(assetClass: nil, credentials: credentials)
        let assets = fetchedAssets.filter { asset in
            !asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && asset.status?.lowercased() == "active"
        }

        assetCache.watchlistAssets = assets
        assetCache.watchlistAssetsDate = Date()
        return assets
    }

    private static func normalizedWatchlistSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
