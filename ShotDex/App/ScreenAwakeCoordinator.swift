import SwiftUI
import UIKit

/// Keeps the display awake while indexing runs and, after an idle period with
/// no user touch, lowers the screen brightness to save battery. A touch
/// restores the brightness and resets the idle timer.
///
/// `@Observable` for parity with the rest of the app's state holders; the work
/// here is all side effects (idle timer + screen brightness).
///
/// Unlike a full-screen black overlay, dimming the brightness leaves the app
/// content visible (just dark). iOS auto-brightness can nudge the value back up
/// on an ambient-light change; that is an accepted trade-off for not covering
/// the UI. Brightness is always restored on wake, on deactivate, and when the
/// app leaves the foreground, so it can never get stuck dark.
@MainActor
@Observable
final class ScreenAwakeCoordinator {
    /// Idle time with no user touch before the screen dims. iOS exposes no API
    /// for the system Auto-Lock value, so this is a fixed 1-minute stand-in.
    static let idleDimDelay: Duration = .seconds(60)

    /// Brightness applied while idle-dimmed. Deliberately low but **not zero**:
    /// at absolute 0 the display reads as fully off and iOS auto-brightness
    /// takes control, so the programmatic restore on wake gets ignored and the
    /// screen stays dark. A small non-zero floor keeps the screen visibly alive
    /// and lets `wake()` restore reliably.
    private static let dimmedBrightness: CGFloat = 0.15

    /// True while the screen is held at the dimmed brightness.
    private(set) var isDimmed = false

    private var isEnabled = false
    private var isIndexing = false
    private var dimTask: Task<Void, Never>?
    /// Brightness captured just before dimming, restored on wake.
    private var restoreBrightness: CGFloat?

    private var isActive: Bool { isEnabled && isIndexing }

    /// Recompute active state from the setting toggle and the indexing flag.
    func update(enabled: Bool, indexing: Bool) {
        isEnabled = enabled
        isIndexing = indexing
        if isActive {
            UIApplication.shared.isIdleTimerDisabled = true
            scheduleDim()
        } else {
            deactivate()
        }
    }

    /// A user touch arrived: wake the screen and restart the idle countdown.
    func registerActivity() {
        guard isActive else { return }
        wake()
        scheduleDim()
    }

    /// App left the foreground: never leave the display dimmed or awake for
    /// whatever the user switches to.
    func handleBackground() {
        dimTask?.cancel()
        dimTask = nil
        wake()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func deactivate() {
        dimTask?.cancel()
        dimTask = nil
        wake()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func scheduleDim() {
        dimTask?.cancel()
        dimTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDimDelay)
            guard !Task.isCancelled else { return }
            self?.dim()
        }
    }

    private func dim() {
        guard !isDimmed else { return }
        isDimmed = true
        restoreBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = Self.dimmedBrightness
    }

    private func wake() {
        guard isDimmed else { return }
        isDimmed = false
        if let restoreBrightness {
            UIScreen.main.brightness = restoreBrightness
        }
        restoreBrightness = nil
    }
}

/// Invisible probe that observes every touch on the window without consuming or
/// delaying it, reporting activity so `ScreenAwakeCoordinator` can reset its idle
/// timer. Standard app-wide inactivity detection — no `AppDelegate` needed.
struct IdleActivityReporterView: UIViewRepresentable {
    let onActivity: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivity: onActivity)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        // The view isn't in the window yet during makeUIView; attach the
        // recognizer once it is.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onActivity = onActivity
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActivity: () -> Void
        private weak var recognizer: ActivityRecognizer?

        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity
        }

        func attach(to window: UIWindow) {
            let recognizer = ActivityRecognizer { [weak self] in self?.onActivity() }
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        func detach() {
            guard let recognizer else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.recognizer = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Reports touches for the whole gesture then fails once it ends, so it never
/// consumes, cancels, or delays the real gestures underneath. Staying
/// `.possible` (rather than failing on the first touch) is what lets it keep
/// receiving `touchesMoved`: a long continuous drag registers activity the
/// whole time, so the idle timer never fires mid-interaction.
private final class ActivityRecognizer: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // Reset to `.possible` for the next touch sequence.
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }
}
