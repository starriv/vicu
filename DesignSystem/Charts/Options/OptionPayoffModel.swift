import CoreGraphics
import Foundation

/// Contract direction for a single-leg US equity option payoff profile.
enum OptionPayoffSide: Equatable, Sendable {
    case long
    case short
}

/// Complete input specification for a standard single-leg US equity option expiration payoff.
struct OptionPayoffSpec: Equatable, Sendable {
    let contractType: AlpacaOptionContractType
    let side: OptionPayoffSide
    let strike: Double
    let premium: Double
    let contracts: Int
    let multiplier: Double
    let underlyingPrice: Double?
    let currencyCode: String
    let isSimulatedPreview: Bool

    init(
        contractType: AlpacaOptionContractType,
        side: OptionPayoffSide,
        strike: Double,
        premium: Double,
        contracts: Int,
        multiplier: Double = 100,
        underlyingPrice: Double? = nil,
        currencyCode: String = "USD",
        isSimulatedPreview: Bool = false
    ) {
        self.contractType = contractType
        self.side = side
        self.strike = strike
        self.premium = premium
        self.contracts = max(1, contracts)
        self.multiplier = multiplier
        self.underlyingPrice = underlyingPrice.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }
        self.currencyCode = currencyCode
        self.isSimulatedPreview = isSimulatedPreview
    }

    var isValid: Bool {
        strike.isFinite && strike > 0
            && premium.isFinite && premium > 0
            && contracts > 0
            && multiplier > 0
    }

    var totalMultiplier: Double {
        Double(contracts) * multiplier
    }

    var totalPremium: Double {
        premium * totalMultiplier
    }
}

enum OptionPayoffBound: Equatable, Sendable {
    case finite(Double)
    case unlimited
}

struct OptionPayoffMetrics: Equatable, Sendable {
    let breakeven: Double?
    let maxProfit: OptionPayoffBound
    let maxLoss: OptionPayoffBound
    let spotPnL: Double?
    let priceMin: Double
    let priceMax: Double
    let pnlMin: Double
    let pnlMax: Double
}

struct OptionPayoffScrubSample: Equatable, Sendable {
    let underlyingPrice: Double
    let expirationPnL: Double
    let returnFraction: Double?
    let normalizedX: CGFloat
    let snappedAnchor: OptionPayoffAnchor?
}

enum OptionPayoffAnchor: Equatable, Sendable {
    case strike
    case breakeven
    case spot
}

/// Pure, O(1) mathematical engine for standard US equity single-leg option P&L curves.
enum OptionPayoffEngine {
    /// Exact expiration P&L in account currency at a given underlying stock price `S`.
    static func expirationPnL(spec: OptionPayoffSpec, at underlyingPrice: Double) -> Double {
        let clampedS = max(0, underlyingPrice)
        let intrinsic: Double
        switch spec.contractType {
        case .call:
            intrinsic = max(clampedS - spec.strike, 0)
        case .put:
            intrinsic = max(spec.strike - clampedS, 0)
        }

        let perSharePnL: Double
        switch spec.side {
        case .long:
            perSharePnL = intrinsic - spec.premium
        case .short:
            perSharePnL = spec.premium - intrinsic
        }

        return perSharePnL * spec.totalMultiplier
    }

    /// Computes US-standard breakeven, max profit, max loss, and well-framed X/Y plot domains.
    static func computeMetrics(for spec: OptionPayoffSpec) -> OptionPayoffMetrics {
        let breakeven: Double?
        let maxProfit: OptionPayoffBound
        let maxLoss: OptionPayoffBound

        switch (spec.contractType, spec.side) {
        case (.call, .long):
            breakeven = spec.strike + spec.premium
            maxProfit = .unlimited
            maxLoss = .finite(-spec.totalPremium)

        case (.call, .short):
            breakeven = spec.strike + spec.premium
            maxProfit = .finite(spec.totalPremium)
            maxLoss = .unlimited

        case (.put, .long):
            let be = spec.strike - spec.premium
            breakeven = be > 0 ? be : nil
            let atZero = max(0, (spec.strike - spec.premium) * spec.totalMultiplier)
            maxProfit = .finite(atZero)
            maxLoss = .finite(-spec.totalPremium)

        case (.put, .short):
            let be = spec.strike - spec.premium
            breakeven = be > 0 ? be : nil
            let atZeroLoss = -max(0, (spec.strike - spec.premium) * spec.totalMultiplier)
            maxProfit = .finite(spec.totalPremium)
            maxLoss = .finite(atZeroLoss)
        }

        let (priceMin, priceMax) = computePriceDomain(spec: spec, breakeven: breakeven)

        let cornerPrices = [priceMin, spec.strike, breakeven, spec.underlyingPrice, priceMax]
            .compactMap { $0 }
            .filter { $0 >= priceMin && $0 <= priceMax }
        let cornerPnLs = cornerPrices.map { expirationPnL(spec: spec, at: $0) }

        let rawMinPnL = min(0, cornerPnLs.min() ?? -spec.totalPremium)
        let rawMaxPnL = max(0, cornerPnLs.max() ?? spec.totalPremium)
        let span = max(rawMaxPnL - rawMinPnL, max(spec.totalPremium * 0.5, 10))
        let verticalPadding = span * 0.16

        let spotPnL = spec.underlyingPrice.map { expirationPnL(spec: spec, at: $0) }

        return OptionPayoffMetrics(
            breakeven: breakeven,
            maxProfit: maxProfit,
            maxLoss: maxLoss,
            spotPnL: spotPnL,
            priceMin: priceMin,
            priceMax: priceMax,
            pnlMin: rawMinPnL - verticalPadding,
            pnlMax: rawMaxPnL + verticalPadding
        )
    }

    /// Evaluates a scrub sample at normalized X in `[0, 1]`, with subtle magnetic snapping to key landmarks.
    static func scrubSample(
        spec: OptionPayoffSpec,
        metrics: OptionPayoffMetrics,
        normalizedX: CGFloat
    ) -> OptionPayoffScrubSample {
        let clampedNorm = min(max(normalizedX, 0), 1)
        let priceSpan = max(metrics.priceMax - metrics.priceMin, 0.01)
        var resolvedPrice = metrics.priceMin + Double(clampedNorm) * priceSpan
        var snappedAnchor: OptionPayoffAnchor?

        let snapThreshold = priceSpan * 0.022
        let candidates: [(OptionPayoffAnchor, Double?)] = [
            (.breakeven, metrics.breakeven),
            (.strike, spec.strike),
            (.spot, spec.underlyingPrice)
        ]

        var bestDistance = snapThreshold
        for (anchor, target) in candidates {
            guard let target, target >= metrics.priceMin, target <= metrics.priceMax else { continue }
            let distance = abs(resolvedPrice - target)
            if distance < bestDistance {
                bestDistance = distance
                resolvedPrice = target
                snappedAnchor = anchor
            }
        }

        let snappedNorm = CGFloat((resolvedPrice - metrics.priceMin) / priceSpan)
        let pnl = expirationPnL(spec: spec, at: resolvedPrice)
        let basis: Double? = {
            switch spec.side {
            case .long:
                return spec.totalPremium > 0 ? spec.totalPremium : nil
            case .short:
                if case .finite(let loss) = metrics.maxLoss, abs(loss) > 0 {
                    return abs(loss)
                }
                return spec.totalPremium > 0 ? spec.totalPremium : nil
            }
        }()
        let returnFraction = basis.map { pnl / $0 }

        return OptionPayoffScrubSample(
            underlyingPrice: resolvedPrice,
            expirationPnL: pnl,
            returnFraction: returnFraction,
            normalizedX: min(max(snappedNorm, 0), 1),
            snappedAnchor: snappedAnchor
        )
    }

    /// Returns exact ordered piecewise-linear vertices `(price, pnl)` across `[priceMin, priceMax]`.
    static func exactVertices(
        spec: OptionPayoffSpec,
        metrics: OptionPayoffMetrics
    ) -> [(price: Double, pnl: Double)] {
        var xs: [Double] = [metrics.priceMin, metrics.priceMax]
        if spec.strike > metrics.priceMin && spec.strike < metrics.priceMax {
            xs.append(spec.strike)
        }
        if let be = metrics.breakeven, be > metrics.priceMin && be < metrics.priceMax {
            xs.append(be)
        }
        xs.sort()

        var deduplicated: [Double] = []
        for x in xs {
            if let last = deduplicated.last, abs(last - x) < 1e-6 {
                continue
            }
            deduplicated.append(x)
        }

        return deduplicated.map { x in
            let pnl: Double
            if let be = metrics.breakeven, abs(x - be) < 1e-6 {
                pnl = 0
            } else {
                pnl = expirationPnL(spec: spec, at: x)
            }
            return (price: x, pnl: pnl)
        }
    }

    private static func computePriceDomain(
        spec: OptionPayoffSpec,
        breakeven: Double?
    ) -> (Double, Double) {
        var anchors = [spec.strike]
        if let breakeven, breakeven > 0 {
            anchors.append(breakeven)
        }
        if let spot = spec.underlyingPrice, spot > 0 {
            anchors.append(spot)
        }

        let anchorMin = anchors.min() ?? spec.strike
        let anchorMax = anchors.max() ?? spec.strike
        let anchorSpan = anchorMax - anchorMin
        let baseScale = max(spec.strike * 0.18, spec.premium * 2.2, 1.0)
        let padding = max(anchorSpan * 0.35, baseScale)

        let rawMin = max(0, anchorMin - padding)
        var rawMax = anchorMax + padding

        // Ensure breakeven & strike have room to show both profit and loss zones clearly.
        if let breakeven {
            let minMarginRight = max(spec.premium * 1.4, spec.strike * 0.08)
            rawMax = max(rawMax, breakeven + minMarginRight)
        }

        if rawMax <= rawMin + 0.01 {
            rawMax = rawMin + max(spec.strike * 0.25, 1.0)
        }

        return (rawMin, rawMax)
    }
}
