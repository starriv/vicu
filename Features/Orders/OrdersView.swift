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
            OrdersFilterButton(criteria: filterState) {
                presentedSheet = .filters
            }
        } content: {
            content
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
            await OrderActivityManager.updateCancellation(
                for: order,
                phase: .submitting,
                message: L10n.Orders.cancelLiveActivitySubmitting(symbol: order.symbol, locale: locale)
            )
            try await app.cancelOrder(order)
            let message = L10n.Orders.cancelRequestedToast(symbol: order.symbol, locale: locale)
            toastCenter.show(message)
            await OrderActivityManager.endCancellation(
                for: order,
                phase: .submitted,
                message: message
            )
            return true
        } catch {
            toastCenter.show(error.localizedDescription, systemImage: "exclamationmark.circle.fill", tone: .error)
            await OrderActivityManager.endCancellation(
                for: order,
                phase: .failed,
                message: L10n.Orders.cancelLiveActivityFailed(symbol: order.symbol, locale: locale)
            )
            return false
        }
    }

    private func showCancellationPromptActivity(for order: AlpacaOrder) async {
        await OrderActivityManager.startCancellationPrompt(
            for: order,
            message: L10n.Orders.cancelLiveActivityAwaitingConfirmation(symbol: order.symbol, locale: locale)
        )
    }

    private func dismissCancellationPromptActivity(for order: AlpacaOrder) async {
        await OrderActivityManager.dismissCancellationPrompt(
            for: order,
            message: L10n.Orders.cancelLiveActivityDismissed(symbol: order.symbol, locale: locale)
        )
    }

    private func presentCancellationSheet(for order: AlpacaOrder) {
        pendingCancellationOrder = order
        presentedSheet = .cancelOrder(OrderCancellationDraft(order: order))

        Task {
            await showCancellationPromptActivity(for: order)
        }
    }

    private func handleSheetDismissed() {
        guard let order = pendingCancellationOrder else {
            return
        }

        pendingCancellationOrder = nil
        Task {
            await dismissCancellationPromptActivity(for: order)
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
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    orderSnapshot
                    details
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppTheme.ColorToken.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 58, height: 5)
                .padding(.top, 10)

            HStack {
                Button(L10n.Common.cancelText(locale: locale)) {
                    dismiss()
                }
                .font(AppTypography.control)
                .foregroundStyle(.secondary)
                .disabled(isSubmitting)

                Spacer(minLength: 12)

                Text(L10n.Orders.cancelSheetTitle(locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Color.clear
                    .frame(width: 52, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var orderSnapshot: some View {
        OrderCancellationIdentityCard(order: order)
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private var details: some View {
        VStack(spacing: 0) {
            if let limitPrice = OrderDisplay.moneyIfPresent(order.limitPrice) {
                OrderCancellationInfoRow(title: L10n.Orders.Detail.limitPrice, value: limitPrice)
                divider
            }

            if let stopPrice = OrderDisplay.moneyIfPresent(order.stopPrice) {
                OrderCancellationInfoRow(title: L10n.Orders.Detail.stopPrice, value: stopPrice)
                divider
            }

            OrderCancellationInfoRow(
                title: L10n.Orders.Detail.side,
                value: OrderDisplay.sideText(order.side, locale: locale),
                tint: OrderDisplay.sideTint(order.side)
            )
            divider

            OrderCancellationInfoRow(
                title: L10n.Orders.Detail.quantity,
                value: quantityText
            )
            divider

            OrderCancellationInfoRow(
                title: L10n.Orders.Detail.orderType,
                value: OrderDisplay.orderTypeText(order.type ?? order.orderType, locale: locale)
            )
            divider

            OrderCancellationInfoRow(
                title: L10n.Orders.Detail.createdAt,
                value: OrderDisplay.dateTime(order.createdAt, locale: locale)
            )
        }
        .padding(.horizontal, 16)
        .background(AppTheme.ColorToken.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.CornerRadius.groupedSurface, style: .continuous))
    }

    private var footer: some View {
        HoldToConfirmButton(
            title: L10n.Orders.cancelHoldAction(locale: locale),
            progressTitle: L10n.Orders.cancelHoldProgress(locale: locale),
            submittingTitle: L10n.Orders.cancelHoldSubmitting(locale: locale),
            tint: AppTheme.ColorToken.negative,
            isSubmitting: isSubmitting
        ) {
            await submit()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 122)
    }

    private var quantityText: String {
        if let quantity = order.quantity {
            return AppFormatter.numberText(quantity)
        }

        if let notional = order.notional {
            return AppFormatter.money(notional)
        }

        return AppFormatter.placeholder
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

private struct OrderCancellationIdentityCard: View {
    @Environment(\.locale) private var locale

    let order: AlpacaOrder

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(order.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(assetClassText)
                    .font(AppTypography.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(OrderDisplay.statusText(order.status, locale: locale))
                    .font(AppTypography.badge)
                    .foregroundStyle(OrderDisplay.statusTint(order.status))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, AppTheme.Spacing.rowVertical)
        .accessibilityElement(children: .combine)
    }

    private var assetClassText: String {
        OrderDisplay.apiValueIfPresent(order.assetClass) ?? AppFormatter.placeholder
    }
}

private struct OrderCancellationInfoRow: View {
    let title: LocalizedStringKey
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 14)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(L10n.Orders.priceSymbol)
                        Spacer()
                        Text(draft.order.symbol)
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text(L10n.Orders.currentPrice)
                        Spacer()
                        Text(AppFormatter.money(draft.field.currentValue(in: draft.order)))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Text(draft.field.title(locale: locale))

                        TextField(
                            "$0.00",
                            text: $priceText
                        )
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                        .onChange(of: priceText) { _, value in
                            let normalized = Self.normalizedDecimalInput(value)
                            if normalized != value {
                                priceText = normalized
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.Orders.replacePriceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancelText(locale: locale)) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L10n.Orders.savePrice(locale: locale))
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSubmitting)
        .task {
            isFocused = true
        }
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
            toastCenter.show(error.localizedDescription, systemImage: "exclamationmark.circle.fill", tone: .error)
        }
    }

    private static func normalizedDecimalInput(_ value: String) -> String {
        let digitText = value.replacingOccurrences(
            of: #"[^0-9.]"#,
            with: "",
            options: .regularExpression
        )
        var result = ""
        var hasDecimalSeparator = false

        for character in digitText {
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
        if trimmed.isEmpty {
            return value.isEmpty ? "0" : "0"
        }
        return String(trimmed)
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

                        OrderRowActionMenu(
                            order: order,
                            onCancelRequested: onCancelRequested,
                            onReplacePrice: onReplacePrice
                        )
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

    private var hasActions: Bool {
        order.supportsCancellation || canReplacePrice
    }

    var body: some View {
        if hasActions {
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
        } else {
            Color.clear
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
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

private struct OrdersFilterButton: View {
    @Environment(\.locale) private var locale

    let criteria: OrdersFilterCriteria
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Orders.filterTitle(locale: locale))
        .accessibilityValue(L10n.Orders.filterActiveCount(criteria.activeFilterCount, locale: locale))
    }

    @ViewBuilder
    private var label: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.10)).interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(.separator).opacity(0.16))
                }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            filterIcon
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if criteria.activeFilterCount > 0 {
                        filterBadge
                            .offset(x: 3, y: 4)
                    }
                }

            Spacer(minLength: 0)
        }
        .frame(width: criteria.activeFilterCount > 0 ? 60 : 44, height: 44)
        .contentShape(Capsule())
    }

    private var filterIcon: some View {
        Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var filterBadge: some View {
        Text("\(criteria.activeFilterCount)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(AppTheme.ColorToken.brandForeground)
            .frame(minWidth: 16, minHeight: 16)
            .background(AppTheme.ColorToken.brand, in: Circle())
    }
}

#Preview {
    NavigationStack {
        OrdersView()
            .environment(AppModel())
    }
}
