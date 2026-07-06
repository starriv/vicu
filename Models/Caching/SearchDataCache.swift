import Foundation

@MainActor
final class SearchDataCache {
    var popularSymbolsCache: [MarketMostActiveSort: [MarketActiveSymbol]] = [:]
    var popularSymbolsCacheDate: [MarketMostActiveSort: Date] = [:]
    let popularSymbolsCacheTTL: TimeInterval = 60

    var resultCache: [SearchResultCacheKey: TimedCacheEntry<[MarketSearchResult]>] = [:]
    let resultCacheTTL: TimeInterval = 20
}
