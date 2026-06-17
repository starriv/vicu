import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let baseURL: URL
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?
    let cachePolicy: URLRequest.CachePolicy
    let timeoutInterval: TimeInterval?
    let retryPolicy: NetworkRetryPolicy
    let requestInterceptors: [any APIRequestInterceptor]
    let responseInterceptors: [any APIResponseInterceptor]

    init(
        baseURL: URL,
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        timeoutInterval: TimeInterval? = nil,
        retryPolicy: NetworkRetryPolicy = .none,
        requestInterceptors: [any APIRequestInterceptor] = [],
        responseInterceptors: [any APIResponseInterceptor] = []
    ) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
    }
}

struct EmptyAPIResponse: Decodable, Sendable {}

struct NetworkRetryPolicy: Equatable, Sendable {
    let maxRetryCount: Int?
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    let requiresGET: Bool
    let retryableStatusCodes: Set<Int>
    let retryableURLErrorCodes: Set<URLError.Code>
    let retriesInvalidResponse: Bool

    static let none = NetworkRetryPolicy(
        maxRetryCount: 0,
        initialDelay: 0,
        maxDelay: 0,
        multiplier: 1,
        requiresGET: false,
        retryableStatusCodes: [],
        retryableURLErrorCodes: [],
        retriesInvalidResponse: false
    )

    static let marketDataGET = NetworkRetryPolicy(
        maxRetryCount: 2,
        initialDelay: 0.35,
        maxDelay: 2,
        multiplier: 2,
        requiresGET: true,
        retryableStatusCodes: [408, 425, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: [
            .timedOut,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ],
        retriesInvalidResponse: false
    )

    static let alpacaGET = NetworkRetryPolicy(
        maxRetryCount: 1,
        initialDelay: 0.3,
        maxDelay: 1.5,
        multiplier: 2,
        requiresGET: true,
        retryableStatusCodes: [408, 425, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: [
            .timedOut,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ],
        retriesInvalidResponse: false
    )

    static let realtimeStream = NetworkRetryPolicy(
        maxRetryCount: nil,
        initialDelay: 2,
        maxDelay: 30,
        multiplier: 2,
        requiresGET: false,
        retryableStatusCodes: [],
        retryableURLErrorCodes: [],
        retriesInvalidResponse: false
    )

    func shouldRetry(
        _ error: APIClientError,
        method: HTTPMethod,
        retryAttempt: Int
    ) -> Bool {
        guard retryAttempt > 0, allowsRetry(retryAttempt: retryAttempt) else {
            return false
        }

        if requiresGET, method != .get {
            return false
        }

        switch error {
        case .cancelled, .invalidURL, .emptyResponse, .decodingFailed, .underlying:
            return false
        case .invalidResponse:
            return retriesInvalidResponse
        case .transport(let error):
            return retryableURLErrorCodes.contains(error.code)
        case .requestFailed(let statusCode, _):
            return retryableStatusCodes.contains(statusCode)
        }
    }

    func delay(forRetryAttempt retryAttempt: Int) -> TimeInterval {
        guard retryAttempt > 0 else {
            return 0
        }

        let delay = initialDelay * pow(multiplier, Double(retryAttempt - 1))
        return min(maxDelay, delay)
    }

    func sleepBeforeRetry(_ retryAttempt: Int) async throws {
        let delay = delay(forRetryAttempt: retryAttempt)
        guard delay > 0 else {
            return
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func allowsRetry(retryAttempt: Int) -> Bool {
        guard let maxRetryCount else {
            return true
        }

        return retryAttempt <= maxRetryCount
    }
}
