import Foundation

actor NetworkRateLimiter {
    private let minimumSpacingNanoseconds: UInt64
    private var nextAllowedUptimeNanoseconds: UInt64 = 0

    init(maxRequests: Int, per interval: TimeInterval) {
        precondition(maxRequests > 0, "maxRequests must be greater than 0.")
        precondition(interval >= 0, "interval must be greater than or equal to 0.")

        let spacing = interval / Double(maxRequests)
        self.minimumSpacingNanoseconds = UInt64(max(0, spacing) * 1_000_000_000)
    }

    init(minimumSpacing: TimeInterval) {
        precondition(minimumSpacing >= 0, "minimumSpacing must be greater than or equal to 0.")
        self.minimumSpacingNanoseconds = UInt64(minimumSpacing * 1_000_000_000)
    }

    func waitForPermit() async throws {
        guard minimumSpacingNanoseconds > 0 else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let scheduled = max(now, nextAllowedUptimeNanoseconds)
        nextAllowedUptimeNanoseconds = scheduled + minimumSpacingNanoseconds

        let delay = scheduled > now ? scheduled - now : 0
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
    }

    func reset() {
        nextAllowedUptimeNanoseconds = 0
    }
}

struct NetworkRateLimitInterceptor: APIRequestInterceptor {
    private let limiter: NetworkRateLimiter

    init(limiter: NetworkRateLimiter) {
        self.limiter = limiter
    }

    init(maxRequests: Int, per interval: TimeInterval) {
        self.limiter = NetworkRateLimiter(maxRequests: maxRequests, per: interval)
    }

    init(minimumSpacing: TimeInterval) {
        self.limiter = NetworkRateLimiter(minimumSpacing: minimumSpacing)
    }

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        try await limiter.waitForPermit()
        return request
    }
}

// Wraps an async operation with retry semantics on top of the HTTP-layer retry
// already built into APIRequest. Use when a page service composes multiple API
// calls and you want the whole composed operation to retry on transient failure:
//
//   let retry = ServiceRetryMiddleware(retryPolicy: .alpacaGET)
//   return try await retry.run { try await fetchOverview(credentials: credentials) }
//
// For RxSwift callers, pass it to ServiceRx.single(retry:operation:).
struct ServiceRetryMiddleware: Sendable {
    private let retryPolicy: NetworkRetryPolicy
    private let method: HTTPMethod
    private let errorHandler: any APIErrorHandling

    init(
        retryPolicy: NetworkRetryPolicy,
        method: HTTPMethod = .get,
        errorHandler: any APIErrorHandling = DefaultAPIErrorHandler()
    ) {
        self.retryPolicy = retryPolicy
        self.method = method
        self.errorHandler = errorHandler
    }

    func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        var retryAttempt = 0

        while true {
            do {
                return try await operation()
            } catch is CancellationError {
                throw APIClientError.cancelled
            } catch {
                let apiError = errorHandler.map(error)
                retryAttempt += 1

                guard retryPolicy.shouldRetry(
                    apiError,
                    method: method,
                    retryAttempt: retryAttempt
                ) else {
                    throw apiError
                }

                try await retryPolicy.sleepBeforeRetry(retryAttempt)
            }
        }
    }
}

// Provides graceful degradation when a service call fails. Supply a cached-value
// producer as the fallback so the UI can show stale data rather than an error:
//
//   let fallback = ServiceFallbackPolicy<MarketOverview>.cachedValue { cachedOverview }
//   return try await fallback.run { try await alpaca.fetchMarketOverview(credentials: credentials) }
struct ServiceFallbackPolicy<Value: Sendable>: Sendable {
    private let shouldFallback: @Sendable (APIClientError) -> Bool
    private let fallback: @Sendable (APIClientError) async throws -> Value
    private let errorHandler: any APIErrorHandling

    init(
        when shouldFallback: @escaping @Sendable (APIClientError) -> Bool = ServiceFallbackPolicy.isRecoverable,
        errorHandler: any APIErrorHandling = DefaultAPIErrorHandler(),
        fallback: @escaping @Sendable (APIClientError) async throws -> Value
    ) {
        self.shouldFallback = shouldFallback
        self.errorHandler = errorHandler
        self.fallback = fallback
    }

    func run(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch is CancellationError {
            throw APIClientError.cancelled
        } catch {
            let apiError = errorHandler.map(error)
            guard shouldFallback(apiError) else {
                throw apiError
            }

            return try await fallback(apiError)
        }
    }

    static func cachedValue(
        when shouldFallback: @escaping @Sendable (APIClientError) -> Bool = ServiceFallbackPolicy.isRecoverable,
        _ value: @escaping @Sendable () async throws -> Value
    ) -> ServiceFallbackPolicy<Value> {
        ServiceFallbackPolicy(when: shouldFallback) { _ in
            try await value()
        }
    }

    private static func isRecoverable(_ error: APIClientError) -> Bool {
        switch error {
        case .transport:
            return true
        case .requestFailed(let statusCode, _):
            return [408, 425, 429, 500, 502, 503, 504].contains(statusCode)
        case .invalidURL, .invalidResponse, .emptyResponse, .cancelled, .decodingFailed, .underlying:
            return false
        }
    }
}
