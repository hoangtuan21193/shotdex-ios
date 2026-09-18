import SwiftUI
import UIKit

/// State shared between a photo grid and the date scrubber drawn over its
/// right edge, as in iOS Photos: the grid publishes where it is and what date
/// is under the top of the screen, the scrubber asks it to jump.
///
/// An observable object rather than a `Binding` pair because the traffic runs
/// both ways every frame of a drag, and a `UIViewRepresentable` cannot write
/// back into its own bindings mid-layout without fighting SwiftUI's update
/// cycle. Only the scrubber view reads these properties, so a scroll never
/// invalidates the screen hosting the grid.
@MainActor
@Observable
final class PhotoGridScrubberModel {
    /// 0 at the top of the grid, 1 at the bottom. Written by the grid.
    var progress: Double = 0
    /// Header text for whatever sits under the top of the viewport — the date
    /// the handle is over. Empty hides the bubble.
    var label: String = ""
    /// False when the content fits on screen, which hides the scrubber. Set
    /// from layout as well as from scrolling, so the handle can be grabbed
    /// before the grid has been scrolled even once.
    var isScrollable = false
    /// True while a finger is on the handle. The grid stops publishing
    /// `progress` then, so the handle does not fight the drag it is causing.
    var isScrubbing = false
    /// Registered by the grid so the scrubber can drive it. Takes 0…1.
    var scrollTo: ((Double) -> Void)?
}

/// The draggable date index on the right edge of a photo grid.
///
/// A slim handle tracking the scroll position, plus — while dragged — a glass
/// bubble showing the date it is over. It stays on screen whenever the grid is
/// long enough to scroll: at 8pt wide it never competes with a photo, and a
/// handle that fades away is one the user has to go hunting for.
struct PhotoGridScrubber: View {
    @Bindable var model: PhotoGridScrubberModel
    /// Space to leave free at the top and bottom of the track, so the handle
    /// clears the nav bar and the floating chrome.
    var topInset: CGFloat = 8
    var bottomInset: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let handleWidth: CGFloat = 8
    private let handleHeight: CGFloat = 44
    private let trackWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.height - topInset - bottomInset - handleHeight)
            let handleY = topInset + travel * clampedProgress + handleHeight / 2

            ZStack(alignment: .topTrailing) {
                Color.clear

                if model.isScrubbing, !model.label.isEmpty {
                    Text(model.label)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .glassBackground(Capsule())
                        .position(x: geometry.size.width - trackWidth - 60, y: handleY)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                // The touch target is the full 44pt strip, not the 8pt handle —
                // the handle is only how wide it looks. The drag is a UIKit
                // recognizer: a SwiftUI `DragGesture` layered over the grid's
                // `UICollectionView` never receives touches (the same problem
                // the timeline drag zone hit), so the hit view is real UIKit and
                // the handle below is drawn purely for looks.
                ScrubberTouchStrip(
                    model: model,
                    topInset: topInset,
                    handleHeight: handleHeight,
                    travel: travel
                )
                    .frame(width: trackWidth, height: handleHeight * 1.6)
                    .overlay {
                        // Solid rather than a material: behind it is either a
                        // full-bleed photo or a black gap, and a thin material
                        // vanishes against both.
                        Capsule()
                            .fill(Color.primary.opacity(model.isScrubbing ? 0.85 : 0.45))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(.systemBackground).opacity(0.6), lineWidth: 1)
                            )
                            .frame(width: handleWidth, height: handleHeight)
                            .scaleEffect(x: model.isScrubbing ? 1.6 : 1, anchor: .center)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            // Purely decorative: the touches belong to the
                            // UIKit strip underneath, and a SwiftUI overlay
                            // would otherwise swallow them before it sees them.
                            .allowsHitTesting(false)
                    }
                    .position(x: geometry.size.width - trackWidth / 2, y: handleY)
                    .accessibilityLabel("Scroll by date")
                    .accessibilityValue(model.label)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: model.isScrubbing)
        }
        .allowsHitTesting(model.isScrollable)
        .opacity(model.isScrollable ? 1 : 0)
    }

    private var clampedProgress: Double {
        min(max(model.progress, 0), 1)
    }
}

/// The UIKit hit target behind the scrubber handle.
///
/// Two reasons it is not a SwiftUI gesture. First, a `DragGesture` layered over
/// the grid's `UICollectionView` does not receive touches. Second, the strip
/// must be transparent to taps everywhere except the handle itself, so the
/// photos under the right edge stay tappable — that is `point(inside:)`, which
/// SwiftUI has no equivalent for.
private struct ScrubberTouchStrip: UIViewRepresentable {
    let model: PhotoGridScrubberModel
    let topInset: CGFloat
    let handleHeight: CGFloat
    /// Pixels the handle can travel, i.e. the range 0…1 maps onto.
    let travel: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = HitView()
        view.backgroundColor = .clear
        // Press duration 0 so the handle is grabbed the instant a finger lands,
        // then `.changed` drives the scroll — a pan recognizer would swallow the
        // first few points waiting for its slop threshold.
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDrag(_:))
        )
        press.minimumPressDuration = 0
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator {
        var parent: ScrubberTouchStrip

        init(_ parent: ScrubberTouchStrip) {
            self.parent = parent
        }

        @objc func handleDrag(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view, let superview = view.superview else { return }
            let model = parent.model
            switch recognizer.state {
            case .began, .changed:
                model.isScrubbing = true
                guard parent.travel > 0 else { return }
                // Measure in the parent's space: the strip itself moves with the
                // handle, so its own coordinates would fight the drag.
                let y = recognizer.location(in: superview).y
                    - parent.topInset - parent.handleHeight / 2
                let fraction = min(max(Double(y / parent.travel), 0), 1)
                model.progress = fraction
                model.scrollTo?(fraction)
            case .ended, .cancelled, .failed:
                model.isScrubbing = false
            default:
                break
            }
        }
    }

    /// Only the handle area takes touches; the rest of the right edge stays
    /// transparent so photos underneath keep their taps.
    private final class HitView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.contains(point)
        }
    }
}
