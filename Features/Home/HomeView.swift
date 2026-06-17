import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var accountPolling = HomeAccountPolling()

    var body: some View {
        let loadingState = HomeInitialLoadingState(
            portfolio: app.portfolio,
            credentialsStatus: app.credentialsStatus
        )

        BasicLayout(L10n.Tab.home) {
            HomeAccountButton()
        } content: {
            HomeHeroView(showsInitialSkeleton: loadingState.history)
            AccountMetricsView(showsInitialSkeleton: loadingState.account)
            PositionsSummaryView(showsInitialSkeleton: loadingState.positions)
            RecentOrdersSummaryView(showsInitialSkeleton: loadingState.orders)
        }
        .animation(.snappy(duration: 0.18), value: loadingState)
        .refreshable {
            await app.refresh()
        }
        .onAppear {
            accountPolling.start(app: app)
        }
        .onDisappear {
            accountPolling.stop()
        }
    }
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

private struct HomeAccountButton: View {
    var body: some View {
        NavigationLink {
            AccountView()
        } label: {
            AppAccountAvatar(size: 54, iconSize: 42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.AccountDetail.title)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppModel())
    }
}
