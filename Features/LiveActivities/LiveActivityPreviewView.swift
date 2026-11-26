#if DEBUG
import SwiftUI

/// Debug-only gallery that renders the exact Live Activity cards with fixture data.
/// Useful on-device because nobody wants to wait for a real fill to check a layout.
struct LiveActivityPreviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @State private var measuredOrderCardHeight: CGFloat = 0
    @State private var measuredSessionCardHeight: CGFloat = 0

    private var locale: Locale { app.appLanguage.locale }

    private var workingOrderModel: OrderActivityCardModel {
        orderModel(
            symbol: "AAPL",
            side: .buy,
            phase: .partiallyFilled,
            detail: L10n.LiveActivity.detailAveragePrice("$230.98", locale: locale),
            progress: 0.6,
            ratio: "6/10",
            additional: L10n.LiveActivity.additionalWorking(2, locale: locale),
            allowsCancellation: true
        )
    }

    private var regularSessionModel: SessionActivityCardModel {
        sessionModel(phase: .regular)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section(title: "Order · working") {
                    OrderActivityLockScreenCard(model: workingOrderModel)
                        .background(heightReader(for: LiveActivityOrderHeightKey.self))
                        .onPreferenceChange(LiveActivityOrderHeightKey.self) { height in
                            measuredOrderCardHeight = height
                        }
                }

                section(title: "Order · filled") {
                    OrderActivityLockScreenCard(model: orderModel(
                        symbol: "NVDA",
                        side: .sell,
                        phase: .filled,
                        detail: L10n.LiveActivity.detailAveragePrice("$182.34", locale: locale),
                        progress: 1,
                        ratio: "25/25",
                        additional: nil,
                        allowsCancellation: false
                    ))
                }

                section(title: "Order · rejected") {
                    OrderActivityLockScreenCard(model: orderModel(
                        symbol: "TSLA",
                        side: .buy,
                        phase: .rejected,
                        detail: L10n.LiveActivity.detailLimitPrice("$240.00", locale: locale),
                        progress: 0,
                        ratio: "0/8",
                        additional: nil,
                        allowsCancellation: false
                    ))
                }

                section(title: "Session · regular") {
                    SessionActivityLockScreenCard(model: regularSessionModel)
                        .background(heightReader(for: LiveActivitySessionHeightKey.self))
                        .onPreferenceChange(LiveActivitySessionHeightKey.self) { height in
                            measuredSessionCardHeight = height
                        }
                }

                section(title: "Session · pre-market") {
                    SessionActivityLockScreenCard(model: sessionModel(phase: .preMarket))
                }

                islandSection(title: "Dynamic Island · Order") {
                    VStack(spacing: 12) {
                        compactPill {
                            OrderActivityCompactLeading(model: workingOrderModel)
                        } trailing: {
                            OrderActivityCompactTrailing(model: workingOrderModel)
                        }

                        expandedPill {
                            OrderActivityIslandLeading(model: workingOrderModel)
                        } trailing: {
                            OrderActivityIslandTrailing(model: workingOrderModel)
                        } bottom: {
                            OrderActivityIslandBottom(model: workingOrderModel)
                        }
                    }
                }

                islandSection(title: "Dynamic Island · Session") {
                    VStack(spacing: 12) {
                        compactPill {
                            SessionActivityCompactLeading(model: regularSessionModel)
                        } trailing: {
                            SessionActivityCompactTrailing(model: regularSessionModel)
                        }

                        expandedPill {
                            SessionActivityIslandLeading(model: regularSessionModel)
                        } trailing: {
                            SessionActivityIslandTrailing(model: regularSessionModel)
                        } bottom: {
                            SessionActivityIslandBottom(model: regularSessionModel)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("订单卡高度 \(Int(measuredOrderCardHeight.rounded())) pt · 交易日卡高度 \(Int(measuredSessionCardHeight.rounded())) pt（目标 ≤ 150 pt）")
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            measuredOrderCardHeight <= 150 && measuredSessionCardHeight <= 150
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(Color.red)
                        )

                    Text(L10n.LiveActivity.previewFootnote)
                        .font(AppTypography.detail)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.vertical, 16)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .navigationTitle(L10n.LiveActivity.previewTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? AnyShapeStyle(Color(white: 0.14).opacity(0.95))
                                : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.09)
                                        : Color.black.opacity(0.06),
                                    lineWidth: 0.5
                                )
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.06),
                    radius: 10,
                    x: 0,
                    y: 3
                )
        }
    }

    @ViewBuilder
    private func islandSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .center)
                .environment(\.colorScheme, .dark)
        }
    }

    private func compactPill(
        @ViewBuilder leading: () -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 28) {
            leading()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color.black, in: Capsule())
    }

    private func expandedPill(
        @ViewBuilder leading: () -> some View,
        @ViewBuilder trailing: () -> some View,
        @ViewBuilder bottom: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                leading()
                Spacer(minLength: 12)
                trailing()
            }
            bottom()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func heightReader<Key: PreferenceKey>(for key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }

    private func orderModel(
        symbol: String,
        side: OrderActivitySide,
        phase: OrderActivityPhase,
        detail: String,
        progress: Double,
        ratio: String,
        additional: String?,
        allowsCancellation: Bool
    ) -> OrderActivityCardModel {
        OrderActivityCardModel(
            orderID: UUID().uuidString,
            symbol: symbol,
            side: side,
            sideLabel: side == .buy
                ? L10n.Orders.Detail.sideBuy(locale: locale)
                : L10n.Orders.Detail.sideSell(locale: locale),
            orderTypeLabel: L10n.Orders.Detail.orderTypeLimit(locale: locale),
            phase: phase,
            statusTitle: L10n.LiveActivity.orderStatus(phase, locale: locale),
            detailLine: detail,
            fillProgress: progress,
            fillRatioText: ratio,
            asOfText: L10n.LiveActivity.asOf("10:12", locale: locale),
            cancelActionTitle: allowsCancellation ? L10n.LiveActivity.cancelActionText(locale: locale) : nil,
            additionalOrdersText: additional,
            allowsCancellation: allowsCancellation
        )
    }

    private func sessionModel(phase: MarketSessionKind) -> SessionActivityCardModel {
        let now = Date()
        let regular = phase == .regular
        let titles: [MarketSessionKind] = [.overnight, .preMarket, .regular, .afterHours]
        let weights: [MarketSessionKind: Double] = [
            .overnight: 8 * 3600,
            .preMarket: 5.5 * 3600,
            .regular: 6.5 * 3600,
            .afterHours: 4 * 3600
        ]

        return SessionActivityCardModel(
            marketName: "NYSE",
            phaseTitle: L10n.LiveActivity.sessionPhase(phase, locale: locale),
            phaseSymbol: phase == .regular ? "sun.max.fill" : "sunrise.fill",
            countdownLabel: regular
                ? L10n.LiveActivity.sessionCloses(locale: locale)
                : L10n.LiveActivity.sessionOpens(locale: locale),
            sessionStart: now.addingTimeInterval(regular ? -3.3 * 3600 : -4.75 * 3600),
            transitionAt: now.addingTimeInterval(regular ? 3.2 * 3600 : 45 * 60),
            cycleStart: now.addingTimeInterval(regular ? -2.5 * 3600 : -20 * 60),
            cycleEnd: now.addingTimeInterval(regular ? 12 * 3600 : 14 * 3600),
            segments: titles.map { kind in
                SessionActivitySegment(
                    id: kind.rawValue,
                    title: L10n.LiveActivity.sessionPhaseShort(kind, locale: locale),
                    weight: weights[kind] ?? 3600,
                    isActive: kind == phase
                )
            },
            summaryText: "+$320.12 (+0.28%)",
            summaryIsNegative: false,
            trailingText: L10n.LiveActivity.workingOrders(2, locale: locale)
        )
    }
}

private struct LiveActivityOrderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LiveActivitySessionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif
