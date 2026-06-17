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
                    await appModel.bootstrap()
                }
        }
    }
}

private struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText = ""
    @State private var searchPlaceholderSymbol = AppModel.searchPlaceholderFallbackSymbol

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
        TabView(selection: selection) {
            Tab(L10n.Tab.home, image: AppIcon.Tab.home, value: AppTab.home) {
                NavigationStack {
                    HomeView()
                }
            }

            Tab(L10n.Tab.markets, systemImage: AppIcon.Tab.markets, value: AppTab.markets) {
                NavigationStack {
                    MarketsView()
                }
            }

            Tab(L10n.Tab.orders, systemImage: AppIcon.Tab.orders, value: AppTab.orders) {
                NavigationStack {
                    OrdersView()
                }
            }

            Tab(L10n.Tab.more, systemImage: AppIcon.Tab.more, value: AppTab.more) {
                NavigationStack {
                    MoreView()
                }
            }

            Tab(L10n.Tab.search, systemImage: AppIcon.Tab.search, value: AppTab.search, role: .search) {
                NavigationStack {
                    MarketSearchView(query: $searchText, presentation: .globalTab)
                }
                .searchable(text: $searchText, prompt: Text(searchPlaceholderSymbol))
            }
        }
        .tabBarMinimizeOnScrollIfAvailable()
        .task {
            await refreshSearchPlaceholderSymbol()
        }
        .onChange(of: app.selectedTab) { _, selectedTab in
            guard selectedTab == .search else {
                return
            }

            Task {
                await refreshSearchPlaceholderSymbol()
            }
        }
    }

    private func refreshSearchPlaceholderSymbol() async {
        searchPlaceholderSymbol = await app.fetchSearchPlaceholderSymbol()
    }
}

private extension View {
    @ViewBuilder
    func tabBarMinimizeOnScrollIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
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
