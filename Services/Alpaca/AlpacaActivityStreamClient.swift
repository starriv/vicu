import Foundation
import OSLog
import RxSwift

protocol AlpacaActivityStreaming: Sendable {
    func streamActivities(
        credentials: AlpacaCredentials,
        sinceID: String?
    ) -> Observable<AlpacaActivityEvent>
}

protocol AlpacaTradeEventStreaming: Sendable {
    func streamTradeEvents(
        credentials: AlpacaCredentials,
        sinceID: String?
    ) -> Observable<AlpacaTradeEvent>
}

final class AlpacaActivityStreamClient: AlpacaActivityStreaming, @unchecked Sendable {
    static let shared = AlpacaActivityStreamClient()

    private static let logger = Logger(subsystem: "com.starriv.vicu", category: "AlpacaActivityStream")

    private let session: URLSession
    private let activityPath: String

    init(
        session: URLSession = URLSession(configuration: .vicuEventStream),
        activityPath: String = "v2beta1/events/activities"
    ) {
        self.session = session
        self.activityPath = activityPath
    }

    func streamActivities(
        credentials: AlpacaCredentials,
        sinceID: String? = nil
    ) -> Observable<AlpacaActivityEvent> {
        Observable.create { observer in
            let sink = AlpacaActivityEventObserver(observer)
            let task = Task {
                var nextSinceID = sinceID
                var retryAttempt = 0

                while !Task.isCancelled {
                    do {
                        try await self.streamOnce(credentials: credentials, sinceID: nextSinceID) { event in
                            sink.onNext(event)
                            nextSinceID = event.eventID
                            retryAttempt = 0
                        }

                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch is CancellationError {
                        break
                    } catch let error as APIClientError where error.statusCode == 401 || error.statusCode == 403 {
                        sink.onError(error)
                        return
                    } catch {
                        retryAttempt += 1
                        let message = error.localizedDescription
                        Self.logger.warning("activity stream interrupted environment=\(credentials.environment.rawValue, privacy: .public) attempt=\(retryAttempt, privacy: .public) message=\(message, privacy: .public)")
                        let delay = min(pow(2.0, Double(retryAttempt)), 30.0)

                        do {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } catch {
                            break
                        }
                    }
                }

                sink.onCompleted()
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }

    private func streamOnce(
        credentials: AlpacaCredentials,
        sinceID: String?,
        onEvent: (AlpacaActivityEvent) -> Void
    ) async throws {
        let request = try makeRequest(credentials: credentials, sinceID: sinceID)
        Self.logger.info("activity stream connect environment=\(credentials.environment.rawValue, privacy: .public) sinceID=\(sinceID ?? "none", privacy: .public)")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        var parser = ServerSentEventParser()
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()

            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard let message = try parser.consume(line: line) else {
                continue
            }

            do {
                let event = try decodeEvent(from: message)
                onEvent(event)
            } catch {
                continue
            }
        }

        if let message = parser.finishPendingEvent() {
            if let event = try? decodeEvent(from: message) {
                onEvent(event)
            }
        }
    }

    private func makeRequest(credentials: AlpacaCredentials, sinceID: String?) throws -> URLRequest {
        let url = credentials.environment.baseURL.appendingPathComponent(activityPath)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if let sinceID = sinceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sinceID.isEmpty {
            components?.queryItems = [
                URLQueryItem(name: "since_id", value: sinceID)
            ]
        }

        guard let streamURL = components?.url else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(
            url: streamURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: URLSessionConfiguration.vicuEventStream.timeoutIntervalForRequest
        )
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(credentials.keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }

    private func decodeEvent(from message: ServerSentEventMessage) throws -> AlpacaActivityEvent {
        guard let data = message.data.data(using: .utf8) else {
            throw APIClientError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(AlpacaActivityEvent.self, from: data)
        } catch {
            let payloadPreview = String(message.data.prefix(500))
            Self.logger.error("activity stream decode failed event=\(message.event ?? "message", privacy: .public) error=\(error.localizedDescription, privacy: .public) payload=\(payloadPreview, privacy: .public)")
            throw APIClientError.decodingFailed(
                type: String(describing: AlpacaActivityEvent.self),
                message: error.localizedDescription
            )
        }
    }
}

final class AlpacaTradeEventStreamClient: AlpacaTradeEventStreaming, @unchecked Sendable {
    static let shared = AlpacaTradeEventStreamClient()

    private static let logger = Logger(subsystem: "com.starriv.vicu", category: "AlpacaTradeEventStream")

    private let session: URLSession
    private let tradeEventPath: String

    init(
        session: URLSession = URLSession(configuration: .vicuEventStream),
        tradeEventPath: String = "v2beta1/events/trades"
    ) {
        self.session = session
        self.tradeEventPath = tradeEventPath
    }

    func streamTradeEvents(
        credentials: AlpacaCredentials,
        sinceID: String? = nil
    ) -> Observable<AlpacaTradeEvent> {
        Observable.create { observer in
            let sink = AlpacaTradeEventObserver(observer)
            let task = Task {
                var nextSinceID = sinceID
                var retryAttempt = 0

                while !Task.isCancelled {
                    do {
                        try await self.streamOnce(credentials: credentials, sinceID: nextSinceID) { event in
                            sink.onNext(event)
                            nextSinceID = event.cursorID
                            retryAttempt = 0
                        }

                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch is CancellationError {
                        break
                    } catch let error as APIClientError where error.statusCode == 401 || error.statusCode == 403 {
                        sink.onError(error)
                        return
                    } catch {
                        retryAttempt += 1
                        let message = error.localizedDescription
                        Self.logger.warning("trade event stream interrupted environment=\(credentials.environment.rawValue, privacy: .public) attempt=\(retryAttempt, privacy: .public) message=\(message, privacy: .public)")
                        let delay = min(pow(2.0, Double(retryAttempt)), 30.0)

                        do {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } catch {
                            break
                        }
                    }
                }

                sink.onCompleted()
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }

    private func streamOnce(
        credentials: AlpacaCredentials,
        sinceID: String?,
        onEvent: (AlpacaTradeEvent) -> Void
    ) async throws {
        let request = try makeRequest(credentials: credentials, sinceID: sinceID)
        Self.logger.info("trade event stream connect environment=\(credentials.environment.rawValue, privacy: .public) sinceID=\(sinceID ?? "none", privacy: .public)")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        var parser = ServerSentEventParser()
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()

            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard let message = try parser.consume(line: line) else {
                continue
            }

            do {
                let event = try decodeEvent(from: message)
                onEvent(event)
            } catch {
                continue
            }
        }

        if let message = parser.finishPendingEvent() {
            if let event = try? decodeEvent(from: message) {
                onEvent(event)
            }
        }
    }

    private func makeRequest(credentials: AlpacaCredentials, sinceID: String?) throws -> URLRequest {
        let url = credentials.environment.baseURL.appendingPathComponent(tradeEventPath)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if let sinceID = sinceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sinceID.isEmpty {
            components?.queryItems = [
                URLQueryItem(name: "since_id", value: sinceID)
            ]
        }

        guard let streamURL = components?.url else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(
            url: streamURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: URLSessionConfiguration.vicuEventStream.timeoutIntervalForRequest
        )
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(credentials.keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }

    private func decodeEvent(from message: ServerSentEventMessage) throws -> AlpacaTradeEvent {
        guard let data = message.data.data(using: .utf8) else {
            throw APIClientError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(AlpacaTradeEvent.self, from: data)
        } catch {
            let payloadPreview = String(message.data.prefix(500))
            Self.logger.error("trade event stream decode failed event=\(message.event ?? "message", privacy: .public) error=\(error.localizedDescription, privacy: .public) payload=\(payloadPreview, privacy: .public)")
            throw APIClientError.decodingFailed(
                type: String(describing: AlpacaTradeEvent.self),
                message: error.localizedDescription
            )
        }
    }
}

private final class AlpacaActivityEventObserver: @unchecked Sendable {
    private let observer: AnyObserver<AlpacaActivityEvent>

    init(_ observer: AnyObserver<AlpacaActivityEvent>) {
        self.observer = observer
    }

    func onNext(_ event: AlpacaActivityEvent) {
        observer.onNext(event)
    }

    func onError(_ error: Error) {
        observer.onError(error)
    }

    func onCompleted() {
        observer.onCompleted()
    }
}

private final class AlpacaTradeEventObserver: @unchecked Sendable {
    private let observer: AnyObserver<AlpacaTradeEvent>

    init(_ observer: AnyObserver<AlpacaTradeEvent>) {
        self.observer = observer
    }

    func onNext(_ event: AlpacaTradeEvent) {
        observer.onNext(event)
    }

    func onError(_ error: Error) {
        observer.onError(error)
    }

    func onCompleted() {
        observer.onCompleted()
    }
}

struct AlpacaActivityEvent: Decodable, Identifiable, Equatable, Sendable {
    let accountID: String
    let at: String?
    let eventID: String
    let activityType: String
    let activitySubtype: String?
    let refID: String
    let status: String?
    let executedAt: String?
    let settleDate: String?
    let quantity: String?
    let price: String?
    let netAmount: String?
    let currency: String?
    let swapRate: String?
    let swapFeeBps: String?
    let previousID: String?
    let details: [String: AlpacaActivityDetailsValue]

    var id: String { eventID }

    var symbol: String? {
        detailsString("symbol")
            ?? detailsString("new_symbol")
            ?? detailsString("old_symbol")
            ?? detailsString("underlying_symbol")
    }

    var side: String? {
        detailsString("side")
    }

    var orderID: String? {
        detailsString("order_id")
    }

    var executionType: String? {
        detailsString("execution_type")
    }

    var occurredAt: Date? {
        AlpacaDateParser.date(executedAt) ?? AlpacaDateParser.date(at) ?? AlpacaDateParser.date(settleDate)
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case at
        case eventID = "event_id"
        case activityType = "activity_type"
        case activitySubtype = "activity_subtype"
        case refID = "ref_id"
        case status
        case executedAt = "executed_at"
        case settleDate = "settle_date"
        case quantity = "qty"
        case price
        case netAmount = "net_amount"
        case currency
        case swapRate = "swap_rate"
        case swapFeeBps = "swap_fee_bps"
        case previousID = "previous_id"
        case details
    }

    private func detailsString(_ key: String) -> String? {
        guard let value = details[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

struct AlpacaTradeEvent: Decodable, Identifiable, Equatable, Sendable {
    let accountID: String?
    let at: String?
    let eventID: String?
    let eventULID: String?
    let event: String
    let timestamp: String?
    let order: AlpacaOrder
    let price: String?
    let quantity: String?
    let positionQuantity: String?
    let executionID: String?
    let previousExecutionID: String?

    var id: String {
        cursorID ?? [normalizedEvent, order.id, timestamp ?? at ?? ""].joined(separator: ":")
    }

    var cursorID: String? {
        eventULID ?? eventID
    }

    static func == (lhs: AlpacaTradeEvent, rhs: AlpacaTradeEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.normalizedEvent == rhs.normalizedEvent
            && lhs.order.id == rhs.order.id
    }

    var normalizedEvent: String {
        event.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case at
        case eventID = "event_id"
        case eventULID = "event_ulid"
        case event
        case timestamp
        case order
        case price
        case quantity = "qty"
        case positionQuantity = "position_qty"
        case executionID = "execution_id"
        case previousExecutionID = "previous_execution_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decodeFlexibleStringIfPresent(forKey: .accountID)
        at = try container.decodeFlexibleStringIfPresent(forKey: .at)
        eventID = try container.decodeFlexibleStringIfPresent(forKey: .eventID)
        eventULID = try container.decodeFlexibleStringIfPresent(forKey: .eventULID)
        event = try container.decode(String.self, forKey: .event)
        timestamp = try container.decodeFlexibleStringIfPresent(forKey: .timestamp)
        order = try container.decode(AlpacaOrder.self, forKey: .order)
        price = try container.decodeFlexibleStringIfPresent(forKey: .price)
        quantity = try container.decodeFlexibleStringIfPresent(forKey: .quantity)
        positionQuantity = try container.decodeFlexibleStringIfPresent(forKey: .positionQuantity)
        executionID = try container.decodeFlexibleStringIfPresent(forKey: .executionID)
        previousExecutionID = try container.decodeFlexibleStringIfPresent(forKey: .previousExecutionID)
    }
}

enum AlpacaActivityDetailsValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AlpacaActivityDetailsValue])
    case array([AlpacaActivityDetailsValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .object, .array, .null:
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: AlpacaActivityDetailsValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AlpacaActivityDetailsValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported activity details value."
            )
        }
    }
}

struct NoopAlpacaActivityStreamClient: AlpacaActivityStreaming {
    func streamActivities(
        credentials: AlpacaCredentials,
        sinceID: String?
    ) -> Observable<AlpacaActivityEvent> {
        Observable.empty()
    }
}

struct NoopAlpacaTradeEventStreamClient: AlpacaTradeEventStreaming {
    func streamTradeEvents(
        credentials: AlpacaCredentials,
        sinceID: String?
    ) -> Observable<AlpacaTradeEvent> {
        Observable.empty()
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }

        if let value = try? decode(String.self, forKey: key) {
            return value
        }

        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}

private struct ServerSentEventMessage {
    let event: String?
    let id: String?
    let data: String
}

private struct ServerSentEventParser {
    private var event: String?
    private var id: String?
    private var dataLines: [String] = []

    mutating func consume(line rawLine: String) throws -> ServerSentEventMessage? {
        guard !rawLine.isEmpty else {
            return finishPendingEvent()
        }

        if rawLine.hasPrefix(":") {
            try handleComment(String(rawLine.dropFirst()))
            return nil
        }

        let parts = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.first == " " {
            value.removeFirst()
        }

        switch field {
        case "event":
            event = value
        case "id":
            id = value
        case "data":
            dataLines.append(value)
        default:
            break
        }

        return nil
    }

    mutating func finishPendingEvent() -> ServerSentEventMessage? {
        defer {
            event = nil
            dataLines.removeAll(keepingCapacity: true)
        }

        guard !dataLines.isEmpty else {
            return nil
        }

        return ServerSentEventMessage(
            event: event,
            id: id,
            data: dataLines.joined(separator: "\n")
        )
    }

    private func handleComment(_ comment: String) throws {
        let normalized = comment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return
        }

        if normalized.contains("internal server error") || normalized.contains("dropped") {
            throw AlpacaActivityStreamRecoverableError(message: comment.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private struct AlpacaActivityStreamRecoverableError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

extension URLSessionConfiguration {
    static var vicuEventStream: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}
