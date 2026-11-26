import ActivityKit
import SwiftUI
import WidgetKit

struct SessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityLockScreenCard(model: context.cardModel)
        } dynamicIsland: { context in
            let model = context.cardModel

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionActivityIslandLeading(model: model)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    SessionActivityIslandTrailing(model: model)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    SessionActivityIslandBottom(model: model)
                }
            } compactLeading: {
                SessionActivityCompactLeading(model: model)
            } compactTrailing: {
                SessionActivityCompactTrailing(model: model)
            } minimal: {
                SessionActivityMinimal(model: model)
            }
            .keylineTint(ActivityDesign.brand)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

extension ActivityViewContext where Attributes == SessionActivityAttributes {
    var cardModel: SessionActivityCardModel {
        SessionActivityCardModel(
            marketName: attributes.marketName,
            phaseTitle: state.phaseTitle,
            phaseSymbol: state.phaseSymbol,
            countdownLabel: state.countdownLabel,
            sessionStart: state.sessionStart,
            transitionAt: state.transitionAt,
            cycleStart: state.cycleStart,
            cycleEnd: state.cycleEnd,
            segments: state.segments,
            summaryText: state.summaryText,
            summaryIsNegative: state.summaryIsNegative,
            trailingText: state.trailingText
        )
    }
}
