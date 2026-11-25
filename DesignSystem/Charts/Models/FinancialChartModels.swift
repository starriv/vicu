import CoreGraphics
import Foundation
import SwiftUI

enum FinancialChartKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case line
    case area
    case candles

    var id: String { rawValue }
}

enum FinancialChartInterpolation: Hashable, Sendable {
    /// True price segments without spline overshoot.
    case linear
    /// Fritsch-Carlson monotone cubic spline (smooth yet strictly overshoot-free).
    case monotone
}

enum FinancialChartAreaFillStyle: Hashable, Sendable {
    case none
    case gradient
    /// OKX-inspired dot-matrix halftone gradient fill with soft ambient glow beneath the curve.
    case dotMatrix(spacing: CGFloat = 5.5, dotDiameter: CGFloat = 1.65)
}

struct FinancialChartPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let timestamp: TimeInterval
    let x: Double
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var id: TimeInterval { timestamp }

    var isBullish: Bool {
        close >= open
    }

    init(
        date: Date,
        x: Double,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double = 0
    ) {
        self.date = date
        self.timestamp = date.timeIntervalSince1970
        self.x = x
        self.open = open
        self.high = max(high, open, close)
        self.low = min(low, open, close)
        self.close = close
        self.volume = max(volume, 0)
    }

    init(
        date: Date,
        x: Double,
        value: Double,
        volume: Double = 0
    ) {
        self.date = date
        self.timestamp = date.timeIntervalSince1970
        self.x = x
        self.open = value
        self.high = value
        self.low = value
        self.close = value
        self.volume = max(volume, 0)
    }

    func withX(_ newX: Double) -> FinancialChartPoint {
        FinancialChartPoint(
            date: date,
            x: newX,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
        )
    }
}

enum FinancialChartBaselinePolicy: Hashable, Sendable {
    case none
    /// Includes the reference baseline in the Y-axis domain only if doing so does not
    /// expand the data span beyond `maxExpansionRatio`, preventing gap moves from squashing the series.
    case softInclude(value: Double, maxExpansionRatio: Double = 0.55, showsReferenceLine: Bool = true)
    /// Always includes the reference baseline in the Y-axis domain.
    case alwaysInclude(value: Double, showsReferenceLine: Bool = true)

    var referenceValue: Double? {
        switch self {
        case .none:
            nil
        case .softInclude(let value, _, _), .alwaysInclude(let value, _):
            value.isFinite ? value : nil
        }
    }

    var showsReferenceLine: Bool {
        switch self {
        case .none:
            false
        case .softInclude(_, _, let shows), .alwaysInclude(_, let shows):
            shows
        }
    }
}

enum FinancialChartBaselinePlacement: Equatable, Sendable {
    case hidden
    case inPlot(value: Double)
    case abovePlot(value: Double)
    case belowPlot(value: Double)
}

struct FinancialChartYScaleConfig: Hashable, Sendable {
    /// Minimum relative span compared to the midpoint price (e.g. 0.0025 = 0.25%)
    /// so near-flat sessions do not amplify 1-cent noise across the full chart height.
    let minRelativeSpan: Double
    /// Minimum absolute span floor for very low-priced assets (adaptive when nil).
    let minAbsoluteSpan: Double?
    /// Symmetric breathing padding fraction inside the already inset plot rect.
    let topPaddingFraction: Double
    let bottomPaddingFraction: Double
    /// Optional hard lower clamp (e.g., 0 for non-negative metrics like bid-ask spread).
    let hardLowerBound: Double?

    static let financialPrice = FinancialChartYScaleConfig(
        minRelativeSpan: 0.0025,
        minAbsoluteSpan: nil,
        topPaddingFraction: 0.06,
        bottomPaddingFraction: 0.06,
        hardLowerBound: nil
    )

    static let portfolioEquity = FinancialChartYScaleConfig(
        minRelativeSpan: 0.0015,
        minAbsoluteSpan: 1.0,
        topPaddingFraction: 0.08,
        bottomPaddingFraction: 0.08,
        hardLowerBound: nil
    )

    static let portfolioProfitLoss = FinancialChartYScaleConfig(
        minRelativeSpan: 0.002,
        minAbsoluteSpan: 1.0,
        topPaddingFraction: 0.08,
        bottomPaddingFraction: 0.08,
        hardLowerBound: nil
    )

    static let nonNegativeMetric = FinancialChartYScaleConfig(
        minRelativeSpan: 0.0,
        minAbsoluteSpan: 0.01,
        topPaddingFraction: 0.10,
        bottomPaddingFraction: 0.04,
        hardLowerBound: 0.0
    )

    static let sparkline = FinancialChartYScaleConfig(
        minRelativeSpan: 0.002,
        minAbsoluteSpan: nil,
        topPaddingFraction: 0.08,
        bottomPaddingFraction: 0.10,
        hardLowerBound: nil
    )
}

struct FinancialChartInsets: Equatable, Sendable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    static let standard = FinancialChartInsets(top: 28, leading: 6, bottom: 16, trailing: 14)
    static let okxSimple = FinancialChartInsets(top: 24, leading: 2, bottom: 10, trailing: 15)
    static let compact = FinancialChartInsets(top: 24, leading: 2, bottom: 10, trailing: 6)
    static let sparkline = FinancialChartInsets(top: 12, leading: 10, bottom: 12, trailing: 14)
    static let minimal = FinancialChartInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
}

enum FinancialChartLayoutMetrics {
    /// Computes a balanced financial aspect ratio (~1.62:1 for price plot) instead of
    /// square-ish hardcoded heights that vertically stretch modest price moves.
    static func recommendedHeight(
        forWidth width: CGFloat,
        showsVolume: Bool = false,
        minHeight: CGFloat = 224,
        maxHeight: CGFloat = 268
    ) -> CGFloat {
        let baseHeight: CGFloat
        if width.isFinite, width > 0 {
            baseHeight = min(max(width / 1.56, minHeight), maxHeight)
        } else {
            baseHeight = 244
        }
        return showsVolume ? baseHeight + 48 : baseHeight
    }
}

struct FinancialChartStyle: Sendable {
    let lineColor: Color
    let positiveColor: Color
    let negativeColor: Color
    let areaFillStyle: FinancialChartAreaFillStyle
    let areaTopOpacity: Double
    let areaBottomOpacity: Double
    let lineWidth: CGFloat
    let glowRadius: CGFloat
    let glowOpacity: Double
    let lineHighlightColor: Color?
    let lineHighlightWidth: CGFloat
    let gridColor: Color
    let referenceLineColor: Color
    let crosshairColor: Color
    let volumeOpacity: Double
    let showsGrid: Bool
    let showsVolume: Bool
    let showsEndpointPulse: Bool
    let showsHighLowCallouts: Bool
    let interpolation: FinancialChartInterpolation

    init(
        lineColor: Color = AppTheme.ColorToken.positive,
        positiveColor: Color = AppTheme.ColorToken.positive,
        negativeColor: Color = AppTheme.ColorToken.negative,
        areaFillStyle: FinancialChartAreaFillStyle = .gradient,
        areaTopOpacity: Double = 0.22,
        areaBottomOpacity: Double = 0.02,
        lineWidth: CGFloat = 2.6,
        glowRadius: CGFloat = 0,
        glowOpacity: Double = 0,
        lineHighlightColor: Color? = nil,
        lineHighlightWidth: CGFloat = 0,
        gridColor: Color = Color(.separator).opacity(0.16),
        referenceLineColor: Color = Color(.tertiaryLabel).opacity(0.6),
        crosshairColor: Color = Color(.tertiaryLabel).opacity(0.85),
        volumeOpacity: Double = 0.28,
        showsGrid: Bool = false,
        showsVolume: Bool = false,
        showsEndpointPulse: Bool = true,
        showsHighLowCallouts: Bool = false,
        interpolation: FinancialChartInterpolation = .monotone
    ) {
        self.lineColor = lineColor
        self.positiveColor = positiveColor
        self.negativeColor = negativeColor
        self.areaFillStyle = areaFillStyle
        self.areaTopOpacity = areaTopOpacity
        self.areaBottomOpacity = areaBottomOpacity
        self.lineWidth = lineWidth
        self.glowRadius = glowRadius
        self.glowOpacity = glowOpacity
        self.lineHighlightColor = lineHighlightColor
        self.lineHighlightWidth = lineHighlightWidth
        self.gridColor = gridColor
        self.referenceLineColor = referenceLineColor
        self.crosshairColor = crosshairColor
        self.volumeOpacity = volumeOpacity
        self.showsGrid = showsGrid
        self.showsVolume = showsVolume
        self.showsEndpointPulse = showsEndpointPulse
        self.showsHighLowCallouts = showsHighLowCallouts
        self.interpolation = interpolation
    }
}

struct FinancialChartSeries: Equatable, Sendable {
    let id: Int
    let kind: FinancialChartKind
    let points: [FinancialChartPoint]
    let xDomain: ClosedRange<Double>
    let baselinePolicy: FinancialChartBaselinePolicy
    let yScaleConfig: FinancialChartYScaleConfig
    let allowsZoomAndPan: Bool

    static let empty = FinancialChartSeries(
        id: 0,
        kind: .line,
        points: [],
        xDomain: 0...1,
        baselinePolicy: .none,
        yScaleConfig: .financialPrice,
        allowsZoomAndPan: false
    )

    init(
        id: Int? = nil,
        pointsDigest: Int? = nil,
        kind: FinancialChartKind,
        points: [FinancialChartPoint],
        xDomain: ClosedRange<Double>? = nil,
        baselinePolicy: FinancialChartBaselinePolicy = .none,
        yScaleConfig: FinancialChartYScaleConfig = .financialPrice,
        allowsZoomAndPan: Bool = false
    ) {
        self.kind = kind
        self.points = points
        self.xDomain = xDomain ?? Self.defaultXDomain(for: points)
        self.baselinePolicy = baselinePolicy
        self.yScaleConfig = yScaleConfig
        self.allowsZoomAndPan = allowsZoomAndPan
        self.id = id ?? Self.computeDigest(
            kind: kind,
            pointsDigest: pointsDigest ?? Self.pointsDigest(for: points),
            xDomain: self.xDomain,
            baselinePolicy: baselinePolicy,
            yScaleConfig: yScaleConfig
        )
    }

    static func pointsDigest(for points: [FinancialChartPoint]) -> Int {
        var hasher = Hasher()
        hasher.combine(points.count)
        for p in points {
            hasher.combine(p.timestamp)
            hasher.combine(p.x)
            hasher.combine(p.open)
            hasher.combine(p.high)
            hasher.combine(p.low)
            hasher.combine(p.close)
            hasher.combine(p.volume)
        }
        return hasher.finalize()
    }

    private static func defaultXDomain(for points: [FinancialChartPoint]) -> ClosedRange<Double> {
        guard let first = points.first, let last = points.last, last.x > first.x else {
            return 0...1
        }
        return first.x...last.x
    }

    private static func computeDigest(
        kind: FinancialChartKind,
        pointsDigest: Int,
        xDomain: ClosedRange<Double>,
        baselinePolicy: FinancialChartBaselinePolicy,
        yScaleConfig: FinancialChartYScaleConfig
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(pointsDigest)
        hasher.combine(xDomain.lowerBound)
        hasher.combine(xDomain.upperBound)
        hasher.combine(baselinePolicy)
        hasher.combine(yScaleConfig)
        return hasher.finalize()
    }
}

struct FinancialChartSelection: Equatable, Sendable {
    let point: FinancialChartPoint
    let index: Int
    let axisDates: [Date?]
}
