import SwiftUI
import UIKit

/// Keeps the display awake while indexing runs and, after an idle period with
/// no user touch, covers it with a black overlay to save battery. A touch
/// removes the overlay and resets the idle timer.
///
/// `@Observable` so the black dim overlay reacts to `isDimmed`; the rest is
/// side effects (idle timer + overlay window).
///
/// Deliberately does NOT touch `UIScreen.brightness`: iOS auto-brightness
/// fights a programmatic value, and a restore that runs while the scene is
/// resigning can miss — leaving the user's brightness stuck near zero. The
/// black overlay alone keeps the panel dark (on OLED, black pixels are off).
@MainActor
@Observable
final class ScreenAwakeCoordinator {
    /// Idle time with no user touch before the screen dims. iOS exposes no API
    /// for the system Auto-Lock value, so this is a fixed 1-minute stand-in.
    static let idleDimDelay: Duration = .seconds(60)

    /// Drives the full-screen black overlay.
    private(set) var isDimmed = false

    /// Source of index progress/throughput for the dim overlay. Weak — owned by
    /// the root tab view for the whole session.
    weak var libraryModel: LibraryModel?

    private var isEnabled = false
    private var isIndexing = false
    private var dimTask: Task<Void, Never>?
    /// Hosts the dim visuals in a top-level window so they sit above everything
    /// — tab UI, sheets, and the photo-detail `fullScreenCover` (a SwiftUI
    /// `.overlay` on the root tab view would be hidden behind that cover).
    private var overlayWindow: UIWindow?

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
        showOverlay()
    }

    private func wake() {
        isDimmed = false
        hideOverlay()
    }

    // MARK: Overlay window

    private func showOverlay() {
        guard overlayWindow == nil, let scene = Self.currentWindowScene() else { return }
        let window = UIWindow(windowScene: scene)
        // Above the app content, sheets, and the photo-detail fullScreenCover.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.backgroundColor = .clear
        let host = UIHostingController(
            rootView: DimOverlayView(
                library: libraryModel,
                onWake: { [weak self] in self?.registerActivity() }
            )
        )
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // Visible but not key: swallow taps to wake without stealing focus.
        window.isHidden = false
        overlayWindow = window
    }

    private func hideOverlay() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }

    private static func currentWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }
}

/// Root of the dim overlay window: black fill + faint live progress, and a
/// touch-to-wake gesture that swallows the tap so it never reaches the app.
private struct DimOverlayView: View {
    let library: LibraryModel?
    let onWake: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            DimIndexProgressView(
                progress: library?.indexProgress,
                throughput: library?.indexThroughput,
                networkStatus: library?.indexNetworkStatus,
                diagnostics: library?.indexDiagnostics
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onWake() }
        )
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
