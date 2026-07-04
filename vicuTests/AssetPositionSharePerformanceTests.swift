import XCTest
@testable import vicu

final class AssetPositionSharePerformanceTests: XCTestCase {
    func testSharePerformanceUsesCumulativeUnrealizedProfitLoss() {
        let position = makePosition(
            unrealizedPL: "120.00",
            unrealizedPLPC: "0.25",
            unrealizedIntradayPL: "5.00",
            unrealizedIntradayPLPC: "0.01"
        )

        let performance = AssetPositionSharePerformance.unrealized(position: position)

        XCTAssertEqual(performance.amount ?? .nan, 120.0, accuracy: 0.0001)
        XCTAssertEqual(performance.percent ?? .nan, 0.25, accuracy: 0.0001)
    }

    func testSharePerformanceFallsBackToMarketValueAndCostBasis() {
        let position = makePosition(
            marketValue: "1250.00",
            costBasis: "1000.00",
            unrealizedPL: nil,
            unrealizedPLPC: nil
        )

        let performance = AssetPositionSharePerformance.unrealized(position: position)

        XCTAssertEqual(performance.amount ?? .nan, 250.0, accuracy: 0.0001)
        XCTAssertEqual(performance.percent ?? .nan, 0.25, accuracy: 0.0001)
    }

    private func makePosition(
        symbol: String = "AAPL",
        exchange: String? = "NASDAQ",
        assetClass: String? = "us_equity",
        quantity: String? = "10",
        averageEntryPrice: String? = "100.00",
        side: String? = "long",
        marketValue: String? = "1120.00",
        costBasis: String? = "1000.00",
        unrealizedPL: String? = nil,
        unrealizedPLPC: String? = nil,
        unrealizedIntradayPL: String? = nil,
        unrealizedIntradayPLPC: String? = nil,
        currentPrice: String? = "112.00",
        lastDayPrice: String? = "111.50",
        changeToday: String? = "0.0045"
    ) -> AlpacaPosition {
        AlpacaPosition(
            assetID: nil,
            symbol: symbol,
            exchange: exchange,
            assetClass: assetClass,
            assetMarginable: true,
            quantity: quantity,
            quantityAvailable: quantity,
            averageEntryPrice: averageEntryPrice,
            side: side,
            marketValue: marketValue,
            costBasis: costBasis,
            unrealizedPL: unrealizedPL,
            unrealizedPLPC: unrealizedPLPC,
            unrealizedIntradayPL: unrealizedIntradayPL,
            unrealizedIntradayPLPC: unrealizedIntradayPLPC,
            currentPrice: currentPrice,
            lastDayPrice: lastDayPrice,
            changeToday: changeToday
        )
    }
}
