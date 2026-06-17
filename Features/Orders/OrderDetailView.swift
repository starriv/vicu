import SwiftUI

struct OrderDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppToastCenter.self) private var toastCenter
    @State private var order: AlpacaOrder
    @State private var loadState: LoadState<AlpacaOrder>
    @State private var isAdditionalExpanded = false

    init(order: AlpacaOrder) {
        _order = State(initialValue: order)
        _loadState = State(initialValue: .loaded(order))
    }

    var body: some View {
        BasicLayout(L10n.Orders.Detail.navigationTitle, style: .scroll(spacing: 26)) {
            VStack(alignment: .leading, spacing: 26) {
                OrderDetailSection(title: L10n.Orders.Detail.title) {
                    OrderDetailRows(fields: primaryFields)
                }

                OrderDisclosureSection(
                    title: L10n.Orders.Detail.additionalDetails,
                    isExpanded: $isAdditionalExpanded
                ) {
                    OrderDetailRows(fields: additionalFields)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 18)
                    .padding(.trailing, AppTheme.Spacing.pageHorizontal)
            }
        }
        .refreshable {
            await loadOrder()
        }
        .task(id: order.id) {
            await loadOrder()
        }
    }

    private var primaryFields: [OrderDetailField] {
        [
            OrderDetailField(
                id: "asset",
                title: L10n.Orders.Detail.asset,
                value: order.symbol
            ),
            OrderDetailField(
                id: "orderType",
                title: L10n.Orders.Detail.orderType,
                value: OrderDisplay.orderTypeText(order.orderType ?? order.type, locale: app.appLanguage.locale),
                badge: OrderDisplay.orderTypeBadge(order.orderType ?? order.type)
            ),
            OrderDetailField(
                id: "side",
                title: L10n.Orders.Detail.side,
                value: OrderDisplay.sideText(order.side, locale: app.appLanguage.locale),
                tint: OrderDisplay.sideTint(order.side)
            ),
            OrderDetailField(
                id: "quantity",
                title: L10n.Orders.Detail.quantity,
                value: AppFormatter.numberText(order.quantity)
            ),
            OrderDetailField(
                id: "filledQuantity",
                title: L10n.Orders.Detail.filledQuantity,
                value: AppFormatter.numberText(order.filledQuantity)
            ),
            OrderDetailField(
                id: "averageFillPrice",
                title: L10n.Orders.Detail.averageFillPrice,
                value: AppFormatter.money(order.filledAveragePrice)
            ),
            OrderDetailField(
                id: "status",
                title: L10n.Orders.Detail.status,
                value: OrderDisplay.statusText(order.status, locale: app.appLanguage.locale),
                tint: OrderDisplay.statusTint(order.status),
                systemImage: OrderDisplay.statusSymbol(order.status)
            ),
            OrderDetailField(
                id: "source",
                title: L10n.Orders.Detail.source,
                value: OrderDisplay.apiValue(order.source)
            ),
            OrderDetailField(
                id: "submittedAt",
                title: L10n.Orders.Detail.submittedAt,
                value: OrderDisplay.dateTime(order.submittedAt, locale: app.appLanguage.locale)
            ),
            OrderDetailField(
                id: "filledAt",
                title: L10n.Orders.Detail.filledAt,
                value: OrderDisplay.dateTime(order.filledAt, locale: app.appLanguage.locale)
            ),
            OrderDetailField(
                id: "expiresAt",
                title: L10n.Orders.Detail.expiresAt,
                value: OrderDisplay.dateTime(order.expiresAt, locale: app.appLanguage.locale)
            )
        ]
    }

    private var additionalFields: [OrderDetailField] {
        [
            identifierField(id: "orderID", title: L10n.Orders.Detail.orderID, value: order.id),
            identifierField(id: "clientOrderID", title: L10n.Orders.Detail.clientOrderID, value: order.clientOrderID),
            identifierField(id: "assetID", title: L10n.Orders.Detail.assetID, value: order.assetID),
            apiField(id: "assetClass", title: L10n.Orders.Detail.assetClass, value: order.assetClass),
            apiField(id: "positionIntent", title: L10n.Orders.Detail.positionIntent, value: order.positionIntent),
            apiField(id: "orderClass", title: L10n.Orders.Detail.orderClass, value: order.orderClass),
            moneyField(id: "notional", title: L10n.Orders.Detail.notional, value: order.notional),
            timeInForceField,
            extendedHoursField,
            moneyField(id: "limitPrice", title: L10n.Orders.Detail.limitPrice, value: order.limitPrice),
            moneyField(id: "stopPrice", title: L10n.Orders.Detail.stopPrice, value: order.stopPrice),
            moneyField(id: "trailPrice", title: L10n.Orders.Detail.trailPrice, value: order.trailPrice),
            percentField(id: "trailPercent", title: L10n.Orders.Detail.trailPercent, value: order.trailPercent),
            moneyField(id: "highWaterMark", title: L10n.Orders.Detail.highWaterMark, value: order.highWaterMark),
            dateTimeField(id: "createdAt", title: L10n.Orders.Detail.createdAt, value: order.createdAt),
            dateTimeField(id: "updatedAt", title: L10n.Orders.Detail.updatedAt, value: order.updatedAt),
            dateTimeField(id: "expiredAt", title: L10n.Orders.Detail.expiredAt, value: order.expiredAt),
            dateTimeField(id: "canceledAt", title: L10n.Orders.Detail.canceledAt, value: order.canceledAt),
            dateTimeField(id: "failedAt", title: L10n.Orders.Detail.failedAt, value: order.failedAt),
            dateTimeField(id: "replacedAt", title: L10n.Orders.Detail.replacedAt, value: order.replacedAt),
            identifierField(id: "replacedBy", title: L10n.Orders.Detail.replacedBy, value: order.replacedBy),
            identifierField(id: "replaces", title: L10n.Orders.Detail.replaces, value: order.replaces),
            textField(id: "subtag", title: L10n.Orders.Detail.subtag, value: order.subtag),
            legsField
        ].compactMap { $0 }
    }

    private var isLoading: Bool {
        if case .loading = loadState {
            return true
        }

        return false
    }

    private var legsField: OrderDetailField? {
        guard let legs = order.legs, !legs.isEmpty else {
            return nil
        }

        return OrderDetailField(id: "legs", title: L10n.Orders.Detail.legs, value: "\(legs.count)")
    }

    private var timeInForceField: OrderDetailField? {
        guard OrderDisplay.clean(order.timeInForce) != nil else {
            return nil
        }

        return OrderDetailField(
            id: "timeInForce",
            title: L10n.Orders.Detail.timeInForce,
            value: OrderDisplay.timeInForceText(order.timeInForce, locale: app.appLanguage.locale)
        )
    }

    private var extendedHoursField: OrderDetailField? {
        guard order.extendedHours != nil else {
            return nil
        }

        return OrderDetailField(
            id: "extendedHours",
            title: L10n.Orders.Detail.extendedHours,
            value: OrderDisplay.boolean(order.extendedHours, locale: app.appLanguage.locale)
        )
    }

    private func identifierField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.clean(value) else {
            return nil
        }

        return OrderDetailField(
            id: id,
            title: title,
            value: value,
            copyValue: value
        )
    }

    private func apiField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.apiValueIfPresent(value) else {
            return nil
        }

        return OrderDetailField(id: id, title: title, value: value)
    }

    private func textField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.clean(value) else {
            return nil
        }

        return OrderDetailField(id: id, title: title, value: value)
    }

    private func moneyField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.moneyIfPresent(value) else {
            return nil
        }

        return OrderDetailField(id: id, title: title, value: value)
    }

    private func percentField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.percentTextIfPresent(value) else {
            return nil
        }

        return OrderDetailField(id: id, title: title, value: value)
    }

    private func dateTimeField(id: String, title: LocalizedStringKey, value: String?) -> OrderDetailField? {
        guard let value = OrderDisplay.dateTimeIfPresent(value, locale: app.appLanguage.locale) else {
            return nil
        }

        return OrderDetailField(id: id, title: title, value: value)
    }

    private func loadOrder() async {
        loadState = .loading

        do {
            let fetchedOrder = try await app.fetchOrderDetail(orderID: order.id)
            try Task.checkCancellation()
            order = fetchedOrder
            loadState = .loaded(fetchedOrder)
        } catch where error.isOrderDetailCancellation {
            return
        } catch {
            loadState = .loaded(order)
            toastCenter.showError(error, locale: app.appLanguage.locale)
        }
    }
}

private struct OrderDetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                Divider()
                content
            }
        }
    }
}

private struct OrderDisclosureSection<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                Divider()
                content
            }
            .padding(.top, 14)
        } label: {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
        .tint(.secondary)
    }
}

private struct OrderDetailRows: View {
    let fields: [OrderDetailField]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                OrderDetailRow(field: field)

                if index != fields.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct OrderDetailRow: View {
    let field: OrderDetailField

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(field.title)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueContent
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueContent: some View {
        if let copyValue = field.copyValue, OrderDisplay.clean(copyValue) != nil {
            AppCopyableIdentifier(
                value: copyValue,
                displayValue: field.value,
                accessibilityLabel: field.title
            )
        } else {
            valueStack
        }
    }

    private var valueStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if let systemImage = field.systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }

                if let badge = field.badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(field.tint ?? AppTheme.ColorToken.brand)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke((field.tint ?? AppTheme.ColorToken.brand).opacity(0.9), lineWidth: 1)
                        }
                }

                Text(field.value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(field.value == AppFormatter.placeholder ? Color.secondary : field.tint ?? Color.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            if let secondaryValue = field.secondaryValue {
                Text(secondaryValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
            }
        }
    }
}

private struct OrderDetailField: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String
    var secondaryValue: String?
    var tint: Color?
    var systemImage: String?
    var badge: String?
    var copyValue: String?
}

enum OrderDisplay {
    static func clean(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    static func apiValue(_ value: String?) -> String {
        guard let value = clean(value) else {
            return AppFormatter.placeholder
        }

        return value
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    static func apiValueIfPresent(_ value: String?) -> String? {
        guard let value = clean(value) else {
            return nil
        }

        return value
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    static func sideText(_ side: String?, locale: Locale) -> String {
        switch side?.lowercased() {
        case "buy":
            L10n.Orders.Detail.sideBuy(locale: locale)
        case "sell":
            L10n.Orders.Detail.sideSell(locale: locale)
        default:
            apiValue(side)
        }
    }

    static func statusText(_ status: String?, locale: Locale) -> String {
        switch status?.lowercased() {
        case "filled":
            L10n.Orders.Detail.statusFilled(locale: locale)
        case "partially_filled":
            L10n.Orders.Detail.statusPartiallyFilled(locale: locale)
        case "accepted", "new", "pending_new":
            L10n.Orders.Detail.statusAccepted(locale: locale)
        case "canceled":
            L10n.Orders.Detail.statusCanceled(locale: locale)
        case "expired":
            L10n.Orders.Detail.statusExpired(locale: locale)
        case "failed", "rejected":
            L10n.Orders.Detail.statusFailed(locale: locale)
        default:
            apiValue(status)
        }
    }

    static func orderTypeText(_ type: String?, locale: Locale) -> String {
        switch type?.lowercased() {
        case "market":
            L10n.Orders.Detail.orderTypeMarket(locale: locale)
        case "limit":
            L10n.Orders.Detail.orderTypeLimit(locale: locale)
        case "stop":
            L10n.Orders.Detail.orderTypeStop(locale: locale)
        case "stop_limit":
            L10n.Orders.Detail.orderTypeStopLimit(locale: locale)
        case "trailing_stop":
            L10n.Orders.Detail.orderTypeTrailingStop(locale: locale)
        default:
            apiValue(type)
        }
    }

    static func orderTypeBadge(_ type: String?) -> String? {
        switch type?.lowercased() {
        case "market":
            "MKT"
        case "limit":
            "LMT"
        case "stop":
            "STP"
        case "stop_limit":
            "STP LMT"
        case "trailing_stop":
            "TRAIL"
        default:
            nil
        }
    }

    static func timeInForceText(_ value: String?, locale: Locale) -> String {
        switch value?.lowercased() {
        case "day":
            L10n.Orders.Detail.timeInForceDay(locale: locale)
        case "gtc":
            L10n.Orders.Detail.timeInForceGTC(locale: locale)
        case "opg":
            L10n.Orders.Detail.timeInForceOPG(locale: locale)
        case "cls":
            L10n.Orders.Detail.timeInForceCLS(locale: locale)
        case "ioc":
            L10n.Orders.Detail.timeInForceIOC(locale: locale)
        case "fok":
            L10n.Orders.Detail.timeInForceFOK(locale: locale)
        default:
            apiValue(value)
        }
    }

    static func sessionText(extendedHours: Bool?, locale: Locale) -> String {
        guard let extendedHours else {
            return AppFormatter.placeholder
        }

        return extendedHours
            ? L10n.Orders.Detail.extendedSession(locale: locale)
            : L10n.Orders.Detail.regularSession(locale: locale)
    }

    static func boolean(_ value: Bool?, locale: Locale) -> String {
        guard let value else {
            return AppFormatter.placeholder
        }

        return value ? L10n.Orders.Detail.yes(locale: locale) : L10n.Orders.Detail.no(locale: locale)
    }

    static func dateTime(_ value: String?, locale: Locale) -> String {
        let lines = dateLines(value, locale: locale)
        guard lines.date != AppFormatter.placeholder else {
            return AppFormatter.placeholder
        }

        return [lines.date, lines.time].compactMap { $0 }.joined(separator: " ")
    }

    static func dateTimeIfPresent(_ value: String?, locale: Locale) -> String? {
        let lines = dateLines(value, locale: locale)
        guard lines.date != AppFormatter.placeholder else {
            return nil
        }

        return [lines.date, lines.time].compactMap { $0 }.joined(separator: " ")
    }

    static func dateLines(_ value: String?, locale: Locale) -> (date: String, time: String?) {
        guard let date = AlpacaDateParser.date(value) else {
            return (AppFormatter.placeholder, nil)
        }

        return (
            fullDateFormatter.string(from: date),
            "\(timeFormatter.string(from: date)) \(L10n.Orders.Detail.timezoneET(locale: locale))"
        )
    }

    static func percentTextIfPresent(_ value: String?) -> String? {
        guard let double = NumberParser.double(from: value) else {
            return nil
        }

        return AppFormatter.percent(double / 100)
    }

    static func moneyIfPresent(_ value: String?) -> String? {
        guard NumberParser.decimal(from: value) != nil else {
            return nil
        }

        return AppFormatter.money(value)
    }

    static func sideTint(_ side: String?) -> Color {
        side?.lowercased() == "buy" ? AppTheme.ColorToken.positive : AppTheme.ColorToken.negative
    }

    static func statusTint(_ status: String?) -> Color {
        switch status?.lowercased() {
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

    static func statusSymbol(_ status: String?) -> String? {
        switch status?.lowercased() {
        case "filled":
            "checkmark.circle.fill"
        case "canceled", "expired":
            "xmark.circle.fill"
        case "failed", "rejected":
            "exclamationmark.circle.fill"
        case "accepted", "new", "pending_new", "partially_filled":
            "clock.badge.checkmark"
        default:
            nil
        }
    }

    private static let easternTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = easternTimeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension Error {
    var isOrderDetailCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let apiError = self as? APIClientError, apiError == .cancelled {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        return false
    }
}

#Preview {
    NavigationStack {
        OrderDetailView(
            order: AlpacaOrder(
                id: "5d2fd07b-6706-4cc2-9f60-10ddd6547fe4",
                clientOrderID: "addea887-5ad4-46b2-ac91-5dd695420055",
                createdAt: "2026-06-13T18:39:59.991835877Z",
                updatedAt: "2026-06-13T18:39:59.993064397Z",
                submittedAt: "2026-06-13T18:39:59.991835877Z",
                filledAt: nil,
                expiredAt: nil,
                canceledAt: nil,
                failedAt: nil,
                replacedAt: nil,
                replacedBy: nil,
                replaces: nil,
                assetID: "2d9e926c-e17c-47c3-ad8c-26c7a594e48f",
                symbol: "QQQ",
                assetClass: "us_equity",
                quantity: "1",
                filledQuantity: "0",
                filledAveragePrice: nil,
                notional: nil,
                orderClass: "",
                orderType: "market",
                side: "buy",
                type: "market",
                positionIntent: "buy_to_open",
                timeInForce: "day",
                limitPrice: nil,
                stopPrice: nil,
                status: "accepted",
                extendedHours: false,
                legs: nil,
                trailPercent: nil,
                trailPrice: nil,
                highWaterMark: nil,
                subtag: nil,
                source: nil,
                expiresAt: "2026-06-15T20:00:00Z"
            )
        )
        .environment(AppModel())
        .environment(AppToastCenter())
    }
}
