import Foundation

// Page services wrap AlpacaServicing into domain-focused protocols so each feature
// can be tested in isolation with a narrow mock, and so business logic (caching,
// fallback, composition) can be added per domain without touching AlpacaClient.
// The default implementations are thin forwards; they grow richer as each domain's
// requirements evolve.
struct AppServices: Sendable {
    let alpaca: any AlpacaServicing
    let home: any HomeServicing
    let portfolio: any PortfolioServicing
    let orders: any OrdersServicing
    let markets: any MarketsServicing
    let watchlists: any WatchlistsServicing
    let trade: any TradeServicing
    let credentialConnection: any CredentialConnectionServicing
    let stockStream: any AlpacaStockStreaming
    let activityStream: any AlpacaActivityStreaming
    let tradeEventStream: any AlpacaTradeEventStreaming
    let appNotifier: any AppNotifying
    let credentialStore: any CredentialStore
    let configurationStore: any AppConfigurationStoring

    init(
        alpaca: any AlpacaServicing,
        home: (any HomeServicing)? = nil,
        portfolio: (any PortfolioServicing)? = nil,
        orders: (any OrdersServicing)? = nil,
        markets: (any MarketsServicing)? = nil,
        watchlists: (any WatchlistsServicing)? = nil,
        trade: (any TradeServicing)? = nil,
        credentialConnection: (any CredentialConnectionServicing)? = nil,
        stockStream: any AlpacaStockStreaming = AlpacaStockStreamClient.shared,
        activityStream: any AlpacaActivityStreaming = NoopAlpacaActivityStreamClient(),
        tradeEventStream: any AlpacaTradeEventStreaming = AlpacaTradeEventStreamClient.shared,
        appNotifier: any AppNotifying = AppNotificationCenter.shared,
        credentialStore: any CredentialStore,
        // Default evaluates at call site — opens SQLite and runs migration.
        // Tests should pass MemoryAppConfigurationStore() explicitly to avoid disk I/O.
        configurationStore: any AppConfigurationStoring = AppConfigurationStoreFactory.live()
    ) {
        self.alpaca = alpaca
        self.home = home ?? HomeService(alpaca: alpaca)
        self.portfolio = portfolio ?? PortfolioService(alpaca: alpaca)
        self.orders = orders ?? OrdersService(alpaca: alpaca)
        self.markets = markets ?? MarketsService(alpaca: alpaca)
        self.watchlists = watchlists ?? WatchlistsService(alpaca: alpaca)
        self.trade = trade ?? TradeService(alpaca: alpaca)
        self.credentialConnection = credentialConnection ?? CredentialConnectionService(alpaca: alpaca)
        self.stockStream = stockStream
        self.activityStream = activityStream
        self.tradeEventStream = tradeEventStream
        self.appNotifier = appNotifier
        self.credentialStore = credentialStore
        self.configurationStore = configurationStore
    }

    static var live: AppServices {
        let alpaca = AlpacaClient()
        return AppServices(
            alpaca: alpaca,
            credentialStore: KeychainCredentialStore()
        )
    }
}
