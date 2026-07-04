import XCTest
@testable import vicu

final class OrderDraftTests: XCTestCase {

    func testValidMarketBuyWithQuantity() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.side = .buy
        draft.orderType = .market
        draft.timeInForce = .day
        draft.quantityText = "10"

        let payload = try draft.requestPayload()

        XCTAssertEqual(payload.symbol, "AAPL")
        XCTAssertEqual(payload.qty, "10")
        XCTAssertNil(payload.notional)
        XCTAssertEqual(payload.side, "buy")
        XCTAssertEqual(payload.type, "market")
        XCTAssertEqual(payload.time_in_force, "day")
        XCTAssertNil(payload.limit_price)
        XCTAssertNil(payload.extended_hours)
    }

    func testValidMarketSellWithNotionalDayOnly() throws {
        var draft = OrderDraft()
        draft.symbol = "MSFT"
        draft.side = .sell
        draft.orderType = .market
        draft.timeInForce = .day
        draft.notionalText = "500.00"

        let payload = try draft.requestPayload()

        XCTAssertEqual(payload.symbol, "MSFT")
        XCTAssertNil(payload.qty)
        XCTAssertEqual(payload.notional, "500")
        XCTAssertEqual(payload.side, "sell")
    }

    func testValidLimitOrderWithQuantityAndLimitPrice() throws {
        var draft = OrderDraft()
        draft.symbol = "GOOG"
        draft.orderType = .limit
        draft.timeInForce = .gtc
        draft.quantityText = "5"
        draft.limitPriceText = "150.50"

        let payload = try draft.requestPayload()

        XCTAssertEqual(payload.type, "limit")
        XCTAssertEqual(payload.qty, "5")
        XCTAssertEqual(payload.limit_price, "150.5")
        XCTAssertEqual(payload.time_in_force, "gtc")
    }

    func testExtendedHoursRequiresLimitOrder() throws {
        var draft = OrderDraft()
        draft.symbol = "TSLA"
        draft.orderType = .market
        draft.timeInForce = .day
        draft.quantityText = "3"
        draft.extendedHours = true

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.extendedHoursRequiresLimitDayOrGTC = error else {
                XCTFail("Expected extendedHoursRequiresLimitDayOrGTC, got \(error)")
                return
            }
        }
    }

    func testExtendedHoursWithLimitDayIsValid() throws {
        var draft = OrderDraft()
        draft.symbol = "TSLA"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "3"
        draft.limitPriceText = "200"
        draft.extendedHours = true

        let payload = try draft.requestPayload()
        XCTAssertEqual(payload.extended_hours, true)
    }

    func testMissingSymbolThrows() {
        var draft = OrderDraft()
        draft.symbol = "   "
        draft.quantityText = "10"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.missingSymbol = error else {
                XCTFail("Expected missingSymbol, got \(error)")
                return
            }
        }
    }

    func testMissingSizeThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = ""
        draft.notionalText = ""

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.missingSize = error else {
                XCTFail("Expected missingSize, got \(error)")
                return
            }
        }
    }

    func testConflictingSizeThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "10"
        draft.notionalText = "500"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.conflictingSize = error else {
                XCTFail("Expected conflictingSize, got \(error)")
                return
            }
        }
    }

    func testZeroQuantityIsTreatedAsMissing() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "0"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.missingSize = error else {
                XCTFail("Expected missingSize for zero quantity, got \(error)")
                return
            }
        }
    }

    func testNegativeQuantityThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "-5"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.invalidQuantity = error else {
                XCTFail("Expected invalidQuantity, got \(error)")
                return
            }
        }
    }

    func testQuantityWithMoreThanSixDecimalPlacesThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "1.1234567"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.invalidQuantityFormat = error else {
                XCTFail("Expected invalidQuantityFormat, got \(error)")
                return
            }
        }
    }

    func testNotionalWithGTCThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .market
        draft.timeInForce = .gtc
        draft.notionalText = "1000"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.notionalRequiresDay = error else {
                XCTFail("Expected notionalRequiresDay, got \(error)")
                return
            }
        }
    }

    func testLimitOrderWithoutLimitPriceThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "10"
        draft.limitPriceText = ""

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.missingLimitPrice = error else {
                XCTFail("Expected missingLimitPrice, got \(error)")
                return
            }
        }
    }

    func testNegativeLimitPriceThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "10"
        draft.limitPriceText = "-50"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.invalidLimitPrice = error else {
                XCTFail("Expected invalidLimitPrice, got \(error)")
                return
            }
        }
    }

    func testLimitPriceOverOneDollarWithMoreThanTwoDecimalsThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "10"
        draft.limitPriceText = "150.123"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.invalidLimitPriceIncrement = error else {
                XCTFail("Expected invalidLimitPriceIncrement, got \(error)")
                return
            }
        }
    }

    func testLimitPriceUnderOneDollarAllowsFourDecimals() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "10"
        draft.limitPriceText = "0.1234"

        let payload = try draft.requestPayload()
        XCTAssertEqual(payload.limit_price, "0.1234")
    }

    func testLimitPriceUnderOneDollarWithFiveDecimalsThrows() {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.orderType = .limit
        draft.timeInForce = .day
        draft.quantityText = "10"
        draft.limitPriceText = "0.12345"

        XCTAssertThrowsError(try draft.requestPayload()) { error in
            guard case OrderDraftError.invalidLimitPriceIncrement = error else {
                XCTFail("Expected invalidLimitPriceIncrement, got \(error)")
                return
            }
        }
    }

    func testSymbolNormalizationUppercasesAndTrims() throws {
        var draft = OrderDraft()
        draft.symbol = "  aapl  "
        draft.quantityText = "10"

        let payload = try draft.requestPayload()
        XCTAssertEqual(payload.symbol, "AAPL")
    }

    func testQuantityTrailingZerosAreTrimmed() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "10.0000"

        let payload = try draft.requestPayload()
        XCTAssertEqual(payload.qty, "10")
    }

    func testClientOrderIDIsPropagatedWhenProvided() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "10"

        let payload = try draft.requestPayload(clientOrderID: "abc-123")
        XCTAssertEqual(payload.client_order_id, "abc-123")
    }

    func testClientOrderIDNilWhenNotProvided() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.quantityText = "10"

        let payload = try draft.requestPayload()
        XCTAssertNil(payload.client_order_id)
    }

    func testPositionIntentIsPropagated() throws {
        var draft = OrderDraft()
        draft.symbol = "AAPL"
        draft.side = .buy
        draft.quantityText = "10"
        draft.positionIntent = .buyToOpen

        let payload = try draft.requestPayload()
        XCTAssertEqual(payload.position_intent, "buy_to_open")
    }

    func testNormalizedSizeTextTrimsTrailingZeros() {
        XCTAssertEqual(OrderDraft.normalizedSizeText("10.000"), "10")
        XCTAssertEqual(OrderDraft.normalizedSizeText("0.0"), "")
        XCTAssertEqual(OrderDraft.normalizedSizeText("1.50"), "1.5")
        XCTAssertEqual(OrderDraft.normalizedSizeText("100"), "100")
    }

    func testOrderTypeRequiresLimitPrice() {
        XCTAssertTrue(OrderType.limit.requiresLimitPrice)
        XCTAssertFalse(OrderType.market.requiresLimitPrice)
    }

    func testOrderPositionIntentSideMapping() {
        XCTAssertEqual(OrderPositionIntent.buyToOpen.side, .buy)
        XCTAssertEqual(OrderPositionIntent.buyToClose.side, .buy)
        XCTAssertEqual(OrderPositionIntent.sellToOpen.side, .sell)
        XCTAssertEqual(OrderPositionIntent.sellToClose.side, .sell)
    }
}
