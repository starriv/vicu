import Foundation

struct TimedCacheEntry<Value> {
    let value: Value
    let cachedAt: Date
}

struct SearchResultCacheKey: Hashable {
    let query: String
    let limit: Int
}

struct NewsPageCacheKey: Hashable {
    let symbol: String
    let startDay: String
    let limit: Int
    let pageToken: String?
}

struct OptionChainPageCacheKey: Hashable {
    let symbol: String
    let type: AlpacaOptionContractType?
    let expirationDate: String?
    let limit: Int
    let pageToken: String?
}

struct OptionExpirationCacheKey: Hashable {
    let symbol: String
    let startDate: String
    let endDate: String
}

struct OptionSnapshotCacheKey: Hashable {
    let symbol: String
}

struct OptionLatestTradeCacheKey: Hashable {
    let symbol: String
}

struct OptionBarsPageCacheKey: Hashable {
    let symbol: String
    let range: AssetChartRange
    let limit: Int
    let pageToken: String?
}

struct OptionTradesPageCacheKey: Hashable {
    let symbol: String
    let range: AssetChartRange
    let limit: Int
    let pageToken: String?
}
