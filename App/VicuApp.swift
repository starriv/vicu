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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tab whose icon is drawn as selected. Lags `app.selectedTab` briefly (see `tabIconSwapDelay`);
    /// nil until the first sync so the restored tab never flashes the home icon.
    @State private var displayedSelectedTab: AppTab?
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
        let iconTab = displayedSelectedTab ?? selection.wrappedValue

        return TabView(selection: selection) {
            Tab(
                L10n.Tab.home,
                image: AppIcon.Tab.assetName(for: .home, isSelected: iconTab == .home),
                value: AppTab.home
            ) {
                NavigationStack {
                    HomeView()
                }
                .tint(.accentColor)
            }

            Tab(
                L10n.Tab.markets,
                image: AppIcon.Tab.assetName(for: .markets, isSelected: iconTab == .markets),
                value: AppTab.markets
            ) {
                NavigationStack {
                    MarketsView()
                }
                .tint(.accentColor)
            }

            Tab(
                L10n.Tab.orders,
                image: AppIcon.Tab.assetName(for: .orders, isSelected: iconTab == .orders),
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
                image: AppIcon.Tab.assetName(for: .more, isSelected: iconTab == .more),
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
        .task(id: app.selectedTab) {
            let targetTab = app.selectedTab
            guard let currentTab = displayedSelectedTab, !reduceMotion else {
                // First sync, or no glass morph to wait for.
                displayedSelectedTab = targetTab
                return
            }
            guard currentTab != targetTab else {
                return
            }
            // Wait for the Liquid Glass tab-selection morph to settle before swapping
            // custom UITab images so the glass lens doesn't get interrupted mid-stretch.
            try? await Task.sleep(for: Self.tabIconSwapDelay)
            guard !Task.isCancelled else {
                return
            }
            displayedSelectedTab = targetTab
        }
        .task {
            openPendingOrderDetail(app.pendingOrderDetailRequest)
        }
        .onChange(of: app.pendingOrderDetailRequest) { _, request in
            openPendingOrderDetail(request)
        }
    }

    /// Tuned by eye against the iOS 26.0 tab bar selection morph; revisit if the system animation changes.
    private static let tabIconSwapDelay: Duration = .milliseconds(260)

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
