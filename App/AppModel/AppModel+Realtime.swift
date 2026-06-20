import Foundation
import RxSwift

extension AppModel {
    func streamAssetMarketData(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        channels: Set<AlpacaRealtimeChannel> = AlpacaRealtimeChannel.assetDetail
    ) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return services.stockStream.stream(
            symbol: symbol,
            feed: feed,
            channels: channels,
            credentials: credentials
        )
    }

    func streamAssetMarketData(
        symbols: [String],
        feed: AlpacaMarketDataFeed = .iex,
        channels: Set<AlpacaRealtimeChannel> = AlpacaRealtimeChannel.assetDetail
    ) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        var seenSymbols = Set<String>()
        let normalizedSymbols = symbols
            .map(normalizedMarketSymbol)
            .filter { symbol in
                !symbol.isEmpty && seenSymbols.insert(symbol).inserted
            }
        let streams = normalizedSymbols
            .map { symbol in
                services.stockStream.stream(
                    symbol: symbol,
                    feed: feed,
                    channels: channels,
                    credentials: credentials
                )
            }

        guard !streams.isEmpty else {
            return Observable.empty()
        }

        return Observable.merge(streams)
    }

    func streamTradeQuoteEvents(symbol: String, feed: AlpacaMarketDataFeed = .iex) throws -> Observable<AssetRealtimeEvent> {
        guard let credentials else {
            throw APIClientError.underlying(L10n.Credentials.apiKeyRequired(locale: appLanguage.locale))
        }

        return services.stockStream.stream(
            symbol: symbol,
            feed: feed,
            channels: AlpacaRealtimeChannel.tradeQuote,
            credentials: credentials
        )
    }

    func startAccountEventListeners(credentials activeCredentials: AlpacaCredentials) {
        startActivityEventListener(credentials: activeCredentials)
        startTradeEventListener(credentials: activeCredentials)
    }

    func stopAccountEventListeners() {
        stopActivityEventListener()
        stopTradeEventListener()
    }

    private func startActivityEventListener(credentials activeCredentials: AlpacaCredentials) {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if activityStreamCredentials == activeCredentials, activityStreamDisposable != nil {
            return
        }

        stopActivityEventListener()
        loadRecentActivityRefIDs(credentials: activeCredentials)
        activityStreamCredentials = activeCredentials

        let services = services
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
                    await self?.refreshAfterActivityEvent(credentials: activeCredentials)
                }
            })

        activityStreamDisposable = Disposables.create(eventSubscription, refreshSubscription)

        Task {
            await services.appNotifier.prepare()
        }
    }

    private func stopActivityEventListener() {
        activityStreamDisposable?.dispose()
        activityStreamDisposable = nil
        activityStreamCredentials = nil
    }

    private func startTradeEventListener(credentials activeCredentials: AlpacaCredentials) {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if tradeEventStreamCredentials == activeCredentials, tradeEventStreamDisposable != nil {
            return
        }

        stopTradeEventListener()
        loadRecentTradeEventIDs(credentials: activeCredentials)
        tradeEventStreamCredentials = activeCredentials

        let services = services
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
                    self?.handleTradeEventStreamError(error, credentials: activeCredentials)
                }
            }
        )

        let refreshSubscription = stream
            .debounce(.milliseconds(1200), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAfterTradeEvent(credentials: activeCredentials)
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
        guard isCurrentCredentialContext(activeCredentials),
              !hasProcessedActivityEvent(event, credentials: activeCredentials) else {
            return
        }

        rememberProcessedActivityEvent(event, credentials: activeCredentials)
        await services.appNotifier.notify(
            event: event,
            locale: appLanguage.locale,
            preferences: notificationPreferences
        )
    }

    private func handleTradeEvent(_ event: AlpacaTradeEvent, credentials activeCredentials: AlpacaCredentials) async {
        guard isCurrentCredentialContext(activeCredentials),
              !hasProcessedTradeEvent(event, credentials: activeCredentials) else {
            return
        }

        rememberProcessedTradeEvent(event, credentials: activeCredentials)
        await services.appNotifier.notify(
            tradeEvent: event,
            locale: appLanguage.locale,
            preferences: notificationPreferences
        )
    }

    private func refreshAfterActivityEvent(credentials activeCredentials: AlpacaCredentials) async {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        await refresh()
    }

    private func refreshAfterTradeEvent(credentials activeCredentials: AlpacaCredentials) async {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        await refresh()
    }

    private func handleActivityStreamError(_ error: Error, credentials activeCredentials: AlpacaCredentials) {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if error.isAuthenticationFailure {
            credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
            stopAccountEventListeners()
        } else {
            lastError = error.localizedDescription
        }
    }

    private func handleTradeEventStreamError(_ error: Error, credentials activeCredentials: AlpacaCredentials) {
        guard isCurrentCredentialContext(activeCredentials) else {
            return
        }

        if error.isAuthenticationFailure {
            credentialsStatus = .failed(activeCredentials.environment, message: error.localizedDescription)
            stopAccountEventListeners()
        } else {
            lastError = error.localizedDescription
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
