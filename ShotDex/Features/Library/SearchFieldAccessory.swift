import SwiftUI
import UIKit

/// Puts a button *inside* the search field, at its trailing edge.
///
/// SwiftUI's `.searchable` owns the field and exposes nothing to add to it, so this
/// reaches the `UISearchTextField` behind it and uses the one hook a text field
/// already has there: `rightView`.
///
/// Why the text field and not the search bar: `.searchable` before iOS 26 is backed
/// by a `UISearchBar`, whose `searchTextField` is this class, and
/// `showsBookmarkButton` — UIKit's own in-field trailing control — is a separate
/// button that cannot carry an app symbol as cleanly.
///
/// **Known cost on iOS 26.** A `.search`-role tab hosts its field in
/// `_UITabHostedSearchContainer`, and everything in that container is mirrored into
/// the status-bar strip, so the icon is also drawn — smaller and inert — at the top
/// of the screen. Measured, not guessed: it happens with `rightView` and with a
/// sibling button laid over the field, at any install timing, and there is no public
/// way to opt out of the mirror. Kept anyway because the button belongs in the field.
///
/// The field does not exist when this view first appears, and it is rebuilt when the
/// surface is dismissed and shown again, so the installer keeps looking and
/// re-applies.
struct SearchFieldTrailingButton: ViewModifier {
    /// SF Symbol drawn inside the field.
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    func body(content: Content) -> some View {
        content.background(
            SearchFieldButtonInstaller(
                systemImage: systemImage,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
    }
}

extension View {
    /// Adds a button inside the trailing edge of this scope's search field.
    func searchFieldTrailingButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            SearchFieldTrailingButton(
                systemImage: systemImage,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
        )
    }
}

private struct SearchFieldButtonInstaller: UIViewRepresentable {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(systemImage: systemImage, accessibilityLabel: accessibilityLabel, action: action)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.start(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private let systemImage: String
        private let accessibilityLabel: String
        var action: () -> Void

        private weak var host: UIView?
        private weak var installedField: UISearchTextField?
        private weak var installedButton: UIButton?
        private var timer: Timer?

        /// Polls rather than guessing one delay: the field appears a few frames late
        /// and comes back as a new object on a later visit. A quarter-second tick that
        /// only walks the view tree is cheap, and it stops as soon as the screen goes
        /// away.
        private static let interval: TimeInterval = 0.6

        init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
            self.action = action
        }

        func start(from view: UIView) {
            host = view
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self, self.host?.window != nil else {
                        timer.invalidate()
                        return
                    }
                    self.install()
                }
            }
            // Deliberately no immediate install: the iOS 26 tab bar is mid-morph into
            // the search field when this view appears, and touching the field then
            // leaves a stale snapshot of it drawn near the top of the screen.
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        private func install() {
            guard let field = Self.findSearchField(near: host) else { return }
            if let previous = installedField, previous !== field { clear(previous) }
            guard field !== installedField || installedButton?.window == nil else { return }

            let button = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
                self?.action()
            })
            button.setImage(UIImage(systemName: systemImage), for: .normal)
            button.accessibilityLabel = accessibilityLabel

            button.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
            // A text field shows either its clear button or its right view, never
            // both, so this trades the in-field "x" for the Advanced Search icon. The
            // field is still cleared by Cancel beside it, which the system draws
            // whenever a search is active.
            field.rightView = button
            field.rightViewMode = .always
            installedField = field
            installedButton = button
        }

        private func clear(_ field: UISearchTextField) {
            field.rightView = nil
            field.rightViewMode = .never
            installedButton?.removeFromSuperview()
            installedButton = nil
        }

        /// The one field the user can actually see.
        ///
        /// Every window of the scene, not just this view's own: iOS 26 hosts the
        /// search field of a `.search`-role tab outside the content window, and a
        /// second copy of it lives up in the status-bar strip — a button installed in
        /// that one shows up as a stray icon at the top of the screen. Picking the
        /// *largest visible* field, and clearing whichever field held the button
        /// before, keeps exactly one on screen.
        private static func findSearchField(near view: UIView?) -> UISearchTextField? {
            guard let window = view?.window, let scene = window.windowScene else { return nil }
            var candidates: [UISearchTextField] = []
            for sceneWindow in scene.windows {
                collectSearchFields(in: sceneWindow, into: &candidates)
            }
            return candidates
                .filter { field in
                    guard !field.isHidden, field.alpha > 0.01, field.bounds.width > 40 else {
                        return false
                    }
                    let frame = field.convert(field.bounds, to: window)
                    return window.bounds.intersects(frame) && frame.minY >= 0
                }
                .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }

        private static func collectSearchFields(
            in view: UIView,
            into result: inout [UISearchTextField]
        ) {
            if let field = view as? UISearchTextField { result.append(field) }
            for subview in view.subviews { collectSearchFields(in: subview, into: &result) }
        }
    }
}
