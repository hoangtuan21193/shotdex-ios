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
final class ScreenAwakeController {
    /// Idle time with no user touch before the screen dims. iOS exposes no API
    /// for the system Auto-Lock value, so this is a fixed 1-minute stand-in.
    static let idleDimDelay: Duration = .seconds(60)

    /// Drives the full-screen black overlay.
    private(set) var isDimmed = false

    /// Source of index progress/throughput for the dim overlay. Weak — owned by
    /// the root tab view for the whole session.
    weak var libraryController: LibraryController?

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
                library: libraryController,
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
    let library: LibraryController?
    let onWake: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            DimmedIndexProgress(
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

/// Faint, large index readout shown on the dim overlay so the user can still
/// read how far indexing has got. Drifts slowly to avoid OLED burn-in.
private struct DimmedIndexProgress: View {
    let progress: IndexProgress?
    let throughput: IndexThroughput?
    let networkStatus: IndexNetworkStatus?
    let diagnostics: IndexDiagnostics?

    /// Slow vertical drift so static text never sits on the same OLED pixels.
    /// Each step glides over ~the full interval, so motion is ~1–2 pt/s —
    /// below the perception threshold but enough travel to avoid burn-in.
    private static let driftPositions: [CGFloat] = [-16, 0, 16, 0]
    private static let driftInterval: TimeInterval = 20
    @State private var driftIndex = 0
    private let driftTimer = Timer.publish(every: driftInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Text("Indexing")
                .font(.title.weight(.semibold))
            if let progress {
                ProgressView(value: progress.fraction)
                    .frame(maxWidth: 260)
                Text("\(progress.processed)/\(progress.total) · \(progress.percent)%")
                    .font(.title3.monospacedDigit())
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            if let throughput {
                VStack(spacing: 6) {
                    Text(throughput.rateText)
                        .font(.headline.monospacedDigit())
                    if let remaining = throughput.remainingText {
                        Text(remaining)
                            .font(.headline)
                    }
                }
                .padding(.top, 4)
            }
            // Always-on network readout — speed and downloaded total show even
            // at zero (`Wi-Fi · 0 KB/s · 0 KB`) so the state is legible at a
            // glance without waiting for traffic to start.
            if let networkStatus {
                Text(networkStatus.detailedLine)
                    .font(.headline.monospacedDigit())
                    .padding(.top, 4)
            }
            if let diagnostics {
                VStack(spacing: 6) {
                    Text(diagnostics.thermalLine)
                    Text(diagnostics.iCloudLine)
                }
                .font(.subheadline.monospacedDigit())
            }
            Text("When originals live in iCloud, ShotDex streams only the first few hundred kilobytes of each photo to read its camera metadata — nothing is stored on this device.")
                .font(.footnote)
                .padding(.top, 8)
                .padding(.horizontal, 40)
        }
        .multilineTextAlignment(.center)
        .tint(.white.opacity(0.6))
        .foregroundStyle(.white.opacity(0.6))
        .offset(y: Self.driftPositions[driftIndex])
        .animation(.easeInOut(duration: Self.driftInterval - 1), value: driftIndex)
        .onReceive(driftTimer) { _ in
            driftIndex = (driftIndex + 1) % Self.driftPositions.count
        }
    }
}

/// Invisible probe that observes every touch on the window without consuming or
/// delaying it, reporting activity so `ScreenAwakeController` can reset its idle
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
