import SwiftUI

struct MarketSessionTimeline: Sendable {
    let segments: [MarketSessionTimelineSegment]
    let referenceDate: Date

    init?(progress: MarketSessionProgress?) {
        guard let progress, !progress.intervals.isEmpty else {
            return nil
        }

        segments = progress.intervals.map(MarketSessionTimelineSegment.init(interval:))
        referenceDate = progress.referenceDate
    }

    var start: Date? {
        segments.first?.start
    }

    var end: Date? {
        segments.last?.end
    }

    func markerDate(for selectedDate: Date?) -> Date {
        let date = selectedDate ?? referenceDate
        if contains(date) {
            return date
        }

        if let selectedDate,
           let sessionPosition = MarketSessionTimelineSessionPosition(date: selectedDate),
           let matchingSegment = segments.first(where: { $0.session == sessionPosition.session }) {
            return matchingSegment.start.addingTimeInterval(matchingSegment.duration * sessionPosition.fraction)
        }

        guard let start, let end else {
            return date
        }

        return min(max(date, start), end)
    }

    func activeSession(for selectedDate: Date?) -> MarketSessionKind? {
        if let selectedDate,
           let sessionPosition = MarketSessionTimelineSessionPosition(date: selectedDate),
           segments.contains(where: { $0.session == sessionPosition.session }) {
            return sessionPosition.session
        }

        return segments.first { segment in
            segment.start <= referenceDate && referenceDate < segment.end
        }?.session
    }

    private func contains(_ date: Date) -> Bool {
        segments.contains { segment in
            segment.start <= date && date <= segment.end
        }
    }
}

struct MarketSessionTimelineSegment: Identifiable, Sendable {
    let id: String
    let session: MarketSessionKind
    let start: Date
    let end: Date
    let marketDate: String

    init(interval: MarketSessionInterval) {
        id = interval.id
        session = interval.session
        start = interval.start
        end = interval.end
        marketDate = interval.marketDate
    }

    var duration: TimeInterval {
        max(end.timeIntervalSince(start), 0)
    }
}

enum MarketSessionTimelineStyle {
    case bar
    case dot
}

struct MarketSessionTimelineView: View {
    let timeline: MarketSessionTimeline?
    let selectedDate: Date?
    let style: MarketSessionTimelineStyle
    let dotSize: CGFloat

    init(
        timeline: MarketSessionTimeline?,
        selectedDate: Date?,
        style: MarketSessionTimelineStyle = .bar,
        dotSize: CGFloat = 9
    ) {
        self.timeline = timeline
        self.selectedDate = selectedDate
        self.style = style
        self.dotSize = dotSize
    }

    var body: some View {
        switch style {
        case .bar:
            timelineBar
        case .dot:
            timelineDot
        }
    }

    private var timelineBar: some View {
        GeometryReader { geometry in
            if let timeline,
               let cycleStart = timeline.start,
               let cycleEnd = timeline.end {
                let totalDuration = cycleEnd.timeIntervalSince(cycleStart)
                if totalDuration > 0 {
                    let spacing: CGFloat = 2
                    let availableWidth = max(0, geometry.size.width - spacing * CGFloat(max(timeline.segments.count - 1, 0)))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: spacing) {
                            ForEach(timeline.segments) { segment in
                                let width = segmentWidth(segment, totalDuration: totalDuration, availableWidth: availableWidth)
                                Text(segment.session.timelineLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(width: width, height: 10, alignment: .center)
                            }
                        }

                        ZStack(alignment: .leading) {
                            HStack(spacing: spacing) {
                                ForEach(timeline.segments) { segment in
                                    Capsule()
                                        .fill(segment.session.timelineTint)
                                        .frame(width: segmentWidth(segment, totalDuration: totalDuration, availableWidth: availableWidth))
                                }
                            }
                            .frame(height: 5)

                            Capsule()
                                .fill(Color(.label).opacity(0.88))
                                .frame(width: 3, height: 10)
                                .offset(
                                    x: markerOffset(
                                        timeline,
                                        totalDuration: totalDuration,
                                        availableWidth: availableWidth,
                                        spacing: spacing,
                                        totalWidth: geometry.size.width
                                    )
                                )
                        }
                        .frame(height: 10)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var timelineDot: some View {
        Circle()
            .fill(dotTint)
            .frame(width: dotSize, height: dotSize)
            .accessibilityLabel(dotAccessibilityLabel)
    }

    private var dotTint: Color {
        timeline?.activeSession(for: selectedDate)?.timelineTint ?? Color(.tertiaryLabel)
    }

    private var dotAccessibilityLabel: String {
        timeline?.activeSession(for: selectedDate)?.timelineLabel ?? "Market session unavailable"
    }

    private func segmentWidth(
        _ segment: MarketSessionTimelineSegment,
        totalDuration: TimeInterval,
        availableWidth: CGFloat
    ) -> CGFloat {
        max(4, availableWidth * CGFloat(segment.duration / totalDuration))
    }

    private func markerOffset(
        _ timeline: MarketSessionTimeline,
        totalDuration: TimeInterval,
        availableWidth: CGFloat,
        spacing: CGFloat,
        totalWidth: CGFloat
    ) -> CGFloat {
        let markerDate = timeline.markerDate(for: selectedDate)
        var cursor: CGFloat = 0

        for segment in timeline.segments {
            let segmentWidthValue = segmentWidth(segment, totalDuration: totalDuration, availableWidth: availableWidth)
            if markerDate < segment.start {
                break
            }

            if markerDate <= segment.end {
                let elapsed = min(max(markerDate.timeIntervalSince(segment.start), 0), segment.duration)
                let duration = max(segment.duration, 1)
                return min(max(cursor + segmentWidthValue * CGFloat(elapsed / duration) - 1.5, 0), max(totalWidth - 3, 0))
            }

            cursor += segmentWidthValue + spacing
        }

        return min(max(cursor - spacing - 1.5, 0), max(totalWidth - 3, 0))
    }
}

private struct MarketSessionTimelineSessionPosition {
    let session: MarketSessionKind
    let fraction: Double

    init?(date: Date) {
        let minutes = Self.easternMinutes(from: date)

        switch minutes {
        case 20 * 60 ..< 24 * 60:
            session = .overnight
            fraction = Double(minutes - 20 * 60) / Double(8 * 60)
        case 0 ..< 4 * 60:
            session = .overnight
            fraction = Double(minutes + 4 * 60) / Double(8 * 60)
        case 4 * 60 ..< 9 * 60 + 30:
            session = .preMarket
            fraction = Double(minutes - 4 * 60) / Double(5 * 60 + 30)
        case 9 * 60 + 30 ..< 16 * 60:
            session = .regular
            fraction = Double(minutes - (9 * 60 + 30)) / Double(6 * 60 + 30)
        case 16 * 60 ..< 20 * 60:
            session = .afterHours
            fraction = Double(minutes - 16 * 60) / Double(4 * 60)
        default:
            return nil
        }
    }

    private static func easternMinutes(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private extension MarketSessionKind {
    var timelineLabel: String {
        switch self {
        case .overnight:
            "Overnight"
        case .preMarket:
            "Pre"
        case .regular:
            "Regular"
        case .afterHours:
            "After"
        }
    }

    var timelineTint: Color {
        switch self {
        case .overnight:
            Color.indigo
        case .preMarket:
            Color.yellow
        case .regular:
            AppTheme.ColorToken.positive
        case .afterHours:
            Color.orange
        }
    }
}
