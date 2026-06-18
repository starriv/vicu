import SwiftUI

struct OptionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var store: OptionDetailStore
    @State private var chartSelection: AssetChartSelection?
    @State private var isChartScrubbing = false

    init(contractSymbol: String, initialSnapshot: AlpacaOptionSnapshot? = nil) {
        _store = State(initialValue: OptionDetailStore(contractSymbol: contractSymbol, initialSnapshot: initialSnapshot))
    }

    var body: some View {
        AppInfiniteScrollView(
            spacing: 20,
            canLoadMore: false,
            isLoadingMore: false,
            loadMoreTrigger: false,
            loadMore: {}
        ) {
            if !app.hasCredentials {
                ContentUnavailableView(
                    L10n.Common.noData,
                    systemImage: AppIcon.More.alpaca
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if !store.hasInitialContent && store.isLoadingSnapshot {
                OptionDetailSkeleton()
            } else {
                OptionDetailContent(
                    store: store,
                    chartSelection: $chartSelection,
                    isChartScrubbing: $isChartScrubbing
                )
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(store.descriptor.underlyingSymbol)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.start(app: app)
        }
        .refreshable {
            store.reloadAll(forceReload: true)
        }
        .onChange(of: store.snapshotErrorMessage) { _, message in
            showErrorMessage(message)
        }
        .onChange(of: store.chartErrorMessage) { _, message in
            showErrorMessage(message)
        }
        .onDisappear {
            store.stop()
        }
    }

    private func showErrorMessage(_ message: String?) {
        guard let message else {
            return
        }

        toastCenter.showErrorMessage(message)
    }
}

private struct OptionDetailContent: View {
    let store: OptionDetailStore
    @Binding var chartSelection: AssetChartSelection?
    @Binding var isChartScrubbing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OptionDetailHeader(model: store.snapshotModel)

            OptionPriceHeroSection(store: store, chartSelection: $chartSelection)
            OptionChartSection(
                store: store,
                chartSelection: $chartSelection,
                isChartScrubbing: $isChartScrubbing
            )
            OptionQuoteSection(model: store.snapshotModel)
            OptionTradeActionSection(store: store)
            OptionMetricsSection(title: store.snapshotModel.metricsTitle, metrics: store.snapshotModel.metrics)
            OptionMetricsSection(title: "Contract", metrics: store.snapshotModel.specs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OptionDetailHeader: View {
    let model: OptionDetailSnapshotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.descriptor.symbol)
                        .font(.title3.monospaced().weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text("\(model.descriptor.expirationText)  \(model.descriptor.strikeText)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.descriptor.typeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.typeTint)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(model.typeTint.opacity(0.10), in: Capsule())
            }

            Label("Option quotes and trades are delayed.", systemImage: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OptionPriceHeroSection: View {
    let store: OptionDetailStore
    @Binding var chartSelection: AssetChartSelection?

    var body: some View {
        let displayPrice = chartSelection?.point.close ?? store.snapshotModel.displayPrice

        VStack(alignment: .leading, spacing: 4) {
            AppPriceText(
                displayPrice,
                fractionLength: OptionValueText.moneyFractionLength(for: displayPrice),
                font: .system(size: 44, weight: .medium, design: .rounded),
                minimumScaleFactor: 0.72,
                isAnimated: chartSelection == nil
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
                } else if let periodChange = store.chartRenderModels.model(for: store.effectiveChartMode).periodPriceChange {
                    AssetPriceChangeLine(
                        change: periodChange.change,
                        percent: periodChange.percentChange,
                        label: store.selectedRange.performanceLabel,
                        isPositive: periodChange.isPositive
                    )
                } else {
                    Text("Updated \(store.snapshotModel.updatedText)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 34, alignment: .top)
        }
        .redacted(reason: store.isLoadingSnapshot && store.snapshotModel.displayPrice == nil ? .placeholder : [])
    }
}

private struct OptionChartSection: View {
    let store: OptionDetailStore
    @Binding var chartSelection: AssetChartSelection?
    @Binding var isChartScrubbing: Bool

    private static let chartHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                AssetPriceChart(
                    model: store.chartRenderModels.model(for: store.effectiveChartMode),
                    isLoading: store.isLoadingChart,
                    range: store.selectedRange,
                    selection: $chartSelection,
                    isScrubbing: $isChartScrubbing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!store.isLoadingChart)

                if store.isLoadingChart {
                    AssetPeriodChartSkeleton(
                        mode: store.effectiveChartMode,
                        tint: store.chartRenderModels.model(for: store.effectiveChartMode).periodTint
                    )
                    .transition(.opacity)
                }
            }
            .frame(height: Self.chartHeight)
            .animation(.snappy(duration: 0.18), value: store.isLoadingChart)

            HStack(spacing: 12) {
                AssetRangePicker(selection: store.selectedRange) { range in
                    chartSelection = nil
                    isChartScrubbing = false
                    store.selectRange(range)
                }

                Spacer(minLength: 8)

                if store.selectedRange != .oneDay {
                    AssetChartModePicker(
                        selection: Binding(
                            get: { store.chartMode },
                            set: { store.selectChartMode($0) }
                        )
                    )
                }
            }

        }
    }
}

private struct OptionQuoteSection: View {
    let model: OptionDetailSnapshotModel

    var body: some View {
        AssetDetailSection(title: "Quote") {
            VStack(spacing: 12) {
                AssetLevelOneQuoteContent(
                    bidPrice: model.bidPrice,
                    askPrice: model.askPrice,
                    bidSize: model.bidSize,
                    askSize: model.askSize,
                    spread: model.spread,
                    sizeUnit: "contracts",
                    priceFormatter: OptionValueText.money
                )

                HStack {
                    Text("Indicative quote")
                    Spacer()
                    Text(model.updatedText)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct OptionMetricsSection: View {
    let title: String
    let metrics: [OptionDetailMetricModel]

    var body: some View {
        AssetDetailSection(title: title) {
            LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 12) {
                ForEach(metrics) { metric in
                    AssetMetricTile(title: metric.title, value: metric.value)
                }
            }
        }
    }
}

private struct OptionTradeActionSection: View {
    let store: OptionDetailStore

    var body: some View {
        AssetDetailSection(title: "Trade") {
            HStack(spacing: 12) {
                OptionTradeNavigationButton(
                    title: "Buy",
                    subtitle: "Open",
                    tint: OrderSide.buy.tradeActionTint
                ) {
                    OptionTradeView(
                        contractSymbol: store.descriptor.symbol,
                        initialIntent: .buyToOpen,
                        initialSnapshotModel: store.snapshotModel
                    )
                }

                OptionTradeNavigationButton(
                    title: "Sell",
                    subtitle: "Close",
                    tint: OrderSide.sell.tradeActionTint
                ) {
                    OptionTradeView(
                        contractSymbol: store.descriptor.symbol,
                        initialIntent: .sellToClose,
                        initialSnapshotModel: store.snapshotModel
                    )
                }
            }
        }
    }
}

private struct OptionTradeNavigationButton<Destination: View>: View {
    let title: String
    let subtitle: String
    let tint: Color
    let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.bold))

                    Text(subtitle)
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct OptionTradesSection: View {
    let store: OptionDetailStore

    var body: some View {
        AssetDetailSection(title: "Trades") {
            VStack(spacing: 0) {
                if store.isLoadingTrades && store.tradeRows.isEmpty {
                    OptionTradesSkeleton(rowCount: 5)
                } else if store.tradeRows.isEmpty {
                    ContentUnavailableView(
                        "No trades",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("No recent delayed option trades were returned for this range.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    let rows = store.tradeRows
                    let lastID = rows.last?.id

                    ForEach(rows) { row in
                        OptionTradeRow(row: row)
                            .equatable()

                        if row.id != lastID {
                            Divider()
                        }
                    }

                }
            }
            .padding(.horizontal, 14)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct OptionTradeRow: Equatable, View {
    let row: OptionTradeRowModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.priceText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

                Text(row.timeText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(row.sizeText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

                Text(row.exchangeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct OptionDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                AssetSkeletonCapsule(width: 230, height: 22, fill: Color(.secondarySystemFill), cornerRadius: 6)
                AssetSkeletonCapsule(width: 160, height: 14, fill: Color(.tertiarySystemFill), cornerRadius: 5)
                AssetSkeletonCapsule(width: 240, height: 28, fill: Color(.tertiarySystemFill))
            }

            AssetSkeletonCapsule(width: 150, height: 48, fill: Color(.secondarySystemFill), cornerRadius: 16)
            AssetPeriodChartSkeleton(mode: .line)
                .frame(height: 300)

            LazyVGrid(columns: AssetDetailGrid.twoColumns, spacing: 12) {
                ForEach(0..<8, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        AssetSkeletonCapsule(width: [56, 68, 44, 62][index % 4], height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                        AssetSkeletonCapsule(width: [82, 74, 96, 58][index % 4], height: 17, fill: Color(.secondarySystemFill), cornerRadius: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct OptionTradesSkeleton: View {
    let rowCount: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        AssetSkeletonCapsule(width: [74, 86, 66][index % 3], height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)
                        AssetSkeletonCapsule(width: [90, 72, 82][index % 3], height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        AssetSkeletonCapsule(width: [42, 54, 36][index % 3], height: 16, fill: Color(.secondarySystemFill), cornerRadius: 5)
                        AssetSkeletonCapsule(width: 34, height: 11, fill: Color(.tertiarySystemFill), cornerRadius: 4)
                    }
                }
                .padding(.vertical, 12)

                if index < rowCount - 1 {
                    Divider()
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
