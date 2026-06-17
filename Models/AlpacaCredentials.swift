struct AlpacaCredentials: Codable, Equatable, Sendable {
    var keyID: String
    var secretKey: String
    var environment: TradeEnvironment
}
