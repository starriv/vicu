import SwiftUI

struct OrderSummaryListCard: View {
    let orders: [AlpacaOrder]
    var usesLazyStack = false
    var allowsNavigation = true
    @State private var selectedOrder: SelectedOrder?

    var body: some View {
        stack
            .padding(.horizontal, 16)
            .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
            .navigationDestination(item: $selectedOrder) { selectedOrder in
                OrderDetailView(order: selectedOrder.order)
            }
    }

    @ViewBuilder
    private var stack: some View {
        if usesLazyStack {
            LazyVStack(spacing: 0) {
                rows
            }
        } else {
            VStack(spacing: 0) {
                rows
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let lastOrderID = orders.last?.id

        ForEach(orders) { order in
            if allowsNavigation {
                Button {
                    selectedOrder = SelectedOrder(order: order)
                } label: {
                    OrderSummaryRow(order: order, showsDisclosure: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                OrderSummaryRow(order: order)
            }

            if order.id != lastOrderID {
                Divider()
            }
        }
    }
}

private struct SelectedOrder: Identifiable, Hashable {
    let order: AlpacaOrder

    var id: String { order.id }

    static func == (lhs: SelectedOrder, rhs: SelectedOrder) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct OrderSummaryRow: View {
    @Environment(\.locale) private var locale

    let order: AlpacaOrder
    var showsDisclosure = false

    private var sideColor: Color {
        order.side?.lowercased() == "buy" ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    private var statusColor: Color {
        switch order.status?.lowercased() {
        case "filled":
            AppTheme.ColorToken.positive
        case "canceled", "rejected", "expired", "failed":
            AppTheme.ColorToken.negative
        case "accepted", "new", "pending_new", "partially_filled":
            AppTheme.ColorToken.warning
        default:
            .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(order.symbol)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(order.side?.uppercased() ?? AppFormatter.placeholder)
                        .font(AppTypography.badge)
                        .foregroundStyle(sideColor)
                }

                HStack(spacing: 7) {
                    Text(orderDetailText)
                        .font(AppTypography.rowMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if order.extendedHours == true {
                        OrderExtendedHoursTag(title: L10n.Orders.extendedHoursTag(locale: locale))
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                Text(order.status?.uppercased() ?? AppFormatter.placeholder)
                    .font(AppTypography.badge)
                    .foregroundStyle(statusColor)

                Text(submittedTimeText)
                    .font(AppTypography.detail.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
        .accessibilityElement(children: .combine)
    }

    private var orderDetailText: String {
        let size = order.quantity.map { "\(L10n.Orders.quantityPrefix(locale: locale)) \(AppFormatter.numberText($0))" }
            ?? order.notional.map { "\(L10n.Orders.notionalPrefix(locale: locale)) \(AppFormatter.money($0))" }
            ?? AppFormatter.placeholder
        let type = order.type?.uppercased() ?? AppFormatter.placeholder
        return "\(size) · \(type)"
    }

    private var submittedTimeText: String {
        let date = AlpacaDateParser.date(order.submittedAt ?? order.createdAt)
        return AppFormatter.time(date)
    }
}

private struct OrderExtendedHoursTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.ColorToken.warning)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(AppTheme.ColorToken.warning.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(AppTheme.ColorToken.warning.opacity(0.34), lineWidth: 1)
            }
            .fixedSize()
    }
}
