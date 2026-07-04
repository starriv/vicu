import Foundation

@MainActor
final class OptionDataCache {
    var chainPageCache: [OptionChainPageCacheKey: TimedCacheEntry<AlpacaOptionChainPage>] = [:]
    let chainPageCacheTTL: TimeInterval = 20

    var expirationCache: [OptionExpirationCacheKey: TimedCacheEntry<[String]>] = [:]
    let expirationCacheTTL: TimeInterval = 5 * 60

    var snapshotCache: [OptionSnapshotCacheKey: TimedCacheEntry<AlpacaOptionSnapshot?>] = [:]
    let snapshotCacheTTL: TimeInterval = 15

    var latestTradeCache: [OptionLatestTradeCacheKey: TimedCacheEntry<AlpacaOptionTrade?>] = [:]
    let latestTradeCacheTTL: TimeInterval = 15

    var barsPageCache: [OptionBarsPageCacheKey: TimedCacheEntry<AlpacaOptionBarsPage>] = [:]
    let barsPageCacheTTL: TimeInterval = 45

    var tradesPageCache: [OptionTradesPageCacheKey: TimedCacheEntry<AlpacaOptionTradesPage>] = [:]
    let tradesPageCacheTTL: TimeInterval = 30
}
