import Foundation

/// Turns a region curve (Shadows · Darks · Lights · Highlights and the three
/// splits between them) into control points and a lookup table.
///
/// Each region moves the curve at its own centre, up or down by at most
/// `reach` of half the region's width. Two neighbours pushed toward each other
/// can at worst meet, never cross, and the monotone interpolation of
/// `ToneCurveMath` then keeps the whole curve rising — a region curve that
/// folded back would print a band darker than the band below it.
public enum ParametricCurveMath {
    /// How far a ±100 region moves its centre, as a fraction of its half-width.
    /// Anything up to 1 keeps every combination monotone.
    static let reach = 0.9

    /// The splits kept in order and apart, so no region has zero width.
    static func splits(of curve: ParametricCurve) -> (Double, Double, Double) {
        let gap = 0.05
        let low = min(max(curve.shadowSplit, gap), 1 - 3 * gap)
        let middle = min(max(curve.midtoneSplit, low + gap), 1 - 2 * gap)
        let high = min(max(curve.highlightSplit, middle + gap), 1 - gap)
        return (low, middle, high)
    }

    /// The black and white ends plus one point at the centre of each region.
    public static func points(for curve: ParametricCurve) -> [CurvePoint] {
        let (low, middle, high) = splits(of: curve)
        let bounds = [0, low, middle, high, 1]
        let values = [curve.shadows, curve.darks, curve.lights, curve.highlights]
        var points = [CurvePoint(x: 0, y: 0)]
        for region in 0..<4 {
            let halfWidth = (bounds[region + 1] - bounds[region]) / 2
            let centre = bounds[region] + halfWidth
            let value = min(1, max(-1, values[region]))
            points.append(CurvePoint(x: centre, y: centre + value * halfWidth * reach))
        }
        points.append(CurvePoint(x: 1, y: 1))
        return points
    }

    public static func lut(_ curve: ParametricCurve, count: Int = 256) -> [Float] {
        guard !curve.isIdentity else {
            return (0..<count).map { Float(Double($0) / Double(count - 1)) }
        }
        return ToneCurveMath.lut(points: points(for: curve), count: count)
    }

    /// The region curve first, then a point curve read through it — one table,
    /// so the render runs a single curve pass (FS-03.15 D51).
    public static func combinedLUT(
        region: ParametricCurve,
        points: [CurvePoint],
        count: Int = 256
    ) -> [Float] {
        let regionTable = lut(region, count: count)
        let pointTable = ToneCurveMath.lut(points: points, count: count)
        return regionTable.map { value in
            let position = Double(value) * Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(count - 1, lower + 1)
            let t = Float(position - Double(lower))
            return pointTable[lower] * (1 - t) + pointTable[upper] * t
        }
    }
}
