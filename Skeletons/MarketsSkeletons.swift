import SwiftUI

struct MarketOverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MarketStatusCard(overview: .skeleton, usesSkeletonStyle: true)
            MarketListModePicker(selection: .constant(.favorites))
            MarketSymbolSectionSkeleton(rowCount: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MarketSymbolRowsSkeleton: View {
    let rowCount: Int

    var body: some View {
        ForEach(Array(MarketOverview.skeleton.mostActive.prefix(rowCount))) { symbol in
            MarketSymbolRow(item: MarketSymbolItem(activeSymbol: symbol))
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

struct MarketSearchPopularSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 7) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 17, height: 17)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 116, height: 18)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 148, height: 12)
            }

            MarketSearchRowsSkeleton(rowCount: rowCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MarketSearchResultsSkeleton: View {
    let rowCount: Int

    var body: some View {
        MarketSearchRowsSkeleton(rowCount: rowCount)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MarketSymbolSectionSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            MarketSymbolRowsSkeleton(rowCount: rowCount)
        }
        .padding(.horizontal, 14)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MarketSearchRowsSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                MarketSearchRowSkeleton(symbolWidth: symbolWidth(for: index))

                if index < rowCount - 1 {
                    Divider()
                }
            }
        }
    }

    private func symbolWidth(for index: Int) -> CGFloat {
        [52, 64, 58, 46, 72, 56][index % 6]
    }
}

private struct MarketSearchRowSkeleton: View {
    let symbolWidth: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: symbolWidth, height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 74, height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 48, height: 11)
            }

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 42, height: 42)
        }
        .frame(minHeight: 64)
        .padding(.vertical, 10)
    }
}

private extension MarketOverview {
    static let skeleton = MarketOverview(
        clock: AlpacaMarketClock(
            timestamp: "2026-06-15T01:30:00-04:00",
            isOpen: false,
            nextOpen: "2026-06-15T04:00:00-04:00",
            nextClose: "2026-06-15T04:00:00-04:00",
            phase: "overnight",
            phaseUntil: "2026-06-15T04:00:00-04:00"
        ),
        calendar: [
            AlpacaCalendarDay(
                date: "2026-06-15",
                coreStart: "2026-06-15T09:30:00-04:00",
                coreEnd: "2026-06-15T16:00:00-04:00",
                preStart: "2026-06-15T04:00:00-04:00",
                preEnd: "2026-06-15T09:30:00-04:00",
                postStart: "2026-06-15T16:00:00-04:00",
                postEnd: "2026-06-15T20:00:00-04:00",
                settlementDate: nil
            )
        ],
        overnightCalendar: [],
        indexQuotes: [
            MarketIndexQuote(id: "SPY", title: "S&P 500", symbol: "SPY", price: 741.67, change: 4.02, percentChange: 0.0054),
            MarketIndexQuote(id: "QQQ", title: "Nasdaq 100", symbol: "QQQ", price: 722.10, change: 5.43, percentChange: 0.0076),
            MarketIndexQuote(id: "DIA", title: "Dow", symbol: "DIA", price: 513.20, change: 3.88, percentChange: 0.0076)
        ],
        gainers: [],
        losers: [],
        mostActive: [
            MarketActiveSymbol(symbol: "QQQ", companyName: "Invesco QQQ Trust, Series 1", price: 722.10, change: 5.43, percentChange: 0.0076, volume: nil, tradeCount: nil),
            MarketActiveSymbol(symbol: "SNDK", companyName: "Sandisk Corporation Common Stock", price: 1969.21, change: 89.31, percentChange: 0.0475, volume: nil, tradeCount: nil),
            MarketActiveSymbol(symbol: "NVDA", companyName: "NVIDIA Corporation Common Stock", price: 205.10, change: 0.24, percentChange: 0.0012, volume: nil, tradeCount: nil),
            MarketActiveSymbol(symbol: "SQQQ", companyName: "ProShares UltraPro Short QQQ", price: 39.92, change: -0.84, percentChange: -0.0206, volume: nil, tradeCount: nil)
        ]
    )
}
