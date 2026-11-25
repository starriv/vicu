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

@MainActor
final class TradeStoreEstimationTests: XCTestCase {

    private func makeAccount(
        buyingPower: String = "1000.00",
        nonMarginableBuyingPower: String? = "500.00",
        shortingEnabled: Bool = true
    ) -> AlpacaAccount {
        AlpacaAccount(
            id: "acct-1",
            accountNumber: "123456",
            createdAt: nil,
            status: "ACTIVE",
            currency: "USD",
            buyingPower: buyingPower,
            regtBuyingPower: nil,
            daytradingBuyingPower: nil,
            effectiveBuyingPower: nil,
            nonMarginableBuyingPower: nonMarginableBuyingPower,
            optionsBuyingPower: nil,
            bodDtbp: nil,
            cash: buyingPower,
            accruedFees: nil,
            portfolioValue: buyingPower,
            patternDayTrader: false,
            tradingBlocked: false,
            transfersBlocked: false,
            accountBlocked: false,
            tradeSuspendedByUser: false,
            multiplier: "2",
            shortingEnabled: shortingEnabled,
            equity: buyingPower,
            lastEquity: buyingPower,
            longMarketValue: nil,
            shortMarketValue: nil,
            positionMarketValue: nil,
            initialMargin: nil,
            maintenanceMargin: nil,
            lastMaintenanceMargin: nil,
            sma: nil,
            daytradeCount: 0,
            balanceAsOf: nil,
            cryptoStatus: nil,
            optionsApprovedLevel: nil,
            optionsTradingLevel: nil,
            cryptoTier: nil,
            intradayAdjustments: nil,
            pendingRegTAFFees: nil
        )
    }

    private func makeAsset(
        symbol: String = "AAPL",
        fractionable: Bool = true,
        marginable: Bool = true,
        shortable: Bool = true
    ) -> AlpacaAsset {
        AlpacaAsset(
            id: "asset-1",
            assetClass: "us_equity",
            exchange: "NASDAQ",
            symbol: symbol,
            name: "\(symbol) Inc.",
            status: "active",
            tradable: true,
            marginable: marginable,
            maintenanceMarginRequirement: nil,
            marginRequirementLong: nil,
            marginRequirementShort: nil,
            shortable: shortable,
            easyToBorrow: true,
            borrowStatus: nil,
            fractionable: fractionable,
            attributes: nil
        )
    }

    private func makePosition(
        symbol: String = "AAPL",
        quantity: String,
        quantityAvailable: String? = nil,
        marketValue: String = "1500.00",
        currentPrice: String? = "150.00"
    ) -> AlpacaPosition {
        AlpacaPosition(
            assetID: "asset-1",
            symbol: symbol,
            exchange: "NASDAQ",
            assetClass: "us_equity",
            assetMarginable: true,
            quantity: quantity,
            quantityAvailable: quantityAvailable,
            averageEntryPrice: "140.00",
            side: "long",
            marketValue: marketValue,
            costBasis: "1400.00",
            unrealizedPL: "100.00",
            unrealizedPLPC: "0.07",
            unrealizedIntradayPL: "10.00",
            unrealizedIntradayPLPC: "0.01",
            currentPrice: currentPrice,
            lastDayPrice: "149.00",
            changeToday: "0.01"
        )
    }

    private func makeQuote(bid: Double?, ask: Double?) -> AlpacaRealtimeQuote {
        AlpacaRealtimeQuote(
            symbol: "AAPL",
            askExchange: "V",
            askPrice: ask,
            askSize: 100,
            bidExchange: "V",
            bidPrice: bid,
            bidSize: 100,
            conditions: nil,
            timestamp: nil,
            tape: "C"
        )
    }

    private func makeTrade(price: Double) -> AlpacaRealtimeTrade {
        AlpacaRealtimeTrade(
            symbol: "AAPL",
            price: price,
            size: 10,
            exchange: "V",
            timestamp: nil,
            conditions: nil,
            tape: "C"
        )
    }

    func testZeroAndStubAskQuoteFallsBackToLastTradePrice() {
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "1000.00"),
            asset: makeAsset(),
            latestQuote: makeQuote(bid: 0.0, ask: 0.0),
            latestTrade: makeTrade(price: 225.40)
        )
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, sizingMode: .notional, seed: seed)

        XCTAssertEqual(store.estimatedExecutionPrice, Decimal(string: "225.4"))
        XCTAssertEqual(store.estimatedExecutionPriceSource, .last)

        // Extreme IEX stub ask quote ($199,999.99) should also fall back to last trade
        store.realtimeQuote = makeQuote(bid: 0.01, ask: 199999.99)
        XCTAssertEqual(store.estimatedExecutionPrice, Decimal(string: "225.4"))
        XCTAssertEqual(store.estimatedExecutionPriceSource, .last)
    }

    func testOptionContractPastePreservesLastValidQuantity() throws {
        let store = OptionTradeStore(contractSymbol: "NVDA261218C00140000", initialIntent: .buyToOpen, initialSnapshotModel: nil)
        store.setLimitPriceText("4")
        store.setContractsText("1.5")
        XCTAssertThrowsError(try store.draft.requestPayload())
        store.setContractsText("2")
        for invalid in ["1.5", "-3", "2e4", "1,000", "12345678901234567890"] {
            store.setContractsText(invalid)
            XCTAssertEqual(try store.draft.requestPayload().qty, "2")
        }
        store.setContractsText("")
        XCTAssertThrowsError(try store.draft.requestPayload())
    }

    func testPayoffPreviewIsOnlyShownForOpeningIntents() {
        for intent in [OrderPositionIntent.buyToOpen, .sellToOpen, .buyToClose, .sellToClose] {
            let store = OptionTradeStore(contractSymbol: "NVDA261218C00140000", initialIntent: intent, initialSnapshotModel: nil)
            store.setLimitPriceText("4")
            XCTAssertEqual(store.payoffSpec != nil, intent == .buyToOpen || intent == .sellToOpen)
        }
    }

    func testExtendedHoursPreserveFractionalDayLimitQuantity() throws {
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .limit,
                               seed: TradeSeedContext(account: makeAccount(), asset: makeAsset()))
        store.setLimitPriceText("100")
        store.setLimitQuantityText("1.9")
        store.setExtendedHours(true)
        XCTAssertEqual(try store.draft.requestPayload().qty, "1.9")
        store.setLimitQuantityText("0.25")
        XCTAssertEqual(try store.draft.requestPayload().qty, "0.25")
    }

    func testCoherentQuoteAfterOpeningGapSizesMarketBuyAtAsk() throws {
        let seed = TradeSeedContext(account: makeAccount(buyingPower: "1000"), asset: makeAsset(),
                                    latestQuote: makeQuote(bid: 119.99, ask: 120.01), latestTrade: makeTrade(price: 100))
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, seed: seed)
        store.fillQuantity(percent: 1)
        XCTAssertEqual(store.estimatedExecutionPrice, Decimal(string: "120.01"))
        let quantity = try XCTUnwrap(Decimal(string: store.draft.quantityText))
        XCTAssertGreaterThan(quantity, 8)
        XCTAssertLessThanOrEqual(quantity * Decimal(string: "120.01")!, 1000)
        XCTAssertTrue(store.validation.canSubmit)
    }

    func testExactDecimalConversionAvoidsBinaryDoubleDrift() {
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "10000.00"),
            asset: makeAsset(),
            latestQuote: makeQuote(bid: 729.73, ask: 729.78),
            latestTrade: makeTrade(price: 729.75)
        )
        let store = TradeStore(symbol: "QQQ", side: .buy, orderType: .market, sizingMode: .shares, seed: seed)

        XCTAssertEqual(store.askPrice, Decimal(string: "729.78"))
        XCTAssertEqual(store.bidPrice, Decimal(string: "729.73"))
        XCTAssertEqual(store.estimatedExecutionPrice, Decimal(string: "729.78"))
        XCTAssertEqual(store.estimatedExecutionPriceSource, .ask)
    }

    func testQuickFillMaxInSharesFloorsDownAndNeverExceedsBuyingPower() {
        // 100 / 1.50 = 66.6666666... -> .plain would round UP to 66.666667 (100.0000005 > 100!)
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "100.00"),
            asset: makeAsset(fractionable: true),
            latestQuote: makeQuote(bid: 1.49, ask: 1.50),
            latestTrade: makeTrade(price: 1.50)
        )
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, sizingMode: .shares, seed: seed)

        store.fillQuickAmount(percent: Decimal(1))

        XCTAssertEqual(store.draft.quantityText, "66.666666")
        XCTAssertTrue(store.validation.canSubmit, "Max quick-fill must never trigger buyExceedsBuyingPower: \(store.validation.errors)")
        XCTAssertLessThanOrEqual(store.estimatedNotional ?? 0, Decimal(100))
    }

    func testNonFractionableAssetQuickFillFloorsToWholeShares() {
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "100.00"),
            asset: makeAsset(fractionable: false),
            latestQuote: makeQuote(bid: 14.95, ask: 15.00),
            latestTrade: makeTrade(price: 15.00)
        )
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, sizingMode: .shares, seed: seed)

        store.fillQuickAmount(percent: Decimal(1))

        XCTAssertEqual(store.draft.quantityText, "6")
        XCTAssertEqual(store.estimatedNotional, Decimal(90))
        XCTAssertTrue(store.validation.canSubmit, "Whole-share floor should pass validation: \(store.validation.errors)")
    }

    func testSellUsesAvailableQuantityWhenSharesReservedByOpenOrders() {
        let position = makePosition(
            quantity: "273.721435",
            quantityAvailable: "133.860717",
            marketValue: "200000.00",
            currentPrice: "730.00"
        )
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "50000.00"),
            asset: makeAsset(fractionable: true),
            position: position,
            latestQuote: makeQuote(bid: 730.00, ask: 730.10),
            latestTrade: makeTrade(price: 730.05)
        )
        let store = TradeStore(symbol: "QQQ", side: .sell, orderType: .market, sizingMode: .shares, seed: seed)

        XCTAssertEqual(store.availableSellQuantity, Decimal(string: "133.860717"))

        store.fillQuickAmount(percent: Decimal(1))
        XCTAssertEqual(store.draft.quantityText, "133.860717")
        XCTAssertTrue(store.validation.canSubmit, "Max sell of available shares should be valid: \(store.validation.errors)")

        // Attempting to sell more than available (even if <= total position) must fail
        store.setSimpleInputText("200")
        XCTAssertFalse(store.validation.canSubmit)
        XCTAssertEqual(store.validation.firstIssue?.kind, .sellExceedsPosition)
    }

    func testShortSellQuickFillRespectsThreePercentBufferAndWholeShares() {
        // Buying power $1000, ask $100 -> buffered short price $103 -> floor(1000/103) = 9 shares
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "1000.00", shortingEnabled: true),
            asset: makeAsset(fractionable: true, shortable: true),
            position: nil,
            latestQuote: makeQuote(bid: 99.90, ask: 100.00),
            latestTrade: makeTrade(price: 100.00)
        )
        let store = TradeStore(symbol: "AAPL", side: .sell, orderType: .market, sizingMode: .shares, seed: seed)

        store.fillQuickAmount(percent: Decimal(1))

        XCTAssertEqual(store.draft.quantityText, "9")
        XCTAssertTrue(store.validation.canSubmit, "Short sell Max should respect 3% buffer and integer shares: \(store.validation.errors)")
    }

    func testBidirectionalNotionalAndSharesEstimationAndToggle() {
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "5000.00"),
            asset: makeAsset(fractionable: true),
            latestQuote: makeQuote(bid: 199.90, ask: 200.00),
            latestTrade: makeTrade(price: 199.95)
        )
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, sizingMode: .notional, seed: seed)

        store.setSimpleInputText("500")
        XCTAssertEqual(store.estimatedNotional, Decimal(500))
        XCTAssertEqual(store.estimatedQuantity, Decimal(string: "2.5"))

        store.toggleSizingMode()
        XCTAssertEqual(store.sizingMode, .shares)
        XCTAssertEqual(store.draft.quantityText, "2.5")
        XCTAssertEqual(store.draft.notionalText, "")
        XCTAssertEqual(store.estimatedNotional, Decimal(500))

        store.toggleSizingMode()
        XCTAssertEqual(store.sizingMode, .notional)
        XCTAssertEqual(store.draft.notionalText, "500")
        XCTAssertEqual(store.draft.quantityText, "")
    }

    func testTradeInputFormatKeyApplicationAndDisplayGrouping() {
        var text = ""
        text = TradeInputFormat.applyKey(.digit("1"), to: text, maxFractionDigits: 2)
        text = TradeInputFormat.applyKey(.digit("2"), to: text, maxFractionDigits: 2)
        text = TradeInputFormat.applyKey(.digit("3"), to: text, maxFractionDigits: 2)
        text = TradeInputFormat.applyKey(.digit("4"), to: text, maxFractionDigits: 2)
        XCTAssertEqual(text, "1234")
        XCTAssertEqual(TradeInputFormat.formattedDisplay(text), "1,234")

        text = TradeInputFormat.applyKey(.decimal, to: text, maxFractionDigits: 2)
        XCTAssertEqual(text, "1234.")
        XCTAssertEqual(TradeInputFormat.formattedDisplay(text), "1,234.")

        // Second decimal is ignored
        XCTAssertEqual(TradeInputFormat.applyKey(.decimal, to: text, maxFractionDigits: 2), "1234.")

        text = TradeInputFormat.applyKey(.digit("5"), to: text, maxFractionDigits: 2)
        text = TradeInputFormat.applyKey(.digit("6"), to: text, maxFractionDigits: 2)
        // Third decimal digit is ignored when maxFractionDigits == 2
        text = TradeInputFormat.applyKey(.digit("7"), to: text, maxFractionDigits: 2)
        XCTAssertEqual(text, "1234.56")
        XCTAssertEqual(TradeInputFormat.formattedDisplay(text), "1,234.56")

        // Decimal blocked when maxFractionDigits == 0 (non-fractionable shares)
        XCTAssertEqual(TradeInputFormat.applyKey(.decimal, to: "5", maxFractionDigits: 0), "5")

        // Leading decimal becomes "0."
        XCTAssertEqual(TradeInputFormat.applyKey(.decimal, to: "", maxFractionDigits: 2), "0.")

        // Clear resets to empty
        XCTAssertEqual(TradeInputFormat.applyKey(.clear, to: text, maxFractionDigits: 2), "")
        XCTAssertEqual(TradeInputFormat.formattedDisplay(""), "0")

        // Enforces realistic max integer & total digit limits to prevent layout overflow
        let maxedNotional = TradeInputFormat.applyKey(
            .digit("9"),
            to: "99999999",
            maxIntegerDigits: TradeInputLimit.notionalMaxIntegerDigits,
            maxFractionDigits: 2,
            maxTotalDigits: TradeInputLimit.notionalMaxTotalDigits
        )
        XCTAssertEqual(maxedNotional, "99999999")

        let maxedPrice = TradeInputFormat.applyKey(
            .digit("5"),
            to: "999999",
            maxIntegerDigits: TradeInputLimit.priceMaxIntegerDigits,
            maxFractionDigits: 2,
            maxTotalDigits: TradeInputLimit.priceMaxTotalDigits
        )
        XCTAssertEqual(maxedPrice, "999999")

        let maxedShares = TradeInputFormat.applyKey(
            .digit("9"),
            to: "1234.567891",
            maxIntegerDigits: TradeInputLimit.sharesMaxIntegerDigits,
            maxFractionDigits: 6,
            maxTotalDigits: TradeInputLimit.sharesMaxTotalDigits
        )
        XCTAssertEqual(maxedShares, "1234.567891")
    }

    func testAssetDetailTradeBarScrollVisibilityBehavior() {
        let tracker = AssetDetailTradeBarScrollTracker()
        XCTAssertTrue(tracker.isVisible)

        // Establish initial offset at top
        XCTAssertNil(tracker.update(offsetY: 0, maxOffsetY: 600, isUserDriven: true))
        XCTAssertTrue(tracker.isVisible)

        // Small downward jitter below threshold stays visible
        XCTAssertNil(tracker.update(offsetY: 18, maxOffsetY: 600, isUserDriven: true))
        XCTAssertTrue(tracker.isVisible)

        // Scrolling down past threshold hides the trade bar
        XCTAssertEqual(tracker.update(offsetY: 50, maxOffsetY: 600, isUserDriven: true), false)
        XCTAssertFalse(tracker.isVisible)

        // Bottom overscroll bounce must NOT falsely reveal the bar
        XCTAssertNil(tracker.update(offsetY: 600, maxOffsetY: 600, isUserDriven: true))
        XCTAssertNil(tracker.update(offsetY: 640, maxOffsetY: 600, isUserDriven: true))
        XCTAssertNil(tracker.update(offsetY: 605, maxOffsetY: 600, isUserDriven: true))
        XCTAssertFalse(tracker.isVisible)

        // Deliberate upward scroll reveals the bar
        XCTAssertEqual(tracker.update(offsetY: 580, maxOffsetY: 600, isUserDriven: true), true)
        XCTAssertTrue(tracker.isVisible)

        // Pull-to-refresh negative offset keeps the bar visible
        XCTAssertNil(tracker.update(offsetY: -45, maxOffsetY: 600, isUserDriven: true))
        XCTAssertTrue(tracker.isVisible)

        // Hide again then return to top reveals even if not user-driven (e.g. status-bar tap to top)
        XCTAssertNil(tracker.update(offsetY: 20, maxOffsetY: 600, isUserDriven: true))
        XCTAssertEqual(tracker.update(offsetY: 80, maxOffsetY: 600, isUserDriven: true), false)
        XCTAssertEqual(tracker.update(offsetY: 0, maxOffsetY: 600, isUserDriven: false), true)
        XCTAssertTrue(tracker.isVisible)
    }

    func testLimitOrderPriceSteppingAndTimeInForceRules() {
        let seed = TradeSeedContext(
            account: makeAccount(buyingPower: "1000.00"),
            asset: makeAsset(fractionable: true),
            latestQuote: makeQuote(bid: 199.98, ask: 200.02),
            latestTrade: makeTrade(price: 200.00)
        )
        let store = TradeStore(symbol: "AAPL", side: .buy, orderType: .market, sizingMode: .notional, seed: seed)

        // Switching to limit pre-fills midpoint ($200) and moves to shares mode
        store.prepareLimitOrder()
        XCTAssertEqual(store.draft.orderType, .limit)
        XCTAssertEqual(store.sizingMode, .shares)
        XCTAssertEqual(store.draft.limitPriceText, "200")
        XCTAssertEqual(store.limitPriceDeltaFraction ?? 1, 0, accuracy: 0.0001)

        // Stepping limit price by +1 / -1 uses $0.01 ticks above $1
        store.stepLimitPrice(steps: 1)
        XCTAssertEqual(store.draft.limitPriceText, "200.01")
        store.stepLimitPrice(steps: -2)
        XCTAssertEqual(store.draft.limitPriceText, "199.99")

        // Sub-dollar stepping uses $0.0001 ticks
        store.setLimitPriceText("0.50")
        store.stepLimitPrice(steps: 1)
        XCTAssertEqual(store.draft.limitPriceText, "0.5001")

        // Switching to GTC floors fractional quantity to whole shares and keeps order valid
        store.setLimitPriceText("200")
        store.setLimitQuantityText("2.75")
        store.setTimeInForce(.gtc)
        XCTAssertEqual(store.draft.timeInForce, .gtc)
        XCTAssertEqual(store.draft.quantityText, "2")
        XCTAssertEqual(store.maxShareInputScale, 0)
        XCTAssertTrue(store.validation.canSubmit, "GTC whole-share limit order must be valid: \(store.validation.errors)")

        // Extended hours enabled on limit order stays valid
        store.setExtendedHours(true)
        XCTAssertTrue(store.draft.extendedHours)
        XCTAssertTrue(store.validation.canSubmit, "Extended hours limit order must be valid: \(store.validation.errors)")

        // Switching back to market resets extended hours and limit price
        store.prepareMarketOrder()
        XCTAssertEqual(store.draft.orderType, .market)
        XCTAssertFalse(store.draft.extendedHours)
        XCTAssertEqual(store.draft.limitPriceText, "")
    }

    func testOptionTradeStorePrecisionSteppingAndContractQuickFill() throws {
        let descriptor = OptionContractDescriptor(symbol: "NVDA261218C00140000")
        let payloadData = Data(#"{"latestQuote":{"bp":4.20,"ap":4.30,"bs":15,"as":20}}"#.utf8)
        let payload = try JSONDecoder().decode(AlpacaOptionSnapshotPayload.self, from: payloadData)
        let snapshot = AlpacaOptionSnapshot(contractSymbol: descriptor.symbol, payload: payload)
        let snapshotModel = OptionDetailSnapshotModel(descriptor: descriptor, snapshot: snapshot)
        let store = OptionTradeStore(
            contractSymbol: "NVDA261218C00140000",
            initialIntent: .buyToOpen,
            initialSnapshotModel: snapshotModel
        )

        let account = AlpacaAccount(
            id: "acct-opt",
            accountNumber: "123456",
            createdAt: nil,
            status: "ACTIVE",
            currency: "USD",
            buyingPower: "1500.00",
            regtBuyingPower: nil,
            daytradingBuyingPower: nil,
            effectiveBuyingPower: nil,
            nonMarginableBuyingPower: nil,
            optionsBuyingPower: "1500.00",
            bodDtbp: nil,
            cash: "1500.00",
            accruedFees: nil,
            portfolioValue: "1500.00",
            patternDayTrader: false,
            tradingBlocked: false,
            transfersBlocked: false,
            accountBlocked: false,
            tradeSuspendedByUser: false,
            multiplier: "2",
            shortingEnabled: true,
            equity: "1500.00",
            lastEquity: "1500.00",
            longMarketValue: nil,
            shortMarketValue: nil,
            positionMarketValue: nil,
            initialMargin: nil,
            maintenanceMargin: nil,
            lastMaintenanceMargin: nil,
            sma: nil,
            daytradeCount: 0,
            balanceAsOf: nil,
            cryptoStatus: nil,
            optionsApprovedLevel: 2,
            optionsTradingLevel: 2,
            cryptoTier: nil,
            intradayAdjustments: nil,
            pendingRegTAFFees: nil
        )
        store.configureForTesting(
            account: account,
            position: makePosition(symbol: "NVDA261218C00140000", quantity: "5", quantityAvailable: "4"),
            underlyingPosition: makePosition(symbol: "NVDA", quantity: "250", quantityAvailable: "250")
        )

        // Default limit price is exact midpoint $4.25 (zero Double drift)
        XCTAssertEqual(store.midPrice, Decimal(string: "4.25"))
        XCTAssertEqual(store.draft.limitPriceText, "4.25")
        XCTAssertEqual(store.limitPriceDeltaFraction ?? 1, 0, accuracy: 0.0001)

        // Stepping limit price uses $0.01 ticks
        store.stepLimitPrice(steps: 5)
        XCTAssertEqual(store.draft.limitPriceText, "4.3")
        XCTAssertGreaterThan(store.limitPriceDeltaFraction ?? 0, 0)

        // Buy to Open Max: floor(1500 / (4.30 * 100)) = 3 contracts ($1,290 <= $1,500)
        XCTAssertEqual(store.maxContractsAvailable, 3)
        store.fillContracts(percent: Decimal(1))
        XCTAssertEqual(store.draft.quantityText, "3")
        XCTAssertEqual(store.estimatedNotional, Decimal(1290))
        XCTAssertTrue(store.validation.canSubmit, "Buy to Open Max should pass: \(store.validation.errors)")

        // Sell to Close Max uses available long contracts (4, not 5)
        store.intent = .sellToClose
        XCTAssertEqual(store.maxContractsAvailable, 4)
        store.fillContracts(percent: Decimal(1))
        XCTAssertEqual(store.draft.quantityText, "4")
        XCTAssertTrue(store.validation.canSubmit, "Sell to Close Max should pass: \(store.validation.errors)")

        // Sell to Open (Covered Call): 250 shares -> floor(250 / 100) = 2 contracts
        store.intent = .sellToOpen
        XCTAssertEqual(store.maxContractsAvailable, 2)
        store.fillContracts(percent: Decimal(1))
        XCTAssertEqual(store.draft.quantityText, "2")
        XCTAssertTrue(store.validation.canSubmit, "Covered Call Max should pass: \(store.validation.errors)")
    }

    func testOptionPayoffEngineStandardUSOptionCurves() {
        // Long Call: K = 200, P = 10, 2 contracts -> BE = 210, Max Loss = -2000, Max Profit = Unlimited
        let longCall = OptionPayoffSpec(
            contractType: .call,
            side: .long,
            strike: 200,
            premium: 10,
            contracts: 2,
            underlyingPrice: 205
        )
        let lcMetrics = OptionPayoffEngine.computeMetrics(for: longCall)
        XCTAssertEqual(lcMetrics.breakeven ?? 0, 210, accuracy: 0.0001)
        XCTAssertEqual(lcMetrics.maxProfit, .unlimited)
        XCTAssertEqual(lcMetrics.maxLoss, .finite(-2000))
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: longCall, at: 180), -2000, accuracy: 0.001)
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: longCall, at: 210), 0, accuracy: 0.001)
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: longCall, at: 225), 3000, accuracy: 0.001)

        // Short Put (CSP): K = 100, P = 4, 1 contract -> BE = 96, Max Profit = +400, Max Loss = -9600
        let shortPut = OptionPayoffSpec(
            contractType: .put,
            side: .short,
            strike: 100,
            premium: 4,
            contracts: 1,
            underlyingPrice: 102
        )
        let spMetrics = OptionPayoffEngine.computeMetrics(for: shortPut)
        XCTAssertEqual(spMetrics.breakeven ?? 0, 96, accuracy: 0.0001)
        XCTAssertEqual(spMetrics.maxProfit, .finite(400))
        XCTAssertEqual(spMetrics.maxLoss, .finite(-9600))
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: shortPut, at: 110), 400, accuracy: 0.001)
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: shortPut, at: 96), 0, accuracy: 0.001)
        XCTAssertEqual(OptionPayoffEngine.expirationPnL(spec: shortPut, at: 0), -9600, accuracy: 0.001)

        // Long Put: K = 50, P = 3, 1 contract -> BE = 47, Max Profit = +4700, Max Loss = -300
        let longPut = OptionPayoffSpec(contractType: .put, side: .long, strike: 50, premium: 3, contracts: 1)
        let lpMetrics = OptionPayoffEngine.computeMetrics(for: longPut)
        XCTAssertEqual(lpMetrics.breakeven ?? 0, 47, accuracy: 0.0001)
        XCTAssertEqual(lpMetrics.maxProfit, .finite(4700))
        XCTAssertEqual(lpMetrics.maxLoss, .finite(-300))

        // Short Call: K = 150, P = 5, 1 contract -> BE = 155, Max Profit = +500, Max Loss = Unlimited
        let shortCall = OptionPayoffSpec(contractType: .call, side: .short, strike: 150, premium: 5, contracts: 1)
        let scMetrics = OptionPayoffEngine.computeMetrics(for: shortCall)
        XCTAssertEqual(scMetrics.breakeven ?? 0, 155, accuracy: 0.0001)
        XCTAssertEqual(scMetrics.maxProfit, .finite(500))
        XCTAssertEqual(scMetrics.maxLoss, .unlimited)

        // Exact piecewise vertices include breakeven (pnl == 0) and strike
        let vertices = OptionPayoffEngine.exactVertices(spec: longCall, metrics: lcMetrics)
        XCTAssertTrue(vertices.contains { abs($0.price - 210) < 1e-4 && abs($0.pnl) < 1e-4 })
        XCTAssertTrue(vertices.contains { abs($0.price - 200) < 1e-4 })
    }
}
