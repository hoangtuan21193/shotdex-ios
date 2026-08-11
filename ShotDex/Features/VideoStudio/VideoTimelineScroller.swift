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
        case textBody(UUID)
        case textLeadingHandle(UUID)
        case textTrailingHandle(UUID)

        /// Reorder rides a long-press so a plain drag over a selected clip
        /// still scrubs; the handle/body zones block the scroll pan instead.
        var isReorder: Bool {
            if case .clipReorder = self { return true }
            return false
        }
    }
    var kind: Kind
    var rect: CGRect
}

enum TimelineZoneDragPhase {
    case changed(translationX: CGFloat)
    case ended(translationX: CGFloat)
    case cancelled
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
    var currentTime: Double
    var pps: CGFloat
    var dragZones: [TimelineDragZone]
    var onScrubStart: () -> Void
    var onScrubTime: (Double) -> Void
    var onScrubEnd: (Double) -> Void
    var onPinch: (TimelinePinchPhase) -> Void
    var onZoneDrag: (TimelineDragZone.Kind, TimelineZoneDragPhase) -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TimelineScrollView {
        let scrollView = TimelineScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.decelerationRate = .fast
        scrollView.scrollsToTop = false
        scrollView.delaysContentTouches = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)
        let widthConstraint = host.view.widthAnchor.constraint(equalToConstant: max(contentWidth, 1))
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            host.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            widthConstraint,
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

        // Reorder: long-press a clip body then drag. Coexists with scrolling —
        // a quick drag scrubs, a held drag reorders.
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleReorder(_:))
        )
        longPress.minimumPressDuration = 0.32
        longPress.delegate = context.coordinator
        scrollView.addGestureRecognizer(longPress)
        context.coordinator.reorderPress = longPress

        context.coordinator.host = host
        context.coordinator.widthConstraint = widthConstraint
        scrollView.hostView = host.view
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
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
        scrollView.dragZones = dragZones
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
        var zonePan: UIPanGestureRecognizer?
        var reorderPress: UILongPressGestureRecognizer?

        private var isProgrammaticScroll = false
        private(set) var isPinching = false
        private var pinchAnchorTime: Double = 0
        private var activeZone: TimelineDragZone?
        private var reorderZone: TimelineDragZone?
        private var reorderStart: CGPoint = .zero

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
            guard !isProgrammaticScroll, !isPinching, isUserDriven(scrollView) else { return }
            parent.onScrubTime(time(at: scrollView.contentOffset.x, in: scrollView))
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

        // MARK: Reorder (long-press then drag a clip body)

        @objc func handleReorder(_ recognizer: UILongPressGestureRecognizer) {
            guard let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return }
            let point = recognizer.location(in: hostView)
            switch recognizer.state {
            case .began:
                reorderZone = scrollView.reorderZone(at: point)
                reorderStart = point
                if reorderZone != nil {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    parent.onZoneDrag(reorderZone!.kind, .changed(translationX: 0))
                }
            case .changed:
                guard let reorderZone else { return }
                parent.onZoneDrag(reorderZone.kind, .changed(translationX: point.x - reorderStart.x))
            case .ended:
                guard let reorderZone else { return }
                parent.onZoneDrag(reorderZone.kind, .ended(translationX: point.x - reorderStart.x))
                self.reorderZone = nil
            case .cancelled, .failed:
                if let reorderZone { parent.onZoneDrag(reorderZone.kind, .cancelled) }
                reorderZone = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView = gestureRecognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return true }
            let point = gestureRecognizer.location(in: hostView)
            if gestureRecognizer === zonePan {
                return scrollView.blockingZone(at: point) != nil
            }
            if gestureRecognizer === reorderPress {
                return scrollView.reorderZone(at: point) != nil
            }
            return true
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
            if gestureRecognizer === reorderPress || otherGestureRecognizer === reorderPress {
                return true
            }
            return true
        }
    }
}
