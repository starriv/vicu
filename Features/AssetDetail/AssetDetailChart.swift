import SwiftUI

enum AssetChartMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case line
    case candles

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .line:
            "chart.xyaxis.line"
        case .candles:
            "chart.bar.xaxis"
        }
    }

    var title: String {
        switch self {
        case .line:
            "Line"
        case .candles:
            "Candles"
        }
    }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .line:
            L10n.Chart.line
        case .candles:
            L10n.Chart.candles
        }
    }

    var financialChartKind: FinancialChartKind {
        switch self {
        case .line:
            .area
        case .candles:
            .candles
        }
    }
}

struct AssetChartRenderModels: Sendable {
    let line: AssetChartRenderModel
    let candles: AssetChartRenderModel

    static let empty = AssetChartRenderModels(
        line: .empty(mode: .line),
        candles: .empty(mode: .candles)
    )

    func model(for mode: AssetChartMode) -> AssetChartRenderModel {
        switch mode {
        case .line:
            line
        case .candles:
            candles
        }
    }
}

struct AssetChartRenderModel: Sendable {
    let mode: AssetChartMode
    let points: [AssetChartPoint]
    let financialPoints: [FinancialChartPoint]
    let pointsDigest: Int
    let xDomain: ClosedRange<Double>
    let priceChangeBaseline: Double?
    let periodPriceChange: AssetPeriodPriceChange?
    let isPeriodPositive: Bool

    static func empty(mode: AssetChartMode) -> AssetChartRenderModel {
        AssetChartRenderModel(
            mode: mode,
            points: [],
            financialPoints: [],
            pointsDigest: FinancialChartSeries.pointsDigest(for: []),
            xDomain: 0...1,
            priceChangeBaseline: nil,
            periodPriceChange: nil,
            isPeriodPositive: true
        )
    }

    var periodTint: Color {
        isPeriodPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    /// O(1) mode switch that reuses the precomputed points, digest, domain, and period metrics.
    func withMode(_ newMode: AssetChartMode) -> AssetChartRenderModel {
        guard mode != newMode else {
            return self
        }
        return AssetChartRenderModel(
            mode: newMode,
            points: points,
            financialPoints: financialPoints,
            pointsDigest: pointsDigest,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline,
            periodPriceChange: periodPriceChange,
            isPeriodPositive: isPeriodPositive
        )
    }

    /// O(1) per SwiftUI body evaluation: reuses pre-converted `financialPoints`, precomputed `pointsDigest`,
    /// and pre-hashed `tradeMarkers` so 120Hz scrubbing never re-maps or re-hashes the full series.
    func makeFinancialSeries(
        for range: AssetChartRange,
        tradeMarkers: AssetChartTradeMarkerSet = .empty
    ) -> FinancialChartSeries {
        let baselinePolicy: FinancialChartBaselinePolicy
        if range == .oneDay, mode == .line, let baseline = priceChangeBaseline {
            baselinePolicy = .softInclude(
                value: baseline,
                maxExpansionRatio: 0.55,
                showsReferenceLine: true
            )
        } else {
            baselinePolicy = .none
        }

        let activeMarkers = range == .oneDay ? [] : tradeMarkers.markers
        let activeMarkersDigest = range == .oneDay ? 0 : tradeMarkers.digest

        return FinancialChartSeries(
            pointsDigest: pointsDigest,
            kind: mode.financialChartKind,
            points: financialPoints,
            xDomain: xDomain,
            baselinePolicy: baselinePolicy,
            yScaleConfig: .financialPrice,
            allowsZoomAndPan: mode == .candles,
            tradeMarkers: activeMarkers,
            tradeMarkersDigest: activeMarkersDigest
        )
    }
}

enum AssetChartPreprocessor {
    static func makeRenderModels(from bars: [AlpacaMarketBar]) -> AssetChartRenderModels {
        let inputBars = bars.enumerated().map { offset, bar in
            AssetChartInputBar(bar: bar, xPosition: Double(offset))
        }
        return makeRenderModels(from: inputBars, xDomain: nil, priceChangeBaseline: nil, mode: .line)
    }

    static func makeRenderModels(
        from inputBars: [AssetChartInputBar],
        xDomain: ClosedRange<Double>?,
        priceChangeBaseline: Double?,
        mode: AssetChartMode
    ) -> AssetChartRenderModels {
        let points = inputBars.compactMap { inputBar in
            AssetChartPoint(bar: inputBar.bar, parsedDate: inputBar.date, xPosition: inputBar.xPosition)
        }
        let financialPoints = points.map(\.financialPoint)
        let pointsDigest = FinancialChartSeries.pointsDigest(for: financialPoints)

        let lineModel = makeRenderModel(
            points: points,
            financialPoints: financialPoints,
            pointsDigest: pointsDigest,
            mode: .line,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline
        )
        // Share the exact same CoW point arrays & precomputed digest for O(1) instant Line <-> Candles switching.
        let candleModel = lineModel.withMode(.candles)

        return AssetChartRenderModels(
            line: lineModel,
            candles: candleModel
        )
    }

    private static func makeRenderModel(
        points: [AssetChartPoint],
        financialPoints: [FinancialChartPoint],
        pointsDigest: Int,
        mode: AssetChartMode,
        xDomain: ClosedRange<Double>?,
        priceChangeBaseline: Double?
    ) -> AssetChartRenderModel {
        let baseline = priceChangeBaseline ?? points.first?.close
        let resolvedXDomain = xDomain ?? Self.xDomain(for: points)

        return AssetChartRenderModel(
            mode: mode,
            points: points,
            financialPoints: financialPoints,
            pointsDigest: pointsDigest,
            xDomain: resolvedXDomain,
            priceChangeBaseline: baseline,
            periodPriceChange: periodPriceChange(for: points, baseline: baseline),
            isPeriodPositive: isPeriodPositive(for: points, baseline: baseline)
        )
    }

    private static func xDomain(for points: [AssetChartPoint]) -> ClosedRange<Double> {
        guard let first = points.first, let last = points.last, last.xPosition > first.xPosition else {
            return 0...1
        }
        return first.xPosition...last.xPosition
    }

    private static func periodPriceChange(for points: [AssetChartPoint], baseline: Double?) -> AssetPeriodPriceChange? {
        guard let baseline, let last = points.last else {
            return nil
        }
        return AssetPeriodPriceChange(current: last.close, baseline: baseline)
    }

    private static func isPeriodPositive(for points: [AssetChartPoint], baseline: Double?) -> Bool {
        guard let baseline, let last = points.last else {
            return true
        }
        return last.close >= baseline
    }
}

struct AssetPriceChart: View {
    let model: AssetChartRenderModel
    let isLoading: Bool
    let range: AssetChartRange
    var tradeMarkers: AssetChartTradeMarkerSet = .empty
    @Binding var selection: AssetChartSelection?
    @Binding var isScrubbing: Bool

    @State private var chartSelection: FinancialChartSelection?

    var body: some View {
        let series = model.makeFinancialSeries(for: range, tradeMarkers: tradeMarkers)
        let activeTint: Color = if let selection, model.mode == .line {
            selection.isPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
        } else {
            model.periodTint
        }
        let style = FinancialChartStyle(
            lineColor: activeTint,
            positiveColor: AppTheme.ColorToken.positive,
            negativeColor: AppTheme.ColorToken.negative,
            areaFillStyle: .dotMatrix(spacing: 4.5, dotDiameter: 1.5),
            areaTopOpacity: 0.20,
            areaBottomOpacity: 0.0,
            lineWidth: 2.0,
            glowRadius: 5.0,
            glowOpacity: 0.45,
            referenceLineColor: Color(.tertiaryLabel).opacity(0.45),
            crosshairColor: Color(.tertiaryLabel).opacity(0.90),
            volumeOpacity: 0.28,
            showsGrid: false,
            showsVolume: model.mode == .candles,
            showsEndpointPulse: model.mode == .line && !isLoading,
            showsHighLowCallouts: model.mode == .candles,
            interpolation: .monotone
        )

        FinancialChartView(
            series: series,
            style: style,
            insets: model.mode == .line ? .okxSimple : .standard,
            isLoading: isLoading,
            transitionKey: "\(range.rawValue)-\(model.mode.rawValue)",
            selection: $chartSelection,
            isScrubbing: $isScrubbing
        ) { point in
            AssetChartDateLabelFormatter.string(from: point.date, range: range)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: chartSelection) { _, next in
            guard let next else {
                if selection != nil {
                    selection = nil
                }
                return
            }

            let assetPoint = AssetChartPoint(financialPoint: next.point)
            let baseline = model.priceChangeBaseline ?? model.points.first?.close ?? assetPoint.open
            selection = AssetChartSelection(point: assetPoint, baseline: baseline, axisDates: next.axisDates)
        }
        .onChange(of: model.mode) { _, _ in
            clearSelection()
        }
        .onChange(of: range) { _, _ in
            clearSelection()
        }
    }

    private func clearSelection() {
        chartSelection = nil
        selection = nil
        isScrubbing = false
    }
}

struct AssetChartModePicker: View {
    @Binding var selection: AssetChartMode
    var showsTradeMarkers: Binding<Bool>? = nil

    var body: some View {
        Menu {
            Section {
                ForEach(AssetChartMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        if selection == mode {
                            Label(mode.localizedTitle, systemImage: "checkmark")
                        } else {
                            Label(mode.localizedTitle, systemImage: mode.icon)
                        }
                    }
                }
            }

            if let showsTradeMarkers {
                Section {
                    Toggle(isOn: showsTradeMarkers) {
                        Label(L10n.Chart.tradeMarkers, systemImage: "arrow.up.arrow.down.circle")
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: selection.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 32)
                    .contentShape(Capsule())

                if showsTradeMarkers?.wrappedValue == true {
                    Circle()
                        .fill(AppTheme.ColorToken.positive)
                        .frame(width: 5, height: 5)
                        .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemFill).opacity(0.75), in: Capsule())
        .accessibilityLabel(L10n.Chart.optionsAccessibility)
    }
}

/// Compact inline trade execution readout shown in the reserved hero subline while scrubbing
/// over a bar that contains buy/sell fills (zero layout shift).
struct AssetChartTradeSelectionLine: View {
    let markers: [FinancialChartTradeMarker]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                if index > 0 {
                    Text("·")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    Text(marker.side == .buy ? "B" : "S")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(
                            marker.side == .buy ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative,
                            in: Circle()
                        )

                    Text(Self.summaryText(for: marker))
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.76)
        .accessibilityElement(children: .combine)
    }

    private static func summaryText(for marker: FinancialChartTradeMarker) -> String {
        let qtyText = formatQuantity(marker.totalQuantity)
        let priceText = FinancialChartBaseCanvas.formatExtremaPrice(marker.averagePrice)
        if marker.fillCount > 1 {
            return "\(qtyText) @ \(priceText) (\(marker.fillCount))"
        }
        return "\(qtyText) @ \(priceText)"
    }

    private static func formatQuantity(_ value: Double) -> String {
        guard value.isFinite else {
            return AppFormatter.placeholder
        }
        let rounded = value.rounded()
        if abs(value - rounded) < 1e-6 {
            return rounded.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
        }
        return value.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US")))
    }
}

struct AssetRangePicker: View {
    let selection: AssetChartRange
    let select: (AssetChartRange) -> Void

    var body: some View {
        AppRangePicker(
            options: AssetChartRange.allCases,
            selection: selection,
            layout: .compact,
            title: \.title,
            select: select
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssetChartSelection: Sendable {
    let point: AssetChartPoint
    let baseline: Double
    let axisDates: [Date?]

    var change: Double {
        point.close - baseline
    }

    var percentChange: Double? {
        guard baseline != 0 else {
            return nil
        }

        return change / baseline
    }

    var isPositive: Bool {
        change >= 0
    }
}

struct AssetPeriodPriceChange: Sendable {
    let current: Double
    let baseline: Double

    var change: Double {
        current - baseline
    }

    var percentChange: Double? {
        guard baseline != 0 else {
            return nil
        }

        return change / baseline
    }

    var isPositive: Bool {
        change >= 0
    }
}

struct AssetChartInputBar: Sendable {
    let bar: AlpacaMarketBar
    let date: Date?
    let xPosition: Double

    init(bar: AlpacaMarketBar, date: Date? = nil, xPosition: Double) {
        self.bar = bar
        self.date = date
        self.xPosition = xPosition
    }
}

struct AssetChartPoint: Identifiable, Sendable {
    let date: Date
    let xPosition: Double
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var id: Date { date }

    var tint: Color {
        close >= open ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    var financialPoint: FinancialChartPoint {
        FinancialChartPoint(
            date: date,
            x: xPosition,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
        )
    }

    func dateLabel(for range: AssetChartRange) -> String {
        AssetChartDateLabelFormatter.string(from: date, range: range)
    }

    init?(bar: AlpacaMarketBar, parsedDate: Date? = nil, xPosition: Double = 0) {
        guard let date = parsedDate ?? AlpacaDateParser.date(bar.timestamp),
              let close = bar.close,
              close.isFinite else {
            return nil
        }

        let open = bar.open ?? close
        self.date = date
        self.xPosition = xPosition
        self.open = open
        self.high = max(bar.high ?? close, open, close)
        self.low = min(bar.low ?? close, open, close)
        self.close = close
        self.volume = max(bar.volume ?? 0, 0)
    }

    init(date: Date, xPosition: Double, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.date = date
        self.xPosition = xPosition
        self.open = open
        self.high = max(high, open, close)
        self.low = min(low, open, close)
        self.close = close
        self.volume = max(volume, 0)
    }

    init(financialPoint: FinancialChartPoint) {
        self.date = financialPoint.date
        self.xPosition = financialPoint.x
        self.open = financialPoint.open
        self.high = financialPoint.high
        self.low = financialPoint.low
        self.close = financialPoint.close
        self.volume = financialPoint.volume
    }
}

enum AssetChartDateLabelFormatter {
    private static let formatter = LockedAssetChartDateFormatter()

    static func string(from date: Date, range: AssetChartRange) -> String {
        formatter.string(from: date, range: range)
    }

    static func axisTick(from date: Date, range: AssetChartRange) -> String {
        formatter.axisTick(from: date, range: range)
    }
}

// @unchecked Sendable: DateFormatter access guarded by NSLock
private final class LockedAssetChartDateFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let intradayFormatter = makeFormatter("MM/dd/yyyy, HH:mm")
    private let shortRangeFormatter = makeFormatter("MMM d, HH:mm")
    private let longRangeFormatter = makeFormatter(
        "MMM d, yyyy",
        timeZone: TimeZone(identifier: "America/New_York")
    )
    private let intradayTickFormatter = makeFormatter("HH:mm")
    private let shortTickFormatter = makeFormatter("M/d")
    private let dailyTickFormatter = makeFormatter(
        "M/d",
        timeZone: TimeZone(identifier: "America/New_York")
    )
    private let longTickFormatter = makeFormatter(
        "MMM yy",
        timeZone: TimeZone(identifier: "America/New_York")
    )

    func string(from date: Date, range: AssetChartRange) -> String {
        lock.lock()
        defer { lock.unlock() }

        let formatter = switch range {
        case .oneDay:
            intradayFormatter
        case .oneWeek:
            shortRangeFormatter
        case .oneMonth, .threeMonths, .oneYear, .yearToDate:
            longRangeFormatter
        }

        return formatter.string(from: date)
    }

    func axisTick(from date: Date, range: AssetChartRange) -> String {
        lock.lock()
        defer { lock.unlock() }

        let formatter = switch range {
        case .oneDay:
            intradayTickFormatter
        case .oneWeek:
            shortTickFormatter
        case .oneMonth, .threeMonths:
            dailyTickFormatter
        case .oneYear, .yearToDate:
            longTickFormatter
        }

        return formatter.string(from: date)
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

extension AssetChartRange {
    var performanceLabel: String {
        switch self {
        case .oneDay:
            "Today"
        case .oneWeek:
            "Past week"
        case .oneMonth:
            "Past month"
        case .threeMonths:
            "Past 3 months"
        case .oneYear:
            "Past year"
        case .yearToDate:
            "Year to date"
        }
    }
}
