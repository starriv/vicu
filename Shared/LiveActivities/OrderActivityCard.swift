import SwiftUI
import WidgetKit

/// Presentational snapshot of an order Live Activity. The widget builds it from
/// `ActivityViewContext`; the in-app preview screen builds it from fixtures, so
/// both render exactly the same views.
struct OrderActivityCardModel: Hashable, Sendable {
    var orderID: String
    var symbol: String
    var side: OrderActivitySide
    var sideLabel: String
    var orderTypeLabel: String
    var phase: OrderActivityPhase
    var statusTitle: String
    var detailLine: String
    var fillProgress: Double
    var fillRatioText: String
    var asOfText: String
    var cancelActionTitle: String?
    var additionalOrdersText: String?
    var allowsCancellation: Bool

    var cancelURL: URL? {
        VicuDeepLink.order(orderID: orderID, symbol: symbol, armsCancellation: true)
    }

    var detailURL: URL? {
        VicuDeepLink.order(orderID: orderID, symbol: symbol)
    }

    var footerSummary: String {
        [orderTypeLabel, additionalOrdersText, asOfText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }
}

// MARK: - Lock screen & Smart Stack

struct OrderActivityLockScreenCard: View {
    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let model: OrderActivityCardModel
    var showsActions: Bool = true

    var body: some View {
        if activityFamily == .small {
            smallCard
        } else {
            mediumCard
        }
    }

    /// Standard Lock Screen / StandBy Live Activity layout.
    /// Keeps natural height well under the ~160pt system ceiling (~86–116pt) with
    /// clear hierarchy: identity + status on top, thin progress bar when active,
    /// and a quiet metadata footer with an optional compact cancel capsule.
    private var mediumCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 11) {
                ActivitySymbolBadge(
                    symbol: model.phase.systemImage,
                    tint: model.phase.tint
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)

                        Text(model.sideLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isLuminanceReduced ? .secondary : model.side.tint)
                            .lineLimit(1)
                    }

                    statusSubtitle
                }

                Spacer(minLength: 8)

                Text(model.fillRatioText)
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(ratioForegroundStyle)
                    .lineLimit(1)
            }

            if !model.phase.isTerminal {
                ActivityProgressBar(
                    progress: model.fillProgress,
                    tint: model.phase.tint
                )
            }

            if showsFooter {
                HStack(alignment: .center, spacing: 6) {
                    ActivityBrandMark(size: 14)

                    if !model.footerSummary.isEmpty {
                        Text(model.footerSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 6)

                    if showsActions,
                       model.allowsCancellation,
                       let cancelURL = model.cancelURL,
                       let cancelTitle = model.cancelActionTitle {
                        ActivityCompactAction(title: cancelTitle, url: cancelURL)
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: model.phase.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.phase.tint)
                    .widgetAccentable()

                Text(model.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(model.fillRatioText)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if !model.phase.isTerminal {
                ActivityProgressBar(
                    progress: model.fillProgress,
                    tint: model.phase.tint,
                    height: 3
                )
            }

            statusSubtitle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var statusSubtitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.statusTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isLuminanceReduced ? .secondary : model.phase.tint)
                .widgetAccentable()
                .lineLimit(1)

            if !model.detailLine.isEmpty {
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Text(model.detailLine)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var ratioForegroundStyle: AnyShapeStyle {
        switch model.phase {
        case .canceled, .rejected, .expired:
            AnyShapeStyle(.secondary)
        default:
            AnyShapeStyle(.primary)
        }
    }

    private var showsFooter: Bool {
        !model.footerSummary.isEmpty
            || (showsActions && model.allowsCancellation && model.cancelURL != nil && model.cancelActionTitle != nil)
    }
}

// MARK: - Dynamic Island

struct OrderActivityIslandLeading: View {
    let model: OrderActivityCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(model.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)

                Text(model.sideLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.side.tint)
                    .lineLimit(1)
            }

            Text(model.statusTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.phase.tint)
                .widgetAccentable()
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.top, 2)
    }
}

struct OrderActivityIslandTrailing: View {
    let model: OrderActivityCardModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.fillRatioText)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if !model.detailLine.isEmpty {
                Text(model.detailLine)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.trailing, 8)
        .padding(.top, 2)
    }
}

struct OrderActivityIslandBottom: View {
    let model: OrderActivityCardModel
    var showsActions: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.phase.isTerminal {
                ActivityProgressBar(
                    progress: model.fillProgress,
                    tint: model.phase.tint
                )
            }

            HStack(alignment: .center, spacing: 6) {
                ActivityBrandMark(size: 13)

                Text(model.footerSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                if showsActions,
                   model.allowsCancellation,
                   let cancelURL = model.cancelURL,
                   let cancelTitle = model.cancelActionTitle {
                    ActivityCompactAction(title: cancelTitle, url: cancelURL)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

struct OrderActivityCompactLeading: View {
    let model: OrderActivityCardModel

    var body: some View {
        Text(model.symbol)
            .font(.system(size: 13, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

struct OrderActivityCompactTrailing: View {
    let model: OrderActivityCardModel

    var body: some View {
        if !model.phase.isTerminal && model.fillProgress > 0 {
            ActivityProgressRing(progress: model.fillProgress, tint: model.phase.tint)
        } else {
            Image(systemName: model.phase.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.phase.tint)
                .widgetAccentable()
        }
    }
}

struct OrderActivityMinimal: View {
    let model: OrderActivityCardModel

    var body: some View {
        Image(systemName: model.phase.systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(model.phase.tint)
            .widgetAccentable()
    }
}
