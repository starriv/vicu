import Foundation

struct AlpacaAsset: Codable, Identifiable, Sendable {
    let id: String
    let assetClass: String?
    let exchange: String?
    let symbol: String
    let name: String?
    let status: String?
    let tradable: Bool?
    let marginable: Bool?
    let maintenanceMarginRequirement: Double?
    let marginRequirementLong: String?
    let marginRequirementShort: String?
    let shortable: Bool?
    let easyToBorrow: Bool?
    let borrowStatus: String?
    let fractionable: Bool?
    let attributes: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case assetClass = "class"
        case exchange
        case symbol
        case name
        case status
        case tradable
        case marginable
        case maintenanceMarginRequirement = "maintenance_margin_requirement"
        case marginRequirementLong = "margin_requirement_long"
        case marginRequirementShort = "margin_requirement_short"
        case shortable
        case easyToBorrow = "easy_to_borrow"
        case borrowStatus = "borrow_status"
        case fractionable
        case attributes
    }
}

struct AlpacaWatchlist: Decodable, Identifiable, Sendable {
    let id: String
    let accountID: String?
    let name: String
    let assets: [AlpacaAsset]?
    let createdAt: String?
    let updatedAt: String?

    var symbols: [String] {
        (assets ?? []).map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case name
        case assets
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AlpacaWatchlistRequest: Encodable, Sendable {
    let name: String
    let symbols: [String]?
}

struct AlpacaWatchlistAssetRequest: Encodable, Sendable {
    let symbol: String
}
