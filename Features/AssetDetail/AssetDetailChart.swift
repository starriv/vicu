import Charts
import SwiftUI

enum AssetChartMode: String, CaseIterable, Hashable, Identifiable {
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
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let priceChangeBaseline: Double?
    let periodPriceChange: AssetPeriodPriceChange?
    let isPeriodPositive: Bool
    let candleWidth: CGFloat

    static func empty(mode: AssetChartMode) -> AssetChartRenderModel {
        AssetChartRenderModel(
            mode: mode,
            points: [],
            xDomain: 0...1,
            yDomain: 0...1,
            priceChangeBaseline: nil,
            periodPriceChange: nil,
            isPeriodPositive: true,
            candleWidth: 3
        )
    }

    var periodTint: Color {
        isPeriodPositive ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
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
            AssetChartPoint(bar: inputBar.bar)?.withXPosition(inputBar.xPosition)
        }
        let lineModel = makeRenderModel(
            points: points,
            mode: .line,
            xDomain: xDomain,
            priceChangeBaseline: priceChangeBaseline
        )
        let candleModel = mode == .candles
            ? makeRenderModel(
                points: aggregateCandles(points, maxCount: 180),
                mode: .candles,
                xDomain: xDomain,
                priceChangeBaseline: priceChangeBaseline
            )
            : .empty(mode: .candles)

        return AssetChartRenderModels(
            line: lineModel,
            candles: candleModel
        )
    }

    private static func makeRenderModel(
        points: [AssetChartPoint],
        mode: AssetChartMode,
        xDomain: ClosedRange<Double>?,
        priceChangeBaseline: Double?
    ) -> AssetChartRenderModel {
        let baseline = priceChangeBaseline ?? points.first?.close
        return AssetChartRenderModel(
            mode: mode,
            points: points,
            xDomain: xDomain ?? Self.xDomain(for: points),
            yDomain: yDomain(for: points, baseline: baseline),
            priceChangeBaseline: baseline,
            periodPriceChange: periodPriceChange(for: points, baseline: baseline),
            isPeriodPositive: isPeriodPositive(for: points, baseline: baseline),
            candleWidth: candleWidth(for: points)
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

    private static func yDomain(for points: [AssetChartPoint], baseline: Double?) -> ClosedRange<Double> {
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude

        if let baseline {
            minValue = min(minValue, baseline)
            maxValue = max(maxValue, baseline)
        }

        for point in points {
            minValue = min(minValue, point.low)
            maxValue = max(maxValue, point.high)
        }

        guard minValue.isFinite, maxValue.isFinite, maxValue > minValue else {
            let value = points.last?.close ?? 0
            return (value - 1)...(value + 1)
        }

        let padding = max((maxValue - minValue) * 0.08, 0.01)
        return (minValue - padding)...(maxValue + padding)
    }

    private static func candleWidth(for points: [AssetChartPoint]) -> CGFloat {
        switch points.count {
        case 0...45:
            8
        case 46...90:
            5
        default:
            3
        }
    }

    private static func aggregateCandles(_ points: [AssetChartPoint], maxCount: Int) -> [AssetChartPoint] {
        guard points.count > maxCount, maxCount > 0 else {
            return points
        }

        let bucketSize = Int(ceil(Double(points.count) / Double(maxCount)))
        return stride(from: 0, to: points.count, by: bucketSize).compactMap { startIndex in
            let endIndex = min(points.count, startIndex + bucketSize)
            let bucket = points[startIndex..<endIndex]
            guard let first = bucket.first, let last = bucket.last else {
                return nil
            }

            var high = first.high
            var low = first.low
            var volume = 0.0
            for point in bucket {
                high = max(high, point.high)
                low = min(low, point.low)
                volume += point.volume
            }

            return AssetChartPoint(
                date: first.date,
                xPosition: first.xPosition,
                open: first.open,
                high: high,
                low: low,
                close: last.close,
                volume: volume
            )
        }
    }
}

struct AssetPriceChart: View {
    let model: AssetChartRenderModel
    let isLoading: Bool
    let range: AssetChartRange
    @Binding var selection: AssetChartSelection?
    @Binding var isScrubbing: Bool
    @State private var displayedPresentation: AssetChartPresentation?
    @State private var overlayLabel: AssetChartOverlayLabel?

    private static let overlayHorizontalInset: CGFloat = 22
    private static let oneDayDomainPaddingRatio = 0.012
    private static let oneDayDomainPaddingRange = 0.5...1.5

    var body: some View {
        let currentPresentation = AssetChartPresentation(model: model, range: range)
        let activePresentation = displayedPresentation ?? currentPresentation

        chartContent(
            for: activePresentation,
            showsEndpointPulse: !isLoading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            displayedPresentation = currentPresentation
        }
        .onChange(of: currentPresentation.id) { _, _ in
            applyPresentation(currentPresentation)
        }
        .onChange(of: model.mode) { _, _ in
            clearSelection()
        }
        .onChange(of: range) { _, _ in
            clearSelection()
        }
    }

    @ViewBuilder
    private func chartContent(
        for presentation: AssetChartPresentation,
        showsEndpointPulse: Bool
    ) -> some View {
        if presentation.model.points.count < 2 {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(presentation.model.periodTint.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(AppFormatter.placeholder)
                            .font(AppTypography.detail)
                            .foregroundStyle(.secondary)
                    }
                }
        } else {
            GeometryReader { geometry in
                chartView(for: presentation, showsEndpointPulse: showsEndpointPulse)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func chartView(
        for presentation: AssetChartPresentation,
        showsEndpointPulse: Bool
    ) -> some View {
        Chart {
            switch presentation.model.mode {
            case .line:
                ForEach(presentation.model.points) { point in
                    LineMark(
                        x: .value("Point", point.xPosition),
                        y: .value("Price", point.close)
                    )
                    .foregroundStyle(presentation.model.periodTint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            case .candles:
                ForEach(presentation.model.points) { point in
                    RuleMark(
                        x: .value("Point", point.xPosition),
                        yStart: .value("Low", point.low),
                        yEnd: .value("High", point.high)
                    )
                    .foregroundStyle(point.tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.3, lineCap: .round))

                    RectangleMark(
                        x: .value("Point", point.xPosition),
                        yStart: .value("Open", point.bodyLow),
                        yEnd: .value("Close", point.bodyHigh),
                        width: .fixed(presentation.model.candleWidth)
                    )
                    .foregroundStyle(point.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 1.8, style: .continuous))
                }
            }

            if let selectedPoint = selection?.point {
                RuleMark(x: .value("Selected", selectedPoint.xPosition))
                    .foregroundStyle(Color(.tertiaryLabel).opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round))
                    .zIndex(-1)

                PointMark(
                    x: .value("Selected Point", selectedPoint.xPosition),
                    y: .value("Selected Price", selectedPoint.close)
                )
                .foregroundStyle(presentation.model.periodTint)
                .symbolSize(58)
                .zIndex(2)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: visibleXDomain(for: presentation))
        .chartYScale(domain: presentation.model.yDomain)
        .transaction { transaction in
            transaction.animation = nil
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
                .contentShape(Rectangle())
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if showsEndpointPulse,
                       selection == nil,
                       presentation.model.mode == .line,
                       let latestPoint = presentation.model.points.last,
                       let latestPointPosition = chartPosition(
                        for: latestPoint,
                        proxy: proxy,
                        geometry: geometry
                       ) {
                        AssetChartEndpointPulse(tint: presentation.model.periodTint)
                            .position(latestPointPosition)
                            .allowsHitTesting(false)
                    }

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
                                    if !isScrubbing {
                                        isScrubbing = true
                                    }
                                    updateSelectedPoint(
                                        at: value.location,
                                        proxy: proxy,
                                        geometry: geometry,
                                        presentation: presentation
                                    )
                                }
                                .onEnded { _ in
                                    clearSelection()
                                }
                        )
                }
            }
        }
    }

    private func applyPresentation(_ next: AssetChartPresentation) {
        guard let displayedPresentation else {
            self.displayedPresentation = next
            return
        }

        guard displayedPresentation.id != next.id else {
            self.displayedPresentation = next
            return
        }

        if isLoading, hasSameChartContent(displayedPresentation, next) {
            return
        }

        clearSelection()
        withTransaction(Transaction(animation: nil)) {
            self.displayedPresentation = next
        }
    }

    private func hasSameChartContent(
        _ lhs: AssetChartPresentation,
        _ rhs: AssetChartPresentation
    ) -> Bool {
        lhs.model.mode == rhs.model.mode &&
            lhs.id.pointCount == rhs.id.pointCount &&
            lhs.id.firstDate == rhs.id.firstDate &&
            lhs.id.lastDate == rhs.id.lastDate &&
            lhs.id.yLowerBound == rhs.id.yLowerBound &&
            lhs.id.yUpperBound == rhs.id.yUpperBound &&
            lhs.id.sampledDigest == rhs.id.sampledDigest
    }

    private func chartPosition(
        for point: AssetChartPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> CGPoint? {
        guard let plotFrameAnchor = proxy.plotFrame,
              let xPosition = proxy.position(forX: point.xPosition),
              let yPosition = proxy.position(forY: point.close) else {
            return nil
        }

        let plotFrame = geometry[plotFrameAnchor]
        return CGPoint(
            x: plotFrame.origin.x + xPosition,
            y: plotFrame.origin.y + yPosition
        )
    }

    private func visibleXDomain(for presentation: AssetChartPresentation) -> ClosedRange<Double> {
        let lower = presentation.model.xDomain.lowerBound
        let upper = presentation.model.xDomain.upperBound
        let span = upper - lower
        guard span.isFinite, span > 0 else {
            return presentation.model.xDomain
        }

        let padding = presentation.range == .oneDay
            ? oneDayDomainPadding(for: span)
            : max(span * 0.04, 0.35)
        return (lower - padding)...(upper + padding)
    }

    private func oneDayDomainPadding(for span: Double) -> Double {
        min(
            max(span * Self.oneDayDomainPaddingRatio, Self.oneDayDomainPaddingRange.lowerBound),
            Self.oneDayDomainPaddingRange.upperBound
        )
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
        presentation: AssetChartPresentation
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.width > 0 else {
            return
        }

        let xPosition = min(max(location.x - plotFrame.origin.x, 0), plotFrame.width)
        guard let chartXValue = proxy.value(atX: xPosition, as: Double.self) else {
            return
        }

        guard let nearestPoint = AssetChartPoint.nearest(in: presentation.model.points, to: chartXValue) else {
            return
        }

        guard selection?.point.id != nearestPoint.id else {
            return
        }

        let baseline = presentation.model.priceChangeBaseline ?? presentation.model.points.first?.close ?? nearestPoint.open
        let pointX = chartPosition(for: nearestPoint, proxy: proxy, geometry: geometry)?.x ?? location.x
        let nextOverlayLabel = AssetChartOverlayLabel(
            text: nearestPoint.dateLabel(for: presentation.range),
            x: clampedOverlayX(pointX, in: geometry, inset: 64)
        )

        selection = AssetChartSelection(point: nearestPoint, baseline: baseline)
        overlayLabel = nextOverlayLabel
    }

    private func clampedOverlayX(
        _ x: CGFloat,
        in geometry: GeometryProxy,
        inset: CGFloat = Self.overlayHorizontalInset
    ) -> CGFloat {
        let width = geometry.size.width
        guard width > inset * 2 else {
            return width / 2
        }

        return min(max(x, inset), width - inset)
    }
}

private struct AssetChartPresentation: Identifiable {
    let id: AssetChartPresentationID
    let model: AssetChartRenderModel
    let range: AssetChartRange

    init(model: AssetChartRenderModel, range: AssetChartRange) {
        self.model = model
        self.range = range
        id = AssetChartPresentationID(model: model, range: range)
    }
}

private struct AssetChartPresentationID: Hashable {
    let range: AssetChartRange
    let mode: AssetChartMode
    let pointCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let yLowerBound: Double
    let yUpperBound: Double
    let sampledDigest: Int

    init(model: AssetChartRenderModel, range: AssetChartRange) {
        self.range = range
        mode = model.mode
        pointCount = model.points.count
        firstDate = model.points.first?.date
        lastDate = model.points.last?.date
        yLowerBound = model.yDomain.lowerBound
        yUpperBound = model.yDomain.upperBound
        sampledDigest = Self.sampledDigest(for: model.points)
    }

    private static func sampledDigest(for points: [AssetChartPoint]) -> Int {
        guard !points.isEmpty else {
            return 0
        }

        var hasher = Hasher()
        let step = max(points.count / 12, 1)
        var index = 0
        while index < points.count {
            combine(points[index], into: &hasher)
            index += step
        }

        if let last = points.last {
            combine(last, into: &hasher)
        }

        return hasher.finalize()
    }

    private static func combine(_ point: AssetChartPoint, into hasher: inout Hasher) {
        hasher.combine(point.date)
        hasher.combine(point.xPosition)
        hasher.combine(point.open)
        hasher.combine(point.high)
        hasher.combine(point.low)
        hasher.combine(point.close)
        hasher.combine(point.volume)
    }
}

private struct AssetChartEndpointPulse: View {
    let tint: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(isAnimating ? 0 : 0.38), lineWidth: 2)
                .frame(width: 28, height: 28)
                .scaleEffect(isAnimating ? 1.75 : 0.35)

            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.45), radius: 8, x: 0, y: 0)
        }
        .frame(width: 36, height: 36)
        .onAppear {
            withAnimation(.easeOut(duration: 1.45).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

struct AssetChartModePicker: View {
    @Binding var selection: AssetChartMode

    var body: some View {
        Menu {
            ForEach(AssetChartMode.allCases) { mode in
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
                .frame(width: 34, height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(AppTheme.ColorToken.groupedSurface, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color(.separator).opacity(0.18))
        }
        .accessibilityLabel("Chart style")
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
    let xPosition: Double
}

private struct AssetChartOverlayLabel: Equatable, Sendable {
    let text: String
    let x: CGFloat
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

    var bodyLow: Double {
        min(open, close)
    }

    var bodyHigh: Double {
        let upper = max(open, close)
        if upper == bodyLow {
            return upper + max(abs(upper) * 0.0003, 0.01)
        }

        return upper
    }

    var tint: Color {
        close >= open ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    func dateLabel(for range: AssetChartRange) -> String {
        AssetChartDateLabelFormatter.string(from: date, range: range)
    }

    init?(bar: AlpacaMarketBar) {
        guard let date = AlpacaDateParser.date(bar.timestamp), let close = bar.close else {
            return nil
        }

        let open = bar.open ?? close
        self.date = date
        self.xPosition = 0
        self.open = open
        self.high = max(bar.high ?? close, open, close)
        self.low = min(bar.low ?? close, open, close)
        self.close = close
        self.volume = bar.volume ?? 0
    }

    init(date: Date, xPosition: Double, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.date = date
        self.xPosition = xPosition
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    func withXPosition(_ xPosition: Double) -> AssetChartPoint {
        AssetChartPoint(
            date: date,
            xPosition: xPosition,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
        )
    }

    static func nearest(in points: [AssetChartPoint], to xPosition: Double) -> AssetChartPoint? {
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

private enum AssetChartDateLabelFormatter {
    private static let intradayFormatter = makeFormatter("h:mm a")
    private static let shortRangeFormatter = makeFormatter("MMM d, h:mm a")
    private static let longRangeFormatter = makeFormatter(
        "MMM d, yyyy",
        timeZone: TimeZone(identifier: "America/New_York")
    )

    static func string(from date: Date, range: AssetChartRange) -> String {
        let formatter = switch range {
        case .oneDay:
            intradayFormatter
        case .oneWeek, .oneMonth:
            shortRangeFormatter
        case .threeMonths, .oneYear, .yearToDate:
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
