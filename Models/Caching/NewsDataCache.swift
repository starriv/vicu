import Foundation

@MainActor
final class NewsDataCache {
    var pageCache: [NewsPageCacheKey: TimedCacheEntry<AlpacaNewsPage>] = [:]
    let pageCacheTTL: TimeInterval = 45
}
