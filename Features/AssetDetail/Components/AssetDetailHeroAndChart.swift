import SwiftUI

struct AssetIdentityHeader: View {
    let store: AssetDetailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                Text(verbatim: store.symbol)
                    .font(.title.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.primary)

                if let exchangeText {
                    Text("·")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(.tertiaryLabel))

                    Text(verbatim: exchangeText)
                        .font(.subheadline.weight(.bold))
                }

                MarketSessionTimelineView(
                    timeline: store.sessionTimeline,
                    selectedDate: nil,
                    style: .dot,
                    dotSize: 9
                )
                .padding(.leading, 2)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)

            AppMarqueeText(
                store.displayName,
                font: .title2.weight(.semibold),
                foregroundColor: .primary
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exchangeText: String? {
        store.exchangeText == AppFormatter.placeholder ? nil : store.exchangeText
    }
}

struct AssetHeroChartInteractionSection: View {
    let store: AssetDetailStore
    @State private var chartSelection: AssetChartSelection?
    @State private var isChartScrubbing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AssetPriceHeroSection(store: store, chartSelection: chartSelection)
            AssetChartSection(
                store: store,
                chartSelection: $chartSelection,
                isChartScrubbing: $isChartScrubbing
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetPriceHeroSection: View {
    let store: AssetDetailStore
    let chartSelection: AssetChartSelection?

    var body: some View {
        let activeExtendedSession = chartSelection == nil ? store.activeExtendedSession : nil
        let extendedSession = chartSelection == nil && store.selectedRange == .oneDay ? store.extendedSession : nil
        let extendedChange = extendedSession != nil ? store.extendedPriceChange : nil

        VStack(alignment: .leading, spacing: 4) {
            AppPriceText(
                displayedPrice,
                font: .system(size: 48, weight: .medium, design: .rounded),
                minimumScaleFactor: 0.72,
                isAnimated: true,
                animationDuration: chartSelection == nil ? 0.18 : 0.08
            )

            VStack(alignment: .leading, spacing: 2) {
                if let chartSelection {
                    let selectedChange = store.selectedPriceChange(for: chartSelection)
                    AssetPriceChangeLine(
                        change: selectedChange.change,
                        percent: selectedChange.percentChange,
                        label: nil,
                        isPositive: selectedChange.isPositive
                    )
                } else if store.selectedRange != .oneDay, let periodChange = store.chartRenderModels.line.periodPriceChange {
                    AssetPriceChangeLine(
                        change: periodChange.change,
                        percent: periodChange.percentChange,
                        label: store.selectedRange.performanceLabel,
                        isPositive: periodChange.isPositive
                    )
                } else if !(store.selectedRange == .oneDay && activeExtendedSession == .overnight) {
                    AssetPriceChangeLine(
                        change: store.todayPriceChange,
                        percent: store.todayPercentChange,
                        label: "Today",
                        isPositive: store.isTodayPositive
                    )
                }

                if let extendedSession, let extendedChange {
                    AssetPriceChangeLine(
                        change: extendedChange,
                        percent: store.extendedPercentChange,
                        label: store.extendedSessionTitle ?? extendedSession.title,
                        isPositive: extendedChange >= 0
                    )
                } else if let chartSelection,
                          store.showsTradeMarkers,
                          store.selectedRange != .oneDay {
                    let selectedMarkers = store.tradeMarkers(for: chartSelection.point)
                    if !selectedMarkers.isEmpty {
                        AssetChartTradeSelectionLine(markers: selectedMarkers)
                    } else {
                        AssetPriceChangeLine(
                            change: nil,
                            percent: nil,
                            label: "Placeholder",
                            isPositive: true
                        )
                        .hidden()
                    }
                } else {
                    AssetPriceChangeLine(
                        change: nil,
                        percent: nil,
                        label: "Placeholder",
                        isPositive: true
                    )
                    .hidden()
                }
            }
            .frame(height: 38, alignment: .top)
        }
        .redacted(reason: store.isLoading ? .placeholder : [])
    }

    private var displayedPrice: Double? {
        chartSelection?.point.close ?? store.currentPrice
    }
}

private struct AssetChartSection: View {
    @Environment(AppModel.self) private var app
    let store: AssetDetailStore
    @Binding var chartSelection: AssetChartSelection?
    @Binding var isChartScrubbing: Bool

    // Cached formatted axis tick labels so 120Hz scrubbing doesn't run 5 locked DateFormatters per frame.
    @State private var cachedScrubAxisDates: [Date?] = []
    @State private var cachedScrubAxisRange: AssetChartRange = .oneDay
    @State private var cachedScrubAxisTicks: [String] = []

    private static let linePlotHeight: CGFloat = 228
    private static let candlePlotHeight: CGFloat = 272
    private static let timelineHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                AssetPriceChart(
                    model: store.chartRenderModels.model(for: store.effectiveChartMode),
                    isLoading: store.isLoadingChart,
                    range: store.selectedRange,
                    tradeMarkers: store.chartTradeMarkers,
                    selection: $chartSelection,
                    isScrubbing: $isChartScrubbing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.selectedRange == .oneDay {
                    MarketSessionTimelineView(
                        timeline: store.sessionTimeline,
                        selectedDate: chartSelection?.point.date
                    )
                    .frame(height: Self.timelineHeight)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                    .opacity(isChartScrubbing ? 1 : 0)
                    .animation(.easeOut(duration: 0.16), value: isChartScrubbing)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: resolvedPlotHeight)
            .animation(.snappy(duration: 0.22), value: store.effectiveChartMode)

            ZStack {
                HStack(spacing: 8) {
                    AssetRangePicker(selection: store.selectedRange) { range in
                        chartSelection = nil
                        isChartScrubbing = false
                        store.selectRange(range)
                    }

                    if store.selectedRange != .oneDay {
                        AssetChartModePicker(
                            selection: Binding(
                                get: { store.chartMode },
                                set: { store.selectChartMode($0) }
                            ),
                            showsTradeMarkers: Binding(
                                get: { app.showsChartTradeMarkers },
                                set: { app.showsChartTradeMarkers = $0 }
                            )
                        )
                    }
                }
                .opacity(isChartScrubbing ? 0 : 1)
                .allowsHitTesting(!isChartScrubbing)

                if isChartScrubbing, !cachedScrubAxisTicks.isEmpty {
                    FinancialChartTimeAxisStrip(labels: cachedScrubAxisTicks)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isChartScrubbing)
        }
        .onChange(of: chartSelection?.axisDates) { _, nextDates in
            syncScrubAxisTicks(for: nextDates ?? [], range: store.selectedRange)
        }
        .onChange(of: store.selectedRange) { _, nextRange in
            if isChartScrubbing {
                syncScrubAxisTicks(for: chartSelection?.axisDates ?? [], range: nextRange)
            } else {
                cachedScrubAxisDates = []
                cachedScrubAxisTicks = []
            }
        }
    }

    private func syncScrubAxisTicks(for dates: [Date?], range: AssetChartRange) {
        if dates == cachedScrubAxisDates && range == cachedScrubAxisRange {
            return
        }
        cachedScrubAxisDates = dates
        cachedScrubAxisRange = range
        cachedScrubAxisTicks = dates.map { date in
            date.map { AssetChartDateLabelFormatter.axisTick(from: $0, range: range) } ?? ""
        }
    }

    private var resolvedPlotHeight: CGFloat {
        store.effectiveChartMode == .candles ? Self.candlePlotHeight : Self.linePlotHeight
    }
}
