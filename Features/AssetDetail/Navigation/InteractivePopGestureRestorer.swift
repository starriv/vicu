import SwiftUI
import UIKit

extension View {
    func restoreInteractivePopGesture() -> some View {
        background {
            InteractivePopGestureRestorer()
                .frame(width: 0, height: 0)
        }
    }
}

private struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> RestorerViewController {
        let controller = RestorerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: RestorerViewController, context: Context) {
        controller.coordinator = context.coordinator
        controller.restoreInteractivePopGestureIfNeeded()
    }

    static func dismantleUIViewController(_ controller: RestorerViewController, coordinator: Coordinator) {
        coordinator.detach(from: controller.navigationController)
    }

    final class RestorerViewController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            restoreInteractivePopGestureIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreInteractivePopGestureIfNeeded()
        }

        func restoreInteractivePopGestureIfNeeded() {
            if let navigationController,
               coordinator?.isAttached(to: navigationController) == true {
                return
            }

            Task { @MainActor [weak self] in
                self?.coordinator?.attach(to: self?.navigationController)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?
        private weak var originalDelegate: UIGestureRecognizerDelegate?
        private var originalIsEnabled: Bool?

        func isAttached(to navigationController: UINavigationController) -> Bool {
            guard self.navigationController === navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                return false
            }

            let expectedEnabled = navigationController.viewControllers.count > 1
            return gesture.delegate === self && gesture.isEnabled == expectedEnabled
        }

        func attach(to navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                return
            }

            if self.navigationController !== navigationController {
                detach(from: self.navigationController)
                self.navigationController = navigationController
                originalDelegate = gesture.delegate
                originalIsEnabled = gesture.isEnabled
            }

            gesture.delegate = self
            gesture.isEnabled = navigationController.viewControllers.count > 1
        }

        func detach(from navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer else {
                clear()
                return
            }

            if gesture.delegate === self {
                gesture.delegate = originalDelegate
            }

            if let originalIsEnabled {
                gesture.isEnabled = originalIsEnabled
            }

            clear()
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController,
                  navigationController.viewControllers.count > 1 else {
                return false
            }

            if navigationController.transitionCoordinator?.isAnimated == true {
                return false
            }

            return true
        }

        private func clear() {
            navigationController = nil
            originalDelegate = nil
            originalIsEnabled = nil
        }
    }
}
