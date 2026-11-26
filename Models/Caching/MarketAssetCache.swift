import Foundation

@MainActor
final class MarketAssetCache {
    let marketAssetsTTL: TimeInterval = 6 * 60 * 60

    var searchIndex: MarketSearchIndex?
    var searchIndexDate: Date?
    var isSearchIndexStale = false
    var inFlightSearchIndexTask: Task<MarketSearchIndex, Error>?

    var watchlistAssets: [AlpacaAsset]?
    var watchlistAssetsDate: Date?
    let watchlistAssetsTTL: TimeInterval = 60 * 60
}
