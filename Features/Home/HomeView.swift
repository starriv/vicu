import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var accountPolling = HomeAccountPolling()
    @State private var intelligenceSnapshot: PortfolioIntelligenceSnapshot?
    @State private var copilotLaunch: HomeCopilotLaunchRequest?
    @State private var activeNavigation: HomeNavigationRoute?
    @State private var activeTrade: HomeTradeRoute?

    var body: some View {
        let loadingState = HomeInitialLoadingState(
            portfolio: app.portfolio,
            credentialsStatus: app.credentialsStatus
        )
        let snapshot = intelligenceSnapshot ?? LocalPortfolioIntelligenceService().analyzeSync(
            portfolio: app.portfolio,
            environment: app.environment,
            locale: app.appLanguage.locale
        )

        BasicLayout(L10n.HomeAI.cockpitTitle, style: .scroll(spacing: AppTheme.Spacing.section)) {
            HomeHeroView(showsInitialSkeleton: loadingState.history)

            HomeOverviewMetricsCard(
                allocation: snapshot.allocation,
                totalUnrealizedPL: snapshot.attribution.totalUnrealizedPL,
                hasPositions: !app.portfolio.positions.isEmpty,
                showsInitialSkeleton: loadingState.account
            )

            HomeAllocationCard(
                allocation: snapshot.allocation,
                showsInitialSkeleton: loadingState.account && loadingState.positions
            )

            PositionsSummaryView(
                showsInitialSkeleton: loadingState.positions,
                positionWeights: snapshot.positionWeightsBySymbol
            )

            RecentOrdersSummaryView(showsInitialSkeleton: loadingState.orders)
        }
        .modifier(HomePaperNavigationSubtitleModifier(isPaper: app.environment == .paper))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    copilotLaunch = HomeCopilotLaunchRequest(initialPrompt: nil)
                } label: {
                    Image(systemName: AppIcon.Intelligence.copilot)
                }
                .accessibilityLabel(L10n.HomeAI.copilotTitle)
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    HomeAccountButton()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    HomeAccountButton()
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: loadingState)
        .refreshable {
            await app.refresh()
        }
        .task(id: intelligenceSignature) {
            await recomputeIntelligence()
        }
        .onAppear {
            accountPolling.start(app: app)
        }
        .onDisappear {
            accountPolling.stop()
        }
        .navigationDestination(item: $activeNavigation) { route in
            switch route {
            case .account:
                AccountView()
            case .orders:
                OrdersView()
            case .positions:
                PositionsView()
            case .position(let symbol):
                if let position = app.portfolio.positions.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) {
                    PositionDetailView(position: position)
                } else {
                    PositionDetailView(symbol: symbol)
                }
            case .asset(let symbol):
                AssetDetailView(symbol: symbol)
            }
        }
        .sheet(item: $copilotLaunch) { launch in
            HomeAICopilotSheet(
                snapshot: snapshot,
                initialPrompt: launch.initialPrompt,
                onSelectDestination: { destination in
                    copilotLaunch = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        handleActionDestination(destination)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeTrade) { trade in
            NavigationStack {
                switch trade {
                case .stock(let symbol, let side):
                    TradeView(symbol: symbol, side: side)
                case .option(let symbol, let intent):
                    OptionTradeView(contractSymbol: symbol, initialIntent: intent)
                }
            }
        }
    }

    private var intelligenceSignature: Int {
        let portfolio = app.portfolio
        var hasher = Hasher()
        hasher.combine(portfolio.account)
        hasher.combine(portfolio.positions)
        for order in portfolio.orders {
            hasher.combine(order.id)
            hasher.combine(order.status)
            hasher.combine(order.symbol)
        }
        hasher.combine(portfolio.historyRange)
        hasher.combine(portfolio.historyUpdatedAtByRange[portfolio.historyRange])
        hasher.combine(app.environment)
        hasher.combine(app.appLanguage)
        return hasher.finalize()
    }

    private func recomputeIntelligence() async {
        let next = await app.analyzePortfolioIntelligence()
        guard !Task.isCancelled else { return }
        intelligenceSnapshot = next
    }

    private func handleActionDestination(_ destination: PortfolioAIActionDestination) {
        switch destination {
        case .position(let symbol):
            activeNavigation = .position(symbol: symbol)
        case .asset(let symbol):
            activeNavigation = .asset(symbol: symbol)
        case .account:
            activeNavigation = .account
        case .orders:
            activeNavigation = .orders
        case .positions:
            activeNavigation = .positions
        case .trade(let symbol, let side):
            activeTrade = .stock(symbol, side)
        case .closeOption(let symbol, let intent):
            activeTrade = .option(symbol, intent)
        case .copilot(let prompt):
            copilotLaunch = HomeCopilotLaunchRequest(initialPrompt: prompt)
        }
    }
}

private struct HomeCopilotLaunchRequest: Identifiable, Equatable {
    let id = UUID()
    let initialPrompt: String?
}

private enum HomeTradeRoute: Hashable, Identifiable {
    case stock(String, OrderSide)
    case option(String, OrderPositionIntent)

    var id: Self { self }
}

private enum HomeNavigationRoute: Hashable {
    case account
    case orders
    case positions
    case position(symbol: String)
    case asset(symbol: String)
}

private struct HomeInitialLoadingState: Equatable {
    let account: Bool
    let positions: Bool
    let orders: Bool
    let history: Bool

    init(portfolio: PortfolioState, credentialsStatus: CredentialsStatus) {
        let isInitialPortfolioRefresh = credentialsStatus.isTesting || portfolio.isRefreshing
        account = !portfolio.hasLoadedAccount && isInitialPortfolioRefresh
        positions = !portfolio.hasLoadedPositions && isInitialPortfolioRefresh
        orders = !portfolio.hasLoadedOrders && isInitialPortfolioRefresh
        history = !portfolio.hasLoadedHistory && (isInitialPortfolioRefresh || portfolio.isLoadingHistory)
    }
}

private struct HomePaperNavigationSubtitleModifier: ViewModifier {
    let isPaper: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isPaper {
            content.navigationSubtitle(L10n.AccountDetail.paperBadge)
        } else {
            content
        }
    }
}

private struct HomeAccountButton: View {
    var body: some View {
        NavigationLink {
            AccountView()
        } label: {
            if #available(iOS 26.0, *) {
                AppAccountAvatar(size: 44, iconSize: 44)
            } else {
                AppAccountAvatar(size: 36, iconSize: 34)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.AccountDetail.title)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppModel())
            .environment(AppToastCenter())
    }
}
