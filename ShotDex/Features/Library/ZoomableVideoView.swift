import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed video rendering with Photos-style pinch zoom and pan, without
/// AVKit's automatically positioned chrome (the viewer's Close + info chrome
/// owns the top row, so the transport has to stay hand-built).
///
/// Zoom lives in a `UIScrollView` for the same reason `ZoomableImageView` does:
/// an `AVPlayerLayer` inside the scroll view's zooming content view resizes for
/// free, and the scroll view's own recognizers coexist correctly with the outer
/// `UIPageViewController`.
///
/// Also the only place that can answer "does this layer actually have a frame
/// yet" — `isReadyForDisplay` is reported to the model, which needs it to
/// tell a buffering clip apart from a black screen that will never resolve.
struct ZoomableVideoView: UIViewRepresentable {
    let model: VideoPlaybackModel
    let player: AVPlayer
    /// Changing this snaps zoom back to fit. Entering or leaving immersive
    /// fullscreen re-lays-out the view, so a zoom left over from the previous
    /// geometry would be pointing at the wrong part of the frame.
    let resetToken: Int
    /// Normalized scale (1 = fit). Feeds the same host state the image path
    /// uses, which is what suppresses swipe-to-dismiss and swipe-up-for-metadata
    /// while zoomed.
    let onZoomChange: (CGFloat) -> Void
    /// Location-independent: the caller pauses on any tap while playing, and
    /// toggles chrome otherwise.
    let onSingleTap: () -> Void
    /// Tap location plus the view's own size, in the scroll view's coordinates.
    /// The caller maps halves to ∓10 s — including the rotated fullscreen case,
    /// which is why the size travels with the point.
    let onDoubleTap: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        // At fit scale, horizontal movement belongs to the outer photo pager and
        // vertical movement to swipe-to-dismiss. Pinch still works — that is a
        // separate recognizer.
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
        context.coordinator.resetToken = resetToken
        context.coordinator.apply(self)
        context.coordinator.observe(playerView.playerLayer, model: model)

        // UIKit recognizers rather than SwiftUI `.onTapGesture`: a SwiftUI tap
        // layered over a UIScrollView competes with the scroll view's own
        // recognizers and loses taps during/after a pinch.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.apply(self)

        let layer = context.coordinator.playerView?.playerLayer
        // Only reassign when it genuinely changed. SwiftUI re-runs this on every
        // chrome/inset change, and detaching then re-attaching the same player
        // drops the displayed frame — a black flash for no reason.
        if let layer, layer.player !== player {
            layer.player = player
            context.coordinator.observe(layer, model: model)
        }

        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            context.coordinator.reportZoom(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// `UIView` whose backing layer *is* the `AVPlayerLayer`, so the video
    /// resizes with the zooming content view for free.
    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var playerView: PlayerContainerView?
        var resetToken = 0

        private var observation: NSKeyValueObservation?
        private var onZoomChange: ((CGFloat) -> Void)?
        private var onSingleTap: (() -> Void)?
        private var onDoubleTap: ((CGPoint, CGSize) -> Void)?

        func apply(_ view: ZoomableVideoView) {
            onZoomChange = view.onZoomChange
            onSingleTap = view.onSingleTap
            onDoubleTap = view.onDoubleTap
        }

        func observe(_ layer: AVPlayerLayer, model: VideoPlaybackModel) {
            observation?.invalidate()
            observation = layer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { _, change in
                guard let ready = change.newValue else { return }
                Task { @MainActor in model.noteReadyForDisplay(ready) }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            playerView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            reportZoom(scrollView)
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            reportZoom(scrollView)
        }

        /// Zoomed in, a double-tap is the way back out. At fit scale it belongs
        /// to the transport instead — the halves are ∓10 s, as on YouTube.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                onDoubleTap?(gesture.location(in: scrollView), scrollView.bounds.size)
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }

        func reportZoom(_ scrollView: UIScrollView) {
            let normalized = scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.001)
            // At fit scale the outer pager owns drags; once zoomed, this inner
            // pan is what lets the user inspect the frame.
            scrollView.panGestureRecognizer.isEnabled = normalized > 1.01
            onZoomChange?(normalized)
        }

        deinit { observation?.invalidate() }
    }
}
