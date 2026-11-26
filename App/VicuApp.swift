import SwiftUI

@main
struct VicuApp: App {
    @State private var appModel = AppModel()
    @State private var toastCenter = AppToastCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(toastCenter)
                .task {
                    AppImagePipeline.makeShared()
                    await appModel.bootstrap()
                }
        }
    }
}

private struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var ordersNavigationPath: [OrdersRoute] = []

    var body: some View {
        @Bindable var app = app

        Group {
            switch app.credentialGateState {
            case .loading:
                CredentialBootstrapView()
            case .requiresCredentials:
                NavigationStack {
                    AlpacaCredentialOnboardingView()
                }
            case .unlocked:
                appTabs(selection: $app.selectedTab)
            }
        }
        .overlay {
            AppToastOverlay()
        }
        .environment(\.locale, app.appLanguage.locale)
        .preferredColorScheme(app.appearanceMode.colorScheme)
    }

    private func appTabs(selection: Binding<AppTab>) -> some View {
        let activeTab = selection.wrappedValue

        return TabView(selection: selection) {
            Tab(
                L10n.Tab.home,
                image: AppIcon.Tab.assetName(for: .home, isSelected: activeTab == .home),
                value: AppTab.home
            ) {
                NavigationStack {
                    HomeView()
                }
                .tint(.accentColor)
            }

            Tab(
                L10n.Tab.markets,
                image: AppIcon.Tab.assetName(for: .markets, isSelected: activeTab == .markets),
                value: AppTab.markets
            ) {
                NavigationStack {
                    MarketsView()
                }
                .tint(.accentColor)
            }

            Tab(
                L10n.Tab.orders,
                image: AppIcon.Tab.assetName(for: .orders, isSelected: activeTab == .orders),
                value: AppTab.orders
            ) {
                NavigationStack(path: $ordersNavigationPath) {
                    OrdersView()
                        .navigationDestination(for: OrdersRoute.self) { route in
                            switch route {
                            case .orderDetail(let request):
                                OrderDetailView(orderID: request.orderID, symbol: request.symbol)
                            }
                        }
                }
                .tint(.accentColor)
            }

            Tab(
                L10n.Tab.more,
                image: AppIcon.Tab.assetName(for: .more, isSelected: activeTab == .more),
                value: AppTab.more
            ) {
                NavigationStack {
                    MoreView()
                }
                .tint(.accentColor)
            }
        }
        // Monochrome tab bar only; each tab's content re-applies the app accent
        // so buttons, links and pickers keep the brand color.
        .tint(.primary)
        .task {
            openPendingOrderDetail(app.pendingOrderDetailRequest)
        }
        .onChange(of: app.pendingOrderDetailRequest) { _, request in
            openPendingOrderDetail(request)
        }
    }

    private func openPendingOrderDetail(_ request: OrderDetailNavigationRequest?) {
        guard let request else {
            return
        }

        if app.selectedTab != .orders {
            app.selectedTab = .orders
        }
        ordersNavigationPath = [.orderDetail(request)]
        app.consumeOrderDetailRequest(request)
    }
}

private enum OrdersRoute: Hashable {
    case orderDetail(OrderDetailNavigationRequest)
}

private struct CredentialBootstrapView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(L10n.Alpaca.bootstrapLoading)
                .font(AppTypography.detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
    }
}
