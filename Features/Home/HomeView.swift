import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var accountPolling = HomeAccountPolling()

    var body: some View {
        BasicLayout(L10n.Tab.home) {
            HomeAccountButton()
        } content: {
            HomeHeroView()
            AccountMetricsView()
            PositionsSummaryView()
            RecentOrdersSummaryView()
        }
        .refreshable {
            await app.refresh()
            accountPolling.refreshNow()
        }
        .onAppear {
            accountPolling.start(app: app)
        }
        .onDisappear {
            accountPolling.stop()
        }
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
