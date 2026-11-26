import Foundation

enum AppNotificationKind: Sendable {
    case accountActivity
    case tradeOrderSubmitted
    case tradeOrderStatus
}

enum AppNotificationRoute: Equatable, Sendable {
    case orderDetail(orderID: String, symbol: String?)

    static func route(
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> AppNotificationRoute? {
        guard let orderID = stringValue(for: "order_id", in: userInfo) else {
            return nil
        }

        let symbol = stringValue(for: "symbol", in: userInfo)

        switch categoryIdentifier {
        case NotificationPolicy.Category.orderSubmitted,
             NotificationPolicy.Category.orderStatus:
            return .orderDetail(orderID: orderID, symbol: symbol)
        case NotificationPolicy.Category.accountActivity:
            guard stringValue(for: "activity_type", in: userInfo)?.uppercased() == "TRD" else {
                return nil
            }
            return .orderDetail(orderID: orderID, symbol: symbol)
        default:
            return nil
        }
    }

    private static func stringValue(for key: String, in userInfo: [AnyHashable: Any]) -> String? {
        let value = userInfo[key] ?? userInfo[AnyHashable(key)]
        let string: String?

        switch value {
        case let value as String:
            string = value
        case let value as CustomStringConvertible:
            string = value.description
        default:
            string = nil
        }

        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            return nil
        }

        return string
    }
}

struct AppNotificationPreferences: Codable, Equatable, Sendable {
    static let storageKey = "appNotificationPreferences"
    static let `default` = AppNotificationPreferences()

    var isEnabled = true
    var accountActivityNotificationsEnabled = true
    var tradeOrderSubmittedNotificationsEnabled = true
    var tradeOrderStatusNotificationsEnabled = true

    init(
        isEnabled: Bool = true,
        accountActivityNotificationsEnabled: Bool = true,
        tradeOrderSubmittedNotificationsEnabled: Bool = true,
        tradeOrderStatusNotificationsEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.accountActivityNotificationsEnabled = accountActivityNotificationsEnabled
        self.tradeOrderSubmittedNotificationsEnabled = tradeOrderSubmittedNotificationsEnabled
        self.tradeOrderStatusNotificationsEnabled = tradeOrderStatusNotificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        accountActivityNotificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .accountActivityNotificationsEnabled
        ) ?? true
        tradeOrderSubmittedNotificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .tradeOrderSubmittedNotificationsEnabled
        ) ?? true
        tradeOrderStatusNotificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .tradeOrderStatusNotificationsEnabled
        ) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(accountActivityNotificationsEnabled, forKey: .accountActivityNotificationsEnabled)
        try container.encode(tradeOrderSubmittedNotificationsEnabled, forKey: .tradeOrderSubmittedNotificationsEnabled)
        try container.encode(tradeOrderStatusNotificationsEnabled, forKey: .tradeOrderStatusNotificationsEnabled)
    }

    func allows(_ kind: AppNotificationKind) -> Bool {
        guard isEnabled else {
            return false
        }

        switch kind {
        case .accountActivity:
            return accountActivityNotificationsEnabled
        case .tradeOrderSubmitted:
            return tradeOrderSubmittedNotificationsEnabled
        case .tradeOrderStatus:
            return tradeOrderStatusNotificationsEnabled
        }
    }

    func allowsAccountActivityEvent(_ event: AlpacaActivityEvent) -> Bool {
        NotificationPolicy.shouldNotify(activityEvent: event, preferences: self)
    }

    static func load(from store: any AppConfigurationStoring) -> AppNotificationPreferences {
        store.value(for: AppConfigurationKeys.Notifications.preferences)
    }

    func save(to store: any AppConfigurationStoring) {
        store.setValue(self, for: AppConfigurationKeys.Notifications.preferences)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case accountActivityNotificationsEnabled
        case tradeOrderSubmittedNotificationsEnabled
        case tradeOrderStatusNotificationsEnabled
    }
}
