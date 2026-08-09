import CoreImage

extension PhotoRenderService {
    // MARK: Vignette (Effects — with Roundness + Highlights)

    /// The shaped vignette. For the common case (no Roundness, no Highlights) it
    /// stays on the proven `CIVignetteEffect`; only when those two are engaged does
    /// it switch to a colour kernel that can do a super-ellipse falloff and protect
    /// highlights. If the kernel fails to compile it degrades to leaving the image
    /// untouched rather than crashing.
    static func applyVignette(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
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

        guard let kernel = vignetteKernel else { return input }
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

    private static let vignetteKernel = CIColorKernel(source: """
    kernel vec4 shotdexVignette(__sample s, vec2 center, vec2 halfExtent, float inner, float outer, float amount, float roundExponent, float highlights) {
        vec2 d = (destCoord() - center) / halfExtent;
        float dist = pow(pow(abs(d.x), roundExponent) + pow(abs(d.y), roundExponent), 1.0 / roundExponent);
        float w = smoothstep(inner, outer, dist);
        float luma = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722));
        w *= mix(1.0, 1.0 - luma, highlights);
        float factor = 1.0 - w * amount;
        return vec4(s.rgb * factor, s.a);
    }
    """)

    // MARK: Optics

    /// Chromatic-aberration removal and defringe. Both are **approximations** — a
    /// true correction needs a lens profile and edge detection, which ShotDex has
    /// no data for. CA does a gentle chroma cleanup that softens colour fringing
    /// without touching luminance detail; Defringe pulls down the most-saturated
    /// colours (where fringing lives) globally, scaled by amount.
    static func applyOptics(_ adjustments: PhotoAdjustments, to input: CIImage) -> CIImage {
        var image = input
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
        if adjustments.defringe > 0.0001 {
            image = filtered(
                "CIVibrance",
                image: image,
                values: ["inputAmount": -adjustments.defringe * 0.5]
            )
        }
        return image
    }

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
