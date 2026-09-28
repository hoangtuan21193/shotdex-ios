import CoreImage

public extension PhotoRenderService {
    // MARK: Vignette (Effects — with Roundness + Highlights)

    /// The shaped vignette. For the common case (no Roundness, no Highlights) it
    /// stays on the proven `CIVignetteEffect`; only when those two are engaged does
    /// it switch to a colour kernel that can do a super-ellipse falloff and protect
    /// highlights. If the kernel fails to compile it degrades to leaving the image
    /// untouched rather than crashing.
    static func applyVignette(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        applyVignette(adjustments, to: input, kernel: vignetteKernel)
    }

    /// `kernel` is a parameter so a test can hand in `nil` (FS-16 AC-7).
    internal static func applyVignette(
        _ adjustments: PhotoAdjustments,
        to input: CIImage,
        kernel: CIColorKernel?
    ) -> CIImage {
        guard abs(adjustments.vignette) > 0.0001 else { return input }
        let extent = input.extent
        let minDimension = min(extent.width, extent.height)

        if abs(adjustments.vignetteRoundness) < 0.01, adjustments.vignetteHighlights < 0.01 {
            return filtered(
                "CIVignetteEffect",
                image: input,
                values: [
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                    kCIInputRadiusKey: minDimension * (0.35 + adjustments.vignetteMidpoint * 0.65),
                    kCIInputIntensityKey: adjustments.vignette * 2,
                    "inputFalloff": max(0.05, adjustments.vignetteFeather),
                ]
            )
        }

        guard let kernel else { return input }
        // Distance is measured in half-extent units: an ellipse's corner sits at
        // ~1.41, its edge midpoints at 1.0.
        let base = 0.4 + adjustments.vignetteMidpoint * 0.9
        let inner = base * (1 - adjustments.vignetteFeather * 0.6)
        let outer = base + adjustments.vignetteFeather * 0.5 + 0.05
        let roundExponent = max(1.2, 2 + adjustments.vignetteRoundness * 3)
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
        // The kernel scales by 1 − w · amount; at the corner (w = 1) that is
        // the gain 2^amount.
        let kernelAmount = 1 - pow(2, amount)
        let output = kernel.apply(
            extent: extent,
            arguments: [
                input,
                CIVector(x: extent.midX, y: extent.midY),
                CIVector(x: halfDiagonal, y: halfDiagonal),
                inner,
                1.0,
                kernelAmount,
                2.0,
                0.0,
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
    static func applyGeo(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        let extent = input.extent
        var image = input

        let hasAffine = abs(adjustments.geoRotate) > 0.0001
            || abs(adjustments.geoScale) > 0.0001
            || abs(adjustments.geoOffsetX) > 0.0001
            || abs(adjustments.geoOffsetY) > 0.0001
        if hasAffine {
            let angle = adjustments.geoRotate * 0.35
            let scale = 1 + adjustments.geoScale * 0.3
            let tx = adjustments.geoOffsetX * extent.width * 0.2
            let ty = adjustments.geoOffsetY * extent.height * 0.2
            var transform = CGAffineTransform(translationX: extent.midX + tx, y: extent.midY + ty)
            transform = transform.rotated(by: angle)
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
            image = image.clampedToExtent().transformed(by: transform).cropped(to: extent)
        }

        if abs(adjustments.geoVertical) > 0.0001 || abs(adjustments.geoHorizontal) > 0.0001 {
            image = keystone(
                image,
                vertical: adjustments.geoVertical,
                horizontal: adjustments.geoHorizontal,
                extent: extent
            )
        }
        return image
    }

    private static func keystone(
        _ input: CIImage,
        vertical: Double,
        horizontal: Double,
        extent: CGRect
    ) -> CIImage {
        let v = CGFloat(vertical) * 0.25
        let h = CGFloat(horizontal) * 0.25
        let halfWidth = extent.width / 2
        let halfHeight = extent.height / 2
        func corner(_ signX: CGFloat, _ signY: CGFloat) -> CIVector {
            let xScale = signY > 0 ? (1 + v) : (1 - v)
            let yScale = signX < 0 ? (1 + h) : (1 - h)
            return CIVector(
                x: extent.midX + signX * halfWidth * xScale,
                y: extent.midY + signY * halfHeight * yScale
            )
        }
        return filtered(
            "CIPerspectiveTransform",
            image: input.clampedToExtent(),
            values: [
                "inputTopLeft": corner(-1, 1),
                "inputTopRight": corner(1, 1),
                "inputBottomRight": corner(1, -1),
                "inputBottomLeft": corner(-1, -1),
            ]
        ).cropped(to: extent)
    }
}
