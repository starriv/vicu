import Foundation
import OSLog
import RxSwift

protocol AlpacaStockStreaming: Sendable {
    func stream(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        channels: Set<AlpacaRealtimeChannel>,
        credentials: AlpacaCredentials
    ) -> Observable<AssetRealtimeEvent>
    func reset(credentials: AlpacaCredentials?)
}

extension AlpacaStockStreaming {
    func stream(symbol: String, feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) -> Observable<AssetRealtimeEvent> {
        stream(symbol: symbol, feed: feed, channels: AlpacaRealtimeChannel.assetDetail, credentials: credentials)
    }
}

final class AlpacaStockStreamClient: AlpacaStockStreaming, @unchecked Sendable {
    static let shared = AlpacaStockStreamClient()

    private let session: URLSession
    private let baseURL: URL
    private let lock = NSLock()
    private var streamSessions: [AlpacaStockStreamSessionKey: SharedAlpacaStockStreamSession] = [:]

    init(
        session: URLSession = URLSession(configuration: .vicuWebSocket),
        baseURL: URL = APIPaths.AlpacaStreams.marketDataBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func stream(
        symbol: String,
        feed: AlpacaMarketDataFeed = .iex,
        channels: Set<AlpacaRealtimeChannel> = AlpacaRealtimeChannel.assetDetail,
        credentials: AlpacaCredentials
    ) -> Observable<AssetRealtimeEvent> {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedChannels = channels.isEmpty ? AlpacaRealtimeChannel.assetDetail : channels

        return Observable.create { observer in
            guard !normalizedSymbol.isEmpty else {
                observer.onNext(.connection(.failed("Missing symbol.")))
                observer.onCompleted()
                return Disposables.create()
            }

            let session = self.sharedSession(feed: feed, credentials: credentials)
            let subscription = session.add(symbol: normalizedSymbol, channels: normalizedChannels, observer: observer)
            return Disposables.create {
                session.remove(subscription)
            }
        }
    }

    private func sharedSession(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) -> SharedAlpacaStockStreamSession {
        let key = AlpacaStockStreamSessionKey(feed: feed, credentials: credentials)
        var staleSession: SharedAlpacaStockStreamSession?

        lock.lock()
        if let streamSession = streamSessions[key] {
            if streamSession.matches(credentials) {
                lock.unlock()
                return streamSession
            }

            staleSession = streamSession
            streamSessions.removeValue(forKey: key)
        }

        let streamSession = SharedAlpacaStockStreamSession(
            session: session,
            baseURL: baseURL,
            feed: feed,
            credentials: credentials
        )
        streamSessions[key] = streamSession
        lock.unlock()
        staleSession?.stop()
        return streamSession
    }

    func reset(credentials: AlpacaCredentials? = nil) {
        let sessionsToStop: [SharedAlpacaStockStreamSession]

        lock.lock()
        if let credentials {
            sessionsToStop = streamSessions
                .filter { entry in
                    entry.key.matches(credentials) || entry.value.matches(credentials)
                }
                .map(\.value)
            streamSessions = streamSessions.filter { entry in
                !(entry.key.matches(credentials) || entry.value.matches(credentials))
            }
        } else {
            sessionsToStop = Array(streamSessions.values)
            streamSessions.removeAll()
        }
        lock.unlock()

        sessionsToStop.forEach { $0.stop() }
    }
}

private struct AlpacaStockStreamSessionKey: Hashable {
    let feed: AlpacaMarketDataFeed
    let keyID: String
    let environment: TradeEnvironment

    init(feed: AlpacaMarketDataFeed, credentials: AlpacaCredentials) {
        self.feed = feed
        keyID = credentials.keyID
        environment = credentials.environment
    }

    func matches(_ credentials: AlpacaCredentials) -> Bool {
        keyID == credentials.keyID && environment == credentials.environment
    }
}

private struct AlpacaStreamSubscriptionKey: Hashable {
    let symbol: String
    let channel: AlpacaRealtimeChannel
}

private final class SharedAlpacaStockStreamSession: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.starriv.vicu", category: "AlpacaStockStream")
    private static let reconnectPolicy = NetworkRetryPolicy.realtimeStream
    private static let keepaliveInterval: TimeInterval = 25
    private static let connectionLimitInitialDelay: TimeInterval = 30
    private static let connectionLimitMaxDelay: TimeInterval = 180

    private struct ObserverRegistration {
        let symbol: String
        let channels: Set<AlpacaRealtimeChannel>
        let observer: AnyObserver<AssetRealtimeEvent>
    }

    private let session: URLSession
    private let baseURL: URL
    private let feed: AlpacaMarketDataFeed
    private let credentials: AlpacaCredentials
    private let lock = NSLock()
    private let idleDisconnectDelay: TimeInterval = 6

    private var observers: [UUID: ObserverRegistration] = [:]
    private var observerIDsByKey: [AlpacaStreamSubscriptionKey: Set<UUID>] = [:]
    private var subscriptionCounts: [AlpacaStreamSubscriptionKey: Int] = [:]
    private var subscribedKeys = Set<AlpacaStreamSubscriptionKey>()
    private var connectionStatus: AssetRealtimeConnectionStatus = .disconnected
    private var task: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var idleDisconnectTask: Task<Void, Never>?

    init(
        session: URLSession,
        baseURL: URL,
        feed: AlpacaMarketDataFeed,
        credentials: AlpacaCredentials
    ) {
        self.session = session
        self.baseURL = baseURL
        self.feed = feed
        self.credentials = credentials
    }

    func matches(_ credentials: AlpacaCredentials) -> Bool {
        self.credentials == credentials
    }

    func add(
        symbol: String,
        channels: Set<AlpacaRealtimeChannel>,
        observer: AnyObserver<AssetRealtimeEvent>
    ) -> UUID {
        let id = UUID()
        let subscriptionKeys = Set(channels.map { AlpacaStreamSubscriptionKey(symbol: symbol, channel: $0) })
        var keysToSubscribe = Set<AlpacaStreamSubscriptionKey>()

        lock.lock()
        idleDisconnectTask?.cancel()
        idleDisconnectTask = nil

        observers[id] = ObserverRegistration(symbol: symbol, channels: channels, observer: observer)
        for key in subscriptionKeys {
            observerIDsByKey[key, default: []].insert(id)

            let previousCount = subscriptionCounts[key] ?? 0
            subscriptionCounts[key] = previousCount + 1
            if previousCount == 0, !subscribedKeys.contains(key) {
                keysToSubscribe.insert(key)
            }
        }
        let status = connectionStatus
        let shouldStart = task == nil
        let shouldSubscribe = webSocket != nil && status == .live && !keysToSubscribe.isEmpty
        lock.unlock()

        observer.onNext(.connection(status))

        if shouldStart {
            start()
        }

        if shouldSubscribe {
            Task {
                await updateSubscription(action: .subscribe, keys: keysToSubscribe)
            }
        }

        return id
    }

    func remove(_ id: UUID) {
        var keysToUnsubscribe = Set<AlpacaStreamSubscriptionKey>()
        let shouldScheduleIdleDisconnect: Bool

        lock.lock()
        guard let registration = observers.removeValue(forKey: id) else {
            lock.unlock()
            return
        }

        let symbol = registration.symbol
        for channel in registration.channels {
            let key = AlpacaStreamSubscriptionKey(symbol: symbol, channel: channel)
            if var observerIDs = observerIDsByKey[key] {
                observerIDs.remove(id)
                if observerIDs.isEmpty {
                    observerIDsByKey.removeValue(forKey: key)
                } else {
                    observerIDsByKey[key] = observerIDs
                }
            }

            let remainingCount = max(0, (subscriptionCounts[key] ?? 1) - 1)
            if remainingCount == 0 {
                subscriptionCounts.removeValue(forKey: key)
                if subscribedKeys.contains(key) {
                    keysToUnsubscribe.insert(key)
                }
            } else {
                subscriptionCounts[key] = remainingCount
            }
        }

        shouldScheduleIdleDisconnect = observers.isEmpty
        lock.unlock()

        if !keysToUnsubscribe.isEmpty {
            Task {
                await updateSubscription(action: .unsubscribe, keys: keysToUnsubscribe)
            }
        }

        if shouldScheduleIdleDisconnect {
            scheduleIdleDisconnect()
        }
    }

    private func start() {
        lock.lock()
        if task != nil {
            lock.unlock()
            return
        }

        task = Task { [weak self] in
            await self?.runStream()
        }
        lock.unlock()
    }

    private func runStream() async {
        var retryAttempt = 0
        var shouldBroadcastDisconnected = true

        while !Task.isCancelled, hasObservers {
            do {
                broadcast(.connection(retryAttempt == 0 ? .connecting : .reconnecting("Connection interrupted.")))
                try await connectOnce()
                retryAttempt = 0
            } catch let error as AlpacaStreamFatalError {
                Self.logger.error("stream fatal feed=\(self.feed.rawValue, privacy: .public) message=\(error.localizedDescription, privacy: .public)")
                broadcast(.connection(.failed(error.localizedDescription)))
                shouldBroadcastDisconnected = false
                break
            } catch let error as AlpacaStreamRecoverableError {
                guard !Task.isCancelled, hasObservers else {
                    break
                }

                retryAttempt += 1
                let isConnectionLimit = Self.isConnectionLimit(error)
                let delay = Self.retryDelay(retryAttempt: retryAttempt, isConnectionLimit: isConnectionLimit)
                let message = isConnectionLimit
                    ? "Alpaca market data stream limit reached. Retrying after cooldown."
                    : error.localizedDescription

                Self.logger.warning("stream recoverable feed=\(self.feed.rawValue, privacy: .public) attempt=\(retryAttempt, privacy: .public) cooldownSeconds=\(Int(delay.rounded()), privacy: .public) message=\(message, privacy: .public)")
                broadcast(.connection(.reconnecting(message)))

                do {
                    try await Self.sleepBeforeRetry(retryAttempt: retryAttempt, isConnectionLimit: isConnectionLimit)
                } catch {
                    break
                }
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled, hasObservers else {
                    break
                }

                retryAttempt += 1
                let message = Self.reconnectMessage(for: error)
                if Self.isSocketClosure(error) {
                    Self.logger.info("stream socket closed feed=\(self.feed.rawValue, privacy: .public) attempt=\(retryAttempt, privacy: .public) message=\(message, privacy: .public)")
                } else {
                    Self.logger.warning("stream interrupted feed=\(self.feed.rawValue, privacy: .public) attempt=\(retryAttempt, privacy: .public) message=\(message, privacy: .public)")
                }
                broadcast(.connection(.reconnecting(message)))

                do {
                    try await Self.reconnectPolicy.sleepBeforeRetry(retryAttempt)
                } catch {
                    break
                }
            }
        }

        clearRunState()

        if shouldBroadcastDisconnected {
            broadcast(.connection(.disconnected))
        }
    }

    private func connectOnce() async throws {
        let url = baseURL.appendingPathComponent(feed.streamPath)
        Self.logger.info("stream connect feed=\(self.feed.rawValue, privacy: .public) url=\(url.absoluteString, privacy: .public)")
        let webSocket = session.webSocketTask(with: url)
        setWebSocket(webSocket)
        webSocket.resume()
        let keepaliveTask = startKeepalive(on: webSocket)

        defer {
            keepaliveTask.cancel()
            clearWebSocket(webSocket)
            webSocket.cancel(with: .goingAway, reason: nil)
        }

        broadcast(.connection(.authenticating))
        try await send(AlpacaStreamAuthRequest(key: credentials.keyID, secret: credentials.secretKey), on: webSocket)
        try await waitForSuccessMessage(containing: "authenticated", on: webSocket)
        Self.logger.info("stream authenticated feed=\(self.feed.rawValue, privacy: .public)")

        let subscriptionKeys = activeSubscriptionKeys
        guard !subscriptionKeys.isEmpty else {
            throw CancellationError()
        }

        broadcast(.connection(.subscribing))
        try await send(AlpacaStreamSubscriptionRequest(action: .subscribe, keys: subscriptionKeys), on: webSocket)

        let subscriptionMessages = try await receivePayloads(on: webSocket)
        if let errorPayload = subscriptionMessages.first(where: { $0.messageType == "error" }) {
            throw errorPayload.streamError(fallback: "Alpaca stream subscription failed.")
        }

        let subscription = subscriptionMessages.first(where: { $0.messageType == "subscription" })?.subscription
        if let subscription {
            updateSubscribedSymbols(subscription)
        } else {
            markSubscribed(subscriptionKeys)
        }
        broadcast(.connection(.live))
        Self.logger.info("stream live feed=\(self.feed.rawValue, privacy: .public) subscriptions=\(subscriptionKeys.count, privacy: .public)")
        await reconcileSubscriptions()

        while !Task.isCancelled {
            let payloads = try await receivePayloads(on: webSocket)
            for payload in payloads {
                if payload.messageType == "error" {
                    Self.logger.error("stream payload error feed=\(self.feed.rawValue, privacy: .public) code=\(payload.code ?? -1, privacy: .public) message=\(payload.message ?? "unknown", privacy: .public)")
                    throw payload.streamError(fallback: "Alpaca stream error.")
                } else if let subscription = payload.subscription {
                    updateSubscribedSymbols(subscription)
                } else if let event = payload.event {
                    dispatch(event)
                }
            }
        }

        throw CancellationError()
    }

    private func updateSubscription(action: AlpacaStreamSubscriptionAction, keys: Set<AlpacaStreamSubscriptionKey>) async {
        guard !keys.isEmpty else {
            return
        }

        guard let webSocket = currentWebSocket else {
            return
        }

        do {
            try await send(AlpacaStreamSubscriptionRequest(action: action, keys: keys), on: webSocket)
            switch action {
            case .subscribe:
                markSubscribed(keys)
            case .unsubscribe:
                markUnsubscribed(keys)
            }
        } catch {
            webSocket.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func reconnectMessage(for error: Error) -> String {
        if isSocketClosure(error) {
            return "Socket disconnected. Reconnecting."
        }

        return error.localizedDescription
    }

    private static func isSocketClosure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                URLError.cancelled.rawValue,
                URLError.networkConnectionLost.rawValue,
                URLError.notConnectedToInternet.rawValue,
                URLError.cannotConnectToHost.rawValue,
                URLError.timedOut.rawValue
            ].contains(nsError.code)
        }

        if nsError.domain == NSPOSIXErrorDomain {
            return [
                Int(ENOTCONN),
                Int(ECONNRESET),
                Int(EPIPE),
                Int(ETIMEDOUT)
            ].contains(nsError.code)
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("socket is not connected")
    }

    private static func isConnectionLimit(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("connection limit exceeded")
    }

    private static func retryDelay(retryAttempt: Int, isConnectionLimit: Bool) -> TimeInterval {
        guard isConnectionLimit else {
            return reconnectPolicy.delay(forRetryAttempt: retryAttempt)
        }

        let delay = connectionLimitInitialDelay * pow(2.0, Double(max(0, retryAttempt - 1)))
        return min(connectionLimitMaxDelay, delay)
    }

    private static func sleepBeforeRetry(retryAttempt: Int, isConnectionLimit: Bool) async throws {
        let delay = retryDelay(retryAttempt: retryAttempt, isConnectionLimit: isConnectionLimit)
        guard delay > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func startKeepalive(on webSocket: URLSessionWebSocketTask) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.keepaliveInterval * 1_000_000_000))
                } catch {
                    break
                }

                guard let self, !Task.isCancelled, self.isCurrentWebSocket(webSocket) else {
                    break
                }

                webSocket.sendPing { error in
                    if let error {
                        Self.logger.info("stream ping failed feed=\(self.feed.rawValue, privacy: .public) message=\(error.localizedDescription, privacy: .public)")
                        webSocket.cancel(with: .goingAway, reason: nil)
                    }
                }
            }
        }
    }

    private func isCurrentWebSocket(_ webSocket: URLSessionWebSocketTask) -> Bool {
        lock.lock()
        let isCurrent = self.webSocket === webSocket
        lock.unlock()
        return isCurrent
    }

    private func reconcileSubscriptions() async {
        let missingKeys = missingSubscriptionKeys()
        if !missingKeys.isEmpty {
            await updateSubscription(action: .subscribe, keys: missingKeys)
        }
    }

    private func scheduleIdleDisconnect() {
        lock.lock()
        idleDisconnectTask?.cancel()
        idleDisconnectTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(idleDisconnectDelay * 1_000_000_000))
            } catch {
                return
            }
            stopIfIdle()
        }
        lock.unlock()
    }

    private func stopIfIdle() {
        lock.lock()
        guard observers.isEmpty else {
            lock.unlock()
            return
        }

        let streamTask = task
        let socket = webSocket
        task = nil
        webSocket = nil
        subscribedKeys.removeAll()
        observerIDsByKey.removeAll()
        connectionStatus = .disconnected
        lock.unlock()

        streamTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    func stop() {
        lock.lock()
        let streamTask = task
        let socket = webSocket
        task = nil
        webSocket = nil
        observers.removeAll()
        observerIDsByKey.removeAll()
        subscriptionCounts.removeAll()
        subscribedKeys.removeAll()
        connectionStatus = .disconnected
        idleDisconnectTask?.cancel()
        idleDisconnectTask = nil
        lock.unlock()

        streamTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    private func setWebSocket(_ webSocket: URLSessionWebSocketTask) {
        lock.lock()
        self.webSocket = webSocket
        subscribedKeys.removeAll()
        lock.unlock()
    }

    private func clearWebSocket(_ webSocket: URLSessionWebSocketTask) {
        lock.lock()
        if self.webSocket === webSocket {
            self.webSocket = nil
            subscribedKeys.removeAll()
        }
        lock.unlock()
    }

    private func clearRunState() {
        lock.lock()
        task = nil
        webSocket = nil
        subscribedKeys.removeAll()
        lock.unlock()
    }

    private var currentWebSocket: URLSessionWebSocketTask? {
        lock.lock()
        let currentWebSocket = webSocket
        lock.unlock()
        return currentWebSocket
    }

    private var activeSubscriptionKeys: Set<AlpacaStreamSubscriptionKey> {
        lock.lock()
        let keys = Set(subscriptionCounts.keys)
        lock.unlock()
        return keys
    }

    private var hasObservers: Bool {
        lock.lock()
        let value = !observers.isEmpty
        lock.unlock()
        return value
    }

    private func missingSubscriptionKeys() -> Set<AlpacaStreamSubscriptionKey> {
        lock.lock()
        let keys = Set(subscriptionCounts.keys).subtracting(subscribedKeys)
        lock.unlock()
        return keys
    }

    private func markSubscribed(_ keys: Set<AlpacaStreamSubscriptionKey>) {
        lock.lock()
        subscribedKeys.formUnion(keys)
        lock.unlock()
    }

    private func markUnsubscribed(_ keys: Set<AlpacaStreamSubscriptionKey>) {
        lock.lock()
        subscribedKeys.subtract(keys)
        lock.unlock()
    }

    private func updateSubscribedSymbols(_ subscription: AlpacaRealtimeSubscription) {
        var keys = Set<AlpacaStreamSubscriptionKey>()
        keys.formUnion(subscription.trades.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .trades) })
        keys.formUnion(subscription.quotes.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .quotes) })
        keys.formUnion(subscription.bars.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .bars) })
        keys.formUnion(subscription.updatedBars.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .updatedBars) })
        keys.formUnion(subscription.dailyBars.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .dailyBars) })
        keys.formUnion(subscription.statuses.map { AlpacaStreamSubscriptionKey(symbol: $0, channel: .statuses) })

        lock.lock()
        subscribedKeys = keys
        lock.unlock()
    }

    private func broadcast(_ event: AssetRealtimeEvent) {
        if case .connection(let status) = event {
            lock.lock()
            connectionStatus = status
            let registrations = Array(observers.values)
            lock.unlock()

            registrations.forEach { $0.observer.onNext(event) }
            return
        }

        dispatch(event)
    }

    private func dispatch(_ event: AssetRealtimeEvent) {
        guard let symbol = event.symbol else {
            return
        }

        lock.lock()
        let channel = event.channel
        let key = AlpacaStreamSubscriptionKey(symbol: symbol, channel: channel)
        let registrations = (observerIDsByKey[key] ?? [])
            .compactMap { observers[$0] }
        lock.unlock()

        registrations.forEach { $0.observer.onNext(event) }
    }

    private func waitForSuccessMessage(containing expectedText: String, on webSocket: URLSessionWebSocketTask) async throws {
        while !Task.isCancelled {
            let payloads = try await receivePayloads(on: webSocket)
            for payload in payloads {
                if payload.messageType == "success",
                   payload.message?.localizedCaseInsensitiveContains(expectedText) == true {
                    return
                }

                if payload.messageType == "error" {
                    throw payload.streamError(fallback: "Alpaca stream authentication failed.")
                }
            }
        }

        throw CancellationError()
    }

    private func send<Request: Encodable>(_ request: Request, on webSocket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIClientError.invalidResponse
        }

        try await webSocket.send(.string(text))
    }

    private func receivePayloads(on webSocket: URLSessionWebSocketTask) async throws -> [AlpacaStreamPayload] {
        let message = try await webSocket.receive()
        let data: Data

        switch message {
        case .data(let payload):
            data = payload
        case .string(let text):
            guard let payload = text.data(using: .utf8) else {
                throw APIClientError.invalidResponse
            }
            data = payload
        @unknown default:
            throw APIClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        do {
            if let payloads = try? decoder.decode([AlpacaStreamPayload].self, from: data) {
                return payloads
            }

            return [try decoder.decode(AlpacaStreamPayload.self, from: data)]
        } catch {
            let payloadPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<binary>"
            Self.logger.error("stream decode failed feed=\(self.feed.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) payload=\(String(payloadPreview), privacy: .public)")
            throw error
        }
    }
}

struct NoopAlpacaStockStreamClient: AlpacaStockStreaming {
    func stream(
        symbol: String,
        feed: AlpacaMarketDataFeed,
        channels: Set<AlpacaRealtimeChannel>,
        credentials: AlpacaCredentials
    ) -> Observable<AssetRealtimeEvent> {
        Observable.just(.connection(.disconnected))
    }

    func reset(credentials: AlpacaCredentials?) {}
}

private struct AlpacaStreamAuthRequest: Encodable {
    let action = "auth"
    let key: String
    let secret: String
}

private enum AlpacaStreamSubscriptionAction: String, Encodable {
    case subscribe
    case unsubscribe
}

private struct AlpacaStreamSubscriptionRequest: Encodable {
    let action: AlpacaStreamSubscriptionAction
    let trades: [String]
    let quotes: [String]
    let bars: [String]
    let updatedBars: [String]
    let dailyBars: [String]
    let statuses: [String]

    init(action: AlpacaStreamSubscriptionAction, keys: Set<AlpacaStreamSubscriptionKey>) {
        self.action = action
        trades = Self.symbols(for: .trades, in: keys)
        quotes = Self.symbols(for: .quotes, in: keys)
        bars = Self.symbols(for: .bars, in: keys)
        updatedBars = Self.symbols(for: .updatedBars, in: keys)
        dailyBars = Self.symbols(for: .dailyBars, in: keys)
        statuses = Self.symbols(for: .statuses, in: keys)
    }

    private static func symbols(
        for channel: AlpacaRealtimeChannel,
        in keys: Set<AlpacaStreamSubscriptionKey>
    ) -> [String] {
        keys
            .filter { $0.channel == channel }
            .map(\.symbol)
            .sorted()
    }
}

private struct AlpacaStreamFatalError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct AlpacaStreamRecoverableError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct AlpacaStreamPayload: Decodable {
    let messageType: String
    let code: Int?
    let message: String?
    let symbol: String?
    let askExchange: String?
    let askPrice: Double?
    let askSize: Double?
    let bidExchange: String?
    let bidPrice: Double?
    let bidSize: Double?
    let exchange: String?
    let price: Double?
    let size: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?
    let vwap: Double?
    let tradeCount: Double?
    let conditions: [String]?
    let timestamp: String?
    let tape: String?
    let statusCode: String?
    let statusMessage: String?
    let reasonCode: String?
    let reasonMessage: String?
    let subscription: AlpacaRealtimeSubscription?

    func streamError(fallback: String) -> Error {
        let errorMessage = message ?? fallback
        if code == 406 || errorMessage.localizedCaseInsensitiveContains("connection limit exceeded") {
            return AlpacaStreamRecoverableError(message: errorMessage)
        }

        return AlpacaStreamFatalError(message: errorMessage)
    }

    var event: AssetRealtimeEvent? {
        switch messageType {
        case "t":
            guard let symbol else { return nil }
            return .trade(AlpacaRealtimeTrade(
                symbol: symbol,
                price: price,
                size: size,
                exchange: exchange,
                timestamp: timestamp,
                conditions: conditions,
                tape: tape
            ))
        case "q":
            guard let symbol else { return nil }
            return .quote(AlpacaRealtimeQuote(
                symbol: symbol,
                askExchange: askExchange,
                askPrice: askPrice,
                askSize: askSize,
                bidExchange: bidExchange,
                bidPrice: bidPrice,
                bidSize: bidSize,
                conditions: conditions,
                timestamp: timestamp,
                tape: tape
            ))
        case "b":
            guard let bar else { return nil }
            return .minuteBar(bar)
        case "u":
            guard let bar else { return nil }
            return .updatedBar(bar)
        case "d":
            guard let bar else { return nil }
            return .dailyBar(bar)
        case "s":
            guard let symbol else { return nil }
            return .status(AlpacaRealtimeTradingStatus(
                symbol: symbol,
                statusCode: statusCode,
                statusMessage: statusMessage,
                reasonCode: reasonCode,
                reasonMessage: reasonMessage,
                timestamp: timestamp,
                tape: tape
            ))
        default:
            return nil
        }
    }

    private var bar: AlpacaRealtimeBar? {
        guard let symbol else {
            return nil
        }

        return AlpacaRealtimeBar(
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            vwap: vwap,
            tradeCount: tradeCount,
            timestamp: timestamp
        )
    }

    enum CodingKeys: String, CodingKey {
        case messageType = "T"
        case code
        case message = "msg"
        case symbol = "S"
        case askExchange = "ax"
        case askPrice = "ap"
        case askSize = "as"
        case bidExchange = "bx"
        case bidPrice = "bp"
        case bidSize = "bs"
        case exchange = "x"
        case price = "p"
        case size = "s"
        case open = "o"
        case high = "h"
        case low = "l"
        case c = "c"
        case volume = "v"
        case vwap = "vw"
        case tradeCount = "n"
        case timestamp = "t"
        case tape = "z"
        case statusCode = "sc"
        case statusMessage = "sm"
        case reasonCode = "rc"
        case reasonMessage = "rm"
        case trades
        case quotes
        case bars
        case updatedBars
        case dailyBars
        case statuses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageType = try container.decode(String.self, forKey: .messageType)
        code = try container.decodeIfPresent(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        askExchange = try container.decodeIfPresent(String.self, forKey: .askExchange)
        askPrice = try container.decodeIfPresent(Double.self, forKey: .askPrice)
        askSize = try container.decodeIfPresent(Double.self, forKey: .askSize)
        bidExchange = try container.decodeIfPresent(String.self, forKey: .bidExchange)
        bidPrice = try container.decodeIfPresent(Double.self, forKey: .bidPrice)
        bidSize = try container.decodeIfPresent(Double.self, forKey: .bidSize)
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
        open = try container.decodeIfPresent(Double.self, forKey: .open)
        high = try container.decodeIfPresent(Double.self, forKey: .high)
        low = try container.decodeIfPresent(Double.self, forKey: .low)
        if messageType == "b" || messageType == "u" || messageType == "d" {
            close = try container.decodeIfPresent(Double.self, forKey: .c)
            conditions = nil
        } else {
            close = nil
            conditions = try container.decodeIfPresent([String].self, forKey: .c)
        }
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        vwap = try container.decodeIfPresent(Double.self, forKey: .vwap)
        tradeCount = try container.decodeIfPresent(Double.self, forKey: .tradeCount)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        tape = try container.decodeIfPresent(String.self, forKey: .tape)
        statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage)
        reasonCode = try container.decodeIfPresent(String.self, forKey: .reasonCode)
        reasonMessage = try container.decodeIfPresent(String.self, forKey: .reasonMessage)

        if messageType == "subscription" {
            subscription = AlpacaRealtimeSubscription(
                trades: try container.decodeIfPresent([String].self, forKey: .trades) ?? [],
                quotes: try container.decodeIfPresent([String].self, forKey: .quotes) ?? [],
                bars: try container.decodeIfPresent([String].self, forKey: .bars) ?? [],
                updatedBars: try container.decodeIfPresent([String].self, forKey: .updatedBars) ?? [],
                dailyBars: try container.decodeIfPresent([String].self, forKey: .dailyBars) ?? [],
                statuses: try container.decodeIfPresent([String].self, forKey: .statuses) ?? []
            )
        } else {
            subscription = nil
        }
    }
}

private extension AlpacaRealtimeSubscription {
    var summary: String {
        [
            trades.isEmpty ? nil : "trades",
            quotes.isEmpty ? nil : "quotes",
            bars.isEmpty ? nil : "bars",
            updatedBars.isEmpty ? nil : "updatedBars",
            dailyBars.isEmpty ? nil : "dailyBars",
            statuses.isEmpty ? nil : "statuses"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private extension AssetRealtimeEvent {
    var symbol: String? {
        switch self {
        case .connection:
            nil
        case .trade(let trade):
            trade.symbol
        case .quote(let quote):
            quote.symbol
        case .minuteBar(let bar), .updatedBar(let bar), .dailyBar(let bar):
            bar.symbol
        case .status(let status):
            status.symbol
        }
    }

    var channel: AlpacaRealtimeChannel {
        switch self {
        case .connection:
            .statuses
        case .trade:
            .trades
        case .quote:
            .quotes
        case .minuteBar:
            .bars
        case .updatedBar:
            .updatedBars
        case .dailyBar:
            .dailyBars
        case .status:
            .statuses
        }
    }
}

extension URLSessionConfiguration {
    static var vicuWebSocket: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60 * 60 * 24
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}
