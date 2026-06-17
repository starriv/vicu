import Foundation
import RxSwift

@MainActor
final class HomeAccountPolling {
    private let refreshTrigger = PublishSubject<Void>()
    private var disposeBag = DisposeBag()
    private var isRunning = false

    func start(app: AppModel) {
        guard !isRunning else {
            return
        }

        isRunning = true
        RxPolling.stream(
            interval: .seconds(30),
            manualTrigger: refreshTrigger.asObservable()
        ) {
            try await app.fetchAccountDetails()
        }
        .observe(on: MainScheduler.instance)
        .subscribe(onNext: { event in
            switch event {
            case .loading:
                app.portfolio.isRefreshing = true
            case .value:
                app.portfolio.isRefreshing = false
                app.lastError = nil
            case .failure(let error):
                app.portfolio.isRefreshing = false
                app.lastError = error.localizedDescription
            }
        })
        .disposed(by: disposeBag)
    }

    func refreshNow() {
        refreshTrigger.onNext(())
    }

    func stop() {
        disposeBag = DisposeBag()
        isRunning = false
    }
}
