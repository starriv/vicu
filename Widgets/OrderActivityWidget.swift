import ActivityKit
import SwiftUI
import WidgetKit

struct OrderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            OrderActivityLockScreenCard(model: context.cardModel)
                .widgetURL(VicuDeepLink.order(orderID: context.attributes.orderID))
        } dynamicIsland: { context in
            let model = context.cardModel

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OrderActivityIslandLeading(model: model)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    OrderActivityIslandTrailing(model: model)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    OrderActivityIslandBottom(model: model)
                }
            } compactLeading: {
                OrderActivityCompactLeading(model: model)
            } compactTrailing: {
                OrderActivityCompactTrailing(model: model)
            } minimal: {
                OrderActivityMinimal(model: model)
            }
            .keylineTint(model.phase.tint)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

extension ActivityViewContext where Attributes == OrderActivityAttributes {
    var cardModel: OrderActivityCardModel {
        OrderActivityCardModel(
            orderID: attributes.orderID,
            symbol: attributes.symbol,
            side: attributes.side,
            sideLabel: attributes.sideLabel,
            orderTypeLabel: attributes.orderTypeLabel,
            phase: state.phase,
            statusTitle: state.statusTitle,
            detailLine: state.detailLine,
            fillProgress: state.fillProgress,
            fillRatioText: state.fillRatioText,
            asOfText: state.asOfText,
            cancelActionTitle: state.actionTitle,
            additionalOrdersText: state.additionalOrdersText,
            allowsCancellation: state.allowsCancellation
        )
    }
}
