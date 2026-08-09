import Foundation

/// Geometry of the crop frame's ratio presets. It lives in Domain rather than in
/// the controller because "does tapping a chip cost pixels" is a question about
/// arithmetic, and the arithmetic is what the tests can hold on to.
enum CropFrameGeometry {
    /// Smallest frame any preset or gesture may produce, per axis.
    static let minimumEdge = 0.05

    /// `rect` reshaped to `ratio` around its own centre, keeping its **area**.
    ///
    /// Inscribing the requested ratio inside the current frame — what the crop
    /// panel used to do — loses a slice on every switch, so tapping 1:1 · 4:3 ·
    /// 1:1 walked the frame down towards nothing. Equal area makes the presets a
    /// stable round trip: switching back and forth returns the same two frames,
    /// and only a ratio that cannot fit the image at that area is clamped, once.
    ///
    /// - Parameters:
    ///   - ratio: requested width / height of the **displayed** crop.
    ///   - rect: the current frame, normalized against the whole image.
    ///   - imageAspect: width / height of the image the frame sits on, so the
    ///     ratio can be expressed in the rect's own normalized space.
    static func rect(
        matchingRatio ratio: Double,
        keepingAreaOf rect: NormalizedRect,
        imageAspect: Double
    ) -> NormalizedRect {
        let safeAspect: Double = max(0.0001, imageAspect)
        let normalizedRatio: Double = max(0.0001, ratio / safeAspect)
        let minimumArea: Double = minimumEdge * minimumEdge
        let area: Double = min(1, max(minimumArea, rect.width * rect.height))
        var width: Double = (area * normalizedRatio).squareRoot()
        var height: Double = (area / normalizedRatio).squareRoot()
        // A ratio that does not fit the image at this area shrinks to fit — once,
        // because from then on the area it is compared against is the fitted one.
        let fit: Double = min(1, min(1 / max(0.0001, width), 1 / max(0.0001, height)))
        width = min(1, max(minimumEdge, width * fit))
        height = min(1, max(minimumEdge, height * fit))
        let centerX: Double = rect.x + rect.width / 2
        let centerY: Double = rect.y + rect.height / 2
        let x: Double = min(1 - width, max(0, centerX - width / 2))
        let y: Double = min(1 - height, max(0, centerY - height / 2))
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }
}
