import Foundation

/// Pure-Swift mirror of the math inside the color kernels in
/// `PhotoRenderService+Color`. The kernels interpolate the same constants
/// (`ColorMixerBand.centerDegrees`) into their GLSL source, so unit tests over
/// these functions pin down the GPU behavior without needing a GPU.
enum ColorRenderMath {
    struct HSV: Equatable {
        /// Degrees 0…360.
        var hue: Double
        var saturation: Double
        var value: Double
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - HSV conversion

    static func hsv(fromRed red: Double, green: Double, blue: Double) -> HSV {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        var hue = 0.0
        if delta > 0 {
            if maximum == red {
                hue = (green - blue) / delta
            } else if maximum == green {
                hue = 2 + (blue - red) / delta
            } else {
                hue = 4 + (red - green) / delta
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }

        let saturation = maximum > 0 ? delta / maximum : 0
        return HSV(hue: hue, saturation: saturation, value: maximum)
    }

    static func rgb(from hsv: HSV) -> (red: Double, green: Double, blue: Double) {
        let saturation = min(max(hsv.saturation, 0), 1)
        let value = min(max(hsv.value, 0), 1)
        guard saturation > 0 else { return (value, value, value) }

        var hue = hsv.hue.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        let sector = hue / 60
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))

        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))

        switch index {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }

    // MARK: - Mixer band weights

    /// Partition-of-unity weights over the eight mixer bands for a hue in
    /// degrees. A hue always falls between two neighboring band centers on the
    /// wrapped wheel; the two get smoothstep-complementary weights and every
    /// other band gets zero, so adjacent-band shifts cross over with no dead
    /// zones despite the uneven center spacing.
    static func bandWeights(hueDegrees: Double) -> [Double] {
        var hue = hueDegrees.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }

        let bands = ColorMixerBand.allCases
        let centers = bands.map(\.centerDegrees)
        var weights = [Double](repeating: 0, count: bands.count)

        for index in bands.indices {
            let lower = centers[index]
            let nextIndex = (index + 1) % bands.count
            let upper = nextIndex == 0 ? 360.0 : centers[nextIndex]
            guard hue >= lower, hue < upper else { continue }
            let t = smoothstep(0, 1, (hue - lower) / (upper - lower))
            weights[index] = 1 - t
            weights[nextIndex] = t
            return weights
        }

        weights[0] = 1
        return weights
    }

    // MARK: - Grading region weights

    /// Shadows/midtones/highlights membership for a luma value, shaped by the
    /// grading Blending (overlap width) and Balance (pivot shift) controls.
    static func regionWeights(
        luma: Double,
        blending: Double,
        balance: Double
    ) -> (shadows: Double, midtones: Double, highlights: Double) {
        let feather = 0.08 + (0.35 - 0.08) * min(max(blending, 0), 1)
        let shadowPivot = 0.33 + 0.25 * balance
        let highlightPivot = 0.67 + 0.25 * balance
        let shadows = 1 - smoothstep(shadowPivot - feather, shadowPivot + feather, luma)
        let highlights = smoothstep(highlightPivot - feather, highlightPivot + feather, luma)
        let midtones = min(max(1 - shadows - highlights, 0), 1)
        return (shadows, midtones, highlights)
    }

    // MARK: - Point color weight

    static func circularHueDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    /// Match strength of a pixel against a sampled reference. Hue distance
    /// dominates the metric so a red pixel never matches a blue reference no
    /// matter how close in brightness.
    static func pointWeight(pixel: HSV, reference: HSV, range: Double) -> Double {
        let hueDistance = circularHueDistance(pixel.hue, reference.hue) / 180
        let saturationDistance = abs(pixel.saturation - reference.saturation)
        let valueDistance = abs(pixel.value - reference.value)
        let distance = (
            (2.5 * hueDistance) * (2.5 * hueDistance)
                + saturationDistance * saturationDistance
                + valueDistance * valueDistance
        ).squareRoot()
        let radius = 0.10 + (0.55 - 0.10) * min(max(range, 0), 1)
        return 1 - smoothstep(radius * 0.4, radius, distance)
    }
}
