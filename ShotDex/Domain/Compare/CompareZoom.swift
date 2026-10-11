import CoreGraphics

/// Compare's two zoom levels (FS-01.08c §3): **Fit** — the whole photo in
/// its box — and **100%**, one pixel of the original per pixel of the
/// screen. Zoom scales here are a scroll view's, where 1 is Fit.
enum CompareZoom: Equatable, Sendable {
    case fit
    case actualPixels

    /// The scroll view's zoom scale that shows `pixelSize` at 100% in a box
    /// of `box` points on a display of `screenScale`. A photo smaller than
    /// its box at Fit is already past 100%; it stays at 1 rather than zoom
    /// out.
    static func actualPixelsScale(pixelSize: CGSize, box: CGSize, screenScale: CGFloat) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0, box.width > 0, box.height > 0, screenScale > 0 else {
            return 1
        }
        let fit = min(box.width / pixelSize.width, box.height / pixelSize.height)
        return max(1, 1 / (fit * screenScale))
    }

    /// What a zoom scale is, in percent of the original's pixels, for the
    /// frame's label. Nil at Fit, where the frame says nothing.
    static func percent(zoomScale: CGFloat, pixelSize: CGSize, box: CGSize, screenScale: CGFloat) -> Int? {
        guard zoomScale > 1.01 else { return nil }
        let full = actualPixelsScale(pixelSize: pixelSize, box: box, screenScale: screenScale)
        let value = Int((zoomScale / full * 100).rounded())
        // Within a few percent of the original reads as 100% — a pinch never
        // lands exactly on it, and 98% next to 100% is noise.
        return abs(value - 100) <= 3 ? 100 : value
    }

    /// `Z` and the popup: Fit goes to 100%, anything else back to Fit.
    func toggled() -> CompareZoom { self == .fit ? .actualPixels : .fit }

    /// The level a zoom scale counts as, for the popup's checkmark.
    static func level(zoomScale: CGFloat) -> CompareZoom { zoomScale > 1.01 ? .actualPixels : .fit }
}
