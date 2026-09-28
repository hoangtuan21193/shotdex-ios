import CoreImage
import Foundation

/// The common form every lens-correction source reduces to (FS-03.16a §5):
/// by output radius, how far out to sample the green channel (distortion) and
/// the red and blue ones (distortion and chromatic aberration), already scaled
/// by the strengths. One Metal pass reads R, G and B at their three radii —
/// Core Image's warp kernel gives one coordinate for all three channels, and
/// three warps would cost three passes a frame.
///
/// Radius is in Lensfun's distortion unit: 1 = half the short side of the
/// calibration frame (`lensNormalizationRadius`).
public struct LensCorrectionTable: Equatable, Sendable {
    public static let sampleCount = 256

    /// The radius the last sample stands for.
    public var maximumRadius: Double
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]

    /// Source radius over output radius at radius `r`, each channel.
    public func scales(at r: Double) -> (red: Double, green: Double, blue: Double) {
        let t = min(max(r / maximumRadius, 0), 1) * Double(Self.sampleCount - 1)
        let i = min(Int(t), Self.sampleCount - 2), f = t - Double(i)
        func lerp(_ values: [Float]) -> Double { Double(values[i]) * (1 - f) + Double(values[i + 1]) * f }
        return (lerp(red), lerp(green), lerp(blue))
    }

    /// Whether the table moves anything — strengths at 0 do not.
    public var isIdentity: Bool {
        (red + green + blue).allSatisfy { abs($0 - 1) < 1e-6 }
    }

    /// A Lensfun distortion and TCA at strengths `distortion` and
    /// `chromaticAberration` (0…2): the displacement is s × the profile's, the
    /// red/blue offset s × the profile's (16a §5). `manual` is the kernel
    /// coefficient of the manual Distortion slider over ρ, the radius in
    /// half-diagonals — `manualRadiusRatio` = norm / half-diagonal.
    public static func make(
        distortion term: LensDistortionTerm?,
        tca: LensTCATerm?,
        distortionStrength: Double,
        chromaticAberrationStrength: Double,
        manual: Double = 0,
        manualRadiusRatio: Double = 0,
        maximumRadius: Double
    ) -> LensCorrectionTable {
        var red = [Float](), green = [Float](), blue = [Float]()
        red.reserveCapacity(sampleCount); green.reserveCapacity(sampleCount); blue.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let r = maximumRadius * Double(index) / Double(sampleCount - 1)
            let profile = term?.scale(at: r) ?? 1
            let rho = r * manualRadiusRatio
            let g = (1 + distortionStrength * (profile - 1)) * (1 - manual * rho * rho)
            let (tr, tb) = tca?.scales(at: r) ?? (1, 1)
            green.append(Float(g))
            red.append(Float(g * (1 + chromaticAberrationStrength * (tr - 1))))
            blue.append(Float(g * (1 + chromaticAberrationStrength * (tb - 1))))
        }
        return LensCorrectionTable(maximumRadius: maximumRadius, red: red, green: green, blue: blue)
    }

    /// Any mix of sources, by radius in pixels: green's source/output ratio
    /// and red's and blue's ratio to green, each before strength; the
    /// strengths then scale every deviation from 1 (16a §5). `maximumRadius`
    /// is in pixels too — the kernel runs with a normalisation of 1.
    public static func make(
        green: ((Double) -> Double)?,
        red: ((Double) -> Double)?,
        blue: ((Double) -> Double)?,
        distortionStrength: Double,
        chromaticAberrationStrength: Double,
        manual: Double = 0,
        halfDiagonal: Double,
        maximumRadius: Double
    ) -> LensCorrectionTable {
        var redValues = [Float](), greenValues = [Float](), blueValues = [Float]()
        for index in 0..<sampleCount {
            let r = maximumRadius * Double(index) / Double(sampleCount - 1)
            let rho = r / max(halfDiagonal, 1)
            let g = (1 + distortionStrength * ((green?(r) ?? 1) - 1)) * (1 - manual * rho * rho)
            let tr = red?(r) ?? 1, tb = blue?(r) ?? 1
            greenValues.append(Float(g))
            redValues.append(Float(g * (1 + chromaticAberrationStrength * (tr - 1))))
            blueValues.append(Float(g * (1 + chromaticAberrationStrength * (tb - 1))))
        }
        return LensCorrectionTable(maximumRadius: maximumRadius, red: redValues, green: greenValues, blue: blueValues)
    }

    /// The table as a 256×1 float image the kernel samples: R, G, B scales.
    var image: CIImage {
        var pixels = [Float](repeating: 1, count: Self.sampleCount * 4)
        for index in 0..<Self.sampleCount {
            pixels[index * 4] = red[index]
            pixels[index * 4 + 1] = green[index]
            pixels[index * 4 + 2] = blue[index]
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: Self.sampleCount * 16,
            size: CGSize(width: Self.sampleCount, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
    }
}

extension LensfunLens {
    /// Vignetting at `focal` and `aperture` (16a §2): the farthest measured
    /// distance — EXIF rarely has one — then linear in focal and in 1/aperture
    /// (f-numbers are not spaced evenly) between the nearest measurements.
    public func vignetting(atFocal focal: Double, aperture: Double) -> LensVignettingTerm? {
        guard !vignetting.isEmpty else { return nil }
        let farthest = Dictionary(grouping: vignetting) { FocalAperture(focal: $0.focal, aperture: $0.aperture) }
            .map { $0.value.max { $0.distance < $1.distance }! }
        let focals = Array(Set(farthest.map(\.focal))).sorted()
        func bracket(_ values: [Double], _ x: Double) -> (Double, Double, Double) {
            guard let upper = values.firstIndex(where: { $0 >= x }) else { return (values.last!, values.last!, 0) }
            if upper == 0 { return (values[0], values[0], 0) }
            let a = values[upper - 1], b = values[upper]
            return (a, b, b > a ? (x - a) / (b - a) : 0)
        }
        func atFocal(_ f: Double) -> LensVignettingTerm? {
            let rows = farthest.filter { $0.focal == f }.sorted { $0.aperture < $1.aperture }
            guard let first = rows.first else { return nil }
            let inverse = rows.map { 1 / max($0.aperture, 0.1) }
            let x = 1 / max(aperture, 0.1)
            // Sorted by aperture ascending = 1/aperture descending.
            let reversed = Array(zip(inverse, rows).reversed())
            let keys = reversed.map(\.0)
            let (a, b, t) = bracket(keys, x)
            guard let lower = reversed.first(where: { $0.0 == a })?.1,
                  let upper = reversed.first(where: { $0.0 == b })?.1 else { return first }
            return mix(lower, upper, t, focal: f)
        }
        let (fa, fb, ft) = bracket(focals, focal)
        guard let lower = atFocal(fa), let upper = atFocal(fb) else { return nil }
        return mix(lower, upper, ft, focal: focal)
    }

    /// TCA at `focal`, linear between the nearest measurements of one model.
    public func chromaticAberration(atFocal focal: Double) -> LensTCATerm? {
        let sorted = tca.sorted { $0.focal < $1.focal }
        guard let first = sorted.first else { return nil }
        if focal <= first.focal || sorted.count == 1 { return first }
        if let last = sorted.last, focal >= last.focal { return last }
        guard let upperIndex = sorted.firstIndex(where: { $0.focal >= focal }), upperIndex > 0 else { return first }
        let lower = sorted[upperIndex - 1], upper = sorted[upperIndex]
        guard lower.model == upper.model, upper.focal > lower.focal else { return lower }
        let t = (focal - lower.focal) / (upper.focal - lower.focal)
        func m(_ x: Double?, _ y: Double?) -> Double? {
            guard x != nil || y != nil else { return nil }
            let fallback: Double = 0
            return (x ?? fallback) + ((y ?? fallback) - (x ?? fallback)) * t
        }
        return LensTCATerm(
            model: lower.model, focal: focal,
            kr: m(lower.kr, upper.kr), kb: m(lower.kb, upper.kb),
            br: m(lower.br, upper.br), cr: m(lower.cr, upper.cr), vr: m(lower.vr, upper.vr),
            bb: m(lower.bb, upper.bb), cb: m(lower.cb, upper.cb), vb: m(lower.vb, upper.vb)
        )
    }

    private struct FocalAperture: Hashable {
        var focal: Double
        var aperture: Double
    }

    private func mix(_ a: LensVignettingTerm, _ b: LensVignettingTerm, _ t: Double, focal: Double) -> LensVignettingTerm {
        LensVignettingTerm(
            focal: focal,
            aperture: a.aperture + (b.aperture - a.aperture) * t,
            distance: max(a.distance, b.distance),
            k1: a.k1 + (b.k1 - a.k1) * t,
            k2: a.k2 + (b.k2 - a.k2) * t,
            k3: a.k3 + (b.k3 - a.k3) * t
        )
    }
}
