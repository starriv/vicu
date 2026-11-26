import SwiftUI
import WidgetKit

/// Presentational snapshot of the trading-day Live Activity. Built by the app from
/// market clock + calendar data, rendered by the widget (and by the in-app preview).
struct SessionActivityCardModel: Hashable, Sendable {
    var marketName: String
    var phaseTitle: String
    var phaseSymbol: String
    var countdownLabel: String
    var sessionStart: Date
    var transitionAt: Date
    var cycleStart: Date
    var cycleEnd: Date
    var segments: [SessionActivitySegment]
    var summaryText: String?
    var summaryIsNegative: Bool
    var trailingText: String?
}

// MARK: - Lock screen & Smart Stack

struct SessionActivityLockScreenCard: View {
    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let model: SessionActivityCardModel
    var showsProgress: Bool = true

    var body: some View {
        if activityFamily == .small {
            smallCard
        } else {
            mediumCard
        }
    }

    /// Standard Lock Screen / StandBy Live Activity layout.
    /// One clear hero metric (session countdown), one self-updating progress bar
    /// aligned with that countdown, and a quiet contextual footer.
    private var mediumCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 11) {
                ActivitySymbolBadge(
                    symbol: model.phaseSymbol,
                    tint: ActivityDesign.brand
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.phaseTitle)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)

                        Text(model.marketName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let summaryText = model.summaryText {
                        Text(summaryText)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(summaryColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else if let trailingText = model.trailingText {
                        Text(trailingText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(model.countdownLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ActivityCountdownText(target: model.transitionAt)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            if showsProgress {
                ActivitySessionProgressBar(
                    start: model.sessionStart,
                    end: model.transitionAt
                )
            }

            if showsFooter {
                HStack(alignment: .center, spacing: 6) {
                    ActivityBrandMark(size: 14)

                    if let trailingText = model.trailingText {
                        Text(trailingText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, ActivityDesign.horizontalPadding)
        .padding(.vertical, ActivityDesign.verticalPadding)
        .accessibilityElement(children: .contain)
    }

    /// Compact layout for Apple Watch Smart Stack (`.small` activity family).
    private var smallCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: model.phaseSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ActivityDesign.brand)
                    .widgetAccentable()

                Text(model.phaseTitle)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                ActivityCountdownText(target: model.transitionAt, showsHours: false)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if showsProgress {
                ActivitySessionProgressBar(
                    start: model.sessionStart,
                    end: model.transitionAt
                )
            }

            if let summaryText = model.summaryText {
                Text(summaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(summaryColor)
                    .lineLimit(1)
            } else if let trailingText = model.trailingText {
                Text(trailingText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var summaryColor: AnyShapeStyle {
        if isLuminanceReduced {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(model.summaryIsNegative ? ActivityDesign.negative : ActivityDesign.positive)
    }

    private var showsFooter: Bool {
        model.summaryText != nil && model.trailingText != nil
    }
}

// MARK: - Dynamic Island

struct SessionActivityIslandLeading: View {
    let model: SessionActivityCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: model.phaseSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ActivityDesign.brand)
                    .widgetAccentable()

                Text(model.phaseTitle)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
            }

            Text(model.marketName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.top, 2)
    }
}

struct SessionActivityIslandTrailing: View {
    let model: SessionActivityCardModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(model.countdownLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ActivityCountdownText(target: model.transitionAt)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.trailing, 8)
        .padding(.top, 2)
    }
}

struct SessionActivityIslandBottom: View {
    let model: SessionActivityCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActivitySessionProgressBar(
                start: model.sessionStart,
                end: model.transitionAt
            )

            HStack(alignment: .center, spacing: 6) {
                ActivityBrandMark(size: 13)

                if let summaryText = model.summaryText {
                    Text(summaryText)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(model.summaryIsNegative ? ActivityDesign.negative : ActivityDesign.positive)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let trailingText = model.trailingText {
                    Text(trailingText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

struct SessionActivityCompactLeading: View {
    let model: SessionActivityCardModel

    var body: some View {
        Image(systemName: model.phaseSymbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ActivityDesign.brand)
            .widgetAccentable()
    }
}

struct SessionActivityCompactTrailing: View {
    let model: SessionActivityCardModel

    var body: some View {
        ActivityCountdownText(target: model.transitionAt, showsHours: false)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
    }
}

struct SessionActivityMinimal: View {
    let model: SessionActivityCardModel

    var body: some View {
        ActivityBrandMark(size: 15, tint: ActivityDesign.brand)
            .widgetAccentable()
    }
}
