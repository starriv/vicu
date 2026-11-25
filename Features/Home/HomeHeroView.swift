import SwiftUI

struct HomeHeroView: View {
    @Environment(AppModel.self) private var app
    var showsInitialSkeleton = false

    @State private var chartMode: PortfolioChartMode = .equity
    @State private var chartSelection: PortfolioChartSelection?
    @State private var isChartScrubbing = false

    private var isLoadingPortfolioChart: Bool {
        app.portfolio.isLoadingHistory || (!app.portfolio.hasLoadedHistory && app.portfolio.isRefreshing)
    }

    /// Stable timestamp anchor per range fetch so 120Hz scrubbing never invalidates
    /// `FinancialChartView`'s O(1) render cache or triggers spurious right-edge haptics.
    private var chartReferenceNow: Date {
        if let updatedAt = app.portfolio.historyUpdatedAtByRange[app.portfolio.historyRange] {
            return updatedAt
        }
        let minuteBucket = floor(Date().timeIntervalSince1970 / 60.0) * 60.0
        return Date(timeIntervalSince1970: minuteBucket)
    }

    private func computeNormalizedHistory(now: Date) -> [NormalizedPortfolioHistoryPoint] {
        PortfolioEquitySeriesNormalizer.normalize(
            history: app.portfolio.displayedHistory(for: app.portfolio.historyRange),
            account: app.portfolio.account,
            range: app.portfolio.historyRange,
            now: now
        )
    }

    private func portfolioValue(from history: [NormalizedPortfolioHistoryPoint]) -> Double? {
        PortfolioEquitySeriesNormalizer.liveAccountEquity(from: app.portfolio.account) ??
        history.last?.equity
    }

    private func rangeChange(from history: [NormalizedPortfolioHistoryPoint]) -> PortfolioRangeChange {
        PortfolioRangeChange(amount: history.last?.profitLoss, percent: history.last?.profitLossPercent)
    }

    private func displayedHeroAmount(
        from history: [NormalizedPortfolioHistoryPoint],
        resolvedChange: PortfolioRangeChange
    ) -> Double? {
        if let selectedValue = chartSelection?.point.value {
            return selectedValue
        }

        switch chartMode {
        case .equity:
            return portfolioValue(from: history)
        case .profitLoss:
            return resolvedChange.amount
        }
    }

    private func displayedRangeChange(resolvedChange: PortfolioRangeChange) -> PortfolioRangeChange {
        guard let chartSelection else {
            return resolvedChange
        }

        return PortfolioRangeChange(amount: chartSelection.point.profitLoss, percent: chartSelection.point.profitLossPercent)
    }

    private func changeColor(for change: PortfolioRangeChange) -> Color {
        guard let amount = change.amount else {
            return .secondary
        }

        return amount >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private func heroAmountColor(for heroAmount: Double?) -> Color {
        guard chartMode == .profitLoss,
              let amount = heroAmount else {
            return .primary
        }

        return amount >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var body: some View {
        Group {
            if showsInitialSkeleton {
                HomeHeroSkeleton()
            } else {
                content
            }
        }
        .onChange(of: chartMode) { _, _ in
            clearChartSelection()
        }
        .onChange(of: app.portfolio.historyRange) { _, _ in
            clearChartSelection()
        }
    }

    private var content: some View {
        let referenceNow = chartReferenceNow
        let normalized = computeNormalizedHistory(now: referenceNow)
        let resolvedChange = rangeChange(from: normalized)
        let displayedChange = displayedRangeChange(resolvedChange: resolvedChange)
        let heroAmount = displayedHeroAmount(from: normalized, resolvedChange: displayedChange)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                AppPriceText(
                    heroAmount,
                    font: AppTypography.heroValue,
                    minimumScaleFactor: 0.82,
                    isAnimated: true,
                    animationDuration: chartSelection == nil ? 0.18 : 0.08,
                    isSigned: chartMode == .profitLoss,
                    notation: .compact,
                    usesCompactFormatting: chartMode == .profitLoss
                )
                .foregroundStyle(heroAmountColor(for: heroAmount))
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(AppFormatter.signedCompactMoney(displayedChange.amount))
                    Text("(\(AppFormatter.signedPercent(displayedChange.percent)))")
                    Text(app.portfolio.historyRange.title)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    if app.environment == .paper {
                        Text(L10n.AccountDetail.paperBadge)
                            .font(AppTypography.caption.weight(.medium))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                .font(AppTypography.heroDelta)
                .foregroundStyle(changeColor(for: displayedChange))
            }

            PortfolioChartView(
                mode: chartMode,
                history: normalized,
                referenceNow: referenceNow,
                selection: $chartSelection,
                isScrubbing: $isChartScrubbing
            )
            .frame(height: 216)

            ZStack {
                HStack(spacing: 8) {
                    PortfolioRangePicker()
                        .frame(maxWidth: .infinity)

                    PortfolioChartModePicker(selection: $chartMode)
                }
                .opacity(isChartScrubbing ? 0 : 1)
                .allowsHitTesting(!isChartScrubbing)

                if isChartScrubbing {
                    let ticks = PortfolioChartTimeline.axisLabels(
                        for: app.portfolio.historyRange,
                        dates: normalized.map(\.date),
                        now: referenceNow,
                        locale: app.appLanguage.locale
                    )
                    if !ticks.isEmpty {
                        FinancialChartTimeAxisStrip(labels: ticks)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.16), value: isChartScrubbing)
        }
        .padding(.top, 4)
    }

    private func clearChartSelection() {
        chartSelection = nil
        isChartScrubbing = false
    }
}

private struct PortfolioRangeChange: Equatable {
    let amount: Double?
    let percent: Double?
}

private enum PortfolioChartMode: String, CaseIterable, Identifiable {
    case equity
    case profitLoss

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .equity:
            AppIcon.Portfolio.history
        case .profitLoss:
            "chart.line.uptrend.xyaxis"
        }
    }

    var title: String {
        switch self {
        case .equity:
            "Equity"
        case .profitLoss:
            "P/L"
        }
    }
}

private struct PortfolioChartView: View {
    @Environment(AppModel.self) private var app
    let mode: PortfolioChartMode
    let history: [NormalizedPortfolioHistoryPoint]
    let referenceNow: Date
    @Binding var selection: PortfolioChartSelection?
    @Binding var isScrubbing: Bool
    @State private var chartSelection: FinancialChartSelection?
    @State private var seriesCache = PortfolioChartSeriesCache()

    var body: some View {
        let range = app.portfolio.historyRange
        let prepared = seriesCache.resolve(
            history: history,
            mode: mode,
            range: range,
            referenceNow: referenceNow
        )
        let points = prepared.points
        let isLoadingPortfolioChart = app.portfolio.isLoadingHistory || (!app.portfolio.hasLoadedHistory && app.portfolio.isRefreshing)

        Group {
            if points.count < 2 && !isLoadingPortfolioChart {
                AppEmptyStateView(
                    title: L10n.Common.noData,
                    systemImage: AppIcon.Portfolio.history,
                    minHeight: 216
                )
            } else {
                chart(prepared: prepared, range: range, isLoading: isLoadingPortfolioChart)
            }
        }
        .onChange(of: chartSelection) { _, next in
            guard let next else {
                if selection != nil {
                    selection = nil
                }
                return
            }

            let matchingPoint: PortfolioChartPoint? = {
                if points.indices.contains(next.index), points[next.index].date == next.point.date {
                    return points[next.index]
                }
                return points.first(where: { $0.date == next.point.date })
            }()
            guard let matchingPoint else {
                return
            }

            selection = PortfolioChartSelection(point: matchingPoint)
        }
        .onChange(of: mode) { _, _ in
            clearSelection()
        }
        .onChange(of: app.portfolio.historyRange) { _, _ in
            clearSelection()
        }
    }

    private func chart(
        prepared: PortfolioChartPreparedData,
        range: PortfolioHistoryRange,
        isLoading: Bool
    ) -> some View {
        let style = FinancialChartStyle(
            lineColor: prepared.tint,
            positiveColor: AppTheme.ColorToken.positive,
            negativeColor: AppTheme.ColorToken.negative,
            areaFillStyle: .dotMatrix(spacing: 4.5, dotDiameter: 1.5),
            areaTopOpacity: 0.18,
            areaBottomOpacity: 0.0,
            lineWidth: 2.0,
            glowRadius: 5.0,
            glowOpacity: 0.42,
            referenceLineColor: Color(.tertiaryLabel).opacity(0.42),
            crosshairColor: Color(.tertiaryLabel).opacity(0.85),
            showsGrid: false,
            showsVolume: false,
            showsEndpointPulse: false,
            interpolation: .monotone
        )
        let locale = app.appLanguage.locale

        return FinancialChartView(
            series: prepared.series,
            style: style,
            insets: .compact,
            isLoading: isLoading,
            transitionKey: "\(range.rawValue)-\(mode.rawValue)",
            selection: $chartSelection,
            isScrubbing: $isScrubbing
        ) { point in
            PortfolioChartDateLabelFormatter.string(from: point.date, range: range, locale: locale)
        }
        .accessibilityLabel(L10n.Portfolio.chartAccessibility)
    }

    private func clearSelection() {
        chartSelection = nil
        selection = nil
        isScrubbing = false
    }
}

private struct PortfolioChartPreparedData {
    let points: [PortfolioChartPoint]
    let series: FinancialChartSeries
    let tint: Color
}

/// Caches the prepared `FinancialChartSeries` and point array across 120Hz scrub updates
/// so scrubbing never re-maps or re-hashes the portfolio series.
@MainActor
private final class PortfolioChartSeriesCache {
    private struct CacheKey: Equatable {
        let mode: PortfolioChartMode
        let range: PortfolioHistoryRange
        let referenceTimestamp: TimeInterval
        let count: Int
        let firstTimestamp: TimeInterval?
        let lastTimestamp: TimeInterval?
        let lastEquity: Double?
        let lastProfitLoss: Double?
        let checksum: Int
    }

    private var lastKey: CacheKey?
    private var lastValue: PortfolioChartPreparedData?

    func resolve(
        history: [NormalizedPortfolioHistoryPoint],
        mode: PortfolioChartMode,
        range: PortfolioHistoryRange,
        referenceNow: Date
    ) -> PortfolioChartPreparedData {
        var hasher = Hasher()
        hasher.combine(history.count)
        for point in history {
            hasher.combine(point.date.timeIntervalSince1970)
            switch mode {
            case .equity:
                hasher.combine(point.equity)
            case .profitLoss:
                hasher.combine(point.profitLoss)
            }
        }
        let key = CacheKey(
            mode: mode,
            range: range,
            referenceTimestamp: referenceNow.timeIntervalSince1970,
            count: history.count,
            firstTimestamp: history.first?.date.timeIntervalSince1970,
            lastTimestamp: history.last?.date.timeIntervalSince1970,
            lastEquity: history.last?.equity,
            lastProfitLoss: history.last?.profitLoss,
            checksum: hasher.finalize()
        )
        if let lastKey, lastKey == key, let lastValue {
            return lastValue
        }

        var points: [PortfolioChartPoint] = []
        var financialPoints: [FinancialChartPoint] = []
        var dates: [Date] = []
        points.reserveCapacity(history.count)
        financialPoints.reserveCapacity(history.count)
        dates.reserveCapacity(history.count)

        for point in history {
            let value: Double?
            switch mode {
            case .equity:
                value = point.equity
            case .profitLoss:
                value = point.profitLoss
            }

            guard let value, value.isFinite else {
                continue
            }

            let xPosition = point.date.timeIntervalSince1970
            points.append(
                PortfolioChartPoint(
                    date: point.date,
                    xPosition: xPosition,
                    value: value,
                    profitLoss: point.profitLoss,
                    profitLossPercent: point.profitLossPercent
                )
            )
            financialPoints.append(
                FinancialChartPoint(date: point.date, x: xPosition, value: value)
            )
            dates.append(point.date)
        }

        let baselinePolicy: FinancialChartBaselinePolicy = mode == .profitLoss
            ? .softInclude(value: 0, maxExpansionRatio: 0.60, showsReferenceLine: true)
            : .none
        let scaleConfig: FinancialChartYScaleConfig = mode == .profitLoss
            ? .portfolioProfitLoss
            : .portfolioEquity
        let xDomain = PortfolioChartTimeline.xDomain(for: range, dates: dates, now: referenceNow)
        let series = FinancialChartSeries(
            kind: .area,
            points: financialPoints,
            xDomain: xDomain,
            baselinePolicy: baselinePolicy,
            yScaleConfig: scaleConfig,
            allowsZoomAndPan: false
        )
        let tint: Color = if mode == .profitLoss {
            (points.last?.value ?? 0) >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
        } else {
            AppTheme.ColorToken.brand
        }

        let prepared = PortfolioChartPreparedData(points: points, series: series, tint: tint)
        lastKey = key
        lastValue = prepared
        return prepared
    }
}

private struct PortfolioChartPoint: Identifiable, Equatable {
    let date: Date
    let xPosition: Double
    let value: Double
    let profitLoss: Double?
    let profitLossPercent: Double?

    var id: Date { date }
}

private struct PortfolioChartSelection: Equatable {
    let point: PortfolioChartPoint
}

private enum PortfolioChartDateLabelFormatter {
    private static let cache = LockedPortfolioChartDateFormatterCache()

    static func string(from date: Date, range: PortfolioHistoryRange, locale: Locale) -> String {
        cache.string(from: date, range: range, locale: locale)
    }
}

// @unchecked Sendable: DateFormatter dictionary guarded by NSLock
private final class LockedPortfolioChartDateFormatterCache: @unchecked Sendable {
    private struct Key: Hashable {
        let range: PortfolioHistoryRange
        let localeIdentifier: String
        let timeZoneIdentifier: String
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]

    func string(from date: Date, range: PortfolioHistoryRange, locale: Locale) -> String {
        let resolvedLocale = AppLocale.resolvedLocale(for: locale)
        let timeZone: TimeZone = switch range {
        case .oneDay, .oneWeek:
            // Matches 1D/1W axis ticks in device local timezone so crosshair and axis dates never drift by 1 day.
            .current
        case .oneMonth, .threeMonths, .oneYear, .yearToDate:
            PortfolioHistoryRange.newYorkTimeZone
        }
        let key = Key(
            range: range,
            localeIdentifier: resolvedLocale.identifier,
            timeZoneIdentifier: timeZone.identifier
        )

        lock.lock()
        defer { lock.unlock() }

        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.locale = resolvedLocale
            created.timeZone = timeZone
            switch range {
            case .oneDay:
                created.setLocalizedDateFormatFromTemplate("yMdHm")
            case .oneWeek:
                created.setLocalizedDateFormatFromTemplate("MMMdHm")
            case .oneMonth, .threeMonths, .oneYear, .yearToDate:
                created.setLocalizedDateFormatFromTemplate("yMMMd")
            }
            formatters[key] = created
            formatter = created
        }

        return formatter.string(from: date)
    }
}

private struct PortfolioRangePicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.locale) private var locale

    var body: some View {
        AppRangePicker(
            options: PortfolioHistoryRange.allCases,
            selection: app.portfolio.historyRange,
            layout: .compact,
            isDisabled: false,
            title: \.title,
            accessibilityLabel: { range in
                L10n.PortfolioRange.accessibility(title: range.title, locale: locale)
            }
        ) { range in
            Task {
                await app.selectPortfolioHistoryRange(range)
            }
        }
    }
}

private struct PortfolioChartModePicker: View {
    @Binding var selection: PortfolioChartMode

    var body: some View {
        Menu {
            ForEach(PortfolioChartMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.title, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: selection.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 30)
                .contentShape(Capsule())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .modifier(PortfolioChartModeButtonStyle())
        .accessibilityLabel("Portfolio chart data")
    }
}

private struct PortfolioChartModeButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.08)).interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.12))
                }
        }
    }
}
