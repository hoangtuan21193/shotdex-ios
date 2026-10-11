import AVKit
import SwiftUI
import UIKit

/// Mirrors zoom and pan across Compare's frames (FS-01.08c §1, 08 §5).
/// Always on: comparing two photos at different zooms is not a comparison,
/// so there is no switch (AC-16).
@MainActor
final class CompareScrollSynchronizer {
    /// Told the zoom scale after every change, for the frames' `100%` label
    /// and the zoom popup's checkmark.
    var onZoomChange: ((CGFloat) -> Void)?

    /// Weak, because frames are built and dropped as candidates come and go
    /// — a frame that is gone must not be mirrored into forever.
    private var scrollViews: [Int: WeakScrollView] = [:]
    private var isPropagating = false
    /// The last state a gesture produced, replayed onto frames that are built
    /// later so the next candidate arrives in step.
    private var lastZoomScale: CGFloat?
    private var lastOffsetFraction: CGPoint?

    /// The zoom the comparison is at; 1 is Fit.
    var zoomScale: CGFloat { lastZoomScale ?? 1 }

    func register(_ scrollView: UIScrollView, at index: Int) {
        scrollViews[index] = WeakScrollView(view: scrollView)
        guard lastZoomScale != nil || lastOffsetFraction != nil else { return }
        // `makeUIView` runs before the frame has a size (so no content size to
        // offset against); the catch-up waits for the layout pass after it.
        Task { @MainActor [weak scrollView] in
            guard let scrollView else { return }
            applyStoredState(to: scrollView)
        }
    }

    private struct WeakScrollView {
        weak var view: UIScrollView?
    }

    private var liveScrollViews: [UIScrollView] {
        scrollViews.values.compactMap(\.view)
    }

    private func applyStoredState(to scrollView: UIScrollView) {
        isPropagating = true
        defer { isPropagating = false }
        if let lastZoomScale {
            scrollView.zoomScale = lastZoomScale
        }
        if let lastOffsetFraction {
            scrollView.contentOffset = CGPoint(
                x: lastOffsetFraction.x * scrollView.contentSize.width,
                y: lastOffsetFraction.y * scrollView.contentSize.height
            )
        }
    }

    /// Remembers where a gesture left the source frame, for frames built later.
    private func record(_ source: UIScrollView) {
        let changed = lastZoomScale != source.zoomScale
        lastZoomScale = source.zoomScale
        let width = source.contentSize.width
        let height = source.contentSize.height
        if width > 0, height > 0 {
            lastOffsetFraction = CGPoint(
                x: source.contentOffset.x / width,
                y: source.contentOffset.y / height
            )
        }
        if changed { onZoomChange?(source.zoomScale) }
    }

    /// Called from scroll-view delegate callbacks; copies the source frame's
    /// zoom and normalized offset to the other frames.
    func mirror(from source: UIScrollView) {
        guard !isPropagating else { return }
        record(source)
        isPropagating = true
        defer { isPropagating = false }
        for target in liveScrollViews where target !== source {
            if target.zoomScale != source.zoomScale {
                target.zoomScale = source.zoomScale
            }
            target.contentOffset = Self.normalizedOffset(from: source, to: target)
        }
    }

    /// Zooms frame `index` to `scale` about its centre — the popup's Fit and
    /// 100%, and the `Z` key — and the others follow through `mirror`.
    func zoom(frameAt index: Int, to scale: CGFloat, animated: Bool = true) {
        guard let scrollView = scrollViews[index]?.view else { return }
        let clamped = min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        guard let content = scrollView.delegate?.viewForZooming?(in: scrollView) else { return }
        let size = CGSize(
            width: content.bounds.width / clamped,
            height: content.bounds.height / clamped
        )
        let rect = CGRect(
            x: content.bounds.midX - size.width / 2,
            y: content.bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        scrollView.zoom(to: rect, animated: animated)
    }

    /// Maps an offset between frames proportionally to their content sizes,
    /// so photos with different aspect ratios stay on the same relative spot.
    private static func normalizedOffset(from source: UIScrollView, to target: UIScrollView) -> CGPoint {
        let sw = source.contentSize.width
        let sh = source.contentSize.height
        guard sw > 0, sh > 0 else { return target.contentOffset }
        return CGPoint(
            x: source.contentOffset.x / sw * target.contentSize.width,
            y: source.contentOffset.y / sh * target.contentSize.height
        )
    }
}

/// UIScrollView-backed zoomable video pane: pinch-to-zoom + double-tap zoom
/// over an `AVPlayerLayer`, participating in the same `CompareScrollSynchronizer`
/// group as image panes so zoom/pan mirror across mixed selections.
struct CompareVideoPaneView: UIViewRepresentable {
    let player: AVPlayer
    let sync: CompareScrollSynchronizer
    let paneIndex: Int
    /// A plain tap on the frame, so a video card is picked the same way a photo
    /// card is. Waits for the double-tap to fail — see `ZoomableImageView`.
    var onSingleTap: (() -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        // At Fit the frame has nothing to pan, so a drag is a swipe to the
        // next candidate; zoomed in, one finger pans (FS-01.08c §3). Pinch is
        // a separate recognizer, so it stays live.
        scrollView.panGestureRecognizer.isEnabled = false

        let playerView = PlayerContainerView()
        playerView.playerLayer.player = player
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            playerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            playerView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.playerView = playerView
        context.coordinator.sync = sync
        sync.register(scrollView, at: paneIndex)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.playerView?.playerLayer.player = player
        context.coordinator.onSingleTap = onSingleTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// UIView whose backing layer is the `AVPlayerLayer`, so the video
    /// resizes with the zooming content view for free.
    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var playerView: PlayerContainerView?
        var sync: CompareScrollSynchronizer?

        var onSingleTap: (() -> Void)?

        @objc func handleSingleTap() {
            onSingleTap?()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            playerView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled =
                scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.001) > 1.01
            sync?.mirror(from: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            sync?.mirror(from: scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: playerView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2.5,
                    height: scrollView.bounds.height / 2.5
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
