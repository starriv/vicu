import SwiftUI
import UIKit

struct OrdersView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.locale) private var locale
    @State private var filterState = OrdersFilterCriteria()
    @State private var filterResult = OrdersFilterResult()
    @State private var filterPipeline = OrdersFilterPipeline()
    @State private var presentedSheet: OrdersSheet?
    @State private var pendingCancellationOrder: AlpacaOrder?
    @State private var actionOrderIDs = Set<String>()
    @State private var appliedRequestIDs = Set<UUID>()
    @State private var transientRequestCriteria: OrdersFilterCriteria?

    private let initialRequest: OrdersListRequest?

    init(initialRequest: OrdersListRequest? = nil) {
        self.initialRequest = initialRequest
        _filterState = State(initialValue: initialRequest?.criteria ?? OrdersFilterCriteria())
    }

    private var displayedOrders: [AlpacaOrder] {
        filterResult.orders
    }

    private var ordersFingerprint: String {
        app.portfolio.orders
            .map { "\($0.id)|\($0.summary)|\($0.createdAt ?? "")|\($0.submittedAt ?? "")|\($0.filledAt ?? "")" }
            .joined(separator: "\n")
    }

    private var layoutStyle: BasicLayoutStyle {
        app.portfolio.orders.isEmpty || displayedOrders.isEmpty ? .scroll(spacing: AppTheme.Spacing.group) : .list
    }

    var body: some View {
        BasicLayout(L10n.Orders.title, style: layoutStyle) {
            content
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OrdersFilterButton(criteria: filterState) {
                    presentedSheet = .filters
                }
            }
        }
        .refreshable {
            await app.refresh()
        }
        .sheet(item: $presentedSheet, onDismiss: handleSheetDismissed) { sheet in
            switch sheet {
            case .filters:
                OrdersFilterSheet(
                    criteria: $filterState,
                    orders: app.portfolio.orders,
                    availableSymbols: filterResult.availableSymbols
                )
            case .replacePrice(let draft):
                OrderPriceReplacementSheet(draft: draft)
            case .cancelOrder(let draft):
                OrderCancellationConfirmationSheet(draft: draft) {
                    await cancel(draft.order)
                }
            }
        }
        .task {
            bindFilterPipelineIfNeeded()
            applyOrdersListRequest(initialRequest)
            applyOrdersListRequest(app.pendingOrdersListRequest, consumesAppRequest: true)
        }
        .task(id: app.pendingCancellationOrderID) {
            await presentPendingCancellationIfNeeded()
        }
        .onChange(of: filterState) { _, newValue in
            reconcileTransientFilterTracking(with: newValue)
            filterPipeline.accept(newValue)
        }
        .onChange(of: ordersFingerprint) { _, _ in
            filterPipeline.acceptOrders(app.portfolio.orders)
        }
        .onChange(of: app.pendingOrdersListRequest) { _, request in
            applyOrdersListRequest(request, consumesAppRequest: true)
        }
        .onChange(of: app.selectedTab) { _, selectedTab in
            guard selectedTab != .orders else {
                return
            }

            clearTransientFilterIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.portfolio.orders.isEmpty {
            emptyState(systemImage: AppIcon.More.orders)
        } else if displayedOrders.isEmpty {
            emptyState(systemImage: "line.3.horizontal.decrease.circle")
        } else {
            OrderActionList(
                orders: displayedOrders,
                onCancelRequested: { order in
                    presentCancellationSheet(for: order)
                },
                onReplacePrice: { order, field in
                    presentedSheet = .replacePrice(OrderPriceReplacementDraft(order: order, field: field))
                }
            )
        }
    }

    @discardableResult
    private func cancel(_ order: AlpacaOrder) async -> Bool {
        guard !actionOrderIDs.contains(order.id) else {
            pendingCancellationOrder = nil
            return false
        }

        pendingCancellationOrder = nil
        actionOrderIDs.insert(order.id)
        defer { actionOrderIDs.remove(order.id) }

        do {
            try await app.cancelOrder(order)
            toastCenter.show(L10n.Orders.cancelRequestedToast(symbol: order.symbol, locale: locale))
            return true
        } catch {
            toastCenter.showError(error, locale: locale)
            return false
        }
    }

    private func presentCancellationSheet(for order: AlpacaOrder) {
        pendingCancellationOrder = order
        presentedSheet = .cancelOrder(OrderCancellationDraft(order: order))
    }

    private func handleSheetDismissed() {
        pendingCancellationOrder = nil
    }

    /// A Live Activity can arm the cancel confirmation from the Lock Screen
    /// (`vicu://order/<id>?action=cancel`). The order list is the only place that
    /// owns that sheet, so it resolves the request once the order is available.
    private func presentPendingCancellationIfNeeded() async {
        guard let orderID = app.pendingCancellationOrderID else {
            return
        }

        if let order = app.portfolio.orders.first(where: { $0.id == orderID }) {
            app.pendingCancellationOrderID = nil
            presentCancellationSheet(for: order)
            return
        }

        await app.refresh()

        guard app.pendingCancellationOrderID == orderID else {
            return
        }

        if let order = app.portfolio.orders.first(where: { $0.id == orderID }) {
            app.pendingCancellationOrderID = nil
            presentCancellationSheet(for: order)
        } else {
            app.pendingCancellationOrderID = nil
        }
    }

    private func emptyState(systemImage: String) -> some View {
        AppEmptyStateView(
            title: L10n.Common.noData,
            systemImage: systemImage
        )
    }

    private func bindFilterPipelineIfNeeded() {
        filterPipeline.bind { result in
            filterResult = result
        }
        filterPipeline.acceptOrders(app.portfolio.orders)
        filterPipeline.accept(filterState)
    }

    private func applyOrdersListRequest(
        _ request: OrdersListRequest?,
        consumesAppRequest: Bool = false
    ) {
        guard let request, !appliedRequestIDs.contains(request.id) else {
            return
        }

        appliedRequestIDs.insert(request.id)
        transientRequestCriteria = request.criteria.normalized()
        filterState = request.criteria
        filterPipeline.accept(request.criteria)

        if consumesAppRequest {
            app.consumeOrdersListRequest(request)
        }
    }

    private func reconcileTransientFilterTracking(with criteria: OrdersFilterCriteria) {
        guard let transientRequestCriteria else {
            return
        }

        if criteria.normalized() != transientRequestCriteria {
            self.transientRequestCriteria = nil
        }
    }

    private func clearTransientFilterIfNeeded() {
        guard let transientRequestCriteria else {
            return
        }

        self.transientRequestCriteria = nil
        guard filterState.normalized() == transientRequestCriteria else {
            return
        }

        let defaultCriteria = OrdersFilterCriteria()
        filterState = defaultCriteria
        filterPipeline.accept(defaultCriteria)
    }
}

private enum OrdersSheet: Identifiable {
    case filters
    case replacePrice(OrderPriceReplacementDraft)
    case cancelOrder(OrderCancellationDraft)

    var id: String {
        switch self {
        case .filters:
            "filters"
        case .replacePrice(let draft):
            draft.id
        case .cancelOrder(let draft):
            draft.id
        }
    }
}

private struct OrderCancellationDraft: Identifiable {
    let order: AlpacaOrder

    var id: String { "cancel-\(order.id)" }
}

private struct OrderCancellationConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let draft: OrderCancellationDraft
    let onConfirm: () async -> Bool

    @State private var isSubmitting = false

    private var order: AlpacaOrder { draft.order }

    var body: some View {
        AppActionSheetContainer(
            title: L10n.Orders.cancelSheetTitle(locale: locale),
            isSubmitting: isSubmitting,
            minHeight: 380,
            maxHeight: 660,
            fallbackHeight: 290 + CGFloat(detailItems.count) * 46
        ) {
            VStack(spacing: 0) {
                OrderCancellationHeroHeader(order: order)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                AppSheetInfoCard(items: detailItems)

                AppSheetActionButton(
                    title: L10n.Orders.cancelOrder(locale: locale),
                    submittingTitle: L10n.Orders.cancelHoldSubmitting(locale: locale),
                    tint: AppTheme.ColorToken.negative,
                    isSubmitting: isSubmitting
                ) {
                    await submit()
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
        }
    }

    private var detailItems: [AppSheetInfoItem] {
        var items: [AppSheetInfoItem] = []

        if let limitPrice = OrderDisplay.moneyIfPresent(order.limitPrice) {
            items.append(AppSheetInfoItem(
                title: L10n.Orders.Detail.limitPrice,
                value: limitPrice
            ))
        }

        if let stopPrice = OrderDisplay.moneyIfPresent(order.stopPrice) {
            items.append(AppSheetInfoItem(
                title: L10n.Orders.Detail.stopPrice,
                value: stopPrice
            ))
        }

        if let filled = NumberParser.decimal(from: order.filledQuantity), filled > 0 {
            items.append(AppSheetInfoItem(
                title: L10n.Orders.Detail.filledQuantity,
                value: AppFormatter.numberText(order.filledQuantity)
            ))
        }

        if OrderDisplay.clean(order.timeInForce) != nil {
            items.append(AppSheetInfoItem(
                title: L10n.Orders.Detail.timeInForce,
                value: OrderDisplay.timeInForceText(order.timeInForce, locale: locale)
            ))
        }

        if order.extendedHours == true {
            items.append(AppSheetInfoItem(
                title: L10n.Orders.Detail.extendedHours,
                value: OrderDisplay.sessionText(extendedHours: true, locale: locale)
            ))
        }

        items.append(AppSheetInfoItem(
            title: L10n.Orders.Detail.createdAt,
            value: OrderDisplay.dateTime(order.createdAt, locale: locale)
        ))

        return items
    }

    private func submit() async {
        guard !isSubmitting else {
            return
        }

        isSubmitting = true
        let succeeded = await onConfirm()
        isSubmitting = false

        if succeeded {
            dismiss()
        }
    }
}

private struct OrderCancellationHeroHeader: View {
    @Environment(\.locale) private var locale

    let order: AlpacaOrder

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 6) {
                AppSheetBadgePill(
                    title: sideOrderBadgeText,
                    tint: OrderDisplay.sideTint(order.side)
                )

                AppSheetBadgePill(
                    title: OrderDisplay.statusText(order.status, locale: locale),
                    tint: OrderDisplay.statusTint(order.status),
                    horizontalPadding: 10,
                    backgroundOpacity: 0.14
                )
            }

            Text(heroPrimaryText)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .padding(.top, 14)

            if let heroSubtitleText {
                Text(heroSubtitleText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sideOrderBadgeText: String {
        let side = OrderDisplay.sideText(order.side, locale: locale)
        let type = OrderDisplay.orderTypeText(order.type ?? order.orderType, locale: locale)
        return "\(side) · \(type)"
    }

    private var hasNotional: Bool {
        NumberParser.decimal(from: order.notional) != nil
    }

    private var hasQuantity: Bool {
        NumberParser.decimal(from: order.quantity) != nil
    }

    private var heroPrimaryText: String {
        if hasNotional {
            return AppFormatter.money(order.notional)
        }
        if hasQuantity, order.symbol.count <= 10 {
            return "\(AppFormatter.numberText(order.quantity)) \(order.symbol)"
        }
        return order.symbol
    }

    private var heroSubtitleText: String? {
        if hasNotional {
            return order.symbol
        }
        if hasQuantity, order.symbol.count > 10 {
            return "\(L10n.Orders.quantityPrefix(locale: locale)) \(AppFormatter.numberText(order.quantity))"
        }
        return nil
    }
}

private struct OrderPriceReplacementDraft: Identifiable {
    let order: AlpacaOrder
    let field: AlpacaOrderPriceField

    var id: String { "\(order.id)-\(field.rawValue)" }

    var initialPriceText: String {
        NumberText.trimTrailingZeros(field.currentValue(in: order) ?? "")
    }
}

private struct OrderPriceReplacementSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let draft: OrderPriceReplacementDraft
    @State private var priceText: String
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    init(draft: OrderPriceReplacementDraft) {
        self.draft = draft
        _priceText = State(initialValue: draft.initialPriceText)
    }

    private var order: AlpacaOrder { draft.order }

    var body: some View {
        AppActionSheetContainer(
            title: L10n.Orders.replacePriceTitle,
            isSubmitting: isSubmitting,
            minHeight: 380,
            maxHeight: 560,
            fallbackHeight: 410
        ) {
            VStack(spacing: 0) {
                heroHeader
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                priceInputCard

                AppSheetActionButton(
                    title: L10n.Orders.savePrice(locale: locale),
                    submittingTitle: L10n.Trade.simpleSubmitting(locale: locale),
                    tint: AppTheme.ColorToken.brand,
                    isEnabled: canSubmit,
                    isSubmitting: isSubmitting
                ) {
                    await submit()
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
        }
        .task {
            isFocused = true
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .center, spacing: 0) {
            AppSheetBadgePill(
                title: sideOrderBadgeText,
                tint: OrderDisplay.sideTint(order.side)
            )

            Text(order.symbol)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .padding(.top, 12)

            HStack(spacing: 6) {
                Text(L10n.Orders.currentPrice)
                    .foregroundStyle(.secondary)

                Text(AppFormatter.money(draft.field.currentValue(in: order)))
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var priceInputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.field.title(locale: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if !priceText.isEmpty {
                    Button {
                        priceText = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Common.clear)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("0.00", text: $priceText)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .onChange(of: priceText) { _, value in
                        let normalized = Self.normalizedDecimalInput(value)
                        if normalized != value {
                            priceText = normalized
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appSheetCard(horizontalPadding: 18, verticalPadding: 16)
    }

    private var sideOrderBadgeText: String {
        let side = OrderDisplay.sideText(order.side, locale: locale)
        let type = OrderDisplay.orderTypeText(order.type ?? order.orderType, locale: locale)
        return "\(side) · \(type)"
    }

    private var canSubmit: Bool {
        guard let decimal = NumberParser.decimal(from: NumberText.trimTrailingZeros(priceText)) else {
            return false
        }

        return decimal > 0 && NumberText.trimTrailingZeros(priceText) != draft.initialPriceText
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else {
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await app.replaceOrderPrice(draft.order, field: draft.field, priceText: priceText)
            toastCenter.show(L10n.Orders.priceReplacedToast(symbol: draft.order.symbol, locale: locale))
            dismiss()
        } catch {
            toastCenter.showError(error, locale: locale)
        }
    }

    private static func normalizedDecimalInput(_ value: String) -> String {
        var result = ""
        var hasDecimalSeparator = false

        for character in value {
            if let scalar = character.unicodeScalars.first, scalar.value >= 48, scalar.value <= 57 {
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        guard !result.isEmpty else {
            return ""
        }

        if let separatorIndex = result.firstIndex(of: ".") {
            let integerPart = normalizedInteger(String(result[..<separatorIndex]))
            let fractionPart = String(result[result.index(after: separatorIndex)...].prefix(4))
            return "\(integerPart).\(fractionPart)"
        }

        return normalizedInteger(result)
    }

    private static func normalizedInteger(_ value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

private struct OrderActionList: View {
    let orders: [AlpacaOrder]
    let onCancelRequested: (AlpacaOrder) -> Void
    let onReplacePrice: (AlpacaOrder, AlpacaOrderPriceField) -> Void
    @State private var selectedOrder: SelectedActionOrder?

    var body: some View {
        List {
            Section {
                ForEach(orders) { order in
                    HStack(spacing: 10) {
                        Button {
                            selectedOrder = SelectedActionOrder(order: order)
                        } label: {
                            OrderSummaryRow(order: order)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if order.hasRowActions {
                            OrderRowActionMenu(
                                order: order,
                                onCancelRequested: onCancelRequested,
                                onReplacePrice: onReplacePrice
                            )
                        }
                    }
                    .listRowInsets(rowInsets)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationDestination(item: $selectedOrder) { selectedOrder in
            OrderDetailView(order: selectedOrder.order)
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16)
    }
}

private struct OrderRowActionMenu: View {
    @Environment(\.locale) private var locale

    let order: AlpacaOrder
    let onCancelRequested: (AlpacaOrder) -> Void
    let onReplacePrice: (AlpacaOrder, AlpacaOrderPriceField) -> Void

    private var canReplacePrice: Bool {
        order.supportsPriceReplacement && order.editablePriceField != nil
    }

    var body: some View {
        Menu {
            if order.supportsPriceReplacement, let field = order.editablePriceField {
                Button {
                    onReplacePrice(order, field)
                } label: {
                    Label(L10n.Orders.replacePrice(locale: locale), systemImage: "pencil")
                }
            }

            if order.supportsCancellation {
                if canReplacePrice {
                    Divider()
                }

                Button(role: .destructive) {
                    onCancelRequested(order)
                } label: {
                    Label(L10n.Orders.cancelOrder(locale: locale), systemImage: "xmark.circle")
                }
            }
        } label: {
            OrderRowActionMenuLabel(isEnabled: true)
        }
        .accessibilityLabel(L10n.Orders.actionMenu(locale: locale))
    }
}

private struct OrderRowActionMenuLabel: View {
    let isEnabled: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            icon
                .glassEffect(
                    .regular.tint(Color.white.opacity(isEnabled ? 0.14 : 0.06)).interactive(isEnabled),
                    in: .circle
                )
        } else {
            icon
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color(.separator).opacity(isEnabled ? 0.16 : 0.08))
                }
        }
    }

    private var icon: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.secondary : Color(.tertiaryLabel))
            .frame(width: 36, height: 36)
            .contentShape(Circle())
    }
}

private struct SelectedActionOrder: Identifiable, Hashable {
    let order: AlpacaOrder

    var id: String { order.id }

    static func == (lhs: SelectedActionOrder, rhs: SelectedActionOrder) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension AlpacaOrder {
    var hasRowActions: Bool {
        supportsCancellation || supportsPriceReplacement
    }
}

private struct OrdersFilterButton: View {
    @Environment(\.locale) private var locale

    let criteria: OrdersFilterCriteria
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: criteria.activeFilterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")

                if criteria.activeFilterCount > 0 {
                    Text("\(criteria.activeFilterCount)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                }
            }
        }
        .accessibilityLabel(L10n.Orders.filterTitle(locale: locale))
        .accessibilityValue(L10n.Orders.filterActiveCount(criteria.activeFilterCount, locale: locale))
    }
}

#Preview {
    NavigationStack {
        OrdersView()
            .environment(AppModel())
    }
}
