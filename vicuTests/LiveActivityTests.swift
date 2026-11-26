import XCTest
@testable import vicu

final class LiveActivityTests: XCTestCase {
    // MARK: - Phase mapping

    func testPhaseMappingCoversAlpacaStatuses() {
        let expectations: [String: OrderActivityPhase] = [
            "new": .submitted,
            "pending_new": .submitted,
            "calculated": .submitted,
            "accepted": .working,
            "held": .working,
            "partially_filled": .partiallyFilled,
            "pending_cancel": .cancelRequested,
            "filled": .filled,
            "canceled": .canceled,
            "expired": .expired,
            "done_for_day": .expired,
            "replaced": .replaced,
            "rejected": .rejected,
            "failed": .rejected
        ]

        for (status, phase) in expectations {
            XCTAssertEqual(LiveActivityPolicy.phase(forStatus: status), phase, "status \(status)")
        }

        XCTAssertEqual(LiveActivityPolicy.phase(forStatus: nil), .submitted)
        XCTAssertEqual(LiveActivityPolicy.phase(forStatus: "something_new"), .working)
    }

    func testTerminalPhases() {
        XCTAssertTrue(OrderActivityPhase.filled.isTerminal)
        XCTAssertTrue(OrderActivityPhase.canceled.isTerminal)
        XCTAssertTrue(OrderActivityPhase.rejected.isTerminal)
        XCTAssertTrue(OrderActivityPhase.expired.isTerminal)
        XCTAssertTrue(OrderActivityPhase.replaced.isTerminal)

        XCTAssertFalse(OrderActivityPhase.submitted.isTerminal)
        XCTAssertFalse(OrderActivityPhase.working.isTerminal)
        XCTAssertFalse(OrderActivityPhase.partiallyFilled.isTerminal)
        XCTAssertFalse(OrderActivityPhase.cancelRequested.isTerminal)
    }

    // MARK: - Representative order

    func testRepresentativeOrderPrefersMostRecentlyChangedWorkingOrder() {
        let now = Date()
        let stale = makeOrder(id: "a", status: "accepted", updatedAt: isoString(now.addingTimeInterval(-600)))
        let fresher = makeOrder(id: "b", status: "partially_filled", updatedAt: isoString(now.addingTimeInterval(-30)))

        let representative = LiveActivityPolicy.representativeOrder(in: [stale, fresher], now: now)

        XCTAssertEqual(representative?.id, "b")
        XCTAssertEqual(LiveActivityPolicy.workingOrderCount(in: [stale, fresher]), 2)
    }

    func testRepresentativeOrderFallsBackToRecentlyFinishedOrder() {
        let now = Date()
        let filled = makeOrder(id: "a", status: "filled", updatedAt: isoString(now.addingTimeInterval(-120)))
        let old = makeOrder(id: "b", status: "filled", updatedAt: isoString(now.addingTimeInterval(-3_600)))

        let representative = LiveActivityPolicy.representativeOrder(in: [filled, old], now: now)

        XCTAssertEqual(representative?.id, "a")
    }

    func testRepresentativeOrderIgnoresHistoryOutsideLingerWindow() {
        let now = Date()
        let old = makeOrder(id: "a", status: "canceled", updatedAt: isoString(now.addingTimeInterval(-3_600)))

        XCTAssertNil(LiveActivityPolicy.representativeOrder(in: [old], now: now))
    }

    // MARK: - Progress

    func testFillProgressClampsAndHandlesMissingData() {
        let partial = makeOrder(id: "a", status: "partially_filled", quantity: "10", filled: "6")
        XCTAssertEqual(LiveActivityPolicy.fillProgress(for: partial), 0.6, accuracy: 0.0001)

        let overfilled = makeOrder(id: "b", status: "filled", quantity: "10", filled: "12")
        XCTAssertEqual(LiveActivityPolicy.fillProgress(for: overfilled), 1, accuracy: 0.0001)

        let notional = makeOrder(id: "c", status: "accepted", quantity: nil, notional: "25.00")
        XCTAssertEqual(LiveActivityPolicy.fillProgress(for: notional), 0, accuracy: 0.0001)
    }

    func testStaleDateDependsOnPhase() {
        let now = Date()
        XCTAssertEqual(
            LiveActivityPolicy.staleDate(for: .working, now: now),
            now.addingTimeInterval(LiveActivityPolicy.workingStaleInterval)
        )
        XCTAssertEqual(
            LiveActivityPolicy.staleDate(for: .filled, now: now),
            now.addingTimeInterval(LiveActivityPolicy.terminalLinger)
        )
        XCTAssertNil(LiveActivityPolicy.dismissalDate(for: .working, now: now))
        XCTAssertNotNil(LiveActivityPolicy.dismissalDate(for: .filled, now: now))
    }

    // MARK: - Deep links

    func testDeepLinkRoundTrip() throws {
        let url = try XCTUnwrap(VicuDeepLink.order(orderID: "order-1", symbol: "AAPL", armsCancellation: true))
        XCTAssertEqual(
            VicuDeepLink.destination(for: url),
            .orderDetail(orderID: "order-1", symbol: "AAPL", armsCancellation: true)
        )

        let plain = try XCTUnwrap(VicuDeepLink.order(orderID: "order-2"))
        XCTAssertEqual(
            VicuDeepLink.destination(for: plain),
            .orderDetail(orderID: "order-2", symbol: nil, armsCancellation: false)
        )

        XCTAssertNil(VicuDeepLink.destination(for: URL(string: "https://example.com/order/1")!))
    }

    // MARK: - Session presentation

    func testSessionContentBuildsProportionalSegments() throws {
        let day = AlpacaCalendarDay(
            date: "2026-11-26",
            coreStart: "2026-11-26T14:30:00Z",
            coreEnd: "2026-11-26T21:00:00Z",
            preStart: "2026-11-26T09:00:00Z",
            preEnd: "2026-11-26T14:30:00Z",
            postStart: "2026-11-26T21:00:00Z",
            postEnd: "2026-11-27T01:00:00Z",
            settlementDate: nil
        )
        let intervals = MarketSessionSchedule.intervals(from: [day])
        let reference = try XCTUnwrap(AlpacaDateParser.date("2026-11-26T15:00:00Z"))
        let active = try XCTUnwrap(MarketSessionSchedule.activeInterval(at: reference, in: intervals))
        XCTAssertEqual(active.session, .regular)

        let progress = MarketSessionSchedule.progress(for: active, in: intervals, at: reference)
        let content = LiveActivityPresentation.sessionContent(
            active: active,
            progress: progress,
            account: nil,
            workingOrders: 3,
            marketName: "NYSE",
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(content.segments.count, progress.intervals.count)
        XCTAssertEqual(content.segments.filter(\.isActive).count, 1)
        XCTAssertTrue(content.segments.allSatisfy { $0.weight > 0 })
        XCTAssertEqual(content.cycleStart, progress.intervals.first?.start)
        XCTAssertEqual(content.cycleEnd, progress.intervals.last?.end)
        XCTAssertEqual(content.sessionStart, active.start)
        XCTAssertEqual(content.transitionAt, active.end)
        XCTAssertNil(content.summaryText)
        XCTAssertFalse(content.trailingText?.isEmpty ?? true)
    }

    // MARK: - Fixtures

    private func makeOrder(
        id: String,
        status: String?,
        quantity: String? = "10",
        filled: String? = nil,
        notional: String? = nil,
        updatedAt: String? = nil
    ) -> AlpacaOrder {
        AlpacaOrder(
            id: id,
            clientOrderID: nil,
            createdAt: nil,
            updatedAt: updatedAt,
            submittedAt: nil,
            filledAt: nil,
            expiredAt: nil,
            canceledAt: nil,
            failedAt: nil,
            replacedAt: nil,
            replacedBy: nil,
            replaces: nil,
            assetID: nil,
            symbol: "AAPL",
            assetClass: nil,
            quantity: quantity,
            filledQuantity: filled,
            filledAveragePrice: nil,
            notional: notional,
            orderClass: nil,
            orderType: nil,
            side: "buy",
            type: "limit",
            positionIntent: nil,
            timeInForce: nil,
            limitPrice: nil,
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

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
