import SwiftUI
import UIKit

/// Disables the enclosing navigation stack's interactive pop (edge-swipe back)
/// gesture while `isDisabled` is true. Used so an accidental right-swipe during
/// multi-select doesn't pop the pushed screen out from under the selection.
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
                navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            }
        }

        private func applyState() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
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
