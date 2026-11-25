import Foundation
import Observation
import RxSwift

@MainActor
@Observable
final class AppModel: AssetDetailServicing {
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
    var isMarketOverviewFromStaleCache = false
    var pageCacheScopeID: String?
    var pageCacheRevision = 0
    var isLoadingFavoriteMarketSymbols = false
    var hasLoadedFavoriteMarketSymbols = false
    var favoriteMarketSymbolsError: String?
    var portfolio = PortfolioState()
    var lastError: String?
    var credentialMessage: String?

    @ObservationIgnored static let favoritesWatchlistName = "favorites"
    @ObservationIgnored let services: AppServices
    @ObservationIgnored var credentials: AlpacaCredentials?
    @ObservationIgnored var verifiedCredentialFingerprint: String?
    @ObservationIgnored var favoritesWatchlist: AlpacaWatchlist?
    @ObservationIgnored let marketCacheQueue = DispatchQueue(label: "vicu.market-page-cache", qos: .utility)
    @ObservationIgnored var favoriteCacheRevision = 0
    var cachedMarketOverviewAt: Date?
    @ObservationIgnored var favoriteMarketSymbolsUpdatedAt: Date?
    @ObservationIgnored var inFlightMarketOverviewTask: Task<MarketOverview, Error>?
    @ObservationIgnored var inFlightFavoriteSymbolsTask: Task<Void, Never>?
    @ObservationIgnored var inFlightFavoritesWatchlistTask: Task<AlpacaWatchlist, Error>?
    /// Bumped whenever the user mutates favorites so an overlapping refresh
    /// does not overwrite the newer optimistic or server-confirmed state.
    @ObservationIgnored var favoriteMutationGeneration = 0
    @ObservationIgnored let assetCache = MarketAssetCache()
    @ObservationIgnored let searchCache = SearchDataCache()
    @ObservationIgnored let newsCache = NewsDataCache()
    @ObservationIgnored let optionCache = OptionDataCache()
    @ObservationIgnored var credentialOperationGeneration = 0
    @ObservationIgnored lazy var realtimeCoordinator: RealtimeEventCoordinator = RealtimeEventCoordinator(app: self)

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

    var preferredLocale: Locale {
        appLanguage.locale
    }
}
