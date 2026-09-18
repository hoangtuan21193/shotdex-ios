import Photos
import SwiftUI
import UIKit

/// Payload for the panorama cover.
struct PanoramaPresentation: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// A panorama at full height, scrolled sideways.
///
/// The ordinary viewer fits the whole frame on screen, which for a 10:1 capture
/// is a band a few hundred pixels tall — every reason the photo was taken is
/// thrown away. Here the picture fills the screen's height and the width runs
/// off both edges, so it is seen at the size it was shot, a piece at a time.
///
/// Its own screen rather than a mode inside the viewer: filling the height
/// means the horizontal drag has to scroll the photo, and in the viewer that
/// same drag pages to the next photo. One of the two has to give, and a
/// separate screen is the honest way to say which.
struct PanoramaScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let asset: PHAsset

    @State private var image: UIImage?
    @State private var isTouring = false
    @State private var tourToken = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                PanoramaScrollView(
                    image: image,
                    isTouring: isTouring,
                    tourToken: tourToken,
                    onTourFinished: { isTouring = false }
                )
                .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    GlassIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Close"
                    ) { dismiss() }
                    Spacer()
                    if image != nil {
                        GlassIconButton(
                            systemImage: isTouring ? "pause.fill" : "play.fill",
                            accessibilityLabel: isTouring ? "Stop panning" : "Pan across"
                        ) {
                            if isTouring {
                                isTouring = false
                            } else {
                                // A fresh token restarts the sweep from the
                                // left rather than resuming a stale animation.
                                tourToken += 1
                                isTouring = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                Spacer()
            }
        }
        .statusBarHidden()
        .task { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        // The full frame, not a screen-sized rendition: the whole point is to
        // look at a strip of it at full height, and a fitted rendition would
        // already have thrown the detail away.
        image = await withCheckedContinuation { continuation in
            var hasResumed = false
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

/// Scroll view holding the panorama at screen height, scrolled horizontally,
/// with an optional automatic sweep.
private struct PanoramaScrollView: UIViewRepresentable {
    let image: UIImage
    let isTouring: Bool
    /// Bumped to start a new sweep from the left edge.
    let tourToken: Int
    let onTourFinished: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator
        // Zoom out to the whole panorama, or in past full height.
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 3

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.onTourFinished = onTourFinished
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.onTourFinished = onTourFinished
        context.coordinator.layout(scrollView, image: image)
        context.coordinator.setTouring(isTouring, token: tourToken, in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var onTourFinished: (() -> Void)?
        private var laidOutSize: CGSize = .zero
        private var appliedTourToken: Int?
        private var isTouring = false

        func layout(_ scrollView: UIScrollView, image: UIImage) {
            let bounds = scrollView.bounds.size
            guard bounds.height > 0, image.size.height > 0 else { return }
            guard bounds != laidOutSize else { return }
            laidOutSize = bounds

            // Height fills the screen; width follows the photo's proportions,
            // which for a panorama is many screens wide.
            let width = bounds.height * (image.size.width / image.size.height)
            imageView?.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            scrollView.contentSize = CGSize(width: width, height: bounds.height)
            // Centred, like Photos: a panorama opens in the middle of itself,
            // and the sweep starts from the left when asked for.
            scrollView.contentOffset.x = max(0, (width - bounds.width) / 2)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // A hand on the photo always wins over the automatic sweep.
            guard isTouring else { return }
            stopTour(in: scrollView)
            onTourFinished?()
        }

        func setTouring(_ touring: Bool, token: Int, in scrollView: UIScrollView) {
            if touring, appliedTourToken != token {
                appliedTourToken = token
                startTour(in: scrollView)
            } else if !touring, isTouring {
                stopTour(in: scrollView)
            }
        }

        /// One slow pass from the left edge to the right, at a speed that reads
        /// as looking rather than scrolling: about a screen every four seconds.
        private func startTour(in scrollView: UIScrollView) {
            let travel = scrollView.contentSize.width - scrollView.bounds.width
            guard travel > 1 else {
                onTourFinished?()
                return
            }
            isTouring = true
            scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
            let duration = Double(travel / max(scrollView.bounds.width, 1)) * 4
            UIView.animate(
                withDuration: duration,
                delay: 0.45,
                options: [.curveLinear, .allowUserInteraction]
            ) {
                scrollView.contentOffset = CGPoint(x: travel, y: 0)
            } completion: { [weak self] finished in
                guard finished, self?.isTouring == true else { return }
                self?.isTouring = false
                self?.onTourFinished?()
            }
        }

        private func stopTour(in scrollView: UIScrollView) {
            isTouring = false
            // Freeze where the animation had actually reached, not where it was
            // heading: the presentation layer is what the user can see.
            let visibleX = scrollView.layer.presentation()?.bounds.origin.x
            scrollView.layer.removeAllAnimations()
            if let visibleX {
                scrollView.contentOffset.x = visibleX
            }
        }
    }
}
