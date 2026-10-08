import SwiftUI
import UIKit

/// Pinch phases reported to the owner of the points-per-second scale. The
/// anchor time is captured at `.began` and kept pinned under the playhead.
enum TimelinePinchPhase {
    case began
    case changed(scale: CGFloat)
    case ended
}

/// A draggable region of the timeline content. SwiftUI drag/pinch gestures
/// never activate inside the hosted content of a `UIScrollView` (they defer to
/// the scroll pan forever), so every drag is routed through dedicated UIKit
/// recognizers on the scroller: the rows publish these zones, the scroller
/// hit-tests them, and reports phases back.
struct TimelineDragZone: Equatable {
    enum Kind: Equatable, Hashable {
        case clipLeadingHandle(UUID)
        case clipTrailingHandle(UUID)
        case clipReorder(UUID)
        /// The two corner grips that set a clip's own fade from and to the
        /// background — the affordance every video app the user has touched
        /// puts there, and the one that replaces "open panel, find slider".
        case clipFadeInHandle(UUID)
        case clipFadeOutHandle(UUID)
        /// Text and sticker overlays share these — both are `TimedOverlay`.
        case overlayBody(UUID)
        case overlayLeadingHandle(UUID)
        case overlayTrailingHandle(UUID)
        /// A caption block on C1 (FS-12.14 §5).
        case captionBody(UUID)
        case captionLeadingHandle(UUID)
        case captionTrailingHandle(UUID)
        case musicBody(UUID)
        case musicLeadingHandle(UUID)
        case musicTrailingHandle(UUID)

        /// Reorder rides a long-press so a plain drag over a selected clip
        /// still scrubs; the handle/body zones block the scroll pan instead.
        var isReorder: Bool {
            if case .clipReorder = self { return true }
            return false
        }

        /// A clip's edge handle: held still it opens the frame trim
        /// (FS-12.17 §3).
        var isClipEdgeHandle: Bool {
            switch self {
            case .clipLeadingHandle, .clipTrailingHandle: true
            default: false
            }
        }
    }
    var kind: Kind
    var rect: CGRect
}

enum TimelineZoneDragPhase {
    case changed(translationX: CGFloat)
    case ended(translationX: CGFloat)
    case cancelled
    /// A press on a clip's body that ended without moving it (FS-12.11
    /// §4): held long enough to select, or held and let go for nothing.
    case pressed(TimelinePressClassifier.Outcome)
    /// The press on a clip's body has held `movePress` — at `atX` in the
    /// content: from here on the finger's release is the press's, not the
    /// clip's tap.
    case holding(atX: CGFloat)
    /// A click on a clip's body with ⌘ or ⇧ held — the iPad's pointer and
    /// keyboard (FS-12.11 §4): ⌘ toggles the clip in the group, ⇧ adds the
    /// run of clips up to it.
    case modifiedTap(command: Bool, shift: Bool)
    /// A clip's edge handle held still for `TimelineEdgeHold.duration`
    /// (FS-12.17 §3): the frame trim opens on that edge.
    case edgeHeld
    /// The finger that held the edge moves on: `translationX` from where
    /// the hold began — a drag that walks the frame grid (§5).
    case edgeHeldMoved(translationX: CGFloat)
    /// The finger that held the edge lifts: the loupe goes, the trim stays.
    case edgeHeldEnded
    /// A tap on a clip's edge handle — while trimming, it moves the trim
    /// to that edge (§3).
    case edgeTapped
}

/// The hold that opens the frame trim (FS-12.17 §3): half a second, the
/// finger within 4pt of where it came down. Moved sooner or further, the
/// handle's ordinary drag (FS-12.05) has it.
enum TimelineEdgeHold {
    static let duration: CFTimeInterval = 0.5
    static let slop: CGFloat = 4
}

/// Stops a clip's SwiftUI tap from firing at the end of a press the
/// timeline's long-press already owns (FS-12.11 AC-16: held 0.4 s and let
/// go is nothing, not a selection). The tap gesture lives in the hosted
/// content, where a UIKit recognizer on the scroll view cannot make it
/// fail, so the press leaves word here and the tap asks before acting.
///
/// A reference, not view state: the press's callback and the tap land in
/// the same run-loop turn, before any render could hand back a new value.
@MainActor
final class TimelinePressGate {
    private var heldClip: UUID?
    private var isHolding = false
    private var heldAt: CFTimeInterval = 0
    private var releasedAt: CFTimeInterval = 0

    /// How long after a press ends its clip's tap is still the press's.
    static let window: CFTimeInterval = 0.4
    /// A hold that never reported its end (a gesture the system took over)
    /// stops swallowing taps after this long.
    static let staleHold: CFTimeInterval = 3

    func began(on clip: UUID, now: CFTimeInterval = CACurrentMediaTime()) {
        heldClip = clip
        isHolding = true
        heldAt = now
    }

    func ended(now: CFTimeInterval = CACurrentMediaTime()) {
        isHolding = false
        releasedAt = now
    }

    /// Whether a tap on `clip` is the tail of a press: if so it is
    /// swallowed, once.
    func swallowsTap(on clip: UUID, now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        let holds = isHolding && now - heldAt < Self.staleHold
        guard heldClip == clip, holds || now - releasedAt < Self.window else { return false }
        heldClip = nil
        return true
    }
}

/// The timeline's horizontal scroller: a `UIScrollView` wrapping hosted SwiftUI
/// track rows, with a fixed centre playhead the parent draws over it. The
/// scroller occupies the row area only (the gutter is a sibling column), so its
/// own centre already lands on the playhead.
///
/// Time ↔ offset: `contentInset` is half the viewport on both sides, so
/// `time = (contentOffset.x + inset.left) / pps`, and t = 0 sits under the
/// centre playhead when scrolled fully left.
///
/// Feedback arbitration mirrors the proven v1 bridge: while the user drives the
/// scroll it is the source of truth; while playing, `currentTime` is, and
/// programmatic writes are flagged so the delegate echo is ignored.
struct VideoTimelineScroller<Content: View>: UIViewRepresentable {
    var contentWidth: CGFloat
    /// Height of the lane stack. Taller than the viewport once the overlay or
    /// music lanes stack up, which is what makes the timeline scroll vertically.
    var contentHeight: CGFloat
    var currentTime: Double
    var pps: CGFloat
    var dragZones: [TimelineDragZone]
    var onScrubStart: () -> Void
    var onScrubTime: (Double) -> Void
    var onScrubEnd: (Double) -> Void
    /// Vertical scroll position, so the sibling icon gutter tracks the lanes.
    var onVerticalOffset: (CGFloat) -> Void
    var onPinch: (TimelinePinchPhase) -> Void
    var onZoneDrag: (TimelineDragZone.Kind, TimelineZoneDragPhase) -> Void
    /// At Frame zoom, the project's frame rate: a scroll comes to rest on
    /// a frame (FS-12.17 §6). Nil otherwise.
    var frameSnapFPS: Int? = nil
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TimelineScrollView {
        let scrollView = TimelineScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        // Scrubbing is horizontal and lane-reveal is vertical; the lock keeps a
        // diagonal drag from doing both at once.
        scrollView.isDirectionalLockEnabled = true
        scrollView.decelerationRate = .fast
        scrollView.scrollsToTop = false
        scrollView.delaysContentTouches = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        // A name a UI test can pinch by, and the zoom as its value
        // (FS-12.17 plan task 13 — the phone's tree is not walkable).
        scrollView.accessibilityIdentifier = "VideoTimeline"

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)
        let widthConstraint = host.view.widthAnchor.constraint(equalToConstant: max(contentWidth, 1))
        // The height is a constant, not a pin to the frame: pinning would cap the
        // content at the viewport and extra lanes would clip instead of scroll.
        let heightConstraint = host.view.heightAnchor.constraint(equalToConstant: max(contentHeight, 1))
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            widthConstraint,
            heightConstraint,
        ])

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        scrollView.addGestureRecognizer(pinch)

        // Handle drags (clip trim, text move/resize) begin only inside a
        // blocking zone, so plain scrubbing is never stolen.
        let zonePan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleZonePan(_:))
        )
        zonePan.delegate = context.coordinator
        zonePan.maximumNumberOfTouches = 1
        scrollView.addGestureRecognizer(zonePan)
        context.coordinator.zonePan = zonePan

        // A clip body's press (FS-12.11 §4): held 0.32 s then dragged moves
        // the clip; held 0.5 s and let go selects it; anything shorter that
        // travels is the scroll's. The rule is `TimelinePressClassifier`'s.
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleReorder(_:))
        )
        longPress.minimumPressDuration = TimelinePressClassifier.movePress
        longPress.allowableMovement = TimelinePressClassifier.slop
        longPress.delegate = context.coordinator
        scrollView.addGestureRecognizer(longPress)
        context.coordinator.reorderPress = longPress

        // A clip's edge handle held still (FS-12.17 §3): the frame trim.
        // A finger that moves 4pt fails it at once, so an ordinary trim
        // drag starts as it always did; once it has begun, the handle's
        // own drag stands aside (`gestureRecognizerShouldBegin`).
        let edgeHold = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleEdgeHold(_:))
        )
        edgeHold.minimumPressDuration = TimelineEdgeHold.duration
        edgeHold.allowableMovement = TimelineEdgeHold.slop
        edgeHold.delegate = context.coordinator
        scrollView.addGestureRecognizer(edgeHold)
        context.coordinator.edgeHold = edgeHold

        // A tap on an edge handle: while trimming, switches the edge.
        let edgeTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleEdgeTap(_:))
        )
        edgeTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(edgeTap)
        context.coordinator.edgeTap = edgeTap

        // ⌘- and ⇧-click on a clip's body (an iPad with a keyboard): a tap
        // that only takes touches with a modifier down.
        let modifiedTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleModifiedTap(_:))
        )
        modifiedTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(modifiedTap)
        context.coordinator.modifiedTap = modifiedTap

        context.coordinator.host = host
        context.coordinator.widthConstraint = widthConstraint
        context.coordinator.heightConstraint = heightConstraint
        scrollView.hostView = host.view
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.applyContentHeight(scrollView)
            coordinator.syncOffsetIfIdle(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: TimelineScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.host?.rootView = AnyView(content())
        if let constraint = coordinator.widthConstraint,
           abs(constraint.constant - max(contentWidth, 1)) > 0.5 {
            constraint.constant = max(contentWidth, 1)
        }
        coordinator.applyContentHeight(scrollView)
        scrollView.dragZones = dragZones
        scrollView.accessibilityValue = "\(Int(pps.rounded()))"

        coordinator.syncOffsetIfIdle(scrollView)
    }

    // MARK: - Scroll view subclass

    final class TimelineScrollView: UIScrollView {
        var dragZones: [TimelineDragZone] = []
        weak var hostView: UIView?
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            let half = (bounds.width / 2).rounded()
            if contentInset.left != half {
                contentInset = UIEdgeInsets(top: 0, left: half, bottom: 0, right: half)
            }
            onLayout?()
        }

        /// A blocking (non-reorder) zone at a content point.
        func blockingZone(at point: CGPoint) -> TimelineDragZone? {
            dragZones.first { !$0.kind.isReorder && $0.rect.contains(point) }
        }

        func edgeHandleZone(at point: CGPoint) -> TimelineDragZone? {
            dragZones.first { $0.kind.isClipEdgeHandle && $0.rect.contains(point) }
        }

        func reorderZone(at point: CGPoint) -> TimelineDragZone? {
            dragZones.first { $0.kind.isReorder && $0.rect.contains(point) }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGestureRecognizer, let hostView {
                let point = gestureRecognizer.location(in: hostView)
                if blockingZone(at: point) != nil { return false }
            }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: VideoTimelineScroller
        var host: UIHostingController<AnyView>?
        var widthConstraint: NSLayoutConstraint?
        var heightConstraint: NSLayoutConstraint?
        var zonePan: UIPanGestureRecognizer?
        var reorderPress: UILongPressGestureRecognizer?
        var modifiedTap: UITapGestureRecognizer?
        var edgeHold: UILongPressGestureRecognizer?
        var edgeTap: UITapGestureRecognizer?
        private var heldEdge: TimelineDragZone?
        private var heldEdgeStart: CGPoint = .zero
        private var modifiedTapFlags: UIKeyModifierFlags = []

        private var isProgrammaticScroll = false
        private var lastVerticalOffset: CGFloat = 0
        private(set) var isPinching = false
        private var pinchAnchorTime: Double = 0
        private var activeZone: TimelineDragZone?
        private var reorderZone: TimelineDragZone?
        private var reorderStart: CGPoint = .zero
        /// When the finger came down: the press fires `movePress` after it.
        private var pressDownTime: CFTimeInterval = 0
        /// Whether this press has become a move — once it has, it stays one.
        private var isMovingClip = false
        /// Scrolls the timeline under a clip dragged within 44pt of a lane
        /// edge (FS-12.11 §6), at a speed that grows toward the edge.
        private var autoScrollLink: CADisplayLink?
        private var autoScrollSpeed: CGFloat = 0
        private weak var autoScrollRecognizer: UILongPressGestureRecognizer?
        private var lastAutoScrollTick: CFTimeInterval = 0

        init(_ parent: VideoTimelineScroller) { self.parent = parent }

        private func isUserDriven(_ scrollView: UIScrollView) -> Bool {
            scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        }

        private func time(at offsetX: CGFloat, in scrollView: UIScrollView) -> Double {
            guard parent.pps > 0 else { return 0 }
            return Double((offsetX + scrollView.contentInset.left) / parent.pps)
        }

        private func offsetX(forTime time: Double, in scrollView: UIScrollView) -> CGFloat {
            CGFloat(time) * parent.pps - scrollView.contentInset.left
        }

        /// Lane content never shrinks below the viewport, so a short project
        /// doesn't leave the lanes floating over empty scrollable space.
        func applyContentHeight(_ scrollView: UIScrollView) {
            guard let heightConstraint else { return }
            let target = max(parent.contentHeight, scrollView.bounds.height, 1)
            guard abs(heightConstraint.constant - target) > 0.5 else { return }
            heightConstraint.constant = target
        }

        func syncOffsetIfIdle(_ scrollView: UIScrollView) {
            guard scrollView.bounds.width > 0,
                  isPinching || !isUserDriven(scrollView)
            else { return }
            let target = offsetX(
                forTime: isPinching ? pinchAnchorTime : parent.currentTime,
                in: scrollView
            )
            guard abs(target - scrollView.contentOffset.x) > 0.5 else { return }
            isProgrammaticScroll = true
            scrollView.contentOffset.x = target
            isProgrammaticScroll = false
        }

        // MARK: UIScrollViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onScrubStart()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // The gutter follows the lanes on every scroll, programmatic or not.
            if abs(lastVerticalOffset - scrollView.contentOffset.y) > 0.5 {
                lastVerticalOffset = scrollView.contentOffset.y
                parent.onVerticalOffset(scrollView.contentOffset.y)
            }
            guard !isProgrammaticScroll, !isPinching, isUserDriven(scrollView) else { return }
            parent.onScrubTime(time(at: scrollView.contentOffset.x, in: scrollView))
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard let fps = parent.frameSnapFPS else { return }
            targetContentOffset.pointee.x = TimelineZoomMath.restingOffset(
                targetContentOffset.pointee.x, inset: scrollView.contentInset.left, pps: parent.pps, fps: fps
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            parent.onScrubEnd(time(at: scrollView.contentOffset.x, in: scrollView))
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onScrubEnd(time(at: scrollView.contentOffset.x, in: scrollView))
        }

        // MARK: Pinch → pps

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            switch recognizer.state {
            case .began:
                isPinching = true
                pinchAnchorTime = time(at: scrollView.contentOffset.x, in: scrollView)
                parent.onPinch(.began)
            case .changed:
                parent.onPinch(.changed(scale: recognizer.scale))
                syncOffsetIfIdle(scrollView)
            case .ended, .cancelled, .failed:
                isPinching = false
                parent.onPinch(.ended)
            default:
                break
            }
        }

        // MARK: Handle drags (clip trim, text move/resize)

        @objc func handleZonePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return }
            switch recognizer.state {
            case .began:
                let start = recognizer.location(in: hostView)
                let translation = recognizer.translation(in: hostView)
                let origin = CGPoint(x: start.x - translation.x, y: start.y - translation.y)
                activeZone = scrollView.blockingZone(at: origin) ?? scrollView.blockingZone(at: start)
                if let activeZone {
                    parent.onZoneDrag(activeZone.kind, .changed(translationX: translation.x))
                }
            case .changed:
                guard let activeZone else { return }
                parent.onZoneDrag(
                    activeZone.kind,
                    .changed(translationX: recognizer.translation(in: hostView).x)
                )
            case .ended:
                guard let activeZone else { return }
                parent.onZoneDrag(
                    activeZone.kind,
                    .ended(translationX: recognizer.translation(in: hostView).x)
                )
                self.activeZone = nil
            case .cancelled, .failed:
                if let activeZone { parent.onZoneDrag(activeZone.kind, .cancelled) }
                activeZone = nil
            default:
                break
            }
        }

        // MARK: Press on a clip body (FS-12.11 §4)

        @objc func handleReorder(_ recognizer: UILongPressGestureRecognizer) {
            guard let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return }
            let point = recognizer.location(in: hostView)
            let held = CACurrentMediaTime() - pressDownTime
            let travel = hypot(point.x - reorderStart.x, point.y - reorderStart.y)
            switch recognizer.state {
            case .began:
                reorderZone = scrollView.reorderZone(at: point)
                reorderStart = point
                pressDownTime = CACurrentMediaTime() - recognizer.minimumPressDuration
                isMovingClip = false
                // The press owns the finger from here: the timeline holds
                // still under a clip being held or dragged. Turning the pan
                // off and on again cancels the scroll it may have begun.
                if let reorderZone {
                    scrollView.panGestureRecognizer.isEnabled = false
                    scrollView.panGestureRecognizer.isEnabled = true
                    parent.onZoneDrag(reorderZone.kind, .holding(atX: point.x))
                }
            case .changed:
                guard let reorderZone else { return }
                if !isMovingClip,
                   TimelinePressClassifier.classify(held: held, travel: travel, isReleased: false) == .move {
                    isMovingClip = true
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                if isMovingClip {
                    parent.onZoneDrag(reorderZone.kind, .changed(translationX: point.x - reorderStart.x))
                    updateAutoScroll(recognizer, in: scrollView)
                }
            case .ended:
                stopAutoScroll()
                guard let reorderZone else { return }
                if isMovingClip {
                    // Let go well off the lane — a lane's height above or
                    // below it — is a cancel, not a drop (FS-12.11 §6).
                    let band = reorderZone.rect.height
                    let isOffLane = point.y < reorderZone.rect.minY - band || point.y > reorderZone.rect.maxY + band
                    parent.onZoneDrag(reorderZone.kind, isOffLane ? .cancelled : .ended(translationX: point.x - reorderStart.x))
                } else {
                    let outcome = TimelinePressClassifier.classify(held: held, travel: travel, isReleased: true)
                    parent.onZoneDrag(reorderZone.kind, .pressed(outcome))
                }
                self.reorderZone = nil
                isMovingClip = false
            case .cancelled, .failed:
                stopAutoScroll()
                if let reorderZone, isMovingClip { parent.onZoneDrag(reorderZone.kind, .cancelled) }
                reorderZone = nil
                isMovingClip = false
            default:
                break
            }
        }

        // MARK: Auto-scroll under a dragged clip

        private func updateAutoScroll(_ recognizer: UILongPressGestureRecognizer, in scrollView: UIScrollView) {
            let visibleX = recognizer.location(in: scrollView).x - scrollView.contentOffset.x
            let edge = VideoStudioMetrics.groupAutoScrollEdge
            let width = scrollView.bounds.width
            let speed: CGFloat = if visibleX < edge {
                -(edge - max(0, visibleX)) / edge * 600
            } else if visibleX > width - edge {
                (visibleX - (width - edge)) / edge * 600
            } else {
                0
            }
            autoScrollSpeed = speed
            autoScrollRecognizer = recognizer
            if speed != 0, autoScrollLink == nil {
                parent.onScrubStart()
                lastAutoScrollTick = CACurrentMediaTime()
                let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
                link.add(to: .main, forMode: .common)
                autoScrollLink = link
            } else if speed == 0 {
                stopAutoScroll()
            }
        }

        @objc private func autoScrollTick(_ link: CADisplayLink) {
            guard let recognizer = autoScrollRecognizer,
                  let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView,
                  let reorderZone
            else { stopAutoScroll(); return }
            let now = CACurrentMediaTime()
            let dt = min(0.05, now - lastAutoScrollTick)
            lastAutoScrollTick = now
            let minX = -scrollView.contentInset.left
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
            let target = min(max(minX, scrollView.contentOffset.x + autoScrollSpeed * dt), maxX)
            guard abs(target - scrollView.contentOffset.x) > 0.01 else { return }
            isProgrammaticScroll = true
            scrollView.contentOffset.x = target
            isProgrammaticScroll = false
            parent.onScrubTime(time(at: target, in: scrollView))
            // The finger has not moved, the content under it has.
            let point = recognizer.location(in: hostView)
            parent.onZoneDrag(reorderZone.kind, .changed(translationX: point.x - reorderStart.x))
        }

        private func stopAutoScroll() {
            guard let link = autoScrollLink else { return }
            link.invalidate()
            autoScrollLink = nil
            autoScrollSpeed = 0
            if let scrollView = autoScrollRecognizer?.view as? UIScrollView {
                parent.onScrubEnd(time(at: scrollView.contentOffset.x, in: scrollView))
            }
        }

        // MARK: A clip's edge held still (FS-12.17 §3)

        @objc func handleEdgeHold(_ recognizer: UILongPressGestureRecognizer) {
            guard let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return }
            let point = recognizer.location(in: hostView)
            switch recognizer.state {
            case .began:
                heldEdge = scrollView.edgeHandleZone(at: point)
                heldEdgeStart = point
                if let heldEdge {
                    // The hold owns the finger: nothing under it scrolls.
                    scrollView.panGestureRecognizer.isEnabled = false
                    scrollView.panGestureRecognizer.isEnabled = true
                    parent.onZoneDrag(heldEdge.kind, .edgeHeld)
                }
            case .changed:
                guard let heldEdge else { return }
                parent.onZoneDrag(heldEdge.kind, .edgeHeldMoved(translationX: point.x - heldEdgeStart.x))
            case .ended, .cancelled, .failed:
                // A gesture the system took (a call, Control Center) ends
                // like a lift: the edge stays on the last frame it reached
                // and the trim stays open (§10).
                if let heldEdge { parent.onZoneDrag(heldEdge.kind, .edgeHeldEnded) }
                heldEdge = nil
            default:
                break
            }
        }

        @objc func handleEdgeTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView,
                  let zone = scrollView.edgeHandleZone(at: recognizer.location(in: hostView))
            else { return }
            parent.onZoneDrag(zone.kind, .edgeTapped)
        }

        // MARK: ⌘/⇧-click on a clip body

        @objc func handleModifiedTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView,
                  let zone = scrollView.reorderZone(at: recognizer.location(in: hostView))
            else { return }
            parent.onZoneDrag(zone.kind, .modifiedTap(
                command: modifiedTapFlags.contains(.command),
                shift: modifiedTapFlags.contains(.shift)
            ))
        }

        /// The modified tap takes a touch only with ⌘ or ⇧ down, on a
        /// clip's body; the clip's own tap is told to stand aside.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // The edge's hold and tap only ever see touches on an edge
            // handle: everywhere else they do not exist, so nothing waits
            // on them.
            guard gestureRecognizer === edgeHold || gestureRecognizer === edgeTap else { return true }
            guard let scrollView = gestureRecognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return false }
            return scrollView.edgeHandleZone(at: touch.location(in: hostView)) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
            guard gestureRecognizer === modifiedTap else { return true }
            let flags = event.modifierFlags.intersection([.command, .shift])
            guard !flags.isEmpty,
                  let scrollView = gestureRecognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView,
                  let touch = event.allTouches?.first,
                  let zone = scrollView.reorderZone(at: touch.location(in: hostView))
            else { return false }
            modifiedTapFlags = flags
            parent.onZoneDrag(zone.kind, .holding(atX: touch.location(in: hostView).x))
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView = gestureRecognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return true }
            let point = gestureRecognizer.location(in: hostView)
            if gestureRecognizer === zonePan {
                // A held edge is the frame trim's: its moves walk the grid.
                if let edgeHold, edgeHold.state == .began || edgeHold.state == .changed { return false }
                return scrollView.blockingZone(at: point) != nil
            }
            if gestureRecognizer === reorderPress {
                // A handle's drag is the zone pan's, never a press on the body.
                return scrollView.reorderZone(at: point) != nil && scrollView.blockingZone(at: point) == nil
            }
            if gestureRecognizer === edgeHold || gestureRecognizer === edgeTap {
                return scrollView.edgeHandleZone(at: point) != nil
            }
            return true
        }

        private func scrollView(of recognizer: UIGestureRecognizer) -> UIScrollView? {
            recognizer.view as? UIScrollView
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The zone pan is exclusive. The long-press may run alongside the
            // scroll pan (the press wins once it fires; a quick drag scrubs).
            if gestureRecognizer === zonePan || otherGestureRecognizer === zonePan {
                return false
            }
            // The edge's hold and tap never share the finger with the
            // body's press (the handle sits in front of the body).
            if gestureRecognizer === edgeHold || otherGestureRecognizer === edgeHold
                || gestureRecognizer === edgeTap || otherGestureRecognizer === edgeTap {
                return gestureRecognizer === scrollView(of: gestureRecognizer)?.panGestureRecognizer
                    || otherGestureRecognizer === scrollView(of: gestureRecognizer)?.panGestureRecognizer
            }
            if gestureRecognizer === reorderPress || otherGestureRecognizer === reorderPress {
                return true
            }
            return true
        }
    }
}
