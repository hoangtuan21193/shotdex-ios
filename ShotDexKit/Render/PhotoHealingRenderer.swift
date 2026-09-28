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
    /// `image` with every spot repaired. Every spot samples the frame as it
    /// came in, not the frame with the earlier spots already applied: feeding
    /// one spot's kernel output into the next spot's kernel is a nested colour
    /// kernel, and Core Image folded those wrongly on device (the second spot
    /// cloned black). The repairs only stack through source-over composites.
    /// A spot whose source overlaps an earlier repair therefore copies the
    /// unrepaired pixels there — Lightroom would copy the repaired ones, a
    /// difference that only shows when a spot is filled from another spot.
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
            // The stroke's points on the photo, when the spot is a stroke.
            let strokePoints: [CGPoint]? = spot.stroke.map { relative in
                relative.map { imagePoint(NormalizedPoint(x: spot.center.x + $0.x, y: spot.center.y + $0.y), extent: extent) }
            }
            // Everything this spot reads or writes: the ring reaches 1.7r and
            // the blur a radius past that.
            let footprint = strokePoints.map { points -> CGRect in
                let xs = points.map(\.x), ys = points.map(\.y)
                return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            } ?? CGRect(origin: destination, size: .zero)
            let region = footprint.insetBy(dx: -radius * 2.8, dy: -radius * 2.8)
            // Whole pixels: a fractional edge leaves a row of half-covered
            // pixels, which the composite drew as a hairline across the photo.
            .integral
            .intersection(extent)
            guard !region.isNull, region.width > 0, region.height > 0 else { continue }

            // Only the patch the spot reads is lifted out, clamped and moved,
            // not the whole frame.
            let offset = CGAffineTransform(
                translationX: destination.x - source.x,
                y: destination.y - source.y
            )
            let sourceRegion = region
                .applying(offset.inverted())
                .intersection(extent)
            guard !sourceRegion.isNull, sourceRegion.width > 0, sourceRegion.height > 0 else { continue }
            let shifted = input.cropped(to: sourceRegion)
                .clampedToExtent()
                .transformed(by: offset)
                .cropped(to: region)
            // Distance from the spot's centre as an image rather than
            // `destCoord()`, so the colour kernels below stay position-free —
            // what Core Image assumes a colour kernel is when it rearranges the
            // graph. Linear 0…1 over `distanceSpan`, and deliberately **not**
            // cropped: Core Image may evaluate these kernels outside their
            // extent, and there the map must read "far" (1), never "centre" (0).
            let distanceSpan = radius * 3
            let distanceMap: CIImage? = if let strokePoints {
                strokeDistance(to: strokePoints, around: region, span: distanceSpan)
            } else {
                CIFilter(
                    name: "CIRadialGradient",
                    parameters: [
                        kCIInputCenterKey: CIVector(x: destination.x, y: destination.y),
                        "inputRadius0": 0,
                        "inputRadius1": distanceSpan,
                        "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                        "inputColor1": CIColor(red: 1, green: 1, blue: 1),
                    ]
                )?.outputImage
            }
            guard let distance = distanceMap else { continue }
            let heals: Float = spot.mode == .heal ? 1 : 0

            var numerator = shifted
            var denominator = shifted
            if spot.mode == .heal,
               let difference = ringKernel.apply(
                   extent: region,
                   arguments: [input, shifted, distance, radius, distanceSpan]
               ),
               let weight = weightKernel.apply(
                   extent: region,
                   arguments: [distance, radius, distanceSpan]
               ) {
                numerator = blurred(difference.cropped(to: region), radius: radius)
                denominator = blurred(weight.cropped(to: region), radius: radius)
            }
            guard let repaired = blendKernel.apply(
                extent: region,
                arguments: [
                    shifted, numerator, denominator, distance, radius, distanceSpan,
                    Float(min(1, max(0, spot.feather))), Float(min(1, max(0, spot.opacity))), heals,
                ]
            ) else { continue }
            // The repair is a premultiplied layer whose alpha is its coverage,
            // laid over the photo. It has to be: Core Image folds a colour
            // kernel into the composite as a per-pixel op and may evaluate it
            // over the whole frame, ignoring the extent the kernel was given
            // (measured — an opaque kernel here replaced every pixel of the
            // photo, and cropping first only helped when the crop was not a
            // no-op). With coverage in alpha, anywhere outside the spot the
            // layer is clear whether or not it is evaluated there.
            image = repaired.cropped(to: region).composited(over: image).cropped(to: extent)
        }
        return image
    }

    /// Distance to a stroke, 0…1 over `span`, as the same kind of map the
    /// round spot's radial gradient is — so the ring, weight and blend kernels
    /// heal along a wire exactly as they heal a speck. Measured on a grid of at
    /// most 256 cells a side and scaled up linearly: distance changes by at
    /// most one unit per unit moved, so a coarse grid interpolates it well.
    /// Reads "far" (1) everywhere outside `region`, as the kernels need.
    static func strokeDistance(to points: [CGPoint], around region: CGRect, span: CGFloat) -> CIImage? {
        guard region.width > 0, region.height > 0, span > 0 else { return nil }
        // A little past the region so the scaled grid's edge is already 1.
        let area = region.insetBy(dx: -span * 0.2, dy: -span * 0.2)
        let columns = max(2, min(256, Int(area.width.rounded(.up))))
        let rows = max(2, min(256, Int(area.height.rounded(.up))))
        let cellWidth = area.width / CGFloat(columns), cellHeight = area.height / CGFloat(rows)
        let segments = zip(points, points.dropFirst()).map { ($0, $1) }
        var values = [Float](repeating: 1, count: columns * rows * 4)
        for row in 0..<rows {
            // Bitmap rows run top-down; Core Image's y runs up.
            let y = area.maxY - (CGFloat(row) + 0.5) * cellHeight
            for column in 0..<columns {
                let x = area.minX + (CGFloat(column) + 0.5) * cellWidth
                var nearest = CGFloat.greatestFiniteMagnitude
                for (a, b) in segments {
                    nearest = min(nearest, segmentDistance(CGPoint(x: x, y: y), a, b))
                }
                let value = Float(min(1, nearest / span))
                let index = (row * columns + column) * 4
                values[index] = value
                values[index + 1] = value
                values[index + 2] = value
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        let grid = CIImage(
            bitmapData: data,
            bytesPerRow: columns * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: columns, height: rows),
            format: .RGBAf,
            colorSpace: nil
        )
        let placed = grid.samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: cellWidth, y: cellHeight))
            .transformed(by: CGAffineTransform(translationX: area.minX, y: area.minY))
            .cropped(to: area)
        return placed.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)))
    }

    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared)) : 0
        let dx = p.x - (a.x + t * abx), dy = p.y - (a.y + t * aby)
        return (dx * dx + dy * dy).squareRoot()
    }

    // Kernels: `Kernels/HealingKernels.ci.metal`.
    static let healingRingKernel = CoreImageKernelLibrary.kit.colorKernel(named: "healRing")

    static let healingWeightKernel = CoreImageKernelLibrary.kit.colorKernel(named: "healWeight")

    /// The copy, corrected when healing, as a premultiplied layer: colour
    /// times coverage, coverage in alpha. Source-over then gives
    /// `mix(photo, repair, coverage)` inside the spot and the photo outside.
    static let healingBlendKernel = CoreImageKernelLibrary.kit.colorKernel(named: "healBlend")
}
