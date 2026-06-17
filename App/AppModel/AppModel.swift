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
            UserDefaults.standard.set(environment.rawValue, forKey: TradeEnvironment.storageKey)
        }
    }
    var hasCredentials = false
    var isCredentialBootstrapComplete = false
    var credentialsStatus: CredentialsStatus = .missing
    var connectionDiagnostics: ConnectionDiagnostics?
    var appearanceMode: AppearanceMode = .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: AppearanceMode.storageKey)
        }
    }
    var appLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.storageKey)
        }
    }
    var notificationPreferences: AppNotificationPreferences = .default {
        didSet {
            notificationPreferences.save()
        }
    }
    var logoDevAPIKey: String = "" {
        didSet {
            UserDefaults.standard.set(logoDevAPIKey, forKey: Self.logoDevAPIKeyStorageKey)
        }
    }
    var isLogoDevEnabled = false {
        didSet {
            UserDefaults.standard.set(isLogoDevEnabled, forKey: Self.logoDevEnabledStorageKey)
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

    @ObservationIgnored private static let logoDevAPIKeyStorageKey = "logoDevAPIKey"
    @ObservationIgnored private static let logoDevEnabledStorageKey = "logoDevEnabled"
    @ObservationIgnored static let favoritesWatchlistName = "favorites"
    @ObservationIgnored let services: AppServices
    @ObservationIgnored var credentials: AlpacaCredentials?
    @ObservationIgnored var verifiedCredentialFingerprint: String?
    @ObservationIgnored var marketAssetCache: [AlpacaAsset]?
    @ObservationIgnored var marketAssetCacheDate: Date?
    @ObservationIgnored var favoritesWatchlist: AlpacaWatchlist?
    @ObservationIgnored let marketAssetCacheTTL: TimeInterval = 60 * 60
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
        if let rawEnvironment = UserDefaults.standard.string(forKey: TradeEnvironment.storageKey),
           let environment = TradeEnvironment(rawValue: rawEnvironment) {
            self.environment = environment
        }

        if let rawAppearanceMode = UserDefaults.standard.string(forKey: AppearanceMode.storageKey),
           let appearanceMode = AppearanceMode(rawValue: rawAppearanceMode) {
            self.appearanceMode = appearanceMode
        }

        if let rawAppLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey),
           let appLanguage = AppLanguage(rawValue: rawAppLanguage) {
            self.appLanguage = appLanguage
        }

        self.logoDevAPIKey = UserDefaults.standard.string(forKey: Self.logoDevAPIKeyStorageKey) ?? ""
        self.isLogoDevEnabled = UserDefaults.standard.bool(forKey: Self.logoDevEnabledStorageKey)
        self.notificationPreferences = AppNotificationPreferences.load()

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
