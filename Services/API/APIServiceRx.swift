import Foundation
import RxSwift

private final class ServiceRxSingleEmitter<Value: Sendable>: @unchecked Sendable {
    private let single: (SingleEvent<Value>) -> Void

    init(_ single: @escaping (SingleEvent<Value>) -> Void) {
        self.single = single
    }

    func emit(_ event: SingleEvent<Value>) {
        single(event)
    }
}

enum ServiceRx {
    static func single<Value: Sendable>(
        retry retryMiddleware: ServiceRetryMiddleware? = nil,
        fallback fallbackPolicy: ServiceFallbackPolicy<Value>? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) -> Single<Value> {
        single {
            let request: @Sendable () async throws -> Value = {
                if let retryMiddleware {
                    return try await retryMiddleware.run(operation)
                }

                return try await operation()
            }

            if let fallbackPolicy {
                return try await fallbackPolicy.run(request)
            }

            return try await request()
        }
    }

    static func single<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> Single<Value> {
        Single.create { single in
            let emitter = ServiceRxSingleEmitter(single)
            let task = Task {
                do {
                    let value = try await operation()
                    try Task.checkCancellation()
                    emitter.emit(.success(value))
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    emitter.emit(.failure(error))
                }
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }

    static func observable<Value: Sendable>(
        retry retryMiddleware: ServiceRetryMiddleware? = nil,
        fallback fallbackPolicy: ServiceFallbackPolicy<Value>? = nil,
        operation: @escaping @Sendable () async throws -> Value
    ) -> Observable<Value> {
        single(
            retry: retryMiddleware,
            fallback: fallbackPolicy,
            operation: operation
        )
        .asObservable()
    }
}
