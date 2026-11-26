@preconcurrency import ActivityKit
import Foundation

/// The single writer for every Vicu Live Activity.
///
/// Rules enforced here:
/// * only this type calls `Activity.request/update/end`;
/// * at most one order card and one session card exist at a time;
/// * an identical payload is never pushed twice (ActivityKit has an update budget);
/// * activities left behind by a previous launch are adopted or reconciled on start.
@MainActor
final class LiveActivityCoordinator {
    /// Display label for the session card. Vicu trades US equities, so this is
    /// intentionally a single shared value rather than per-account metadata.
    private static let sessionMarketName = "NYSE"

    private weak var app: AppModel?

    private var orderActivity: Activity<OrderActivityAttributes>?
    private var sessionActivity: Activity<SessionActivityAttributes>?
    private var lastOrderContent: OrderActivityAttributes.ContentState?
    private var lastSessionContent: SessionActivityAttributes.ContentState?
    private var lastMarketOverviewFetch: Date?
    private var isRunning = false

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Lifecycle

    func start() async {
        guard let app, !isRunning, app.canUseAlpacaAPI else {
            return
        }

        isRunning = true
        await adoptExistingActivities()
        await refreshAll()
    }

    func stop() async {
        isRunning = false
        await endAllActivities(policy: .immediate)
    }

    func settingsDidChange() async {
        guard let app, isRunning else {
            return
        }

        guard app.liveActivitySettings.isEnabled else {
            await endAllActivities(policy: .immediate)
            return
        }

        if !app.liveActivitySettings.orderCardEnabled {
            await endOrderActivity(policy: .immediate)
        }

        if !app.liveActivitySettings.sessionCardEnabled {
            await endSessionActivity(policy: .immediate)
        }

        await refreshAll()
    }

    // MARK: - Inputs

    func portfolioDidRefresh() async {
        guard isRunning else {
            return
        }

        await refreshAll()
    }

    func orderDidChange(_ order: AlpacaOrder) async {
        guard isRunning, let app else {
            return
        }

        await refreshOrderCard(
            orders: app.portfolio.orders,
            preferred: order
        )
    }

    func tradeEventDidArrive(_ event: AlpacaTradeEvent) async {
        guard isRunning, let app else {
            return
        }

        await refreshOrderCard(
            orders: app.portfolio.orders,
            preferred: event.order
        )
    }

    func marketOverviewDidChange(_ overview: MarketOverview?) async {
        guard isRunning else {
            return
        }

        await refreshSessionCard(overview: overview)
    }

    func sceneDidBecomeActive() async {
        guard isRunning else {
            return
        }

        await refreshAll()
    }

    // MARK: - Order card

    private func refreshOrderCard(orders: [AlpacaOrder], preferred: AlpacaOrder?) async {
        guard let app, isRunning else {
            return
        }

        let settings = app.liveActivitySettings
        guard settings.isEnabled, settings.orderCardEnabled else {
            await endOrderActivity(policy: .immediate)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let now = Date()
        guard preferred != nil || app.portfolio.hasLoadedOrders else {
            return
        }

        guard let order = preferred ?? LiveActivityPolicy.representativeOrder(in: orders, now: now) else {
            await endOrderActivity(policy: .immediate)
            return
        }

        let workingCount = LiveActivityPolicy.workingOrderCount(in: orders)
        let locale = app.appLanguage.locale
        let attributes = LiveActivityPresentation.orderAttributes(
            for: order,
            locale: locale
        )
        let content = LiveActivityPresentation.orderContent(
            for: order,
            additionalWorkingCount: max(0, workingCount - 1),
            locale: locale,
            now: now
        )

        await pushOrder(attributes: attributes, content: content, now: now)
    }

    private func pushOrder(
        attributes: OrderActivityAttributes,
        content: OrderActivityAttributes.ContentState,
        now: Date
    ) async {
        if let activity = orderActivity, activity.attributes.orderID == attributes.orderID {
            if content.phase.isTerminal {
                // Terminal: `end` sets the final content, so a separate `update` is redundant.
                await activity.end(
                    ActivityContent(state: content, staleDate: nil),
                    dismissalPolicy: LiveActivityPolicy.dismissalDate(for: content.phase, now: now)
                        .map { .after($0) } ?? .default
                )
                orderActivity = nil
                lastOrderContent = nil
            } else if content != lastOrderContent {
                await activity.update(
                    ActivityContent(
                        state: content,
                        staleDate: LiveActivityPolicy.staleDate(for: content.phase, now: now)
                    )
                )
                lastOrderContent = content
            }
            return
        }

        await endOrderActivity(policy: .immediate)

        // History never starts a card on its own; it only closes one that was
        // already on screen. Otherwise every launch would resurrect old fills.
        guard !content.phase.isTerminal else {
            return
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: content,
                    staleDate: LiveActivityPolicy.staleDate(for: content.phase, now: now)
                ),
                pushType: nil
            )
            orderActivity = activity
            lastOrderContent = content
        } catch {
            orderActivity = nil
            lastOrderContent = nil
        }
    }

    private func endOrderActivity(policy: ActivityUIDismissalPolicy) async {
        guard let activity = orderActivity else {
            return
        }

        await activity.end(nil, dismissalPolicy: policy)
        orderActivity = nil
        lastOrderContent = nil
    }

    // MARK: - Session card

    private func refreshSessionCard(overview: MarketOverview?) async {
        guard let app, isRunning else {
            return
        }

        let settings = app.liveActivitySettings
        guard settings.isEnabled, settings.sessionCardEnabled else {
            await endSessionActivity(policy: .immediate)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        var snapshot = overview ?? app.cachedMarketOverview
        if snapshot == nil, shouldRefreshMarketOverview(now: Date()) {
            lastMarketOverviewFetch = Date()
            snapshot = try? await app.fetchMarketOverview()
        }

        guard let snapshot else {
            return
        }

        let now = Date()
        let intervals = MarketSessionSchedule.intervals(
            from: snapshot.calendar,
            overnightDays: snapshot.overnightCalendar
        )

        guard let active = MarketSessionSchedule.activeInterval(at: now, in: intervals) else {
            await endSessionActivity(
                policy: .after(now.addingTimeInterval(LiveActivityPolicy.sessionLinger))
            )
            return
        }

        let progress = MarketSessionSchedule.progress(for: active, in: intervals, at: now)
        let content = LiveActivityPresentation.sessionContent(
            active: active,
            progress: progress,
            account: app.portfolio.account,
            workingOrders: LiveActivityPolicy.workingOrderCount(in: app.portfolio.orders),
            marketName: Self.sessionMarketName,
            locale: app.appLanguage.locale
        )

        guard content != lastSessionContent else {
            return
        }

        let activityContent = ActivityContent(state: content, staleDate: active.end)

        if let activity = sessionActivity {
            await activity.update(activityContent)
        } else {
            sessionActivity = try? Activity.request(
                attributes: LiveActivityPresentation.sessionAttributes(marketName: Self.sessionMarketName),
                content: activityContent,
                pushType: nil
            )
        }

        lastSessionContent = content
    }

    private func shouldRefreshMarketOverview(now: Date) -> Bool {
        guard let lastMarketOverviewFetch else {
            return true
        }

        return now.timeIntervalSince(lastMarketOverviewFetch) > 5 * 60
    }

    private func endSessionActivity(policy: ActivityUIDismissalPolicy) async {
        guard let activity = sessionActivity else {
            return
        }

        await activity.end(nil, dismissalPolicy: policy)
        sessionActivity = nil
        lastSessionContent = nil
    }

    // MARK: - Reconciliation

    private func refreshAll() async {
        guard let app else {
            return
        }

        await refreshOrderCard(orders: app.portfolio.orders, preferred: nil)
        await refreshSessionCard(overview: app.cachedMarketOverview)
    }

    private func adoptExistingActivities() async {
        let orderActivities = Activity<OrderActivityAttributes>.activities
        if let first = orderActivities.first {
            orderActivity = first
            lastOrderContent = first.content.state
        }
        for extra in orderActivities.dropFirst() {
            await extra.end(nil, dismissalPolicy: .immediate)
        }

        let sessionActivities = Activity<SessionActivityAttributes>.activities
        if let first = sessionActivities.first {
            sessionActivity = first
            lastSessionContent = first.content.state
        }
        for extra in sessionActivities.dropFirst() {
            await extra.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAllActivities(policy: ActivityUIDismissalPolicy) async {
        await endOrderActivity(policy: policy)
        await endSessionActivity(policy: policy)

        for activity in Activity<OrderActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: policy)
        }
        for activity in Activity<SessionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: policy)
        }
    }
}
