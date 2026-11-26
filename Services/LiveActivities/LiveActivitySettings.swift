import Foundation

struct LiveActivitySettings: Codable, Equatable, Sendable {
    static let storageKey = "liveActivitySettings"

    static let `default` = LiveActivitySettings()

    var isEnabled: Bool
    var orderCardEnabled: Bool
    var sessionCardEnabled: Bool

    init(
        isEnabled: Bool = true,
        orderCardEnabled: Bool = true,
        sessionCardEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.orderCardEnabled = orderCardEnabled
        self.sessionCardEnabled = sessionCardEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case orderCardEnabled
        case sessionCardEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(orderCardEnabled, forKey: .orderCardEnabled)
        try container.encode(sessionCardEnabled, forKey: .sessionCardEnabled)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        orderCardEnabled = try container.decodeIfPresent(Bool.self, forKey: .orderCardEnabled) ?? true
        sessionCardEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionCardEnabled) ?? true
    }

    static func load(from store: any AppConfigurationStoring) -> LiveActivitySettings {
        store.value(for: AppConfigurationKeys.LiveActivities.settings)
    }

    func save(to store: any AppConfigurationStoring) {
        store.setValue(self, for: AppConfigurationKeys.LiveActivities.settings)
    }
}
