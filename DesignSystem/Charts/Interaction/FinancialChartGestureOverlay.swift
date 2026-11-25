import SwiftUI
import UIKit

/// ScrollView-friendly gesture coordinator for financial charts.
///
/// Gesture policy:
/// - Vertical swipes immediately yield to the enclosing `ScrollView`.
/// - Leading-edge rightward swipes yield to iOS's interactive pop gesture.
/// - Press-and-hold (0.10s) activates high-precision scrubbing with haptic feedback in all modes.
/// - Horizontal drag scrubs immediately when not zoomed, or pans the chart when zoomed in.
/// - Two-finger pinch zooms around the pinch midpoint when `allowsZoomAndPan` is enabled.
/// - Double-tap resets zoom back to 1x when zoomed in.
struct FinancialChartGestureOverlay: UIViewRepresentable {
    let allowsZoomAndPan: Bool
    let isZoomed: Bool
    let onScrubChanged: (CGPoint) -> Void
    let onScrubEnded: () -> Void
    let onPinchChanged: (Double, Double) -> Void
    let onPanChanged: (Double) -> Void
    let onDoubleTapReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let coordinator = context.coordinator

        let longPress = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.10
        longPress.allowableMovement = 24
        longPress.delegate = coordinator
        view.addGestureRecognizer(longPress)
        coordinator.longPressGesture = longPress

        let pan = UIPanGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        coordinator.panGesture = pan

        let pinch = UIPinchGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = coordinator
        view.addGestureRecognizer(pinch)
        coordinator.pinchGesture = pinch

        let doubleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = coordinator
        view.addGestureRecognizer(doubleTap)
        coordinator.doubleTapGesture = doubleTap

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pinchGesture?.isEnabled = allowsZoomAndPan
        context.coordinator.doubleTapGesture?.isEnabled = allowsZoomAndPan && isZoomed
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: FinancialChartGestureOverlay
        weak var longPressGesture: UILongPressGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        weak var pinchGesture: UIPinchGestureRecognizer?
        weak var doubleTapGesture: UITapGestureRecognizer?

        private var isLongPressScrubbing = false
        private var lastPanX: CGFloat = 0
        private var lastPinchScale: CGFloat = 1.0

        init(parent: FinancialChartGestureOverlay) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)

            switch gesture.state {
            case .began:
                isLongPressScrubbing = true
                parent.onScrubChanged(location)
            case .changed:
                parent.onScrubChanged(location)
            case .ended, .cancelled, .failed:
                isLongPressScrubbing = false
                parent.onScrubEnded()
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view, view.bounds.width > 1 else { return }
            let location = gesture.location(in: view)

            if parent.allowsZoomAndPan && parent.isZoomed && !isLongPressScrubbing {
                switch gesture.state {
                case .began:
                    lastPanX = location.x
                case .changed:
                    let deltaX = location.x - lastPanX
                    lastPanX = location.x
                    let deltaFraction = Double(deltaX / view.bounds.width)
                    parent.onPanChanged(deltaFraction)
                default:
                    break
                }
                return
            }

            switch gesture.state {
            case .began, .changed:
                parent.onScrubChanged(location)
            case .ended, .cancelled, .failed:
                parent.onScrubEnded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard parent.allowsZoomAndPan, let view = gesture.view, view.bounds.width > 1 else {
                return
            }

            switch gesture.state {
            case .began:
                lastPinchScale = 1.0
                parent.onScrubEnded()
            case .changed:
                let currentScale = max(gesture.scale, 0.01)
                let deltaFactor = Double(currentScale / max(lastPinchScale, 0.01))
                lastPinchScale = currentScale
                let anchorX = gesture.location(in: view).x
                let anchorFraction = Double(min(max(anchorX / view.bounds.width, 0), 1))
                parent.onPinchChanged(deltaFactor, anchorFraction)
            case .ended, .cancelled, .failed:
                lastPinchScale = 1.0
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.onScrubEnded()
            parent.onDoubleTapReset()
        }

        private static let leadingEdgeBackSwipeExclusionWidth: CGFloat = 24

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGesture,
               let pan = gestureRecognizer as? UIPanGestureRecognizer,
               let view = pan.view {
                if isLongPressScrubbing {
                    return false
                }
                let velocity = pan.velocity(in: view)
                // Preserve native iOS left-edge interactive back-swipe navigation.
                if pan.location(in: view).x < Self.leadingEdgeBackSwipeExclusionWidth && velocity.x > 0 {
                    return false
                }
                // Only claim horizontal pans so vertical scrolling belongs cleanly to ScrollView.
                return abs(velocity.x) > abs(velocity.y) * 1.05
            }

            if gestureRecognizer === pinchGesture {
                return parent.allowsZoomAndPan
            }

            if gestureRecognizer === doubleTapGesture {
                return parent.allowsZoomAndPan && parent.isZoomed
            }

            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Never simultaneously scroll the outer UIScrollView once a chart gesture begins.
            return false
        }
    }
}
