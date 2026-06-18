import SwiftUI

struct AccountMetricsView: View {
    @Environment(AppModel.self) private var app
    var showsInitialSkeleton = false

    var body: some View {
        let account = app.portfolio.account
        let currencyCode = account?.currency ?? "USD"

        if showsInitialSkeleton {
            HomeAccountMetricsSkeleton()
        } else {
            NavigationLink {
                AccountView()
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
                    AppSectionHeader(L10n.Account.sectionTitle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 0) {
                        AppMetricRow(title: L10n.Account.buyingPower, value: AppFormatter.compactMoney(account?.buyingPower, currencyCode: currencyCode), systemImage: AppIcon.Account.buyingPower)
                        Divider().padding(.leading, 44)
                        AppMetricRow(title: L10n.Account.cash, value: AppFormatter.compactMoney(account?.cash, currencyCode: currencyCode), systemImage: AppIcon.Account.cash)
                        Divider().padding(.leading, 44)
                        AppMetricRow(title: L10n.Account.longMarketValue, value: AppFormatter.compactMoney(account?.longMarketValue, currencyCode: currencyCode), systemImage: AppIcon.Account.longMarketValue)
                        Divider().padding(.leading, 44)
                        AppMetricRow(title: L10n.Account.shortMarketValue, value: AppFormatter.compactMoney(account?.shortMarketValue, currencyCode: currencyCode), systemImage: AppIcon.Account.shortMarketValue)
                    }
                    .padding(.horizontal, 16)
                    .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
