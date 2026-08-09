import CoreImage
import CoreGraphics

extension PhotoRenderService {
    /// One `CIColorCurves` pass for the point tone curve. Like the film cube, the
    /// curve was dialled against gamma-encoded values, so it runs in sRGB rather
    /// than the context's linear working space, and the input is clamped first
    /// because a cube/curve says nothing about values outside 0…1.
    ///
    /// The master (RGB) curve and the per-channel curves are baked into one set of
    /// three 256-sample series: each channel is sampled as `channel(master(v))`, so
    /// the master shapes all three tones first and the per-channel curve trims from
    /// there — the order a point-curve panel applies them.
    static func applyCurve(_ curve: ToneCurveAdjustments, to input: CIImage) -> CIImage {
        guard !curve.isIdentity else { return input }
        let clamped = filtered("CIColorClamp", image: input)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return clamped
        }

        let sampleCount = 256
        let master = ToneCurveMath.lut(points: curve.rgb, count: sampleCount)
        let red = ToneCurveMath.lut(points: curve.red, count: sampleCount)
        let green = ToneCurveMath.lut(points: curve.green, count: sampleCount)
        let blue = ToneCurveMath.lut(points: curve.blue, count: sampleCount)

        var series = [Float](repeating: 0, count: sampleCount * 3)
        let lastIndex = Float(sampleCount - 1)
        for i in 0..<sampleCount {
            let composed = Int((master[i] * lastIndex).rounded())
            let j = min(sampleCount - 1, max(0, composed))
            series[i * 3 + 0] = red[j]
            series[i * 3 + 1] = green[j]
            series[i * 3 + 2] = blue[j]
        }
        let data = series.withUnsafeBufferPointer { Data(buffer: $0) }

        return filtered(
            "CIColorCurves",
            image: clamped,
            values: [
                "inputCurvesData": data,
                "inputCurvesDomain": CIVector(x: 0, y: 1),
                "inputColorSpace": colorSpace,
            ]
        ).cropped(to: input.extent)
    }
}
