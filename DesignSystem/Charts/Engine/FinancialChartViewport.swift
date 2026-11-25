import Foundation

/// Pure value-type viewport controller supporting smooth zoom (pinch) and pan
/// over a chart's X domain with guaranteed clamping to valid bounds.
struct FinancialChartViewport: Equatable, Sendable {
    let fullDomain: ClosedRange<Double>
    private(set) var visibleDomain: ClosedRange<Double>
    let maxZoomScale: Double

    init(fullDomain: ClosedRange<Double>, maxZoomScale: Double = 8.0) {
        let safeDomain = fullDomain.upperBound > fullDomain.lowerBound ? fullDomain : 0...1
        self.fullDomain = safeDomain
        self.visibleDomain = safeDomain
        self.maxZoomScale = max(maxZoomScale, 1.0)
    }

    var isZoomed: Bool {
        zoomScale > 1.02
    }

    var zoomScale: Double {
        let fullSpan = max(fullDomain.upperBound - fullDomain.lowerBound, 1e-9)
        let visibleSpan = max(visibleDomain.upperBound - visibleDomain.lowerBound, 1e-9)
        return fullSpan / visibleSpan
    }

    mutating func reset(to newFullDomain: ClosedRange<Double>) {
        self = FinancialChartViewport(fullDomain: newFullDomain, maxZoomScale: maxZoomScale)
    }

    mutating func zoom(by factor: Double, anchorFraction: Double) {
        guard factor.isFinite, factor > 0 else { return }

        let fullSpan = fullDomain.upperBound - fullDomain.lowerBound
        let currentSpan = visibleDomain.upperBound - visibleDomain.lowerBound
        guard fullSpan > 0, currentSpan > 0 else { return }

        let minSpan = fullSpan / maxZoomScale
        let targetSpan = min(max(currentSpan / factor, minSpan), fullSpan)
        let clampedAnchor = min(max(anchorFraction, 0), 1)
        let anchorValue = visibleDomain.lowerBound + currentSpan * clampedAnchor

        var newLower = anchorValue - targetSpan * clampedAnchor
        var newUpper = newLower + targetSpan

        if newLower < fullDomain.lowerBound {
            newLower = fullDomain.lowerBound
            newUpper = newLower + targetSpan
        }
        if newUpper > fullDomain.upperBound {
            newUpper = fullDomain.upperBound
            newLower = max(fullDomain.lowerBound, newUpper - targetSpan)
        }

        visibleDomain = newLower...newUpper
    }

    mutating func pan(byFraction deltaFraction: Double) {
        guard deltaFraction.isFinite else { return }

        let currentSpan = visibleDomain.upperBound - visibleDomain.lowerBound
        let fullSpan = fullDomain.upperBound - fullDomain.lowerBound
        guard currentSpan < fullSpan else { return }

        let deltaData = -deltaFraction * currentSpan
        var newLower = visibleDomain.lowerBound + deltaData
        var newUpper = visibleDomain.upperBound + deltaData

        if newLower < fullDomain.lowerBound {
            newLower = fullDomain.lowerBound
            newUpper = newLower + currentSpan
        }
        if newUpper > fullDomain.upperBound {
            newUpper = fullDomain.upperBound
            newLower = newUpper - currentSpan
        }

        visibleDomain = newLower...newUpper
    }
}
