import CoreGraphics
import Foundation

struct FinancialChartCoordinateSystem: Equatable, Sendable {
    let canvasSize: CGSize
    let insets: FinancialChartInsets
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let plotRect: CGRect
    let volumeRect: CGRect?

    init(
        canvasSize: CGSize,
        insets: FinancialChartInsets,
        xDomain: ClosedRange<Double>,
        yDomain: ClosedRange<Double>,
        showsVolume: Bool = false,
        volumeHeightFraction: CGFloat = 0.20,
        volumeGap: CGFloat = 8
    ) {
        self.canvasSize = canvasSize
        self.insets = insets
        self.xDomain = xDomain
        self.yDomain = yDomain

        let innerWidth = max(canvasSize.width - insets.leading - insets.trailing, 1)
        let innerHeight = max(canvasSize.height - insets.top - insets.bottom, 1)

        if showsVolume && innerHeight > 72 {
            let clampedFraction = min(max(volumeHeightFraction, 0.14), 0.30)
            let volHeight = max((innerHeight - volumeGap) * clampedFraction, 18)
            let priceHeight = max(innerHeight - volHeight - volumeGap, 1)

            self.plotRect = CGRect(
                x: insets.leading,
                y: insets.top,
                width: innerWidth,
                height: priceHeight
            )
            self.volumeRect = CGRect(
                x: insets.leading,
                y: insets.top + priceHeight + volumeGap,
                width: innerWidth,
                height: volHeight
            )
        } else {
            self.plotRect = CGRect(
                x: insets.leading,
                y: insets.top,
                width: innerWidth,
                height: innerHeight
            )
            self.volumeRect = nil
        }
    }

    var xSpan: Double {
        max(xDomain.upperBound - xDomain.lowerBound, 1e-9)
    }

    var ySpan: Double {
        max(yDomain.upperBound - yDomain.lowerBound, 1e-9)
    }

    func axisDates(in points: [FinancialChartPoint], count: Int) -> [Date?] {
        guard count > 0, let first = points.first, let last = points.last else { return [] }
        return (0..<count).map { slot in
            let screenX = canvasSize.width * (CGFloat(slot) + 0.5) / CGFloat(count)
            let value = dataX(for: screenX)
            guard value >= first.x, value <= last.x,
                  let index = FinancialChartDownsampler.nearestIndex(in: points, toX: value) else { return nil }
            return points[index].date
        }
    }

    func x(for dataX: Double) -> CGFloat {
        let progress = (dataX - xDomain.lowerBound) / xSpan
        return plotRect.minX + CGFloat(progress) * plotRect.width
    }

    func y(for price: Double) -> CGFloat {
        let progress = (price - yDomain.lowerBound) / ySpan
        return plotRect.maxY - CGFloat(progress) * plotRect.height
    }

    func point(forX dataX: Double, price: Double) -> CGPoint {
        CGPoint(x: x(for: dataX), y: y(for: price))
    }

    func dataX(for screenX: CGFloat) -> Double {
        let clampedX = min(max(screenX, plotRect.minX), plotRect.maxX)
        let progress = Double((clampedX - plotRect.minX) / max(plotRect.width, 1))
        return xDomain.lowerBound + progress * xSpan
    }

    func price(for screenY: CGFloat) -> Double {
        let clampedY = min(max(screenY, plotRect.minY), plotRect.maxY)
        let progress = Double((plotRect.maxY - clampedY) / max(plotRect.height, 1))
        return yDomain.lowerBound + progress * ySpan
    }

    /// Computes dynamic candle body width from plot width and visible bar count.
    func candleWidth(visibleCount: Int) -> CGFloat {
        guard visibleCount > 0 else {
            return 4
        }

        let step = plotRect.width / CGFloat(max(visibleCount, 1))
        return min(max(step * 0.66, 1.8), 12.0)
    }

    func wickWidth(forCandleWidth candleWidth: CGFloat) -> CGFloat {
        min(max(candleWidth * 0.18, 1.0), 1.5)
    }

    /// Computes candle body rectangle strictly in pixel space so doji bars (`open == close`)
    /// always render as crisp thin horizontal bars without distorting price data.
    func candleBodyRect(
        for point: FinancialChartPoint,
        width: CGFloat,
        minBodyHeight: CGFloat = 1.5
    ) -> CGRect {
        let centerX = x(for: point.x)
        let yOpen = y(for: point.open)
        let yClose = y(for: point.close)
        let topY = min(yOpen, yClose)
        let rawHeight = abs(yClose - yOpen)

        if rawHeight < minBodyHeight {
            let midY = (yOpen + yClose) * 0.5
            return CGRect(
                x: centerX - width * 0.5,
                y: midY - minBodyHeight * 0.5,
                width: width,
                height: minBodyHeight
            )
        }

        return CGRect(
            x: centerX - width * 0.5,
            y: topY,
            width: width,
            height: rawHeight
        )
    }

    func volumeBarRect(
        for point: FinancialChartPoint,
        maxVolume: Double,
        barWidth: CGFloat
    ) -> CGRect? {
        guard let volumeRect, maxVolume > 0, point.volume > 0 else {
            return nil
        }

        let centerX = x(for: point.x)
        let fraction = min(max(point.volume / maxVolume, 0), 1)
        let height = max(CGFloat(fraction) * volumeRect.height, 1.0)
        return CGRect(
            x: centerX - barWidth * 0.5,
            y: volumeRect.maxY - height,
            width: barWidth,
            height: height
        )
    }
}
