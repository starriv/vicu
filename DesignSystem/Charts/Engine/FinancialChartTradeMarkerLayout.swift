import CoreGraphics
import Foundation

/// Pure O(log M + K) screen-space layout and decluttering solver for buy/sell trade markers.
///
/// Design goals:
/// - Runs strictly on snapshot cache misses (range/mode/zoom/size changes), never on 120Hz scrubs.
/// - Separates Buy (below curve/candle) and Sell (above curve/candle) tracks so same-bar fills never collide.
/// - Greedily clusters badges closer than `minHorizontalSpacing` in screen space; zooming in on candles
///   automatically expands clusters into individual execution markers.
/// - Anchors line/area dots directly onto the rendered LTTB display curve via O(log D) interpolation
///   so dots never float detached from the curve.
enum FinancialChartTradeMarkerLayout {
    static let badgeDiameter: CGFloat = 15.0
    static let minHorizontalSpacing: CGFloat = 18.0
    static let lineStemCenterOffset: CGFloat = 16.0
    static let candleBadgeOffset: CGFloat = 13.0
    static let candleWickGap: CGFloat = 2.5

    static func place(
        markers: [FinancialChartTradeMarker],
        displayPoints: [FinancialChartPoint],
        kind: FinancialChartKind,
        coordinateSystem: FinancialChartCoordinateSystem
    ) -> [FinancialChartPlacedTradeMarker] {
        guard !markers.isEmpty, !displayPoints.isEmpty else {
            return []
        }

        let plotRect = coordinateSystem.plotRect
        guard plotRect.width > 1, plotRect.height > 1 else {
            return []
        }

        let visibleSlice = visibleMarkersSlice(in: markers, xDomain: coordinateSystem.xDomain)
        guard !visibleSlice.isEmpty else {
            return []
        }

        var buyMarkers: [FinancialChartTradeMarker] = []
        var sellMarkers: [FinancialChartTradeMarker] = []
        buyMarkers.reserveCapacity(visibleSlice.count)
        sellMarkers.reserveCapacity(visibleSlice.count)

        for marker in visibleSlice {
            switch marker.side {
            case .buy:
                buyMarkers.append(marker)
            case .sell:
                sellMarkers.append(marker)
            }
        }

        let buyClusters = cluster(buyMarkers, coordinateSystem: coordinateSystem)
        let sellClusters = cluster(sellMarkers, coordinateSystem: coordinateSystem)

        let buyPositions = Set(buyClusters.map { Int(($0.screenX / 10.0).rounded()) })
        let sellPositions = Set(sellClusters.map { Int(($0.screenX / 10.0).rounded()) })

        var placed: [FinancialChartPlacedTradeMarker] = []
        placed.reserveCapacity(buyClusters.count + sellClusters.count)

        for item in buyClusters {
            placed.append(
                placeCluster(
                    item,
                    side: .buy,
                    hasOppositeNearby: hasNearbyBucket(item.screenX, in: sellPositions),
                    displayPoints: displayPoints,
                    kind: kind,
                    coordinateSystem: coordinateSystem
                )
            )
        }

        for item in sellClusters {
            placed.append(
                placeCluster(
                    item,
                    side: .sell,
                    hasOppositeNearby: hasNearbyBucket(item.screenX, in: buyPositions),
                    displayPoints: displayPoints,
                    kind: kind,
                    coordinateSystem: coordinateSystem
                )
            )
        }

        return placed
    }

    // MARK: - Helpers

    private struct MarkerCluster {
        var representative: FinancialChartTradeMarker
        var screenX: CGFloat
        var clusterCount: Int
        var maxQuantity: Double
        var minLow: Double
        var maxHigh: Double
    }

    private static func visibleMarkersSlice(
        in markers: [FinancialChartTradeMarker],
        xDomain: ClosedRange<Double>
    ) -> ArraySlice<FinancialChartTradeMarker> {
        let lower = lowerBoundIndex(in: markers, forX: xDomain.lowerBound)
        let upper = upperBoundIndex(in: markers, forX: xDomain.upperBound)
        guard lower <= upper, lower < markers.count, upper >= 0 else {
            return markers[0..<0]
        }
        return markers[lower...upper]
    }

    private static func lowerBoundIndex(in markers: [FinancialChartTradeMarker], forX targetX: Double) -> Int {
        var low = 0
        var high = markers.count
        while low < high {
            let mid = (low + high) / 2
            if markers[mid].x < targetX {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func upperBoundIndex(in markers: [FinancialChartTradeMarker], forX targetX: Double) -> Int {
        var low = 0
        var high = markers.count
        while low < high {
            let mid = (low + high) / 2
            if markers[mid].x <= targetX {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low - 1
    }

    private static func cluster(
        _ markers: [FinancialChartTradeMarker],
        coordinateSystem: FinancialChartCoordinateSystem
    ) -> [MarkerCluster] {
        guard !markers.isEmpty else {
            return []
        }

        var clusters: [MarkerCluster] = []
        clusters.reserveCapacity(markers.count)

        for marker in markers {
            let screenX = coordinateSystem.x(for: marker.x)
            if var last = clusters.last, abs(screenX - last.screenX) < minHorizontalSpacing {
                last.clusterCount += max(marker.fillCount, 1)
                last.minLow = min(last.minLow, marker.barLow)
                last.maxHigh = max(last.maxHigh, marker.barHigh)
                if marker.totalQuantity >= last.maxQuantity {
                    last.representative = marker
                    last.screenX = screenX
                    last.maxQuantity = marker.totalQuantity
                }
                clusters[clusters.count - 1] = last
            } else {
                clusters.append(
                    MarkerCluster(
                        representative: marker,
                        screenX: screenX,
                        clusterCount: max(marker.fillCount, 1),
                        maxQuantity: marker.totalQuantity,
                        minLow: marker.barLow,
                        maxHigh: marker.barHigh
                    )
                )
            }
        }

        return clusters
    }

    private static func hasNearbyBucket(_ screenX: CGFloat, in buckets: Set<Int>) -> Bool {
        let bucket = Int((screenX / 10.0).rounded())
        return buckets.contains(bucket) || buckets.contains(bucket - 1) || buckets.contains(bucket + 1)
    }

    private static func placeCluster(
        _ cluster: MarkerCluster,
        side: FinancialChartTradeSide,
        hasOppositeNearby: Bool,
        displayPoints: [FinancialChartPoint],
        kind: FinancialChartKind,
        coordinateSystem: FinancialChartCoordinateSystem
    ) -> FinancialChartPlacedTradeMarker {
        let plotRect = coordinateSystem.plotRect
        let halfBadge = badgeDiameter * 0.5
        let clampedBadgeX = min(
            max(cluster.screenX, plotRect.minX + halfBadge + 1.5),
            plotRect.maxX - halfBadge - 1.5
        )

        switch kind {
        case .line, .area:
            let curvePrice = interpolatedCurvePrice(
                atX: cluster.representative.x,
                in: displayPoints,
                fallback: cluster.representative.barClose
            )
            let anchorY = min(max(coordinateSystem.y(for: curvePrice), plotRect.minY), plotRect.maxY)
            let anchorPoint = CGPoint(x: cluster.screenX, y: anchorY)

            let defaultBelow = side == .buy
            var isBelow = defaultBelow
            var badgeY = defaultBelow ? (anchorY + lineStemCenterOffset) : (anchorY - lineStemCenterOffset)

            let topLimit = max(plotRect.minY - 8.0, halfBadge + 2.0)
            let bottomLimit = min(plotRect.maxY + 4.0, coordinateSystem.canvasSize.height - halfBadge - 2.0)

            if isBelow && badgeY > bottomLimit {
                if !hasOppositeNearby && (anchorY - lineStemCenterOffset) >= topLimit {
                    isBelow = false
                    badgeY = anchorY - lineStemCenterOffset
                } else {
                    badgeY = bottomLimit
                }
            } else if !isBelow && badgeY < topLimit {
                if !hasOppositeNearby && (anchorY + lineStemCenterOffset) <= bottomLimit {
                    isBelow = true
                    badgeY = anchorY + lineStemCenterOffset
                } else {
                    badgeY = topLimit
                }
            }

            return FinancialChartPlacedTradeMarker(
                side: side,
                anchorPoint: anchorPoint,
                badgeCenter: CGPoint(x: clampedBadgeX, y: badgeY),
                isBelowAnchor: isBelow,
                clusterCount: cluster.clusterCount
            )

        case .candles:
            let matchedCandle = nearestPoint(atX: cluster.representative.x, in: displayPoints)
            let candleX = matchedCandle.map { coordinateSystem.x(for: $0.x) } ?? cluster.screenX
            let candleClampedX = min(
                max(candleX, plotRect.minX + halfBadge + 1.5),
                plotRect.maxX - halfBadge - 1.5
            )
            let effectiveLow = min(matchedCandle?.low ?? cluster.minLow, cluster.minLow)
            let effectiveHigh = max(matchedCandle?.high ?? cluster.maxHigh, cluster.maxHigh)

            let topLimit = max(plotRect.minY - 12.0, halfBadge + 2.0)
            let bottomLimit = plotRect.maxY - halfBadge - 1.0

            if side == .buy {
                let lowY = coordinateSystem.y(for: effectiveLow)
                let anchorY = min(lowY + candleWickGap, bottomLimit - 6.0)
                let badgeY = min(max(anchorY + candleBadgeOffset, topLimit), bottomLimit)
                return FinancialChartPlacedTradeMarker(
                    side: .buy,
                    anchorPoint: CGPoint(x: candleX, y: anchorY),
                    badgeCenter: CGPoint(x: candleClampedX, y: badgeY),
                    isBelowAnchor: true,
                    clusterCount: cluster.clusterCount
                )
            } else {
                let highY = coordinateSystem.y(for: effectiveHigh)
                let anchorY = max(highY - candleWickGap, topLimit + 6.0)
                let badgeY = min(max(anchorY - candleBadgeOffset, topLimit), bottomLimit)
                return FinancialChartPlacedTradeMarker(
                    side: .sell,
                    anchorPoint: CGPoint(x: candleX, y: anchorY),
                    badgeCenter: CGPoint(x: candleClampedX, y: badgeY),
                    isBelowAnchor: false,
                    clusterCount: cluster.clusterCount
                )
            }
        }
    }

    private static func interpolatedCurvePrice(
        atX targetX: Double,
        in displayPoints: [FinancialChartPoint],
        fallback: Double
    ) -> Double {
        guard !displayPoints.isEmpty else {
            return fallback
        }
        if targetX <= displayPoints[0].x {
            return displayPoints[0].close
        }
        if let last = displayPoints.last, targetX >= last.x {
            return last.close
        }

        var low = 0
        var high = displayPoints.count - 1
        while low < high {
            let mid = (low + high) / 2
            if displayPoints[mid].x < targetX {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let right = displayPoints[low]
        if low == 0 || right.x == targetX {
            return right.close
        }
        let left = displayPoints[low - 1]
        let span = right.x - left.x
        guard span > 1e-9 else {
            return right.close
        }
        let t = min(max((targetX - left.x) / span, 0), 1)
        return left.close + (right.close - left.close) * t
    }

    private static func nearestPoint(
        atX targetX: Double,
        in displayPoints: [FinancialChartPoint]
    ) -> FinancialChartPoint? {
        guard let index = FinancialChartDownsampler.nearestIndex(in: displayPoints, toX: targetX) else {
            return nil
        }
        return displayPoints[index]
    }
}
