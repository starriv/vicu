import ActivityKit
import Foundation

enum OrderActivityManager {
    static func startCancellationPrompt(for order: AlpacaOrder, message: String) async {
        await upsertActivity(for: order, phase: .awaitingConfirmation, message: message)
    }

    static func updateCancellation(for order: AlpacaOrder, phase: OrderCancellationPhase, message: String) async {
        await upsertActivity(for: order, phase: phase, message: message)
    }

    static func dismissCancellationPrompt(for order: AlpacaOrder, message: String) async {
        await endActivity(for: order, phase: .dismissed, message: message, dismissalPolicy: .immediate)
    }

    static func endCancellation(for order: AlpacaOrder, phase: OrderCancellationPhase, message: String) async {
        await endActivity(
            for: order,
            phase: phase,
            message: message,
            dismissalPolicy: .after(Date().addingTimeInterval(300))
        )
    }

    private static func upsertActivity(for order: AlpacaOrder, phase: OrderCancellationPhase, message: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let content = content(phase: phase, message: message)
        if let activity = activity(for: order.id) {
            await activity.update(content)
            return
        }

        do {
            _ = try Activity.request(
                attributes: attributes(for: order),
                content: content,
                pushType: nil
            )
        } catch {
            return
        }
    }

    private static func endActivity(
        for order: AlpacaOrder,
        phase: OrderCancellationPhase,
        message: String,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = activity(for: order.id) else {
            return
        }

        await activity.end(
            content(phase: phase, message: message, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )
    }

    private static func activity(for orderID: String) -> Activity<OrderCancellationActivityAttributes>? {
        Activity<OrderCancellationActivityAttributes>.activities.first { activity in
            activity.attributes.orderID == orderID
        }
    }

    private static func attributes(for order: AlpacaOrder) -> OrderCancellationActivityAttributes {
        OrderCancellationActivityAttributes(
            orderID: order.id,
            symbol: order.symbol,
            side: order.side?.uppercased() ?? "--",
            quantityText: quantityText(for: order),
            orderType: (order.orderType ?? order.type ?? "--").uppercased()
        )
    }

    private static func content(
        phase: OrderCancellationPhase,
        message: String,
        staleDate: Date? = Date().addingTimeInterval(120)
    ) -> ActivityContent<OrderCancellationActivityAttributes.ContentState> {
        ActivityContent(
            state: OrderCancellationActivityAttributes.ContentState(
                phase: phase,
                message: message,
                updatedAt: Date()
            ),
            staleDate: staleDate
        )
    }

    private static func quantityText(for order: AlpacaOrder) -> String {
        if let quantity = order.quantity {
            return AppFormatter.numberText(quantity)
        }

        if let notional = order.notional {
            return AppFormatter.money(notional)
        }

        return "--"
    }
}
