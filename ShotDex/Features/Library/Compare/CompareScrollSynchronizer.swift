import SwiftUI
import UIKit

/// Mirrors zoom and pan across Compare's panes (FS-01.08 §3).
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

    /// Zooms frame `index` onto `rect`, given as a share of the photo with a
    /// top-left origin — Zoom to face in the frame picker (FS-06.06 §8).
    /// The other frames, and frames built later, follow.
    func zoom(frameAt index: Int, toNormalized rect: CGRect, scale: CGFloat, animated: Bool = true) {
        guard let scrollView = scrollViews[index]?.view,
              let content = scrollView.delegate?.viewForZooming?(in: scrollView) else { return }
        let clamped = min(max(scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let size = CGSize(width: content.bounds.width / clamped, height: content.bounds.height / clamped)
        let center = CGPoint(x: content.bounds.minX + rect.midX * content.bounds.width,
                             y: content.bounds.minY + rect.midY * content.bounds.height)
        scrollView.zoom(to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                   width: size.width, height: size.height), animated: animated)
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
