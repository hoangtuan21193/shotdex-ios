import SwiftUI
import UIKit

/// Disables the enclosing navigation stack's interactive pop gestures while
/// `isDisabled` is true. Used so a right-swipe during multi-select (swipe to
/// select a range) doesn't pop the pushed screen out from under the selection.
///
/// iOS 26 has two: the edge swipe (`interactivePopGestureRecognizer`) and the
/// swipe-back-from-anywhere-in-content one
/// (`interactiveContentPopGestureRecognizer`). The second is the one that
/// fights swipe-select, since that drag starts mid-grid.
private struct BackSwipeDisabler: UIViewControllerRepresentable {
    var isDisabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isDisabled = isDisabled
    }

    final class Controller: UIViewController {
        var isDisabled = false {
            didSet { applyState() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyState()
        }

        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            // Restore the gesture when this view leaves the hierarchy so the
            // shared recognizer isn't left disabled for the screen underneath.
            if parent == nil {
                setPopGesturesEnabled(true)
            }
        }

        private func applyState() {
            setPopGesturesEnabled(!isDisabled)
        }

        private func setPopGesturesEnabled(_ isEnabled: Bool) {
            guard let navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = isEnabled
            if #available(iOS 26.0, *) {
                navigationController.interactiveContentPopGestureRecognizer?.isEnabled = isEnabled
            }
        }
    }
}

extension View {
    /// Disables the edge-swipe back gesture on the enclosing navigation stack
    /// while `disabled` is true (e.g. during multi-select).
    func disablesBackSwipe(_ disabled: Bool) -> some View {
        background(BackSwipeDisabler(isDisabled: disabled))
    }
}
