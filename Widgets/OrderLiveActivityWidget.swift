import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VicuLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        OrderCancellationLiveActivityWidget()
    }
}

struct OrderCancellationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderCancellationActivityAttributes.self) { context in
            OrderCancellationLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OrderCancellationIslandHeader(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    OrderCancellationIslandStatus(phase: context.state.phase)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(context.attributes.symbol.prefix(4))
                    .font(.caption2.weight(.bold))
            } compactTrailing: {
                Image(systemName: context.state.phase.systemImage)
                    .foregroundStyle(context.state.phase.tint)
            } minimal: {
                Image(systemName: context.state.phase.systemImage)
                    .foregroundStyle(context.state.phase.tint)
            }
            .keylineTint(context.state.phase.tint)
        }
    }
}

private struct OrderCancellationLockScreenView: View {
    let context: ActivityViewContext<OrderCancellationActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.phase.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(context.state.phase.tint)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(context.attributes.symbol)
                        .font(.headline.weight(.bold))

                    Text(context.attributes.side)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(context.state.phase.tint)
                }

                Text(context.state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(context.state.phase.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.phase.tint)

                Text("\(context.attributes.quantityText) \(context.attributes.orderType)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

private struct OrderCancellationIslandHeader: View {
    let context: ActivityViewContext<OrderCancellationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.attributes.symbol)
                .font(.headline.weight(.bold))

            Text("\(context.attributes.quantityText) \(context.attributes.orderType)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct OrderCancellationIslandStatus: View {
    let phase: OrderCancellationPhase

    var body: some View {
        Label(phase.title, systemImage: phase.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(phase.tint)
            .labelStyle(.titleAndIcon)
    }
}

private extension OrderCancellationPhase {
    var title: String {
        switch self {
        case .awaitingConfirmation:
            "Confirm"
        case .submitting:
            "Sending"
        case .submitted:
            "Sent"
        case .failed:
            "Failed"
        case .dismissed:
            "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .awaitingConfirmation:
            "questionmark.circle.fill"
        case .submitting:
            "paperplane.fill"
        case .submitted:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .dismissed:
            "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .awaitingConfirmation:
            .orange
        case .submitting:
            .blue
        case .submitted:
            .green
        case .failed:
            .red
        case .dismissed:
            .secondary
        }
    }
}
