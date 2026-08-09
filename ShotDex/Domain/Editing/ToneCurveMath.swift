import Foundation

/// Turns a tone curve's control points into a sampled lookup table.
///
/// Interpolation is monotone cubic (Fritsch–Carlson): a plain cubic spline can
/// overshoot between points and fold the curve back on itself, which on a tone
/// curve reads as a band that gets *darker* as its input gets brighter. The
/// Fritsch–Carlson tangent limiting guarantees the output never reverses, so a
/// curve the user drew as always-rising renders as always-rising.
enum ToneCurveMath {
    /// A `count`-entry LUT (outputs 0…1) sampled uniformly across the 0…1 input
    /// domain. Fewer than two usable points falls back to the identity ramp.
    static func lut(points rawPoints: [CurvePoint], count: Int = 256) -> [Float] {
        precondition(count >= 2)
        let pts = sanitized(rawPoints)
        guard pts.count >= 2 else {
            return (0..<count).map { Float(Double($0) / Double(count - 1)) }
        }

        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let n = pts.count

        // Secant slope of each segment.
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = xs[i + 1] - xs[i]
            delta[i] = dx > 0 ? (ys[i + 1] - ys[i]) / dx : 0
        }

        // Tangents: average of neighbouring secants, endpoints take the one secant.
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) {
            m[i] = (delta[i - 1] + delta[i]) / 2
        }

        // Fritsch–Carlson: pull tangents back inside the circle of radius 3 so the
        // Hermite segment stays monotone. A flat segment pins both ends to zero.
        for i in 0..<(n - 1) {
            if delta[i] == 0 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let a = m[i] / delta[i]
            let b = m[i + 1] / delta[i]
            let magnitude = (a * a + b * b).squareRoot()
            if magnitude > 3 {
                let t = 3 / magnitude
                m[i] = t * a * delta[i]
                m[i + 1] = t * b * delta[i]
            }
        }

        var lut = [Float](repeating: 0, count: count)
        var segment = 0
        for k in 0..<count {
            let x = Double(k) / Double(count - 1)
            while segment < n - 2, x > xs[segment + 1] { segment += 1 }
            let x0 = xs[segment], x1 = xs[segment + 1]
            let y0 = ys[segment], y1 = ys[segment + 1]
            let h = x1 - x0
            let y: Double
            if h <= 0 {
                y = y0
            } else {
                let t = min(1, max(0, (x - x0) / h))
                let t2 = t * t
                let t3 = t2 * t
                let h00 = 2 * t3 - 3 * t2 + 1
                let h10 = t3 - 2 * t2 + t
                let h01 = -2 * t3 + 3 * t2
                let h11 = t3 - t2
                let tangent0: Double = m[segment]
                let tangent1: Double = m[segment + 1]
                let a = h00 * y0
                let b = h10 * h * tangent0
                let c = h01 * y1
                let d = h11 * h * tangent1
                y = a + b + c + d
            }
            lut[k] = Float(min(1, max(0, y)))
        }
        return lut
    }

    /// Clamp to the unit square, sort by input, and drop any point whose input is
    /// not strictly greater than the previous — a Hermite segment needs a positive
    /// width, and two points at the same x is a vertical step the curve cannot make.
    private static func sanitized(_ points: [CurvePoint]) -> [CurvePoint] {
        let clamped = points
            .map { CurvePoint(x: min(1, max(0, $0.x)), y: min(1, max(0, $0.y))) }
            .sorted { $0.x < $1.x }
        var out: [CurvePoint] = []
        for point in clamped {
            if let last = out.last, point.x <= last.x { continue }
            out.append(point)
        }
        return out
    }
}
