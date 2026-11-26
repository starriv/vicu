import XCTest
@testable import vicu

final class NotificationTests: XCTestCase {
    // MARK: - Policy

    func testPolicySuppressesNoisyIntermediateTradeEvents() {
        let prefs = AppNotificationPreferences.default
        let noisyEvents = [
            "new",
            "pending_new",
            "accepted",
            "accepted_for_bidding",
            "calculated",
            "pending_cancel",
            "pending_replace"
        ]

        for eventName in noisyEvents {
            let event = makeTradeEvent(event: eventName)
            XCTAssertFalse(
                NotificationPolicy.shouldNotify(tradeEvent: event, preferences: prefs),
                "Expected \(eventName) to be suppressed"
            )
        }
    }

    func testPolicyAllowsHighSignalTradeMilestones() {
        let prefs = AppNotificationPreferences.default
        let milestones = [
            "fill",
            "partial_fill",
            "canceled",
            "expired",
            "replaced",
            "rejected",
            "order_cancel_rejected",
            "trade_bust"
        ]

        for eventName in milestones {
            let event = makeTradeEvent(event: eventName)
            XCTAssertTrue(
                NotificationPolicy.shouldNotify(tradeEvent: event, preferences: prefs),
                "Expected \(eventName) to notify"
            )
        }
    }

    func testPolicyDeduplicatesTradeAccountActivityWhenOrderStatusEnabled() {
        let trd = makeActivityEvent(type: "TRD", symbol: "AAPL", netAmount: "-230.98")
        XCTAssertFalse(NotificationPolicy.shouldNotify(activityEvent: trd, preferences: .default))

        var onlyAccount = AppNotificationPreferences.default
        onlyAccount.tradeOrderStatusNotificationsEnabled = false
        XCTAssertTrue(NotificationPolicy.shouldNotify(activityEvent: trd, preferences: onlyAccount))
    }

    func testPolicyPriorityAndThreadGrouping() {
        XCTAssertEqual(NotificationPolicy.priority(forTradeEvent: makeTradeEvent(event: "fill")), .high)
        XCTAssertEqual(NotificationPolicy.priority(forTradeEvent: makeTradeEvent(event: "rejected")), .high)
        XCTAssertEqual(NotificationPolicy.priority(forTradeEvent: makeTradeEvent(event: "partial_fill")), .normal)
        XCTAssertEqual(NotificationPolicy.orderThreadIdentifier(symbol: " aapl "), "vicu.order.AAPL")
    }

    // MARK: - Presentation

    func testTradeEventFillUsesThreeTierHierarchyAndCleanPrice() {
        let event = makeTradeEvent(
            event: "fill",
            symbol: "NVDA",
            side: "sell",
            type: "limit",
            quantity: "25",
            filledQuantity: "25",
            price: "182.3400"
        )

        let payload = NotificationPresentation.tradeEvent(event, locale: Locale(identifier: "en"))

        XCTAssertTrue(payload.title.contains("NVDA"))
        XCTAssertFalse(payload.subtitle.isEmpty)
        XCTAssertTrue(payload.body.contains("$182.34"))
        XCTAssertFalse(payload.body.contains("182.3400"))
        XCTAssertEqual(payload.threadIdentifier, "vicu.order.NVDA")
        XCTAssertEqual(payload.priority, .high)
    }

    func testPartialFillIncludesRatioAndPrice() {
        let event = makeTradeEvent(
            event: "partial_fill",
            symbol: "AAPL",
            side: "buy",
            type: "limit",
            quantity: "10",
            filledQuantity: "6",
            price: "230.98"
        )

        let payload = NotificationPresentation.tradeEvent(event, locale: Locale(identifier: "en"))

        XCTAssertTrue(payload.body.contains("6/10"))
        XCTAssertTrue(payload.body.contains("$230.98"))
    }

    func testSubDollarPriceKeepsFourDecimals() {
        let formatted = NotificationPresentation.formattedPrice("0.4525")
        XCTAssertEqual(formatted, "$0.4525")
    }

    func testAccountActivityDividendPutsAmountInSubtitle() {
        let event = makeActivityEvent(type: "DIV", symbol: "AAPL", netAmount: "12.40")
        let payload = NotificationPresentation.accountActivity(event, locale: Locale(identifier: "en"))

        XCTAssertTrue(payload.title.contains("AAPL"))
        XCTAssertTrue(payload.subtitle.contains("12.40"))
        XCTAssertEqual(payload.threadIdentifier, NotificationPolicy.accountThreadIdentifier)
    }

    // MARK: - Routing

    func testNotificationRouteResolvesOrderDetail() {
        let route = AppNotificationRoute.route(
            categoryIdentifier: NotificationPolicy.Category.orderStatus,
            userInfo: ["order_id": "order-123", "symbol": "AAPL"]
        )
        XCTAssertEqual(route, .orderDetail(orderID: "order-123", symbol: "AAPL"))

        let nonTradeActivity = AppNotificationRoute.route(
            categoryIdentifier: NotificationPolicy.Category.accountActivity,
            userInfo: ["order_id": "order-123", "activity_type": "DIV"]
        )
        XCTAssertNil(nonTradeActivity)
    }

    // MARK: - Fixtures

    private func makeOrder(
        id: String = "order-1",
        symbol: String = "AAPL",
        side: String = "buy",
        type: String = "limit",
        quantity: String = "10",
        filledQuantity: String = "0",
        limitPrice: String? = "230.00",
        status: String = "new"
    ) -> AlpacaOrder {
        AlpacaOrder(
            id: id,
            clientOrderID: nil,
            createdAt: nil,
            updatedAt: nil,
            submittedAt: nil,
            filledAt: nil,
            expiredAt: nil,
            canceledAt: nil,
            failedAt: nil,
            replacedAt: nil,
            replacedBy: nil,
            replaces: nil,
            assetID: nil,
            symbol: symbol,
            assetClass: nil,
            quantity: quantity,
            filledQuantity: filledQuantity,
            filledAveragePrice: nil,
            notional: nil,
            orderClass: nil,
            orderType: type,
            side: side,
            type: type,
            positionIntent: nil,
            timeInForce: nil,
            limitPrice: limitPrice,
            stopPrice: nil,
            status: status,
            extendedHours: nil,
            legs: nil,
            trailPercent: nil,
            trailPrice: nil,
            highWaterMark: nil,
            subtag: nil,
            source: nil,
            expiresAt: nil
        )
    }

    private func makeTradeEvent(
        event: String,
        symbol: String = "AAPL",
        side: String = "buy",
        type: String = "limit",
        quantity: String = "10",
        filledQuantity: String = "10",
        price: String? = "230.98"
    ) -> AlpacaTradeEvent {
        AlpacaTradeEvent(
            eventID: "evt-\(event)",
            event: event,
            order: makeOrder(
                symbol: symbol,
                side: side,
                type: type,
                quantity: quantity,
                filledQuantity: filledQuantity,
                status: event
            ),
            price: price,
            quantity: filledQuantity
        )
    }

    private func makeActivityEvent(
        type: String,
        symbol: String?,
        netAmount: String?
    ) -> AlpacaActivityEvent {
        var details: [String: AlpacaActivityDetailsValue] = [:]
        if let symbol {
            details["symbol"] = .string(symbol)
        }
        return AlpacaActivityEvent(
            accountID: "acct-1",
            at: nil,
            eventID: "act-1",
            activityType: type,
            activitySubtype: nil,
            refID: "ref-1",
            status: "executed",
            executedAt: nil,
            settleDate: nil,
            quantity: nil,
            price: nil,
            netAmount: netAmount,
            currency: "USD",
            swapRate: nil,
            swapFeeBps: nil,
            previousID: nil,
            details: details
        )
    }
}
