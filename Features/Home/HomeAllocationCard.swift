import SwiftUI

struct HomeAllocationCard: View {
    @Environment(AppModel.self) private var app
    let allocation: PortfolioAllocationBreakdown
    var showsInitialSkeleton = false

    var body: some View {
        if showsInitialSkeleton {
            HomeAllocationSkeleton()
        } else if !allocation.segments.isEmpty {
            NavigationLink {
                PositionsView()
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.group) {
                    AppSectionHeader(L10n.HomeAI.tabAllocation) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        AllocationProportionBar(segments: allocation.segments)
                            .frame(height: 6)

                        VStack(spacing: 0) {
                            ForEach(allocation.segments) { segment in
                                allocationRow(segment)

                                if segment.id != allocation.segments.last?.id {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    .padding(16)
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

    private func allocationRow(_ segment: PortfolioAllocationSegment) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Self.color(for: segment.category))
                .frame(width: 8, height: 8)

            Text(categoryTitle(segment.category))
                .font(AppTypography.rowTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(AppFormatter.compactMoney(segment.value, currencyCode: allocation.currencyCode))
                .font(AppTypography.rowValue)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(AppFormatter.percent(segment.weight, fractionLength: 1))
                .font(AppTypography.detail.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }

    private func categoryTitle(_ category: PortfolioAllocationCategory) -> String {
        let locale = app.appLanguage.locale
        switch category {
        case .stock: return PositionAssetCategory.stock.title(locale: locale)
        case .etf: return PositionAssetCategory.etf.title(locale: locale)
        case .option: return PositionAssetCategory.option.title(locale: locale)
        case .crypto: return PositionAssetCategory.crypto.title(locale: locale)
        case .cash: return L10n.string("account.cash", locale: locale)
        }
    }

    static func color(for category: PortfolioAllocationCategory) -> Color {
        switch category {
        case .stock: AppTheme.ColorToken.brandAlt
        case .etf: Color(.systemIndigo).opacity(0.75)
        case .option: Color(.systemTeal).opacity(0.8)
        case .crypto: Color(.systemOrange).opacity(0.8)
        case .cash: Color(.systemGray3)
        }
    }
}

private struct AllocationProportionBar: View {
    let segments: [PortfolioAllocationSegment]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(max(0, segments.count - 1))
            let availableWidth = max(0, proxy.size.width - totalSpacing)
            let totalWeight = max(segments.reduce(0.0) { $0 + max(0, $1.weight) }, 1e-9)

            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    let fraction = max(0, segment.weight) / totalWeight
                    Capsule()
                        .fill(HomeAllocationCard.color(for: segment.category))
                        .frame(width: availableWidth * fraction)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipShape(Capsule())
        }
    }
}
