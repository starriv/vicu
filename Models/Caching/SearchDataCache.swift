import Foundation

@MainActor
final class SearchDataCache {
    var popularSymbolsCache: [MarketMostActiveSort: [MarketActiveSymbol]] = [:]
    var popularSymbolsCacheDate: [MarketMostActiveSort: Date] = [:]
    let popularSymbolsCacheTTL: TimeInterval = 60

    var quoteCache: [String: TimedCacheEntry<MarketActiveSymbol>] = [:]
    let quoteCacheTTL: TimeInterval = 30
}
