import CoreImage

public extension PhotoRenderService {
    // MARK: Vignette (Effects — with Roundness, Highlights and Style)

    /// The post-crop vignette. Lightroom's sign — negative darkens — and its
    /// three styles (FS-03.15b §5), all in the one `vignette` kernel so a
    /// Style change never switches the fall-off shape under the slider. If
    /// the kernel fails to compile the picture is left untouched.
    static func applyVignette(
        _ adjustments: PhotoAdjustments,
        style: PhotoVignetteStyle = .highlightPriority,
        to input: CIImage
    ) -> CIImage {
        applyVignette(adjustments, style: style, to: input, kernel: vignetteKernel)
    }

    /// `kernel` is a parameter so a test can hand in `nil` (FS-16 AC-7).
    internal static func applyVignette(
        _ adjustments: PhotoAdjustments,
        style: PhotoVignetteStyle = .highlightPriority,
        to input: CIImage,
        kernel: CIColorKernel?
    ) -> CIImage {
        guard abs(adjustments.vignette) > 0.0001, let kernel else { return input }
        let extent = input.extent
        // Distance is measured in half-extent units: an ellipse's corner sits at
        // ~1.41, its edge midpoints at 1.0.
        let base = 0.4 + adjustments.vignetteMidpoint * 0.9
        let inner = base * (1 - adjustments.vignetteFeather * 0.6)
        let outer = base + adjustments.vignetteFeather * 0.5 + 0.05
        let roundExponent = max(1.2, 2 + adjustments.vignetteRoundness * 3)
        let styleCode: Double = switch style {
        case .highlightPriority: 0
        case .colorPriority: 1
        case .paintOverlay: 2
        }
        let output = kernel.apply(
            extent: extent,
            arguments: [
                input,
                CIVector(x: extent.midX, y: extent.midY),
                CIVector(x: extent.width / 2, y: extent.height / 2),
                inner,
                outer,
                adjustments.vignette,
                roundExponent,
                adjustments.vignetteHighlights,
                styleCode,
            ]
        )
        return output ?? input
    }

    internal static let vignetteKernel = CoreImageKernelLibrary.kit.colorKernel(named: "vignette")

    // MARK: Optics

    /// Chromatic-aberration removal — an **approximation**: a gentle chroma
    /// cleanup that softens colour fringing without touching luminance detail.
    /// The old whole-frame Defringe is gone; the edge-based purple/green
    /// Defringe of FS-03.15b replaces it.
    static func applyOptics(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        var image = applyDefringe(adjustments, to: input)
        if adjustments.chromaticAberration >= 0.5 {
            image = filtered(
                "CINoiseReduction",
                image: image,
                values: [
                    "inputNoiseLevel": 0.02,
                    "inputSharpness": 0.9,
                ]
            )
        }
        return image
    }

    // MARK: Manual lens vignetting

    /// Manual lens Vignetting (FS-03.15b §3): positive brightens the corners,
    /// negative darkens them, in stops — ±100 is ±1 EV at the corner. A
    /// property of the lens, so it is circular about the centre of the frame
    /// **before** crop and runs in linear light straight after Lens Blur,
    /// where the Effects vignette is framed on the crop and runs last.
    /// Midpoint moves where the fall-off starts. Reuses the `vignette` kernel.
    static func applyManualLensVignetting(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        let amount = min(1, max(-1, adjustments.lensManualVignetting))
        guard abs(amount) > 0.0001, let kernel = vignetteKernel else { return input }
        let extent = input.extent
        let halfDiagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot() / 2
        let inner = 0.1 + min(1, max(0, adjustments.lensManualVignettingMidpoint)) * 0.8
        // Color Priority with nothing held back is plain stops: the kernel
        // moves 2 · amount stops at the corner, so half the slider is ±1 EV.
        let output = kernel.apply(
            extent: extent,
            arguments: [
                input,
                CIVector(x: extent.midX, y: extent.midY),
                CIVector(x: halfDiagonal, y: halfDiagonal),
                inner,
                1.0,
                amount / 2,
                2.0,
                0.0,
                1.0,
            ]
        )
        return output ?? input
    }

    // MARK: Defringe

    /// Purple and green Defringe (FS-03.15b §2): only near high-contrast
    /// edges — a luminance edge map, grown 3px so it covers the fringe beside
    /// the step, then softened — pixels whose hue is in a band lose chroma.
    /// A purple flower mid-frame is not an edge and keeps its colour.
    ///
    /// Amount 0…1 is Lightroom's 0…20; at 10 the band's chroma is 80% gone.
    /// Hue rows 0…1 are Lightroom's 0…100 over 230°…350° (purple) and
    /// 60°…180° (green).
    static func applyDefringe(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        let purpleAmount = min(1, max(0, adjustments.defringePurpleAmount))
        let greenAmount = min(1, max(0, adjustments.defringeGreenAmount))
        guard purpleAmount > 0.001 || greenAmount > 0.001,
              let kernel = defringeKernel,
              let edgeKernel = edgeMaskKernel
        else { return input }
        let extent = input.extent
        let edges = filtered("CIEdges", image: input, values: [kCIInputIntensityKey: 4.0])
        guard let hard = edgeKernel.apply(extent: extent, arguments: [edges, 0.3, 0.6]) else { return input }
        let grown = filtered("CIMorphologyMaximum", image: hard, values: [kCIInputRadiusKey: 3])
        let edgeMap = blurred(grown, radius: 1)

        func band(_ amount: Double, _ hues: ClosedRange<Double>, from start: Double) -> CIVector {
            CIVector(x: min(1, amount * 1.6), y: start + hues.lowerBound * 120, z: start + hues.upperBound * 120)
        }
        let purple = band(
            purpleAmount,
            defringeHueBand(minimum: adjustments.defringePurpleHueMinimum, maximum: adjustments.defringePurpleHueMaximum),
            from: 230
        )
        let green = band(
            greenAmount,
            defringeHueBand(minimum: adjustments.defringeGreenHueMinimum, maximum: adjustments.defringeGreenHueMaximum),
            from: 60
        )
        return kernel.apply(extent: extent, arguments: [input, edgeMap, purple, green]) ?? input
    }

    /// The two hue rows as a band: in order, and at least 10 (Lightroom's
    /// minimum) wide, widened about its middle when the rows sit closer.
    static func defringeHueBand(minimum: Double, maximum: Double) -> ClosedRange<Double> {
        let gap = 0.1
        let low = min(minimum, maximum), high = max(minimum, maximum)
        guard high - low < gap else { return low...high }
        let middle = min(1 - gap / 2, max(gap / 2, (low + high) / 2))
        return (middle - gap / 2)...(middle + gap / 2)
    }

    static let defringeKernel = CoreImageKernelLibrary.kit.colorKernel(named: "defringe")

    // MARK: Geo (transform)

    /// Rotate / scale / offset (affine) then vertical + horizontal keystone
    /// (perspective), clamped so the transform never leaves transparent corners.
    ///
    /// Applied on the whole frame before crop/masks. Upright auto-detection and a
    /// crop-aware coordinate remap are **not** done — combining a heavy Geo warp
    /// with masks can misalign the mask; the common case (Geo without masks) is
    /// exact.
    static func applyGeo(
        _ sliders: PhotoAdjustments,
        upright: PhotoUprightTransform = .identity,
        to input: CIImage
    ) -> CIImage {
        // The solved Upright transform and the sliders add: Upright is stored
        // apart (FS-03.15b §4) so Off hands the sliders back exactly.
        var adjustments = sliders
        adjustments.geoRotate += upright.rotate
        adjustments.geoVertical += upright.vertical
        adjustments.geoHorizontal += upright.horizontal
        adjustments.geoAspect += upright.aspect
        adjustments.geoScale += upright.scale
        adjustments.geoOffsetX += upright.offsetX
        adjustments.geoOffsetY += upright.offsetY
        let extent = input.extent
        var image = input

        let hasAffine = abs(adjustments.geoRotate) > 0.0001
            || abs(adjustments.geoAspect) > 0.0001
            || abs(adjustments.geoScale) > 0.0001
            || abs(adjustments.geoOffsetX) > 0.0001
            || abs(adjustments.geoOffsetY) > 0.0001
        // Where the photo's own corners land: the affine, then the keystone.
        // Constrain Crop fits the frame inside that quad.
        var quad = [
            CGPoint(x: extent.minX, y: extent.minY), CGPoint(x: extent.maxX, y: extent.minY),
            CGPoint(x: extent.maxX, y: extent.maxY), CGPoint(x: extent.minX, y: extent.maxY),
        ]
        if hasAffine {
            let transform = geoAffine(adjustments, extent: extent)
            image = image.clampedToExtent().transformed(by: transform).cropped(to: extent)
            quad = quad.map { $0.applying(transform) }
        }

        if abs(adjustments.geoVertical) > 0.0001 || abs(adjustments.geoHorizontal) > 0.0001 {
            let corners = keystoneCorners(
                vertical: adjustments.geoVertical,
                horizontal: adjustments.geoHorizontal,
                extent: extent
            )
            // With the extent named: plain CIPerspectiveTransform on a
            // clamped (infinite) image has no corners to move and hands the
            // picture back untouched — which is what Vertical and Horizontal
            // did until FS-03.15b AC-29 measured it.
            image = filtered(
                "CIPerspectiveTransformWithExtent",
                image: image.clampedToExtent(),
                values: [
                    "inputExtent": CIVector(cgRect: extent),
                    "inputTopLeft": CIVector(cgPoint: corners[3]),
                    "inputTopRight": CIVector(cgPoint: corners[2]),
                    "inputBottomRight": CIVector(cgPoint: corners[1]),
                    "inputBottomLeft": CIVector(cgPoint: corners[0]),
                ]
            ).cropped(to: extent)
            if let homography = Homography(from: extentCorners(extent), to: corners) {
                quad = quad.map(homography.apply)
            }
        }

        guard adjustments.geoConstrainCrop >= 0.5, hasAffine || abs(adjustments.geoVertical) > 0.0001
            || abs(adjustments.geoHorizontal) > 0.0001
        else { return image }
        let zoom = constrainZoom(quad: quad, extent: extent)
        guard zoom > 1.0001 else { return image }
        let fill = CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return image.transformed(by: fill).cropped(to: extent)
    }

    /// Rotate, Scale, Aspect and Offset as one transform about the centre.
    static func geoAffine(_ adjustments: PhotoAdjustments, extent: CGRect) -> CGAffineTransform {
        let angle = adjustments.geoRotate * 0.35
        let scale = 1 + adjustments.geoScale * 0.3
        let tx = adjustments.geoOffsetX * extent.width * 0.2
        let ty = adjustments.geoOffsetY * extent.height * 0.2
        var transform = CGAffineTransform(translationX: extent.midX + tx, y: extent.midY + ty)
        transform = transform.rotated(by: angle)
        transform = transform.scaledBy(x: scale, y: scale)
        let aspect = aspectScale(adjustments.geoAspect)
        transform = transform.scaledBy(x: aspect.x, y: aspect.y)
        return transform.translatedBy(x: -extent.midX, y: -extent.midY)
    }

    /// Constrain Crop's zoom: the smallest scale about the centre at which the
    /// frame, same aspect, sits wholly inside `quad` — where the photo's
    /// corners landed — so nothing on screen was stretched in from outside
    /// the photo. Found by bisection on the frame's four corners; 1 when the
    /// frame already fits.
    static func constrainZoom(quad: [CGPoint], extent: CGRect) -> Double {
        func fits(_ fraction: Double) -> Bool {
            let halfWidth = extent.width / 2 * fraction, halfHeight = extent.height / 2 * fraction
            let corners = [
                CGPoint(x: extent.midX - halfWidth, y: extent.midY - halfHeight),
                CGPoint(x: extent.midX + halfWidth, y: extent.midY - halfHeight),
                CGPoint(x: extent.midX + halfWidth, y: extent.midY + halfHeight),
                CGPoint(x: extent.midX - halfWidth, y: extent.midY + halfHeight),
            ]
            return corners.allSatisfy { contains(quad, $0) }
        }
        guard !fits(1) else { return 1 }
        var low = 0.05, high = 1.0
        for _ in 0..<30 {
            let middle = (low + high) / 2
            if fits(middle) { low = middle } else { high = middle }
        }
        return 1 / low
    }

    /// Whether a convex quad (either winding) holds `point`, edges included.
    private static func contains(_ quad: [CGPoint], _ point: CGPoint) -> Bool {
        var sign = 0.0
        for index in quad.indices {
            let a = quad[index], b = quad[(index + 1) % quad.count]
            let cross = Double((b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x))
            if abs(cross) < 1e-9 { continue }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }

    static func extentCorners(_ extent: CGRect) -> [CGPoint] {
        [
            CGPoint(x: extent.minX, y: extent.minY), CGPoint(x: extent.maxX, y: extent.minY),
            CGPoint(x: extent.maxX, y: extent.maxY), CGPoint(x: extent.minX, y: extent.maxY),
        ]
    }

    /// Aspect's stretch: width against height becomes 1.5^value. The axis that
    /// grows is the one scaled, never the other shrunk, so no edge pulls in
    /// past the frame and no corner shows empty.
    static func aspectScale(_ value: Double) -> (x: CGFloat, y: CGFloat) {
        let ratio = pow(1.5, min(1, max(-1, value)))
        return (CGFloat(max(1, ratio)), CGFloat(max(1, 1 / ratio)))
    }

    /// Where the keystone sends the frame's corners — bottom-left,
    /// bottom-right, top-right, top-left.
    static func keystoneCorners(vertical: Double, horizontal: Double, extent: CGRect) -> [CGPoint] {
        let v = CGFloat(vertical) * 0.25
        let h = CGFloat(horizontal) * 0.25
        let halfWidth = extent.width / 2
        let halfHeight = extent.height / 2
        func corner(_ signX: CGFloat, _ signY: CGFloat) -> CGPoint {
            let xScale = signY > 0 ? (1 + v) : (1 - v)
            let yScale = signX < 0 ? (1 + h) : (1 - h)
            return CGPoint(
                x: extent.midX + signX * halfWidth * xScale,
                y: extent.midY + signY * halfHeight * yScale
            )
        }
        return [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)]
    }
}

/// The projective map taking four points to four others — what
/// `CIPerspectiveTransform` does to the frame's corners — so a point can be
/// followed through it.
struct Homography: Sendable {
    private let m: [Double]

    init?(from source: [CGPoint], to target: [CGPoint]) {
        guard source.count == 4, target.count == 4 else { return nil }
        // Eight equations, eight unknowns (h33 = 1), by Gaussian elimination.
        var rows: [[Double]] = []
        for (s, t) in zip(source, target) {
            let x = Double(s.x), y = Double(s.y), u = Double(t.x), v = Double(t.y)
            rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u])
            rows.append([0, 0, 0, x, y, 1, -v * x, -v * y, v])
        }
        for column in 0..<8 {
            guard let pivot = (column..<8).max(by: { abs(rows[$0][column]) < abs(rows[$1][column]) }),
                  abs(rows[pivot][column]) > 1e-12 else { return nil }
            rows.swapAt(column, pivot)
            for row in 0..<8 where row != column {
                let factor = rows[row][column] / rows[column][column]
                for k in column...8 { rows[row][k] -= factor * rows[column][k] }
            }
        }
        m = (0..<8).map { rows[$0][8] / rows[$0][$0] } + [1]
    }

    func apply(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x), y = Double(point.y)
        let w = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w, y: (m[3] * x + m[4] * y + m[5]) / w)
    }
}

/// Where Geometry sends a point of the photo: the same affine, keystone and
/// Constrain Crop zoom `applyGeo` applies, followed point by point — so a
/// guide drawn on the corrected picture can be taken back to the photo, and
/// a guide on the photo shown where the correction put it (FS-03.15b §4).
public struct GeoForwardMap: Sendable {
    private let affine: CGAffineTransform?
    private let homography: Homography?
    private let inverseHomography: Homography?
    private let zoom: CGAffineTransform?

    public init(adjustments sliders: PhotoAdjustments, upright: PhotoUprightTransform, extent: CGRect) {
        var adjustments = sliders
        adjustments.geoRotate += upright.rotate
        adjustments.geoVertical += upright.vertical
        adjustments.geoHorizontal += upright.horizontal
        adjustments.geoAspect += upright.aspect
        adjustments.geoScale += upright.scale
        adjustments.geoOffsetX += upright.offsetX
        adjustments.geoOffsetY += upright.offsetY

        let hasAffine = abs(adjustments.geoRotate) > 0.0001 || abs(adjustments.geoAspect) > 0.0001
            || abs(adjustments.geoScale) > 0.0001 || abs(adjustments.geoOffsetX) > 0.0001
            || abs(adjustments.geoOffsetY) > 0.0001
        let hasKeystone = abs(adjustments.geoVertical) > 0.0001 || abs(adjustments.geoHorizontal) > 0.0001
        var quad = PhotoRenderService.extentCorners(extent)
        if hasAffine {
            let transform = PhotoRenderService.geoAffine(adjustments, extent: extent)
            affine = transform
            quad = quad.map { $0.applying(transform) }
        } else {
            affine = nil
        }
        if hasKeystone {
            let corners = PhotoRenderService.keystoneCorners(
                vertical: adjustments.geoVertical,
                horizontal: adjustments.geoHorizontal,
                extent: extent
            )
            let source = PhotoRenderService.extentCorners(extent)
            homography = Homography(from: source, to: corners)
            inverseHomography = Homography(from: corners, to: source)
            if let homography { quad = quad.map(homography.apply) }
        } else {
            homography = nil
            inverseHomography = nil
        }
        if adjustments.geoConstrainCrop >= 0.5, hasAffine || hasKeystone {
            let factor = PhotoRenderService.constrainZoom(quad: quad, extent: extent)
            zoom = factor > 1.0001
                ? CGAffineTransform(translationX: extent.midX, y: extent.midY)
                    .scaledBy(x: factor, y: factor)
                    .translatedBy(x: -extent.midX, y: -extent.midY)
                : nil
        } else {
            zoom = nil
        }
    }

    /// Photo point → corrected frame, both in the frame's own coordinates.
    public func apply(_ point: CGPoint) -> CGPoint {
        var p = point
        if let affine { p = p.applying(affine) }
        if let homography { p = homography.apply(p) }
        if let zoom { p = p.applying(zoom) }
        return p
    }

    /// Corrected frame → photo point.
    public func inverse(_ point: CGPoint) -> CGPoint {
        var p = point
        if let zoom { p = p.applying(zoom.inverted()) }
        if let inverseHomography { p = inverseHomography.apply(p) }
        if let affine { p = p.applying(affine.inverted()) }
        return p
    }
}
