import Charts
import SwiftUI

struct HomeHeroView: View {
    @Environment(AppModel.self) private var app
    var showsInitialSkeleton = false
    @State private var chartMode: PortfolioChartMode = .equity
    @State private var chartSelection: PortfolioChartSelection?
    @State private var isChartScrubbing = false

    private var portfolioValue: Double? {
        app.portfolio.history.last?.equity ??
        NumberParser.double(from: app.portfolio.account?.portfolioValue) ??
        NumberParser.double(from: app.portfolio.account?.equity)
    }

    private var rangeChange: (amount: Double?, percent: Double?) {
        guard let latest = app.portfolio.history.last else {
            return (nil, nil)
        }

        let amount = latest.profitLoss ?? computedRangeChangeAmount
        let percent = latest.profitLossPercent ?? computedRangeChangePercent
        return (amount, percent)
    }

    private var computedRangeChangeAmount: Double? {
        guard let first = app.portfolio.history.first?.equity,
              let last = app.portfolio.history.last?.equity else {
            return nil
        }

        return last - first
    }

    private var computedRangeChangePercent: Double? {
        guard let first = app.portfolio.history.first?.equity,
              first != 0,
              let amount = computedRangeChangeAmount else {
            return nil
        }

        return amount / first
    }

    private var displayedHeroAmount: Double? {
        chartSelection?.point.value ?? currentChartAmount
    }

    private var currentChartAmount: Double? {
        switch chartMode {
        case .equity:
            portfolioValue
        case .profitLoss:
            rangeChange.amount
        }
    }

    private var displayedRangeChange: (amount: Double?, percent: Double?) {
        guard let chartSelection else {
            return rangeChange
        }

        switch chartMode {
        case .equity:
            return (chartSelection.change, chartSelection.percentChange)
        case .profitLoss:
            return (
                chartSelection.point.value,
                chartSelection.point.profitLossPercent ?? chartSelection.percentFromBaseline
            )
        }
    }

    private var changeColor: Color {
        guard let amount = displayedRangeChange.amount else {
            return .secondary
        }

        return amount >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var heroAmountColor: Color {
        guard chartMode == .profitLoss,
              let amount = displayedHeroAmount else {
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
        VStack(alignment: .leading, spacing: 18) {
            AppPriceText(
                displayedHeroAmount,
                font: AppTypography.heroValue,
                minimumScaleFactor: 0.82,
                isAnimated: chartSelection == nil,
                isSigned: chartMode == .profitLoss,
                notation: .compact
            )
            .foregroundStyle(heroAmountColor)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(AppFormatter.signedCompactMoney(displayedRangeChange.amount))
                Text("(\(AppFormatter.signedPercent(displayedRangeChange.percent)))")
                Text(app.portfolio.historyRange.title)
                    .foregroundStyle(.secondary)
            }
            .font(AppTypography.heroDelta)
            .foregroundStyle(changeColor)

            PortfolioChartView(
                mode: chartMode,
                selection: $chartSelection,
                isScrubbing: $isChartScrubbing
            )
                .frame(height: 230)

            HStack(spacing: 12) {
                PortfolioRangePicker()

                Spacer(minLength: 8)

                PortfolioChartModePicker(selection: $chartMode)
            }
        }
        .padding(.top, 4)
    }

    private func clearChartSelection() {
        chartSelection = nil
        isChartScrubbing = false
    }
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
    @Binding var selection: PortfolioChartSelection?
    @Binding var isScrubbing: Bool
    @State private var overlayLabel: PortfolioChartOverlayLabel?

    var body: some View {
        let points = chartPoints

        ZStack {
            if points.isEmpty {
                PortfolioChartEmptyState(
                    isLoading: !app.portfolio.hasLoadedHistory && (app.portfolio.isRefreshing || app.portfolio.isLoadingHistory)
                )
            } else {
                chart(points: points)
            }

            if app.portfolio.isLoadingHistory && !points.isEmpty {
                ProgressView()
                    .padding(14)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .animation(.snappy, value: chartRevision(for: points))
        .animation(.snappy, value: app.portfolio.isLoadingHistory)
        .animation(.snappy, value: mode)
        .onChange(of: mode) { _, _ in
            clearSelection()
        }
        .onChange(of: app.portfolio.historyRange) { _, _ in
            clearSelection()
        }
    }

    private func chart(points: [PortfolioChartPoint]) -> some View {
        let domain = yDomain(for: points)
        let areaBaseline = areaBaseline(for: domain)
        let chartTint = chartTint(for: points)

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Point", point.xPosition),
                    yStart: .value("Floor", areaBaseline),
                    yEnd: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            chartTint.opacity(0.24),
                            chartTint.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Point", point.xPosition),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(chartTint)
            }

            if let selectedPoint = selection?.point {
                RuleMark(x: .value("Selected", selectedPoint.xPosition))
                    .foregroundStyle(Color(.tertiaryLabel).opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))
                    .zIndex(-1)

                PointMark(
                    x: .value("Selected Point", selectedPoint.xPosition),
                    y: .value("Selected Value", selectedPoint.value)
                )
                .foregroundStyle(chartTint)
                .symbolSize(58)
                .zIndex(2)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain(for: points))
        .chartYScale(domain: domain)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
                .contentShape(Rectangle())
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if let overlayLabel {
                        Text(overlayLabel.text)
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .fixedSize()
                            .position(x: overlayLabel.x, y: 12)
                            .allowsHitTesting(false)
                    }

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isScrubbing = true
                                    updateSelectedPoint(
                                        at: value.location,
                                        proxy: proxy,
                                        geometry: geometry,
                                        points: points
                                    )
                                }
                                .onEnded { _ in
                                    clearSelection()
                                }
                        )
                }
            }
        }
        .accessibilityLabel(L10n.Portfolio.chartAccessibility)
    }

    private func chartRevision(for points: [PortfolioChartPoint]) -> PortfolioChartRevision {
        PortfolioChartRevision(
            count: points.count,
            firstDate: points.first?.date,
            lastDate: points.last?.date,
            lastValue: points.last?.value
        )
    }

    private var chartPoints: [PortfolioChartPoint] {
        let history = app.portfolio.history
        let firstEquity = history.first?.equity

        return history.enumerated().compactMap { offset, point in
            let value: Double?
            switch mode {
            case .equity:
                value = point.equity
            case .profitLoss:
                value = point.profitLoss ?? firstEquity.map { point.equity - $0 }
            }

            guard let value, value.isFinite else {
                return nil
            }

            return PortfolioChartPoint(
                date: point.date,
                xPosition: Double(offset),
                value: value,
                profitLossPercent: point.profitLossPercent
            )
        }
    }

    private func xDomain(for points: [PortfolioChartPoint]) -> ClosedRange<Double> {
        guard let first = points.first, let last = points.last, last.xPosition > first.xPosition else {
            return 0...1
        }

        return first.xPosition...last.xPosition
    }

    private func yDomain(for points: [PortfolioChartPoint]) -> ClosedRange<Double> {
        var values = points.map(\.value)
        if mode == .profitLoss {
            values.append(0)
        }

        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.12, 1)
            return (minValue - padding)...(maxValue + padding)
        }

        let padding = (maxValue - minValue) * 0.12
        return (minValue - padding)...(maxValue + padding)
    }

    private func areaBaseline(for domain: ClosedRange<Double>) -> Double {
        switch mode {
        case .equity:
            domain.lowerBound
        case .profitLoss:
            min(max(0, domain.lowerBound), domain.upperBound)
        }
    }

    private func chartTint(for points: [PortfolioChartPoint]) -> Color {
        guard mode == .profitLoss else {
            return AppTheme.ColorToken.brand
        }

        return (points.last?.value ?? 0) >= 0 ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private func clearSelection() {
        selection = nil
        overlayLabel = nil
        isScrubbing = false
    }

    private func updateSelectedPoint(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [PortfolioChartPoint]
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.width > 0 else {
            return
        }

        let xPosition = min(max(location.x - plotFrame.origin.x, 0), plotFrame.width)
        guard let chartPosition = proxy.value(atX: xPosition, as: Double.self),
              let nearestPoint = PortfolioChartPoint.nearest(in: points, to: chartPosition) else {
            return
        }

        selection = PortfolioChartSelection(
            point: nearestPoint,
            baseline: app.portfolio.history.first?.equity
        )
        overlayLabel = PortfolioChartOverlayLabel(
            text: nearestPoint.dateLabel(for: app.portfolio.historyRange),
            x: min(max(location.x, 64), geometry.size.width - 64)
        )
    }
}

private struct PortfolioChartPoint: Identifiable, Equatable {
    let date: Date
    let xPosition: Double
    let value: Double
    let profitLossPercent: Double?

    var id: Date { date }

    func dateLabel(for range: PortfolioHistoryRange) -> String {
        PortfolioChartDateLabelFormatter.string(from: date, range: range)
    }

    static func nearest(in points: [PortfolioChartPoint], to xPosition: Double) -> PortfolioChartPoint? {
        guard !points.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = points.count - 1

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if points[midpoint].xPosition < xPosition {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let next = points[lowerBound]
        guard lowerBound > 0 else {
            return next
        }

        let previous = points[lowerBound - 1]
        return abs(previous.xPosition - xPosition) <= abs(next.xPosition - xPosition) ? previous : next
    }
}

private struct PortfolioChartRevision: Equatable {
    let count: Int
    let firstDate: Date?
    let lastDate: Date?
    let lastValue: Double?
}

private struct PortfolioChartSelection: Equatable {
    let point: PortfolioChartPoint
    let baseline: Double?

    var change: Double? {
        guard let baseline else {
            return nil
        }

        return point.value - baseline
    }

    var percentChange: Double? {
        guard let baseline, baseline != 0, let change else {
            return nil
        }

        return change / baseline
    }

    var percentFromBaseline: Double? {
        guard let baseline, baseline != 0 else {
            return nil
        }

        return point.value / baseline
    }
}

private struct PortfolioChartOverlayLabel: Sendable {
    let text: String
    let x: CGFloat
}

private enum PortfolioChartDateLabelFormatter {
    private static let intradayFormatter = makeFormatter("h:mm a")
    private static let shortRangeFormatter = makeFormatter("MMM d, h:mm a")
    private static let longRangeFormatter = makeFormatter(
        "MMM d, yyyy",
        timeZone: TimeZone(identifier: "America/New_York")
    )

    static func string(from date: Date, range: PortfolioHistoryRange) -> String {
        let formatter = switch range {
        case .oneDay:
            intradayFormatter
        case .oneWeek:
            shortRangeFormatter
        case .oneMonth, .threeMonths, .oneYear, .yearToDate:
            longRangeFormatter
        }

        return formatter.string(from: date).uppercased()
    }

    private static func makeFormatter(_ dateFormat: String, timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter
    }
}

private struct PortfolioChartEmptyState: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            HomeChartSkeleton()
                .frame(maxWidth: .infinity, minHeight: 230)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            AppEmptyStateView(
                title: L10n.Common.noData,
                systemImage: AppIcon.Portfolio.history,
                minHeight: 230
            )
        }
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
            isDisabled: app.portfolio.isLoadingHistory,
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
