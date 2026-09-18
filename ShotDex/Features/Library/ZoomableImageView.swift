import SwiftUI
import UIKit
import VisionKit

/// UIScrollView-backed zoomable image: pinch-to-zoom + double-tap zoom.
/// Optionally participates in a `CompareScrollSynchronizer` group so zoom and pan
/// mirror across panes (compare screen).
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var sync: CompareScrollSynchronizer?
    var paneIndex: Int = 0
    /// Fires at the beginning of a user pinch, before the first scale update.
    /// Detail uses it to start the full-original request reliably.
    var onZoomStart: (() -> Void)?
    /// Reports the current zoom scale on every zoom change — lets a host
    /// (the detail pager) disable swipe-down-dismiss while zoomed in.
    var onZoomChange: ((CGFloat) -> Void)?
    /// Runs Live Text over the displayed image and lets the user select, copy,
    /// translate and look up what it finds — and, from the same analysis, lift
    /// the subject out of the background by pressing and holding it.
    ///
    /// Off by default and driven from the viewer's ⋯ menu for two reasons: the
    /// analysis decodes and scans the image, which is wasted work on the vast
    /// majority of photos; and an active text interaction competes with the
    /// pager's own swipe and the scroll view's pinch.
    var isLiveTextActive: Bool = false
    /// Renders an HDR photo at its real brightness rather than tone-mapped to
    /// the standard range. Off by default and switchable in Settings, because
    /// an HDR frame next to standard chrome makes the chrome look grey, and on
    /// some displays it is simply uncomfortable.
    var showsFullHDR: Bool = false

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
        imageView.preferredImageDynamicRange = showsFullHDR ? .high : .standard
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

        if ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            interaction.preferredInteractionTypes = []
            imageView.addInteraction(interaction)
            imageView.isUserInteractionEnabled = true
            context.coordinator.analysisInteraction = interaction
        }

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
        context.coordinator.imageView?.preferredImageDynamicRange =
            showsFullHDR ? .high : .standard
        context.coordinator.onZoomStart = onZoomStart
        context.coordinator.onZoomChange = onZoomChange
        context.coordinator.setLiveTextActive(isLiveTextActive, for: image)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var analysisInteraction: ImageAnalysisInteraction?
        /// Cutout of everything the analyser considers a subject, for
        /// "Copy Subject". Nil until Live Text has been switched on and the
        /// analysis has landed.
        func copySubjectToPasteboard() async -> Bool {
            guard let interaction = analysisInteraction,
                  interaction.analysis != nil
            else { return false }
            let subjects = await interaction.subjects
            guard !subjects.isEmpty,
                  let cutout = try? await interaction.image(for: subjects)
            else { return false }
            UIPasteboard.general.image = cutout
            return true
        }

        /// Identity of the image the current analysis belongs to, so paging to
        /// another photo does not leave the previous photo's text boxes behind.
        private var analyzedImage: UIImage?
        private var analysisTask: Task<Void, Never>?
        var sync: CompareScrollSynchronizer?
        var onZoomStart: (() -> Void)?
        var onZoomChange: ((CGFloat) -> Void)?

        /// Turns Live Text on or off, analysing lazily the first time it is
        /// asked for a given image.
        @MainActor
        func setLiveTextActive(_ isActive: Bool, for image: UIImage) {
            guard let interaction = analysisInteraction else { return }
            guard isActive else {
                analysisTask?.cancel()
                analysisTask = nil
                interaction.preferredInteractionTypes = []
                interaction.analysis = nil
                analyzedImage = nil
                return
            }
            guard analyzedImage !== image else {
                interaction.preferredInteractionTypes = .automatic
                return
            }
            analysisTask?.cancel()
            analyzedImage = image
            analysisTask = Task { [weak self] in
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
                let analysis = try? await analyzer.analyze(image, configuration: configuration)
                guard !Task.isCancelled, let self, self.analyzedImage === image else { return }
                interaction.analysis = analysis
                // `.automatic` covers text selection and subject lifting in
                // one: a long press on the subject lifts it, exactly as in
                // Photos, with no extra plumbing.
                interaction.preferredInteractionTypes = .automatic
            }
        }

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
