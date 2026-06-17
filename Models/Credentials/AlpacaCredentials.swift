struct AlpacaCredentials: Codable, Equatable, Sendable {
    var keyID: String
    var secretKey: String
    var environment: TradeEnvironment
}

extension AlpacaCredentials {
    var maskedKeyID: String {
        let visibleSuffix = keyID.suffix(4)
        return "••••\(visibleSuffix)"
    }
}
