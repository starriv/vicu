import Foundation
import UserNotifications

protocol AppNotifying: Sendable {
    func prepare(locale: Locale) async
    func authorizationStatus() async -> UNAuthorizationStatus
    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async
    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async
    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async
    func deliver(_ payload: NotificationPayload, locale: Locale) async
}

/// Single writer for every Vicu local notification.
///
/// Mirrors `LiveActivityCoordinator`:
/// - owns `UNUserNotificationCenter` delegate & category registration;
/// - delegates filtering/priority decisions to `NotificationPolicy`;
/// - delegates localized formatting to `NotificationPresentation`;
/// - routes notification taps and actions back to `AppModel`.
// @unchecked Sendable: mutable state (hasPrepared, lastPreparedLocaleIdentifier, responseHandler) mutated only on MainActor
final class AppNotificationCenter: NSObject, AppNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = AppNotificationCenter()

    private let center: UNUserNotificationCenter
    private var hasPrepared = false
    private var lastPreparedLocaleIdentifier: String?
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

    func prepare(locale: Locale) async {
        let viewOrderAction = UNNotificationAction(
            identifier: NotificationPolicy.Action.viewOrder,
            title: L10n.LiveActivity.viewActionText(locale: locale),
            options: [.foreground]
        )

        let activityCategory = UNNotificationCategory(
            identifier: NotificationPolicy.Category.accountActivity,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let orderSubmittedCategory = UNNotificationCategory(
            identifier: NotificationPolicy.Category.orderSubmitted,
            actions: [viewOrderAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let orderStatusCategory = UNNotificationCategory(
            identifier: NotificationPolicy.Category.orderStatus,
            actions: [viewOrderAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        await MainActor.run {
            center.delegate = self

            guard !hasPrepared || lastPreparedLocaleIdentifier != locale.identifier else {
                return
            }

            hasPrepared = true
            lastPreparedLocaleIdentifier = locale.identifier
            center.setNotificationCategories([
                activityCategory,
                orderSubmittedCategory,
                orderStatusCategory
            ])
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async {
        guard NotificationPolicy.shouldNotify(activityEvent: event, preferences: preferences) else {
            return
        }

        let payload = NotificationPresentation.accountActivity(event, locale: locale)
        await deliver(payload, locale: locale)
    }

    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async {
        guard NotificationPolicy.shouldNotify(orderSubmitted: order, preferences: preferences) else {
            return
        }

        let payload = NotificationPresentation.orderSubmitted(order: order, locale: locale)
        await deliver(payload, locale: locale)
    }

    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async {
        guard NotificationPolicy.shouldNotify(tradeEvent: event, preferences: preferences) else {
            return
        }

        let payload = NotificationPresentation.tradeEvent(event, locale: locale)
        await deliver(payload, locale: locale)
    }

    func deliver(_ payload: NotificationPayload, locale: Locale) async {
        await prepare(locale: locale)
        guard await canPresentNotifications() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        content.categoryIdentifier = payload.categoryIdentifier
        content.threadIdentifier = payload.threadIdentifier
        content.relevanceScore = payload.priority.relevanceScore
        content.interruptionLevel = payload.priority.interruptionLevel
        content.sound = payload.priority.playsSound ? .default : nil
        content.userInfo = payload.userInfo

        let request = UNNotificationRequest(
            identifier: payload.requestIdentifier,
            content: content,
            trigger: nil
        )

        try? await add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

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
        let isHandledAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            || response.actionIdentifier == NotificationPolicy.Action.viewOrder

        guard isHandledAction,
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

    // MARK: - Authorization & delivery

    private func canPresentNotifications() async -> Bool {
        let status = await authorizationStatus()

        switch status {
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
    func prepare(locale: Locale) async {}
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func notify(event: AlpacaActivityEvent, locale: Locale, preferences: AppNotificationPreferences) async {}
    func notify(orderSubmitted order: AlpacaOrder, locale: Locale, preferences: AppNotificationPreferences) async {}
    func notify(tradeEvent event: AlpacaTradeEvent, locale: Locale, preferences: AppNotificationPreferences) async {}
    func deliver(_ payload: NotificationPayload, locale: Locale) async {}
}
