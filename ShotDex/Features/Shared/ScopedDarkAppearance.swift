import SwiftUI
import UIKit

/// Dark for one pushed screen and nothing else (FS-05.04 §4): the screen's
/// own views, and what UIKit presents from it — alerts, menus, the keyboard.
///
/// `.preferredColorScheme(.dark)` is a preference: it travels up to the
/// presentation that holds the screen, and on iPad the form-sheet card the
/// Watermark screen was pushed in kept the dark style after Back. This sets
/// the style on the hosting controller of the pushed page only, and gives
/// back what was there when the page leaves.
private struct ScopedDarkAppearance: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private weak var styled: UIViewController?
        private var previous: UIUserInterfaceStyle = .unspecified

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restore()
        }

        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            if parent == nil { restore() }
        }

        /// The page's own hosting controller: the nearest ancestor whose
        /// parent is the navigation controller. Never the navigation
        /// controller itself — that one is the whole card.
        private var page: UIViewController? {
            var candidate = parent
            while let current = candidate, let next = current.parent, !(next is UINavigationController) {
                candidate = next
            }
            return candidate?.parent is UINavigationController ? candidate : parent
        }

        private func apply() {
            guard styled == nil, let page else { return }
            previous = page.overrideUserInterfaceStyle
            page.overrideUserInterfaceStyle = .dark
            styled = page
        }

        private func restore() {
            guard let styled else { return }
            styled.overrideUserInterfaceStyle = previous
            self.styled = nil
        }
    }
}

extension View {
    /// Dark for this pushed page only, alerts and menus included; the sheet
    /// or window it was pushed in keeps its own appearance after Back.
    func scopedDarkAppearance() -> some View {
        environment(\.colorScheme, .dark)
            .background(ScopedDarkAppearance())
    }
}
