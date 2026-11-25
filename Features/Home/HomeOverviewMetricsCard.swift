import SwiftUI

struct HomeOverviewMetricsCard: View {
    let allocation: PortfolioAllocationBreakdown
    let totalUnrealizedPL: Double
    let hasPositions: Bool
    var showsInitialSkeleton = false

    private var currencyCode: String {
        allocation.currencyCode
    }

    private var positionsMarketValue: Double {
        allocation.longMarketValue + allocation.shortMarketValue
    }

    private var unrealizedPLTint: Color {
        guard hasPositions else { return .secondary }
        return totalUnrealizedPL >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var cashTint: Color {
        allocation.cashBalance < 0 ? AppTheme.ColorToken.negative : .primary
    }

    var body: some View {
        if showsInitialSkeleton {
            HomeOverviewMetricsSkeleton()
        } else {
            NavigationLink {
                AccountView()
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
                    AppSectionHeader(L10n.HomeAI.overviewSectionTitle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            metricCell(
                                title: L10n.Account.buyingPower,
                                value: AppFormatter.compactMoney(allocation.buyingPower, currencyCode: currencyCode),
                                valueTint: .primary
                            )

                            Divider()
                                .padding(.vertical, 12)

                            metricCell(
                                title: L10n.Account.cash,
                                value: AppFormatter.compactMoney(allocation.cashBalance, currencyCode: currencyCode),
                                valueTint: cashTint
                            )
                        }

                        Divider()
                            .padding(.horizontal, 16)

                        HStack(spacing: 0) {
                            metricCell(
                                title: L10n.HomeAI.overviewMarketValue,
                                value: AppFormatter.compactMoney(positionsMarketValue, currencyCode: currencyCode),
                                valueTint: .primary
                            )

                            Divider()
                                .padding(.vertical, 12)

                            metricCell(
                                title: L10n.HomeAI.unrealizedPLTitle,
                                value: hasPositions
                                    ? AppFormatter.signedCompactMoney(totalUnrealizedPL, currencyCode: currencyCode)
                                    : AppFormatter.placeholder,
                                valueTint: unrealizedPLTint
                            )
                        }
                    }
                    .background(
                        AppTheme.ColorToken.groupedSurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous)
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func metricCell(
        title: LocalizedStringKey,
        value: String,
        valueTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
