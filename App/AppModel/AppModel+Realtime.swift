import Foundation
import RxSwift

extension AppModel {
    func streamAssetMarketData(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        channels: Set<AlpacaRealtimeChannel> = AlpacaRealtimeChannel.assetDetail
    ) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return services.stockStream.stream(
            symbol: symbol,
            feed: feed,
            channels: channels,
            credentials: credentials
        )
    }

    func streamAssetMarketData(
        symbols: [String],
        feed: AlpacaMarketDataFeed = .iex,
        channels: Set<AlpacaRealtimeChannel> = AlpacaRealtimeChannel.assetDetail
    ) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        var seenSymbols = Set<String>()
        let normalizedSymbols = symbols
            .map(normalizedMarketSymbol)
            .filter { symbol in
                !symbol.isEmpty && seenSymbols.insert(symbol).inserted
            }
        let streams = normalizedSymbols
            .map { symbol in
                services.stockStream.stream(
                    symbol: symbol,
                    feed: feed,
                    channels: channels,
                    credentials: credentials
                )
            }

        guard !streams.isEmpty else {
            return Observable.empty()
        }

        return Observable.merge(streams)
    }

    func streamTradeQuoteEvents(symbol: String, feed: AlpacaMarketDataFeed = .iex) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return services.stockStream.stream(
            symbol: symbol,
            feed: feed,
            channels: AlpacaRealtimeChannel.tradeQuote,
            credentials: credentials
        )
    }

    func startAccountEventListeners(credentials activeCredentials: AlpacaCredentials) {
        realtimeCoordinator.startListeners(credentials: activeCredentials)
    }

    func stopAccountEventListeners() {
        realtimeCoordinator.stopListeners()
    }
}
