import Foundation

struct AppServices: Sendable {
    let alpaca: any AlpacaServicing
    let stockStream: any AlpacaStockStreaming
    let activityStream: any AlpacaActivityStreaming
    let tradeEventStream: any AlpacaTradeEventStreaming
    let appNotifier: any AppNotifying
    let credentialStore: any CredentialStore

    init(
        alpaca: any AlpacaServicing,
        stockStream: any AlpacaStockStreaming = AlpacaStockStreamClient.shared,
        activityStream: any AlpacaActivityStreaming = NoopAlpacaActivityStreamClient(),
        tradeEventStream: any AlpacaTradeEventStreaming = AlpacaTradeEventStreamClient.shared,
        appNotifier: any AppNotifying = AppNotificationCenter.shared,
        credentialStore: any CredentialStore
    ) {
        self.alpaca = alpaca
        self.stockStream = stockStream
        self.activityStream = activityStream
        self.tradeEventStream = tradeEventStream
        self.appNotifier = appNotifier
        self.credentialStore = credentialStore
    }

    static var live: AppServices {
        AppServices(
            alpaca: AlpacaClient(),
            credentialStore: KeychainCredentialStore()
        )
    }
}
