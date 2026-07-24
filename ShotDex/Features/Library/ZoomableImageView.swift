import SwiftUI
import UIKit

/// UIScrollView-backed zoomable image: pinch-to-zoom + double-tap zoom.
/// Optionally participates in a `CompareScrollSync` group so zoom and pan
/// mirror across panes (compare screen).
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var sync: CompareScrollSync?
    var paneIndex: Int = 0
    /// Fires at the beginning of a user pinch, before the first scale update.
    /// Detail uses it to start the full-original request reliably.
    var onZoomStart: (() -> Void)?
    /// Reports the current zoom scale on every zoom change — lets a host
    /// (the detail pager) disable swipe-down-dismiss while zoomed in.
    var onZoomChange: ((CGFloat) -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        // At 1x, horizontal movement belongs to the outer photo pager. Pinch
        // remains active because UIScrollView has a separate pinch recognizer.
        scrollView.panGestureRecognizer.isEnabled = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView
        context.coordinator.sync = sync
        context.coordinator.onZoomStart = onZoomStart
        context.coordinator.onZoomChange = onZoomChange
        sync?.register(scrollView, at: paneIndex)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.onZoomStart = onZoomStart
        context.coordinator.onZoomChange = onZoomChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var sync: CompareScrollSync?
        var onZoomStart: (() -> Void)?
        var onZoomChange: ((CGFloat) -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            onZoomStart?()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            sync?.mirror(from: scrollView)
            reportZoom(scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportZoom(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            sync?.mirror(from: scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let targetScale = scrollView.minimumZoomScale * 2.5
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
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

        private func reportZoom(_ scrollView: UIScrollView) {
            let normalized = scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.001)
            // At 1x, horizontal drags belong to the outer page controller.
            // Once the user zooms further, enable this inner pan so they can
            // inspect the image.
            scrollView.panGestureRecognizer.isEnabled = normalized > 1.01
            onZoomChange?(normalized)
        }
    }
}
