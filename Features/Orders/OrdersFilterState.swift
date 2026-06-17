import Foundation
import RxSwift

struct OrdersFilterResult {
    var orders: [AlpacaOrder] = []
    var availableSymbols: [String] = []
}

struct OrdersFilterCriteria: Equatable, Sendable {
    var status: OrderStatusFilter
    var timeRange: OrderTimeFilter
    var customStartDate: Date
    var customEndDate: Date
    var symbols: Set<String>
    var side: OrderSideFilter

    init(
        status: OrderStatusFilter = .all,
        timeRange: OrderTimeFilter = .lastWeek,
        customStartDate: Date = OrdersFilterCriteria.defaultCustomStartDate(),
        customEndDate: Date = Date(),
        symbols: Set<String> = [],
        side: OrderSideFilter = .all
    ) {
        self.status = status
        self.timeRange = timeRange
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
        self.symbols = symbols
        self.side = side
    }

    var activeFilterCount: Int {
        var count = 0
        if status != .all { count += 1 }
        if timeRange != .lastWeek { count += 1 }
        if !symbols.isEmpty { count += 1 }
        if side != .all { count += 1 }
        return count
    }

    var isDefault: Bool {
        activeFilterCount == 0
    }

    func normalized(calendar: Calendar = .current) -> OrdersFilterCriteria {
        var normalized = self
        normalized.symbols = Set(
            symbols
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )

        let start = calendar.startOfDay(for: customStartDate)
        let end = calendar.startOfDay(for: customEndDate)
        normalized.customStartDate = min(start, end)
        normalized.customEndDate = max(start, end)
        return normalized
    }

    func filteredOrders(from orders: [AlpacaOrder], now: Date = Date(), calendar: Calendar = .current) -> [AlpacaOrder] {
        let criteria = normalized(calendar: calendar)
        return orders.filter { criteria.matches($0, now: now, calendar: calendar) }
    }

    private func matches(_ order: AlpacaOrder, now: Date, calendar: Calendar) -> Bool {
        guard status.matches(order), side.matches(order) else {
            return false
        }

        if !symbols.isEmpty, !symbols.contains(order.symbol.uppercased()) {
            return false
        }

        return matchesDate(orderDate(order), now: now, calendar: calendar)
    }

    private func matchesDate(_ date: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let date else {
            return timeRange == .all
        }

        switch timeRange {
        case .all:
            return true
        case .lastWeek:
            return date >= (calendar.date(byAdding: .day, value: -7, to: now) ?? now) && date <= now
        case .lastMonth:
            return date >= (calendar.date(byAdding: .month, value: -1, to: now) ?? now) && date <= now
        case .lastThreeMonths:
            return date >= (calendar.date(byAdding: .month, value: -3, to: now) ?? now) && date <= now
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
            return date >= start && date < end
        }
    }

    private func orderDate(_ order: AlpacaOrder) -> Date? {
        AlpacaDateParser.date(order.submittedAt ?? order.createdAt ?? order.filledAt)
    }

    private static func defaultCustomStartDate() -> Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }
}

enum OrderStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case open
    case filled
    case canceled
    case other

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:
            "line.3.horizontal.decrease.circle"
        case .open:
            "clock"
        case .filled:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
        case .other:
            "ellipsis.circle"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .all:
            L10n.Orders.filterAll(locale: locale)
        case .open:
            L10n.Orders.filterOpen(locale: locale)
        case .filled:
            L10n.Orders.filterFilled(locale: locale)
        case .canceled:
            L10n.Orders.filterCanceled(locale: locale)
        case .other:
            L10n.Orders.filterOther(locale: locale)
        }
    }

    func matches(_ order: AlpacaOrder) -> Bool {
        let status = order.status?.lowercased() ?? ""

        switch self {
        case .all:
            return true
        case .open:
            return Self.openStatuses.contains(status)
        case .filled:
            return status == "filled"
        case .canceled:
            return Self.canceledStatuses.contains(status)
        case .other:
            return !Self.openStatuses.contains(status)
                && status != "filled"
                && !Self.canceledStatuses.contains(status)
        }
    }

    private static let openStatuses: Set<String> = [
        "accepted",
        "accepted_for_bidding",
        "new",
        "pending_new",
        "partially_filled",
        "pending_cancel",
        "pending_replace",
        "held",
        "stopped",
        "suspended",
        "calculated"
    ]

    private static let canceledStatuses: Set<String> = [
        "canceled",
        "rejected",
        "expired",
        "failed"
    ]
}

enum OrderTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case lastWeek
    case lastMonth
    case lastThreeMonths
    case custom

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .all:
            L10n.Orders.filterTimeAll(locale: locale)
        case .lastWeek:
            L10n.Orders.filterTimeLastWeek(locale: locale)
        case .lastMonth:
            L10n.Orders.filterTimeLastMonth(locale: locale)
        case .lastThreeMonths:
            L10n.Orders.filterTimeLastThreeMonths(locale: locale)
        case .custom:
            L10n.Orders.filterTimeCustom(locale: locale)
        }
    }
}

enum OrderSideFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case buy
    case sell

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .all:
            L10n.Orders.filterSideAll(locale: locale)
        case .buy:
            L10n.Orders.filterSideBuy(locale: locale)
        case .sell:
            L10n.Orders.filterSideSell(locale: locale)
        }
    }

    func matches(_ order: AlpacaOrder) -> Bool {
        switch self {
        case .all:
            true
        case .buy:
            order.side?.lowercased() == "buy"
        case .sell:
            order.side?.lowercased() == "sell"
        }
    }
}

@MainActor
final class OrdersFilterPipeline {
    private let ordersSubject = BehaviorSubject<[AlpacaOrder]>(value: [])
    private let criteriaSubject = BehaviorSubject<OrdersFilterCriteria>(value: OrdersFilterCriteria())
    private let disposeBag = DisposeBag()
    private var isBound = false

    func bind(apply: @escaping @MainActor (OrdersFilterResult) -> Void) {
        guard !isBound else {
            return
        }

        isBound = true
        Observable
            .combineLatest(ordersSubject, criteriaSubject)
            .map { orders, criteria in
                OrdersFilterResult(
                    orders: criteria.filteredOrders(from: orders),
                    availableSymbols: Self.availableSymbols(from: orders)
                )
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { result in
                Task { @MainActor in
                    apply(result)
                }
            })
            .disposed(by: disposeBag)
    }

    func acceptOrders(_ orders: [AlpacaOrder]) {
        ordersSubject.onNext(orders)
    }

    func accept(_ criteria: OrdersFilterCriteria) {
        criteriaSubject.onNext(criteria.normalized())
    }

    private static func availableSymbols(from orders: [AlpacaOrder]) -> [String] {
        Array(Set(orders.map { $0.symbol.uppercased() }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
