import CoreImage
import Foundation

/// The Heal and Clone passes.
///
/// Not generative: Lightroom's Heal never was. Both copy another part of the
/// same photo over the spot. Clone stops there. Heal then corrects the copy's
/// colour so it matches the ground **around** the spot rather than the ground
/// where it was taken from — which is what lets a patch lifted from lower in
/// a sky, where the blue is paler, land without a visible disc.
///
/// The correction is a normalized convolution: the difference between the
/// target and the copy is measured on a ring just outside the spot, blurred,
/// and divided by the blurred ring weight. That interpolates the ring's
/// difference smoothly across the inside, where the dust is and nothing can
/// be measured — a cheap stand-in for a Poisson membrane that needs no solver.
/// Measured on a synthetic gradient sky with a dust speck: mean error inside
/// the spot 0.5/255 and at most 1.9/255 near it, against the FS-03.11 bar of
/// 2/255 mean and no hard edge.
extension PhotoRenderService {
    /// `image` with every spot repaired, in order — a later spot sees the
    /// repairs of the ones before it.
    public static func applyHealing(_ spots: [PhotoHealingSpot], to input: CIImage) -> CIImage {
        guard !spots.isEmpty,
              let ringKernel = healingRingKernel,
              let weightKernel = healingWeightKernel,
              let blendKernel = healingBlendKernel
        else { return input }
        var image = input
        let extent = input.extent
        let shortEdge = min(extent.width, extent.height)
        for spot in spots where spot.opacity > 0.001 {
            let radius = max(1, spot.radius * shortEdge)
            let destination = imagePoint(spot.center, extent: extent)
            let source = imagePoint(spot.source, extent: extent)
            // Everything this spot reads or writes: the ring reaches 1.7r and
            // the blur a radius past that.
            let region = CGRect(
                x: destination.x - radius * 2.8,
                y: destination.y - radius * 2.8,
                width: radius * 5.6,
                height: radius * 5.6
            ).intersection(extent)
            guard !region.isNull, region.width > 0, region.height > 0 else { continue }

            let shifted = image.clampedToExtent()
                .transformed(by: CGAffineTransform(
                    translationX: destination.x - source.x,
                    y: destination.y - source.y
                ))
                .cropped(to: region)
            let center = CIVector(x: destination.x, y: destination.y)
            let heals: Float = spot.mode == .heal ? 1 : 0

            var numerator = shifted
            var denominator = shifted
            if spot.mode == .heal,
               let difference = ringKernel.apply(
                   extent: region,
                   arguments: [image, shifted, center, radius]
               ),
               let weight = weightKernel.apply(extent: region, arguments: [center, radius]) {
                numerator = blurred(difference, radius: radius)
                denominator = blurred(weight, radius: radius)
            }
            guard let repaired = blendKernel.apply(
                extent: region,
                arguments: [
                    image, shifted, numerator, denominator, center, radius,
                    Float(min(1, max(0, spot.feather))), Float(min(1, max(0, spot.opacity))), heals,
                ]
            ) else { continue }
            image = repaired.composited(over: image).cropped(to: extent)
        }
        return image
    }

    /// The ring just outside the spot where the colour match is measured.
    /// Starts a little past the radius so the dust's own soft tail stays out.
    private static let healingRingSource = """
        float healRingWeight(float dist, float radius) {
            return smoothstep(radius * 1.05, radius * 1.2, dist)
                * (1.0 - smoothstep(radius * 1.5, radius * 1.7, dist));
        }
        """

    static let healingRingKernel = CIColorKernel(source: healingRingSource + """
        kernel vec4 healRing(__sample target, __sample shifted, vec2 center, float radius) {
            float w = healRingWeight(distance(destCoord(), center), radius);
            return vec4((target.rgb - shifted.rgb) * w, 1.0);
        }
        """)

    static let healingWeightKernel = CIColorKernel(source: healingRingSource + """
        kernel vec4 healWeight(vec2 center, float radius) {
            float w = healRingWeight(distance(destCoord(), center), radius);
            return vec4(w, w, w, 1.0);
        }
        """)

    /// The copy, corrected when healing, blended in under a soft edge.
    static let healingBlendKernel = CIColorKernel(source: """
        kernel vec4 healBlend(
            __sample target, __sample shifted, __sample numerator, __sample denominator,
            vec2 center, float radius, float feather, float opacity, float heals
        ) {
            float dist = distance(destCoord(), center);
            vec3 correction = heals * numerator.rgb / max(denominator.r, 0.0001);
            vec3 repaired = shifted.rgb + correction;
            float inner = radius * (1.0 - 0.7 * feather);
            float amount = (1.0 - smoothstep(inner, radius, dist)) * opacity;
            return vec4(mix(target.rgb, repaired, amount), target.a);
        }
        """)
}
