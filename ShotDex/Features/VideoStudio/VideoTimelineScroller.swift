import SwiftUI
import UIKit

/// Pinch phases the timeline reports to whoever owns the points-per-second
/// scale. The anchor time is captured at `.began` and the scroller itself
/// keeps it pinned under the playhead while the scale changes.
enum TimelinePinchPhase {
    case began
    case changed(scale: CGFloat)
    case ended
}

/// A draggable region of the timeline content. SwiftUI drag gestures never
/// activate inside the hosted content of a UIScrollView (they defer to the
/// scroll pan forever, even when it is vetoed), so dragging is routed through
/// a UIKit pan on the scroller: rows publish these zones, the scroller
/// hit-tests its dedicated pan against them and reports phases back.
struct TimelineDragZone: Equatable {
    enum Kind: Equatable, Hashable {
        case textBody(UUID)
        case textLeadingHandle(UUID)
        case textTrailingHandle(UUID)
        case clipReorder(UUID)
    }
    var kind: Kind
    var rect: CGRect
}

enum TimelineZoneDragPhase {
    case changed(translationX: CGFloat)
    case ended(translationX: CGFloat)
    case cancelled
}

/// The timeline's horizontal scroller: a `UIScrollView` wrapping hosted
/// SwiftUI track rows, with a fixed centre playhead. iOS 17 has no
/// `onScrollGeometryChange`, and `ScrollViewReader` can neither read a
/// continuous offset nor write one at 30 Hz without animating — so UIKit it is.
///
/// Time ↔ offset mapping: `contentInset` is half the viewport on both sides,
/// so `time = (contentOffset.x + inset.left) / pps` and t = 0 sits exactly
/// under the centre playhead when scrolled fully left.
///
/// Feedback-loop arbitration: while the user drags/decelerates, the offset is
/// the source of truth (`onScrubTime` drives the model, whose time observer
/// already ignores ticks while scrubbing); while playing, `currentTime` is the
/// source of truth and programmatic offset writes are flagged so the delegate
/// echo is ignored. The two can never both write in one frame.
struct VideoTimelineScroller<Content: View>: UIViewRepresentable {
    var contentWidth: CGFloat
    var currentTime: Double
    var pps: CGFloat
    /// Content-space regions the zone pan owns; the scroll pan refuses to
    /// begin inside them.
    var dragZones: [TimelineDragZone]
    var onScrubStart: () -> Void
    var onScrubTime: (Double) -> Void
    var onScrubEnd: (Double) -> Void
    var onPinch: (TimelinePinchPhase) -> Void
    var onZoneDrag: (TimelineDragZone.Kind, TimelineZoneDragPhase) -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

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
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        scrollView.addGestureRecognizer(pinch)

        // The dedicated drag-zone pan (text bars, clip reorder). Begins only
        // inside a published zone, so it never steals plain scrubbing.
        let zonePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleZonePan(_:))
        )
        zonePan.delegate = context.coordinator
        zonePan.maximumNumberOfTouches = 1
        scrollView.addGestureRecognizer(zonePan)
        context.coordinator.zonePan = zonePan

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

        func zone(at point: CGPoint) -> TimelineDragZone? {
            dragZones.first { $0.rect.contains(point) }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGestureRecognizer, let hostView {
                let point = gestureRecognizer.location(in: hostView)
                if zone(at: point) != nil { return false }
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

        private var isProgrammaticScroll = false
        private(set) var isPinching = false
        private var pinchAnchorTime: Double = 0
        private var activeZone: TimelineDragZone?

        init(_ parent: VideoTimelineScroller) {
            self.parent = parent
        }

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

        /// Playback → offset (and initial positioning, pinch re-anchoring).
        /// Never fights the user: only writes while no touch owns the scroll.
        func syncOffsetIfIdle(_ scrollView: UIScrollView) {
            // A pinch keeps `isTracking` true, but the anchor must stay pinned
            // under the playhead while the scale changes — pinch overrides.
            guard scrollView.bounds.width > 0,
                  isPinching || !isUserDriven(scrollView)
            else { return }
            let target = offsetX(
                forTime: isPinching ? pinchAnchorTime : parent.currentTime,
                in: scrollView
            )
            guard abs(target - scrollView.contentOffset.x) > 0.5 else { return }
            // The setter fires scrollViewDidScroll synchronously, so the flag
            // safely brackets it.
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
                // The parent's pps state change re-invokes updateUIView, but
                // re-anchor immediately too so the frame this event lands in
                // doesn't jitter.
                syncOffsetIfIdle(scrollView)
            case .ended, .cancelled, .failed:
                isPinching = false
                parent.onPinch(.ended)
            default:
                break
            }
        }

        // MARK: Zone drag (text bars, clip reorder)

        @objc func handleZonePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = recognizer.view as? TimelineScrollView,
                  let hostView = scrollView.hostView
            else { return }
            switch recognizer.state {
            case .began:
                // shouldBegin already verified the zone; re-resolve it here
                // because the recognizer's location has settled by now.
                let start = recognizer.location(in: hostView)
                let translation = recognizer.translation(in: hostView)
                let origin = CGPoint(x: start.x - translation.x, y: start.y - translation.y)
                activeZone = scrollView.zone(at: origin) ?? scrollView.zone(at: start)
                if let activeZone {
                    parent.onZoneDrag(activeZone.kind, .changed(translationX: translation.x))
                }
            case .changed:
                guard let activeZone else { return }
                let translation = recognizer.translation(in: hostView)
                parent.onZoneDrag(activeZone.kind, .changed(translationX: translation.x))
            case .ended:
                guard let activeZone else { return }
                let translation = recognizer.translation(in: hostView)
                parent.onZoneDrag(activeZone.kind, .ended(translationX: translation.x))
                self.activeZone = nil
            case .cancelled, .failed:
                if let activeZone {
                    parent.onZoneDrag(activeZone.kind, .cancelled)
                }
                activeZone = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === zonePan,
               let scrollView = gestureRecognizer.view as? TimelineScrollView,
               let hostView = scrollView.hostView {
                return scrollView.zone(at: gestureRecognizer.location(in: hostView)) != nil
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The zone pan must stay exclusive: the scroll pan is already
            // vetoed inside zones, and running both would double-handle.
            if gestureRecognizer === zonePan || otherGestureRecognizer === zonePan {
                return false
            }
            // Pinch may start mid-scroll; `isPinching` silences the scrub
            // callbacks while both are active.
            return true
        }
    }
}
