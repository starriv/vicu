import Foundation

/// Pre-parsed bar storage that caches each bar's parsed ISO-8601 `Date` and minute bucket key.
/// Eliminates repeated main-thread `ISO8601DateFormatter` lock acquisitions during realtime ticks,
/// binary search insertions, overnight merges, and chart render dispatch.
struct AssetDetailBarSeries: Sendable {
    private(set) var entries: [AssetParsedMarketBar] = []
    private(set) var untimedBars: [AlpacaMarketBar] = []
    private(set) var overnightSupplementEntries: [AssetParsedMarketBar] = []

    var latestClose: Double? {
        entries.last?.bar.close ?? untimedBars.last?.close
    }

    var latestEntry: AssetParsedMarketBar? {
        entries.last
    }

    var bars: [AlpacaMarketBar] {
        if untimedBars.isEmpty {
            return entries.map(\.bar)
        }
        return untimedBars + entries.map(\.bar)
    }

    static func normalized(
        from rawBars: [AlpacaMarketBar],
        maxCount: Int = AssetIntradaySessionMapper.maxRetainedBars
    ) -> AssetDetailBarSeries {
        var series = AssetDetailBarSeries()
        series.replaceAll(with: rawBars, maxCount: maxCount)
        return series
    }

    mutating func replaceAll(
        with rawBars: [AlpacaMarketBar],
        maxCount: Int = AssetIntradaySessionMapper.maxRetainedBars
    ) {
        var parsed: [AssetParsedMarketBar] = []
        parsed.reserveCapacity(rawBars.count)
        var untimed: [AlpacaMarketBar] = []

        for bar in rawBars {
            if let entry = AssetParsedMarketBar(bar: bar) {
                parsed.append(entry)
            } else {
                untimed.append(bar)
            }
        }

        parsed.sort { $0.date < $1.date }

        let totalCount = untimed.count + parsed.count
        if totalCount > maxCount {
            let overflow = totalCount - maxCount
            if overflow >= untimed.count {
                let parsedDrop = overflow - untimed.count
                untimed.removeAll(keepingCapacity: false)
                if parsedDrop > 0 && parsedDrop < parsed.count {
                    parsed.removeFirst(parsedDrop)
                } else if parsedDrop >= parsed.count {
                    parsed.removeAll(keepingCapacity: false)
                }
            } else {
                untimed.removeFirst(overflow)
            }
        }

        entries = parsed
        untimedBars = untimed
    }

    mutating func replaceParsedEntries(_ parsedEntries: [AssetParsedMarketBar], untimed: [AlpacaMarketBar] = []) {
        entries = parsedEntries
        untimedBars = untimed
    }

    /// Merges a single realtime or latest bar in chronological order using cached `Date`s.
    /// Returns `true` if the underlying bar series changed.
    @discardableResult
    mutating func merge(
        _ bar: AlpacaMarketBar,
        maxCount: Int = AssetIntradaySessionMapper.maxRetainedBars
    ) -> Bool {
        guard let candidate = AssetParsedMarketBar(bar: bar) else {
            untimedBars.append(bar)
            trim(maxCount: maxCount)
            return true
        }

        // Fast path 1: update the latest bar in place (most common realtime case)
        if let last = entries.last {
            if last.bar.timestamp == candidate.bar.timestamp {
                guard last.bar != candidate.bar else {
                    return false
                }
                entries[entries.count - 1] = candidate
                return true
            }

            // Fast path 2: strictly newer bar -> O(1) append
            if candidate.date > last.date {
                entries.append(candidate)
                trim(maxCount: maxCount)
                return true
            }
        } else {
            entries.append(candidate)
            trim(maxCount: maxCount)
            return true
        }

        // Fast path 3: binary search by cached `Date` (zero DateFormatter calls)
        let lowerIndex = lowerBoundIndex(for: candidate.date)
        var scanIndex = lowerIndex
        while scanIndex < entries.count && entries[scanIndex].date == candidate.date {
            if entries[scanIndex].bar.timestamp == candidate.bar.timestamp {
                guard entries[scanIndex].bar != candidate.bar else {
                    return false
                }
                entries[scanIndex] = candidate
                return true
            }
            scanIndex += 1
        }

        entries.insert(candidate, at: scanIndex)
        trim(maxCount: maxCount)
        return true
    }

    mutating func resetOvernightSupplementBars(with latestBar: AlpacaMarketBar? = nil) {
        overnightSupplementEntries.removeAll(keepingCapacity: true)
        if let latestBar {
            mergeOvernightSupplementBar(latestBar)
        }
    }

    @discardableResult
    mutating func mergeOvernightSupplementBar(
        _ bar: AlpacaMarketBar?,
        maxCount: Int = AssetIntradaySessionMapper.maxOvernightSupplementBars
    ) -> Bool {
        guard let bar, let candidate = AssetParsedMarketBar(bar: bar) else {
            return false
        }

        if let last = overnightSupplementEntries.last {
            if last.minuteKey == candidate.minuteKey {
                guard candidate.date >= last.date, last.bar != candidate.bar else {
                    return false
                }
                overnightSupplementEntries[overnightSupplementEntries.count - 1] = candidate
                return true
            }
            if candidate.minuteKey > last.minuteKey {
                overnightSupplementEntries.append(candidate)
                trimOvernight(maxCount: maxCount)
                return true
            }
        } else {
            overnightSupplementEntries.append(candidate)
            return true
        }

        // Binary search by minuteKey
        var low = 0
        var high = overnightSupplementEntries.count
        while low < high {
            let mid = (low + high) / 2
            if overnightSupplementEntries[mid].minuteKey < candidate.minuteKey {
                low = mid + 1
            } else {
                high = mid
            }
        }

        if low < overnightSupplementEntries.count && overnightSupplementEntries[low].minuteKey == candidate.minuteKey {
            let existing = overnightSupplementEntries[low]
            guard candidate.date >= existing.date, existing.bar != candidate.bar else {
                return false
            }
            overnightSupplementEntries[low] = candidate
            return true
        }

        overnightSupplementEntries.insert(candidate, at: low)
        trimOvernight(maxCount: maxCount)
        return true
    }

    private mutating func trim(maxCount: Int) {
        let total = untimedBars.count + entries.count
        guard total > maxCount else {
            return
        }

        let overflow = total - maxCount
        if overflow <= untimedBars.count {
            untimedBars.removeFirst(overflow)
        } else {
            let remaining = overflow - untimedBars.count
            untimedBars.removeAll(keepingCapacity: false)
            if remaining < entries.count {
                entries.removeFirst(remaining)
            } else {
                entries.removeAll(keepingCapacity: false)
            }
        }
    }

    private mutating func trimOvernight(maxCount: Int) {
        if overnightSupplementEntries.count > maxCount {
            overnightSupplementEntries.removeFirst(overnightSupplementEntries.count - maxCount)
        }
    }

    private func lowerBoundIndex(for date: Date) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
