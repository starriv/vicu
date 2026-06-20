import Foundation
import UserNotifications

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
        case AppNotificationTemplates.CategoryIdentifier.tradeOrderSubmitted,
             AppNotificationTemplates.CategoryIdentifier.tradeOrderStatus:
            return .orderDetail(orderID: orderID, symbol: symbol)
        case AppNotificationTemplates.CategoryIdentifier.accountActivityEvent:
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
        guard allows(.accountActivity) else {
            return false
        }

        if event.activityType.uppercased() == "TRD", tradeOrderStatusNotificationsEnabled {
            return false
        }

        return true
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

protocol AppNotifying: Sendable {
    func prepare() async
    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async
    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async
    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async
}

final class AppNotificationCenter: NSObject, AppNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = AppNotificationCenter()

    private let center: UNUserNotificationCenter
    private var hasPrepared = false
    private var responseHandler: (@MainActor (AppNotificationRoute) -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    @MainActor
    func installDelegate() {
        center.delegate = self
    }

    @MainActor
    func setResponseHandler(_ handler: (@MainActor (AppNotificationRoute) -> Void)?) {
        responseHandler = handler
        installDelegate()
    }

    func prepare() async {
        let activityCategory = UNNotificationCategory(
            identifier: AppNotificationTemplates.CategoryIdentifier.accountActivityEvent,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let orderCategory = UNNotificationCategory(
            identifier: AppNotificationTemplates.CategoryIdentifier.tradeOrderSubmitted,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let tradeEventCategory = UNNotificationCategory(
            identifier: AppNotificationTemplates.CategoryIdentifier.tradeOrderStatus,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        await MainActor.run {
            center.delegate = self

            guard !hasPrepared else {
                return
            }

            hasPrepared = true
            center.setNotificationCategories([activityCategory, orderCategory, tradeEventCategory])
        }
    }

    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async {
        guard preferences.allowsAccountActivityEvent(event) else {
            return
        }

        await prepare()
        guard await canPresentNotifications() else {
            return
        }

        let template = AppNotificationTemplates.accountActivityEvent(event, locale: locale)
        let content = UNMutableNotificationContent()
        content.title = template.title
        content.body = template.body
        content.sound = .default
        content.categoryIdentifier = template.categoryIdentifier
        content.threadIdentifier = template.threadIdentifier
        var userInfo: [AnyHashable: Any] = [
            "event_id": event.eventID,
            "ref_id": event.refID,
            "activity_type": event.activityType,
            "account_id": event.accountID
        ]
        if let orderID = event.orderID {
            userInfo["order_id"] = orderID
        }
        if let symbol = event.symbol {
            userInfo["symbol"] = symbol
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "alpaca-activity-\(event.eventID)",
            content: content,
            trigger: nil
        )

        try? await add(request)
    }

    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async {
        guard preferences.allows(.tradeOrderSubmitted) else {
            return
        }

        await prepare()
        guard await canPresentNotifications() else {
            return
        }

        let template = AppNotificationTemplates.orderSubmitted(order: order, locale: locale)
        let content = UNMutableNotificationContent()
        content.title = template.title
        content.body = template.body
        content.sound = .default
        content.categoryIdentifier = template.categoryIdentifier
        content.threadIdentifier = template.threadIdentifier
        content.userInfo = [
            "order_id": order.id,
            "client_order_id": order.clientOrderID ?? "",
            "symbol": order.symbol,
            "side": order.side ?? "",
            "order_type": order.type ?? order.orderType ?? "",
            "status": order.status ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: "alpaca-order-submitted-\(order.id)",
            content: content,
            trigger: nil
        )

        try? await add(request)
    }

    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async {
        guard preferences.allows(.tradeOrderStatus) else {
            return
        }

        await prepare()
        guard await canPresentNotifications() else {
            return
        }

        let template = AppNotificationTemplates.tradeEvent(event, locale: locale)
        let content = UNMutableNotificationContent()
        content.title = template.title
        content.body = template.body
        content.sound = .default
        content.categoryIdentifier = template.categoryIdentifier
        content.threadIdentifier = template.threadIdentifier
        content.userInfo = [
            "event_id": event.cursorID ?? "",
            "event": event.event,
            "order_id": event.order.id,
            "symbol": event.order.symbol,
            "side": event.order.side ?? "",
            "order_type": event.order.type ?? event.order.orderType ?? "",
            "status": event.order.status ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: "alpaca-trade-event-\(event.id)",
            content: content,
            trigger: nil
        )

        try? await add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let route = AppNotificationRoute.route(
                categoryIdentifier: response.notification.request.content.categoryIdentifier,
                userInfo: response.notification.request.content.userInfo
              ) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            responseHandler?(route)
        }
        completionHandler()
    }

    private func canPresentNotifications() async -> Bool {
        let authorizationStatus = await notificationAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct NoopAppNotificationCenter: AppNotifying {
    func prepare() async {}
    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async {}
    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async {}

    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async {}
}
