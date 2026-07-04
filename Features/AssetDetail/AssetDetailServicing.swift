import Foundation
import RxSwift

@MainActor
protocol AssetDetailServicing: AnyObject {
    func fetchAssetDetailSnapshot(
        symbol: String,
        range: AssetChartRange,
        feed: AlpacaMarketDataFeed
    ) async throws -> AssetDetailSnapshot

    func fetchAssetSnapshot(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaStockSnapshot?

    func fetchResolvedAssetSnapshot(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaResolvedStockSnapshot

    func fetchLatestStockBar(symbol: String, feed: AlpacaMarketDataFeed) async throws -> AlpacaMarketBar?

    func fetchOpenPosition(symbol: String) async throws -> AlpacaPosition?

    func streamAssetMarketData(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        channels: Set<AlpacaRealtimeChannel>
    ) throws -> Observable<AssetRealtimeEvent>

    var preferredLocale: Locale { get }
}


