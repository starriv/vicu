import SwiftUI

struct RecentOrdersSummaryView: View {
    @Environment(AppModel.self) private var app

    private var recentOrders: [AlpacaOrder] {
        Array(app.portfolio.orders.prefix(3))
    }

    var body: some View {
        let orders = recentOrders

        NavigationLink {
            OrdersView()
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
                AppSectionHeader(L10n.Orders.recentTitle) {
                    HStack(spacing: 6) {
                        if !orders.isEmpty {
                            Text("\(orders.count)")
                                .font(AppTypography.detail.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }

                if orders.isEmpty {
                    AppEmptyStateView(
                        title: L10n.Common.noData,
                        systemImage: AppIcon.More.orders,
                        minHeight: 150
                    )
                } else {
                    orderList(orders)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func orderList(_ orders: [AlpacaOrder]) -> some View {
        OrderSummaryListCard(orders: orders)
    }
}

#Preview {
    NavigationStack {
        RecentOrdersSummaryView()
            .environment(AppModel())
    }
}
