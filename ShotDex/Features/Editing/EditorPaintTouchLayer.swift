import SwiftUI
import UIKit

/// The paint surface under the mask brush and Clean Up: one finger paints, two
/// fingers zoom and pan the photo.
///
/// `DragGesture` could not do this job. It tracks any number of fingers, so the
/// first finger of a pinch opened a stroke; SwiftUI gave the layer's own gesture
/// priority over the photo-level `MagnifyGesture`, so the pinch often never
/// arrived; and a gesture the system cancels never calls `onEnded`, so the stroke
/// state stayed "in progress" and every later touch appended to a stroke that had
/// been abandoned.
///
/// So this layer owns its recognisers. Which touches are strokes and which belong
/// to zoom is not decided here, though — `PaintTouchArbiter` decides, and the
/// reasons are documented there. This file only turns UIKit's callbacks into the
/// arbiter's vocabulary and the arbiter's verdicts into the closures below.
///
/// The paint recogniser deliberately stays `.possible` for its whole life, like
/// `ActivityRecognizer` in `ScreenAwakeCoordinator`. It never needs to *own* a
/// touch: it only watches. That buys two things a recognising recogniser could
/// not. It never competes with the pinch above it, so there is no arbitration to
/// lose. And it keeps receiving touches after refusing one — a recogniser that
/// has failed is cut off until every finger lifts, which is precisely the
/// bookkeeping the arbiter needs to spot a finger joining a two-finger pan.
///
/// Points arrive in the coordinate space the caller positions in: the recogniser
/// reads the finger in this view's own bounds — untouched by the `scaleEffect`
/// wrapping it, so a stroke lands under the finger at any zoom — and `origin`
/// shifts that back into stage coordinates.
struct EditorPaintTouchLayer: UIViewRepresentable {
    struct Touch {
        var location: CGPoint
        var startLocation: CGPoint
        /// Apple Pencil force at this point, 0…1 against the Pencil's
        /// maximum. `nil` for a finger, which reports a constant that means
        /// nothing — the brush draws at its nominal width for those.
        var pressure: Double?

        var translation: CGSize {
            CGSize(
                width: location.x - startLocation.x,
                height: location.y - startLocation.y
            )
        }
    }

    /// Where this layer sits in the space the callbacks should speak — the photo
    /// rect's origin for every current caller.
    var origin: CGPoint
    /// The finger moved, but no stroke is being painted: follow it with the
    /// cursor and nothing else. `nil` means take the cursor off the photo — the
    /// touch has been refused, so promising a stroke there would be a lie.
    var onTracked: (CGPoint?) -> Void
    var onBegan: (Touch) -> Void
    var onMoved: (Touch) -> Void
    var onEnded: (Touch) -> Void
    /// The stroke was abandoned. Whatever it started must be rolled back here:
    /// no `onEnded` follows.
    var onCancelled: () -> Void
    /// Two fingers began dragging: the photo is about to be panned, so the caller
    /// takes the current offset as the origin for the translations that follow.
    var onPanBegan: () -> Void
    /// Two-finger drag, reported as the translation in *screen* points since the
    /// pan began — the space `zoomOffset` lives in, unscaled by the zoom.
    var onPanChanged: (CGSize) -> Void
    var onPanEnded: () -> Void
    /// Apple Pencil double-tap (or squeeze, on the Pro): swap brush and
    /// eraser. Every drawing app on iPad maps the gesture to the same thing,
    /// and this is the only tool in the editor a Pencil stays in for minutes.
    var onPencilToggle: () -> Void = {}

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let paint = PaintTouchObserver { [weak coordinator = context.coordinator] event in
            coordinator?.handle(event)
        }
        // Watching only: it must not consume, delay or cancel anything.
        paint.cancelsTouchesInView = false
        paint.delaysTouchesBegan = false
        paint.delaysTouchesEnded = false
        paint.delegate = context.coordinator
        view.addGestureRecognizer(paint)

        // Panning the zoomed photo belongs here too, and with an explicit
        // two-finger recogniser rather than the photo-level `DragGesture`: that
        // gesture had to be told apart from a one-finger stroke on the very same
        // touches, and it lost — two fingers zoomed but would not slide the
        // picture. Two fingers here is unambiguous, and it composes with the pinch
        // above because both are allowed to recognise simultaneously.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)

        // The system decides what the double-tap means in Settings; ShotDex
        // honours the two that make sense here and ignores the rest rather
        // than overriding the user's choice.
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        view.addInteraction(pencil)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // The closures and the origin are captured fresh every layout pass: the
        // photo rect moves when the panel resizes or the crop changes aspect.
        context.coordinator.layer = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(layer: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var layer: EditorPaintTouchLayer
        private var arbiter = PaintTouchArbiter()
        /// First point of the stroke being painted, so every `Touch` can report
        /// the translation callers expect.
        private var strokeStart: CGPoint?
        /// Where the finger was last seen, which is where a stroke cut short by a
        /// second finger has to end.
        private var lastPoint: CGPoint?
        /// Force of the touch that produced the event being handled. The
        /// arbiter deals in points and times only, so the pressure rides
        /// alongside it rather than through it.
        private var latestPressure: Double?

        init(layer: EditorPaintTouchLayer) {
            self.layer = layer
        }

        func handle(_ event: PaintTouchObserver.Event) {
            switch event {
            case .down(let activeTouches, let location, let pressure, let time):
                latestPressure = pressure
                apply(arbiter.touchDown(
                    activeTouches: activeTouches,
                    at: location,
                    time: time
                ))
            case .moved(let location, let pressure, let time):
                latestPressure = pressure
                apply(arbiter.touchMoved(to: location, time: time))
            case .up(let time):
                // A tap confirms and ends in the same breath, so the stroke it
                // opens has to be closed here rather than waiting for a decision
                // that will never come.
                let decision = arbiter.touchUp(time: time)
                apply(decision)
                if case .begin(let points) = decision, let last = points.last {
                    layer.onEnded(touch(at: last))
                }
                strokeStart = nil
                lastPoint = nil
            case .extraFinger(let time):
                apply(arbiter.extraFingerDown(time: time))
            case .systemCancel:
                apply(arbiter.systemCancelled())
            case .allUp(let time):
                arbiter.allFingersUp(time: time)
                strokeStart = nil
                lastPoint = nil
                layer.onTracked(nil)
            }
        }

        private func apply(_ decision: PaintTouchArbiter.Decision) {
            switch decision {
            case .ignore:
                layer.onTracked(nil)
            case .track(let point):
                lastPoint = point
                layer.onTracked(stagePoint(point))
            case .begin(let points):
                guard let first = points.first else { return }
                strokeStart = first
                lastPoint = points.last
                layer.onBegan(touch(at: first))
                for point in points.dropFirst() {
                    layer.onMoved(touch(at: point))
                }
            case .extend(let point):
                lastPoint = point
                layer.onMoved(touch(at: point))
            case .finish:
                layer.onEnded(touch(at: lastPoint ?? strokeStart ?? .zero))
                strokeStart = nil
            case .discard:
                layer.onCancelled()
                strokeStart = nil
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                layer.onPanBegan()
            case .changed:
                // In window coordinates, not the view's: the view carries the
                // zoom's `scaleEffect`, which would divide every translation by
                // the zoom factor, while the offset it feeds is screen points.
                let translation = recognizer.translation(in: nil)
                layer.onPanChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                layer.onPanEnded()
            default:
                break
            }
        }

        private func stagePoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + layer.origin.x, y: point.y + layer.origin.y)
        }

        // MARK: Pencil

        @available(iOS 17.5, *)
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveTap tap: UIPencilInteraction.Tap
        ) {
            handlePencilPreference()
        }

        /// The pre-17.5 callback. Deployment target is iOS 17, so both exist.
        @available(iOS, introduced: 12.1, deprecated: 17.5)
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            handlePencilPreference()
        }

        /// Honour only the preferences that mean something on a mask: swapping
        /// tools and "switch to the previous tool" both land on brush ↔ eraser
        /// here. Show Color Palette and Ignore are left alone — a gesture the
        /// user pointed somewhere else should not be quietly repurposed.
        private func handlePencilPreference() {
            switch UIPencilInteraction.preferredTapAction {
            case .switchEraser, .switchPrevious:
                layer.onPencilToggle()
            default:
                break
            }
        }

        private func touch(at point: CGPoint) -> Touch {
            Touch(
                location: stagePoint(point),
                startLocation: stagePoint(strokeStart ?? point),
                pressure: latestPressure
            )
        }

        /// Zoom, pan and the hold-before press all live on the photo above this
        /// layer. Returning true here is what lets them recognise through it —
        /// UIKit needs only one of the two recognisers to agree.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Reports raw touch traffic on the paint layer and never recognises anything.
/// `PaintTouchArbiter` turns this into strokes; see `EditorPaintTouchLayer` for
/// why watching beats recognising here.
final class PaintTouchObserver: UIGestureRecognizer {
    enum Event {
        /// The first finger of a sequence. `activeTouches` counts every finger on
        /// the layer including this one — `touches.count` from the event would
        /// count only the ones that arrived together, which is how a finger
        /// joining a two-finger pan used to read as the start of a fresh stroke.
        case down(activeTouches: Int, location: CGPoint, pressure: Double?, time: TimeInterval)
        case moved(location: CGPoint, pressure: Double?, time: TimeInterval)
        case up(time: TimeInterval)
        case extraFinger(time: TimeInterval)
        case systemCancel
        case allUp(time: TimeInterval)
    }

    private let onEvent: (Event) -> Void
    private var trackedTouch: UITouch?

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        super.init(target: nil, action: nil)
    }

    /// Normalised Pencil force, or `nil` for anything else. A finger's
    /// `force` is a constant on a non-3D-Touch display, so treating it as
    /// pressure would make every finger stroke the same wrong width rather
    /// than the right nominal one.
    static func pressure(of touch: UITouch) -> Double? {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return nil }
        return Double(touch.force / touch.maximumPossibleForce)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else { return }
        // A Pencil anywhere in this event owns the stroke, and the tracked finger
        // steps aside for it. This is the contract every drawing app on iPad has:
        // Pencil paints, finger navigates, palm is ignored — and without it the
        // palm that lands first becomes the stroke and the Pencil arriving second
        // is reported as a second finger.
        let pencil = touches.first { $0.type == .pencil }
        if let pencil {
            if let trackedTouch, trackedTouch.type != .pencil {
                onEvent(.systemCancel)
            }
            trackedTouch = pencil
            onEvent(.down(
                activeTouches: 1,
                location: pencil.location(in: view),
                pressure: Self.pressure(of: pencil),
                time: event.timestamp
            ))
            return
        }
        if trackedTouch?.type == .pencil {
            // A finger while the Pencil is down is a pan, never a second stroke.
            onEvent(.extraFinger(time: event.timestamp))
            return
        }
        if trackedTouch != nil {
            onEvent(.extraFinger(time: event.timestamp))
            return
        }
        guard let touch = touches.first else { return }
        trackedTouch = touch
        // Keep tracking even when the arbiter is about to refuse this touch: the
        // refusal has to survive until the finger lifts, and only the touch it
        // was reported for can tell us that.
        onEvent(.down(
            activeTouches: activeTouches(in: event, on: view),
            location: touch.location(in: view),
            pressure: Self.pressure(of: touch),
            time: event.timestamp
        ))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view, let trackedTouch, touches.contains(trackedTouch) else { return }
        onEvent(.moved(
            location: trackedTouch.location(in: view),
            pressure: Self.pressure(of: trackedTouch),
            time: event.timestamp
        ))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let trackedTouch, touches.contains(trackedTouch) {
            onEvent(.up(time: event.timestamp))
            self.trackedTouch = nil
        }
        finishIfPhotoIsClear(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let trackedTouch, touches.contains(trackedTouch) {
            onEvent(.systemCancel)
            self.trackedTouch = nil
        }
        finishIfPhotoIsClear(event)
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    /// The multi-touch latch and the cooldown both hang off "every finger is
    /// off the photo", so that moment has to be reported exactly once.
    private func finishIfPhotoIsClear(_ event: UIEvent) {
        guard let view, activeTouches(in: event, on: view) == 0 else { return }
        onEvent(.allUp(time: event.timestamp))
        // Back to `.possible` for the next sequence.
        state = .failed
    }

    private func activeTouches(in event: UIEvent, on view: UIView) -> Int {
        (event.touches(for: view) ?? [])
            .filter { $0.phase != .ended && $0.phase != .cancelled }
            .count
    }
}
