import Foundation

struct FinancialChartYAxisSolution: Equatable, Sendable {
    let domain: ClosedRange<Double>
    let dataMin: Double
    let dataMax: Double
    let baselinePlacement: FinancialChartBaselinePlacement
}

enum FinancialChartYAxisSolver {
    /// Solves a balanced Y-axis domain for the visible slice of points.
    ///
    /// Key guarantees:
    /// 1. `.line` and `.area` compute extrema strictly from `close` (never distorted by OHLC wicks).
    /// 2. `.candles` computes extrema strictly from `low` / `high` of visible bars.
    /// 3. `.softInclude` baseline only expands the domain when it won't squash the main series.
    /// 4. A price-proportional minimum visual span prevents flat noise from stretching 100% vertically.
    static func solve(
        points: ArraySlice<FinancialChartPoint>,
        kind: FinancialChartKind,
        baselinePolicy: FinancialChartBaselinePolicy,
        config: FinancialChartYScaleConfig
    ) -> FinancialChartYAxisSolution {
        var rawMin = Double.greatestFiniteMagnitude
        var rawMax = -Double.greatestFiniteMagnitude

        switch kind {
        case .line, .area:
            for point in points where point.close.isFinite {
                rawMin = min(rawMin, point.close)
                rawMax = max(rawMax, point.close)
            }
        case .candles:
            for point in points where point.low.isFinite && point.high.isFinite {
                rawMin = min(rawMin, point.low)
                rawMax = max(rawMax, point.high)
            }
        }

        guard rawMin.isFinite, rawMax.isFinite else {
            let fallbackCenter = baselinePolicy.referenceValue ?? 0
            let fallbackHalf = max(config.minAbsoluteSpan ?? 1.0, 0.5)
            var lower = fallbackCenter - fallbackHalf
            let upper = fallbackCenter + fallbackHalf
            if let hardLower = config.hardLowerBound {
                lower = max(lower, hardLower)
            }
            return FinancialChartYAxisSolution(
                domain: lower...max(upper, lower + 0.01),
                dataMin: fallbackCenter,
                dataMax: fallbackCenter,
                baselinePlacement: .hidden
            )
        }

        let dataMin = rawMin
        let dataMax = rawMax
        var workingMin = dataMin
        var workingMax = dataMax
        var baselinePlacement: FinancialChartBaselinePlacement = .hidden

        // Evaluate baseline inclusion before applying minimum visual span & breathing padding.
        // Domain inclusion is decoupled from whether the dashed reference line is visually rendered.
        if let reference = baselinePolicy.referenceValue {
            let showsLine = baselinePolicy.showsReferenceLine
            switch baselinePolicy {
            case .none:
                baselinePlacement = .hidden
            case .alwaysInclude:
                workingMin = min(workingMin, reference)
                workingMax = max(workingMax, reference)
                baselinePlacement = showsLine ? .inPlot(value: reference) : .hidden
            case .softInclude(_, let maxExpansionRatio, _):
                let dataSpan = max(dataMax - dataMin, adaptiveMinimumSpan(around: (dataMin + dataMax) * 0.5, config: config))
                let allowedMargin = dataSpan * max(maxExpansionRatio, 0)
                if reference >= dataMin - allowedMargin && reference <= dataMax + allowedMargin {
                    workingMin = min(workingMin, reference)
                    workingMax = max(workingMax, reference)
                    baselinePlacement = showsLine ? .inPlot(value: reference) : .hidden
                } else if showsLine {
                    baselinePlacement = reference > dataMax ? .abovePlot(value: reference) : .belowPlot(value: reference)
                } else {
                    baselinePlacement = .hidden
                }
            }
        }

        let midpoint = (workingMin + workingMax) * 0.5
        let minSpan = adaptiveMinimumSpan(around: midpoint, config: config)
        let currentSpan = workingMax - workingMin

        if currentSpan < minSpan {
            let halfSpan = minSpan * 0.5
            workingMin = midpoint - halfSpan
            workingMax = midpoint + halfSpan
        }

        let effectiveSpan = max(workingMax - workingMin, 1e-6)
        var lower = workingMin - effectiveSpan * max(config.bottomPaddingFraction, 0)
        var upper = workingMax + effectiveSpan * max(config.topPaddingFraction, 0)

        if let hardLower = config.hardLowerBound {
            lower = max(lower, hardLower)
            if upper <= lower {
                upper = lower + max(minSpan, 0.01)
            }
        }

        // Re-check baseline placement against the final padded domain.
        if case .abovePlot(let reference) = baselinePlacement, reference <= upper {
            baselinePlacement = .inPlot(value: reference)
        } else if case .belowPlot(let reference) = baselinePlacement, reference >= lower {
            baselinePlacement = .inPlot(value: reference)
        }

        return FinancialChartYAxisSolution(
            domain: lower...upper,
            dataMin: dataMin,
            dataMax: dataMax,
            baselinePlacement: baselinePlacement
        )
    }

    static func solve(
        points: [FinancialChartPoint],
        kind: FinancialChartKind,
        baselinePolicy: FinancialChartBaselinePolicy,
        config: FinancialChartYScaleConfig
    ) -> FinancialChartYAxisSolution {
        solve(points: points[...], kind: kind, baselinePolicy: baselinePolicy, config: config)
    }

    private static func adaptiveMinimumSpan(
        around midpoint: Double,
        config: FinancialChartYScaleConfig
    ) -> Double {
        let absMid = abs(midpoint)
        let relativeFloor = absMid * max(config.minRelativeSpan, 0)

        if let explicitFloor = config.minAbsoluteSpan {
            return max(relativeFloor, explicitFloor, 1e-6)
        }

        // Price-magnitude-aware tick floor so low-priced options ($0.05) and high-priced equities ($700)
        // both maintain realistic vertical proportions.
        let tickFloor: Double
        switch absMid {
        case ..<0.25:
            tickFloor = 0.004
        case 0.25..<1.0:
            tickFloor = 0.01
        case 1.0..<10.0:
            tickFloor = 0.04
        case 10.0..<100.0:
            tickFloor = 0.15
        default:
            tickFloor = 0.25
        }

        return max(relativeFloor, tickFloor, 1e-6)
    }
}
