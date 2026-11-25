import Foundation

enum FinancialChartDownsampler {
    /// Largest-Triangle-Three-Buckets (LTTB) downsampling for line/area series.
    /// Preserves visual peaks, troughs, and inflection points while bounding vertex count.
    static func lttb(
        _ points: ArraySlice<FinancialChartPoint>,
        targetCount: Int
    ) -> [FinancialChartPoint] {
        guard targetCount >= 3, points.count > targetCount else {
            return Array(points)
        }

        let array = Array(points)
        var sampled: [FinancialChartPoint] = []
        sampled.reserveCapacity(targetCount)

        let bucketSize = Double(array.count - 2) / Double(targetCount - 2)
        var selectedIndex = 0
        sampled.append(array[0])

        for bucket in 0..<(targetCount - 2) {
            let nextRangeStart = min(Int(floor(Double(bucket + 1) * bucketSize)) + 1, array.count - 1)
            let nextRangeEnd = min(Int(floor(Double(bucket + 2) * bucketSize)) + 1, array.count)

            var avgX = 0.0
            var avgY = 0.0
            let nextCount = max(nextRangeEnd - nextRangeStart, 1)
            for idx in nextRangeStart..<nextRangeEnd {
                avgX += array[idx].x
                avgY += array[idx].close
            }
            avgX /= Double(nextCount)
            avgY /= Double(nextCount)

            let rangeStart = min(Int(floor(Double(bucket) * bucketSize)) + 1, array.count - 1)
            let rangeEnd = max(rangeStart + 1, min(nextRangeStart, array.count - 1))

            let prevX = array[selectedIndex].x
            let prevY = array[selectedIndex].close

            var maxArea = -1.0
            var bestIndex = rangeStart

            for idx in rangeStart..<rangeEnd {
                let area = abs(
                    (prevX - avgX) * (array[idx].close - prevY)
                    - (prevX - array[idx].x) * (avgY - prevY)
                ) * 0.5
                if area > maxArea {
                    maxArea = area
                    bestIndex = idx
                }
            }

            sampled.append(array[bestIndex])
            selectedIndex = bestIndex
        }

        sampled.append(array[array.count - 1])
        return sampled
    }

    /// Aggregates OHLCV candles into buckets when there are more bars than can be legibly drawn.
    static func aggregateCandles(
        _ points: ArraySlice<FinancialChartPoint>,
        maxCount: Int
    ) -> [FinancialChartPoint] {
        guard maxCount > 0, points.count > maxCount else {
            return Array(points)
        }

        let array = Array(points)
        let bucketSize = Int(ceil(Double(array.count) / Double(maxCount)))
        var result: [FinancialChartPoint] = []
        result.reserveCapacity((array.count + bucketSize - 1) / bucketSize)

        var startIndex = 0
        while startIndex < array.count {
            let endIndex = min(array.count, startIndex + bucketSize)
            let first = array[startIndex]
            let last = array[endIndex - 1]

            var high = first.high
            var low = first.low
            var volume = 0.0
            for idx in startIndex..<endIndex {
                let p = array[idx]
                if p.high > high { high = p.high }
                if p.low < low { low = p.low }
                volume += p.volume
            }

            let centerX = (first.x + last.x) * 0.5
            result.append(
                FinancialChartPoint(
                    date: first.date,
                    x: centerX,
                    open: first.open,
                    high: high,
                    low: low,
                    close: last.close,
                    volume: volume
                )
            )
            startIndex = endIndex
        }

        return result
    }

    /// Extracts the visible sub-slice for `xDomain` (with 1-bar padding on each side for edge continuity) in O(log N).
    static func visibleSlice(
        in points: [FinancialChartPoint],
        xDomain: ClosedRange<Double>
    ) -> ArraySlice<FinancialChartPoint> {
        guard !points.isEmpty else {
            return points[...]
        }

        let startIndex = max(lowerBoundIndex(in: points, forX: xDomain.lowerBound) - 1, 0)
        let endIndex = min(upperBoundIndex(in: points, forX: xDomain.upperBound) + 1, points.count - 1)

        guard startIndex <= endIndex else {
            return points[...]
        }
        return points[startIndex...endIndex]
    }

    /// Binary search for the nearest point index to `targetX` in O(log N).
    static func nearestIndex(
        in points: [FinancialChartPoint],
        toX targetX: Double
    ) -> Int? {
        guard !points.isEmpty else {
            return nil
        }

        let idx = lowerBoundIndex(in: points, forX: targetX)
        if idx >= points.count {
            return points.count - 1
        }
        if idx == 0 {
            return 0
        }

        let prev = points[idx - 1]
        let next = points[idx]
        return abs(prev.x - targetX) <= abs(next.x - targetX) ? (idx - 1) : idx
    }

    private static func lowerBoundIndex(
        in points: [FinancialChartPoint],
        forX targetX: Double
    ) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].x < targetX {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func upperBoundIndex(
        in points: [FinancialChartPoint],
        forX targetX: Double
    ) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].x <= targetX {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(low - 1, 0)
    }
}
