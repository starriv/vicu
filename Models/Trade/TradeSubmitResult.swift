enum TradeSubmitResult: Sendable {
    case success(AlpacaOrder)
    case failure(String)
}
