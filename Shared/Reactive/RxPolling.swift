import Foundation
import RxSwift

enum RxPollingEvent<Value> {
    case loading
    case value(Value)
    case failure(Error)
}

private final class RxPollingObserverBox<Value: Sendable>: @unchecked Sendable {
    private let observer: AnyObserver<RxPollingEvent<Value>>

    init(_ observer: AnyObserver<RxPollingEvent<Value>>) {
        self.observer = observer
    }

    @MainActor
    func onNext(_ event: RxPollingEvent<Value>) {
        observer.onNext(event)
    }
}

@MainActor
enum RxPolling {
    static func stream<Value: Sendable>(
        interval: RxTimeInterval,
        scheduler: SchedulerType = MainScheduler.instance,
        startsImmediately: Bool = true,
        manualTrigger: Observable<Void> = .empty(),
        operation: @MainActor @Sendable @escaping () async throws -> Value
    ) -> Observable<RxPollingEvent<Value>> {
        let automaticTrigger: Observable<Void>
        if startsImmediately {
            automaticTrigger = Observable<Int>
                .timer(.seconds(0), period: interval, scheduler: scheduler)
                .map { _ in () }
        } else {
            automaticTrigger = Observable<Int>
                .interval(interval, scheduler: scheduler)
                .map { _ in () }
        }

        return Observable
            .merge(automaticTrigger, manualTrigger)
            .flatMapLatest { _ in
                asyncOperation(operation)
            }
            .share(replay: 1, scope: .whileConnected)
    }

    private static func asyncOperation<Value: Sendable>(
        _ operation: @MainActor @Sendable @escaping () async throws -> Value
    ) -> Observable<RxPollingEvent<Value>> {
        Observable.create { observer in
            let observerBox = RxPollingObserverBox(observer)
            observerBox.onNext(.loading)

            let task = Task { @MainActor [operation, observerBox] in
                do {
                    let value = try await operation()
                    try Task.checkCancellation()
                    observerBox.onNext(.value(value))
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    observerBox.onNext(.failure(error))
                }
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }
}
