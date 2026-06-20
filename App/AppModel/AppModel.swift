import Foundation
import Observation
import RxSwift

@MainActor
@Observable
final class AppModel {
    nonisolated static let searchPlaceholderFallbackSymbol = "AAPL"

    var selectedTab: AppTab = .home
    var pendingOrdersListRequest: OrdersListRequest?
    var pendingOrderDetailRequest: OrderDetailNavigationRequest?
    var environment: TradeEnvironment = .paper {
        didSet {
            services.configurationStore.setValue(environment, for: AppConfigurationKeys.App.tradeEnvironment)
        }
    }
    var hasCredentials = false
    var isCredentialBootstrapComplete = false
    var credentialsStatus: CredentialsStatus = .missing
    var connectionDiagnostics: ConnectionDiagnostics?
    var appearanceMode: AppearanceMode = .system {
        didSet {
            services.configurationStore.setValue(appearanceMode, for: AppConfigurationKeys.App.appearanceMode)
        }
    }
    var appLanguage: AppLanguage = .system {
        didSet {
            services.configurationStore.setValue(appLanguage, for: AppConfigurationKeys.App.appLanguage)
        }
    }
    var notificationPreferences: AppNotificationPreferences = .default {
        didSet {
            notificationPreferences.save(to: services.configurationStore)
        }
    }
    var logoDevAPIKey: String = "" {
        didSet {
            services.configurationStore.setValue(logoDevAPIKey, for: AppConfigurationKeys.Integrations.logoDevAPIKey)
        }
    }
    var isLogoDevEnabled = false {
        didSet {
            services.configurationStore.setValue(
                isLogoDevEnabled,
                for: AppConfigurationKeys.Integrations.isLogoDevEnabled
            )
        }
    }
    var favoriteMarketSymbols: [String] = []
    var favoriteMarketAssetBySymbol: [String: AlpacaAsset] = [:]
    var favoriteMarketQuotesBySymbol: [String: MarketActiveSymbol] = [:]
    var cachedMarketOverview: MarketOverview?
    var isLoadingFavoriteMarketSymbols = false
    var favoriteMarketSymbolsError: String?
    var portfolio = PortfolioState()
    var lastError: String?
    var credentialMessage: String?

    @ObservationIgnored static let favoritesWatchlistName = "favorites"
    @ObservationIgnored let services: AppServices
    @ObservationIgnored var credentials: AlpacaCredentials?
    @ObservationIgnored var verifiedCredentialFingerprint: String?
    @ObservationIgnored var marketAssetCache: [AlpacaAsset]?
    @ObservationIgnored var marketAssetCacheDate: Date?
    @ObservationIgnored var watchlistAssetCache: [AlpacaAsset]?
    @ObservationIgnored var watchlistAssetCacheDate: Date?
    @ObservationIgnored var favoritesWatchlist: AlpacaWatchlist?
    @ObservationIgnored let marketAssetCacheTTL: TimeInterval = 60 * 60
    @ObservationIgnored let watchlistAssetCacheTTL: TimeInterval = 60 * 60
    @ObservationIgnored var searchPopularSymbolsCache: [MarketMostActiveSort: [MarketActiveSymbol]] = [:]
    @ObservationIgnored var searchPopularSymbolsCacheDate: [MarketMostActiveSort: Date] = [:]
    @ObservationIgnored let searchPopularSymbolsCacheTTL: TimeInterval = 60
    @ObservationIgnored var searchResultCache: [SearchResultCacheKey: TimedCacheEntry<[MarketSearchResult]>] = [:]
    @ObservationIgnored let searchResultCacheTTL: TimeInterval = 20
    @ObservationIgnored var newsPageCache: [NewsPageCacheKey: TimedCacheEntry<AlpacaNewsPage>] = [:]
    @ObservationIgnored let newsPageCacheTTL: TimeInterval = 45
    @ObservationIgnored var optionChainPageCache: [OptionChainPageCacheKey: TimedCacheEntry<AlpacaOptionChainPage>] = [:]
    @ObservationIgnored let optionChainPageCacheTTL: TimeInterval = 20
    @ObservationIgnored var optionExpirationCache: [OptionExpirationCacheKey: TimedCacheEntry<[String]>] = [:]
    @ObservationIgnored let optionExpirationCacheTTL: TimeInterval = 5 * 60
    @ObservationIgnored var optionSnapshotCache: [OptionSnapshotCacheKey: TimedCacheEntry<AlpacaOptionSnapshot?>] = [:]
    @ObservationIgnored let optionSnapshotCacheTTL: TimeInterval = 15
    @ObservationIgnored var optionLatestTradeCache: [OptionLatestTradeCacheKey: TimedCacheEntry<AlpacaOptionTrade?>] = [:]
    @ObservationIgnored let optionLatestTradeCacheTTL: TimeInterval = 15
    @ObservationIgnored var optionBarsPageCache: [OptionBarsPageCacheKey: TimedCacheEntry<AlpacaOptionBarsPage>] = [:]
    @ObservationIgnored let optionBarsPageCacheTTL: TimeInterval = 45
    @ObservationIgnored var optionTradesPageCache: [OptionTradesPageCacheKey: TimedCacheEntry<AlpacaOptionTradesPage>] = [:]
    @ObservationIgnored let optionTradesPageCacheTTL: TimeInterval = 30
    @ObservationIgnored var credentialOperationGeneration = 0
    @ObservationIgnored var activityStreamDisposable: Disposable?
    @ObservationIgnored var activityStreamCredentials: AlpacaCredentials?
    @ObservationIgnored var recentActivityRefIDs = Set<String>()
    @ObservationIgnored var recentActivityRefIDOrder: [String] = []
    @ObservationIgnored let recentActivityRefLimit = 50
    @ObservationIgnored var tradeEventStreamDisposable: Disposable?
    @ObservationIgnored var tradeEventStreamCredentials: AlpacaCredentials?
    @ObservationIgnored var recentTradeEventIDs = Set<String>()
    @ObservationIgnored var recentTradeEventIDOrder: [String] = []
    @ObservationIgnored let recentTradeEventLimit = 100

    init(services: AppServices = .live) {
        self.services = services
        let configurationStore = services.configurationStore
        self.environment = configurationStore.value(for: AppConfigurationKeys.App.tradeEnvironment)
        self.appearanceMode = configurationStore.value(for: AppConfigurationKeys.App.appearanceMode)
        self.appLanguage = configurationStore.value(for: AppConfigurationKeys.App.appLanguage)
        self.logoDevAPIKey = configurationStore.value(for: AppConfigurationKeys.Integrations.logoDevAPIKey)
        self.isLogoDevEnabled = configurationStore.value(for: AppConfigurationKeys.Integrations.isLogoDevEnabled)
        self.notificationPreferences = AppNotificationPreferences.load(from: configurationStore)

        if let notificationCenter = services.appNotifier as? AppNotificationCenter {
            notificationCenter.setResponseHandler { [weak self] route in
                self?.handleNotificationRoute(route)
            }
        }
    }

    var canUseAlpacaAPI: Bool {
        hasCredentials && credentialsStatus.isConnected
    }

    var credentialGateState: CredentialGateState {
        guard isCredentialBootstrapComplete else {
            return .loading
        }

        guard hasCredentials, !credentialsStatus.blocksAuthenticatedRoutes else {
            return .requiresCredentials
        }

        return .unlocked
    }

    var maskedCredentialKeyID: String? {
        credentials?.maskedKeyID
    }

    var trimmedLogoDevAPIKey: String {
        logoDevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
