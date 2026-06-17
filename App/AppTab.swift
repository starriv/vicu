import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case markets
    case search
    case orders
    case more

    var id: String { rawValue }

    @MainActor
    @ViewBuilder
    var content: some View {
        switch self {
        case .home:
            HomeView()
        case .markets:
            MarketsView()
        case .search:
            MarketSearchView(presentation: .globalTab)
        case .orders:
            OrdersView()
        case .more:
            MoreView()
        }
    }

    @MainActor
    @ViewBuilder
    var label: some View {
        switch self {
        case .home:
            Label(L10n.Tab.home, image: AppIcon.Tab.home)
        case .markets:
            Label(L10n.Tab.markets, systemImage: AppIcon.Tab.markets)
        case .search:
            Label(L10n.Tab.search, systemImage: AppIcon.Tab.search)
        case .orders:
            Label(L10n.Tab.orders, systemImage: AppIcon.Tab.orders)
        case .more:
            Label(L10n.Tab.more, systemImage: AppIcon.Tab.more)
        }
    }
}
