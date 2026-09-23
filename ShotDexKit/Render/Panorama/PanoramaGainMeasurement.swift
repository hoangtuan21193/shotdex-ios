import Foundation

/// Measures how bright each frame is where it meets the next, from the points
/// registration already matched.
///
/// No new sampling pass over the overlaps: the matcher has already found, for
/// every pair, several hundred places that are the same point in the world. The
/// mean of the two frames at exactly those places is the comparison the gain
/// solve wants, and it costs a lookup each.
public enum PanoramaGainMeasurement {

    /// Brightness of every overlapping pair, ready for `PanoramaGainSolver`.
    ///
    /// Values are converted out of the frames' gamma-encoded numbers into
    /// linear light first. Exposure is linear in light and not in what a JPEG
    /// stores, so solving on the stored numbers would be solving for the wrong
    /// quantity — the spike measured a 10–19% error from exactly that class of
    /// mistake.
    public static func overlaps(
        pairs: [PanoramaPairObservation],
        images: [PanoramaImage]
    ) -> [PanoramaOverlapBrightness] {
        pairs.compactMap { pair in
            guard pair.a < images.count, pair.b < images.count else { return nil }
            let a = images[pair.a], b = images[pair.b]
            var sumA = 0.0, sumB = 0.0, count = 0
            for point in pair.correspondences {
                guard let valueA = sample(a, x: point.ax, y: point.ay),
                      let valueB = sample(b, x: point.bx, y: point.by)
                else { continue }
                sumA += linear(valueA)
                sumB += linear(valueB)
                count += 1
            }
            guard count >= 8 else { return nil }
            return PanoramaOverlapBrightness(
                a: pair.a,
                b: pair.b,
                meanA: sumA / Double(count),
                meanB: sumB / Double(count),
                // Weighted by how much agreement the pair had, which stands in
                // for how much of the frames actually overlap: a pair matched
                // on twenty points should not outvote one matched on six
                // hundred.
                pixelCount: count
            )
        }
    }

    private static func sample(_ image: PanoramaImage, x: Double, y: Double) -> Double? {
        let xi = Int(x.rounded()), yi = Int(y.rounded())
        guard xi >= 0, yi >= 0, xi < image.width, yi < image.height else { return nil }
        return Double(image[xi, yi])
    }

    /// sRGB transfer curve, undone.
    static func linear(_ value: Double) -> Double {
        let v = min(1, max(0, value))
        return v <= 0.04045 ? v / 12.92 : Foundation.pow((v + 0.055) / 1.055, 2.4)
    }
}
