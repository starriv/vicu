import Foundation
import RxSwift

@MainActor
final class RealtimeEventCoordinator {
    private var activityStreamDisposable: Disposable?
    private var activityStreamCredentials: AlpacaCredentials?
    private var recentActivityRefIDs = Set<String>()
    private var recentActivityRefIDOrder: [String] = []
    private let recentActivityRefLimit = 50

    private var tradeEventStreamDisposable: Disposable?
    private var tradeEventStreamCredentials: AlpacaCredentials?
    private var recentTradeEventIDs = Set<String>()
    private var recentTradeEventIDOrder: [String] = []
    private let recentTradeEventLimit = 100

    private weak var app: AppModel?
    private let services: AppServices

    init(app: AppModel) {
        self.app = app
        self.services = app.services
    }

    func startListeners(credentials activeCredentials: AlpacaCredentials) {
        startActivityListener(credentials: activeCredentials)
        startTradeEventListener(credentials: activeCredentials)
    }

    func stopListeners() {
        stopActivityListener()
        stopTradeEventListener()
    }

    func clearDeduplicationState() {
        recentActivityRefIDs.removeAll()
        recentActivityRefIDOrder.removeAll()
        recentTradeEventIDs.removeAll()
        recentTradeEventIDOrder.removeAll()
    }

    private func startActivityListener(credentials activeCredentials: AlpacaCredentials) {
        guard app?.isCurrentCredentialContext(activeCredentials) == true else {
            return
        }

        if activityStreamCredentials == activeCredentials, activityStreamDisposable != nil {
            return
        }

        stopActivityListener()
        loadRecentActivityRefIDs(credentials: activeCredentials)
        activityStreamCredentials = activeCredentials

        let stream = services.activityStream
            .streamActivities(
                credentials: activeCredentials,
                sinceID: lastActivityEventID(credentials: activeCredentials)
            )
            .observe(on: MainScheduler.instance)
            .share()

        let eventSubscription = stream.subscribe(
            onNext: { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handleActivityEvent(event, credentials: activeCredentials)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleActivityStreamError(error, credentials: activeCredentials)
                }
            }
        )

        let refreshSubscription = stream
            .debounce(.milliseconds(1200), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAfterEvent(credentials: activeCredentials)
                }
            })

        activityStreamDisposable = Disposables.create(eventSubscription, refreshSubscription)

        Task {
            await services.appNotifier.prepare()
        }
    }

    private func stopActivityListener() {
        activityStreamDisposable?.dispose()
        activityStreamDisposable = nil
        activityStreamCredentials = nil
    }

    private func startTradeEventListener(credentials activeCredentials: AlpacaCredentials) {
        guard app?.isCurrentCredentialContext(activeCredentials) == true else {
            return
        }

        if tradeEventStreamCredentials == activeCredentials, tradeEventStreamDisposable != nil {
            return
        }

        stopTradeEventListener()
        loadRecentTradeEventIDs(credentials: activeCredentials)
        tradeEventStreamCredentials = activeCredentials

        let stream = services.tradeEventStream
            .streamTradeEvents(
                credentials: activeCredentials,
                sinceID: lastTradeEventID(credentials: activeCredentials)
            )
            .observe(on: MainScheduler.instance)
            .share()

        let eventSubscription = stream.subscribe(
            onNext: { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handleTradeEvent(event, credentials: activeCredentials)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleTradeStreamError(error, credentials: activeCredentials)
                }
            }
        )

        let refreshSubscription = stream
            .debounce(.milliseconds(1200), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAfterEvent(credentials: activeCredentials)
                }
            })

        tradeEventStreamDisposable = Disposables.create(eventSubscription, refreshSubscription)

        Task {
            await services.appNotifier.prepare()
        }
    }

    private func stopTradeEventListener() {
        tradeEventStreamDisposable?.dispose()
        tradeEventStreamDisposable = nil
        tradeEventStreamCredentials = nil
    }

    private func handleActivityEvent(_ event: AlpacaActivityEvent, credentials activeCredentials: AlpacaCredentials) async {
        guard let app,
              app.isCurrentCredentialContext(activeCredentials),
              !hasProcessedActivityEvent(event, credentials: activeCredentials) else {
            return
        }

        rememberProcessedActivityEvent(event, credentials: activeCredentials)
        await services.appNotifier.notify(
            event: event,
            locale: app.appLanguage.locale,
            preferences: app.notificationPreferences
        )
    }

    private func handleTradeEvent(_ event: AlpacaTradeEvent, credentials activeCredentials: AlpacaCredentials) async {
        guard let app,
              app.isCurrentCredentialContext(activeCredentials),
              !hasProcessedTradeEvent(event, credentials: activeCredentials) else {
            return
        }

        rememberProcessedTradeEvent(event, credentials: activeCredentials)
        await services.appNotifier.notify(
            tradeEvent: event,
            locale: app.appLanguage.locale,
            preferences: app.notificationPreferences
        )
        await app.liveActivities.tradeEventDidArrive(event)
    }

    private func refreshAfterEvent(credentials activeCredentials: AlpacaCredentials) async {
        guard app?.isCurrentCredentialContext(activeCredentials) == true else {
            return
        }

        await app?.refresh()
    }

    private func handleActivityStreamError(_ error: Error, credentials activeCredentials: AlpacaCredentials) {
        guard let app, app.isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if error.isAuthenticationFailure {
            app.credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
            stopListeners()
        } else {
            app.lastError = error.localizedDescription
        }
    }

    private func handleTradeStreamError(_ error: Error, credentials activeCredentials: AlpacaCredentials) {
        guard let app, app.isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if error.isAuthenticationFailure {
            app.credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
            stopListeners()
        } else {
            app.lastError = error.localizedDescription
        }
    }

    private func hasProcessedActivityEvent(
        _ event: AlpacaActivityEvent,
        credentials activeCredentials: AlpacaCredentials
    ) -> Bool {
        recentActivityRefIDs.contains(event.refID)
            || lastActivityEventID(credentials: activeCredentials) == event.eventID
    }

    private func rememberProcessedActivityEvent(
        _ event: AlpacaActivityEvent,
        credentials activeCredentials: AlpacaCredentials
    ) {
        recentActivityRefIDs.insert(event.refID)
        recentActivityRefIDOrder.removeAll { $0 == event.refID }
        recentActivityRefIDOrder.append(event.refID)

        while recentActivityRefIDOrder.count > recentActivityRefLimit {
            let removedRefID = recentActivityRefIDOrder.removeFirst()
            recentActivityRefIDs.remove(removedRefID)
        }

        services.configurationStore.setValue(
            event.eventID,
            for: AppConfigurationKeys.Realtime.activityLastEventID(credentials: activeCredentials)
        )
        services.configurationStore.setValue(
            recentActivityRefIDOrder,
            for: AppConfigurationKeys.Realtime.recentActivityRefIDs(credentials: activeCredentials)
        )
    }

    private func hasProcessedTradeEvent(
        _ event: AlpacaTradeEvent,
        credentials activeCredentials: AlpacaCredentials
    ) -> Bool {
        recentTradeEventIDs.contains(event.id)
            || (event.cursorID != nil && lastTradeEventID(credentials: activeCredentials) == event.cursorID)
    }

    private func rememberProcessedTradeEvent(
        _ event: AlpacaTradeEvent,
        credentials activeCredentials: AlpacaCredentials
    ) {
        recentTradeEventIDs.insert(event.id)
        recentTradeEventIDOrder.removeAll { $0 == event.id }
        recentTradeEventIDOrder.append(event.id)

        while recentTradeEventIDOrder.count > recentTradeEventLimit {
            let removedEventID = recentTradeEventIDOrder.removeFirst()
            recentTradeEventIDs.remove(removedEventID)
        }

        if let cursorID = event.cursorID {
            services.configurationStore.setValue(
                cursorID,
                for: AppConfigurationKeys.Realtime.tradeLastEventID(credentials: activeCredentials)
            )
        }
        services.configurationStore.setValue(
            recentTradeEventIDOrder,
            for: AppConfigurationKeys.Realtime.recentTradeEventIDs(credentials: activeCredentials)
        )
    }

    private func loadRecentActivityRefIDs(credentials activeCredentials: AlpacaCredentials) {
        let refIDs = services.configurationStore.value(
            for: AppConfigurationKeys.Realtime.recentActivityRefIDs(credentials: activeCredentials)
        )
        recentActivityRefIDOrder = Array(refIDs.suffix(recentActivityRefLimit))
        recentActivityRefIDs = Set(recentActivityRefIDOrder)
    }

    private func loadRecentTradeEventIDs(credentials activeCredentials: AlpacaCredentials) {
        let eventIDs = services.configurationStore.value(
            for: AppConfigurationKeys.Realtime.recentTradeEventIDs(credentials: activeCredentials)
        )
        recentTradeEventIDOrder = Array(eventIDs.suffix(recentTradeEventLimit))
        recentTradeEventIDs = Set(recentTradeEventIDOrder)
    }

    private func lastActivityEventID(credentials activeCredentials: AlpacaCredentials) -> String? {
        services.configurationStore.optionalValue(
            for: AppConfigurationKeys.Realtime.activityLastEventID(credentials: activeCredentials)
        )
    }

    private func lastTradeEventID(credentials activeCredentials: AlpacaCredentials) -> String? {
        services.configurationStore.optionalValue(
            for: AppConfigurationKeys.Realtime.tradeLastEventID(credentials: activeCredentials)
        )
    }
}
