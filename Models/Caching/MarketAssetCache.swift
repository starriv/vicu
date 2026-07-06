import Foundation

@MainActor
final class MarketAssetCache {
    var marketAssets: [AlpacaAsset]?
    var marketAssetsDate: Date?
    let marketAssetsTTL: TimeInterval = 60 * 60

    var watchlistAssets: [AlpacaAsset]?
    var watchlistAssetsDate: Date?
    let watchlistAssetsTTL: TimeInterval = 60 * 60
}
