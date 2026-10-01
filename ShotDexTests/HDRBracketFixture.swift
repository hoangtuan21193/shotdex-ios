import CoreGraphics
import CoreImage
import Foundation
@testable import ShotDexKit

/// A synthetic bracketed series whose true radiance is known (FS-01.11 §8,
/// spike §1): a seeded scene of sky, ground and coloured shapes stretched to
/// a given dynamic range, each frame a RAW exposure of it — shot and read
/// noise, 14 bits, clipping at 1.
struct HDRBracketFixture {
    var width = 480
    var height = 360
    var seed: UInt64 = 7
    /// Stops between the darkest and the brightest 0.1 % of the scene.
    var dynamicRange = 14.0
    /// Where the brightest 0.1 % sits, in stops over the reference's clip.
    var highlightStops = 3.0
    var noise = HDRNoiseModel.raw

    static let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    /// Linear RGB radiance relative to the reference's clip point, row-major
    /// from the top, three floats a pixel.
    func scene() -> [Float] {
        var generator = SplitMix64(seed: seed)
        func unit() -> Double { Double(generator.next() % 1_000_000) / 1_000_000 }
        // log2 luminance and a tint per pixel, built in layers.
        var logL = [Double](repeating: 0, count: width * height)
        var tint = [SIMD3<Double>](repeating: SIMD3(1, 1, 1), count: width * height)
        let horizon = Double(height) * 0.4
        for y in 0..<height {
            let t = Double(y) / Double(height)
            for x in 0..<width {
                let i = y * width + x
                if Double(y) < horizon {
                    logL[i] = 1.0 - 2.0 * Double(y) / horizon           // sky: bright at the top
                    tint[i] = SIMD3(0.85, 0.95, 1.2)
                } else {
                    logL[i] = -3.0 - 4.0 * (t - 0.4) / 0.6              // ground: darker towards the bottom
                    tint[i] = SIMD3(1.1, 1.0, 0.8)
                }
            }
        }
        // Shapes: mostly mid-tones, some deep shadow, a few hot spots.
        for k in 0..<260 {
            let w = 6 + unit() * 46, h = 6 + unit() * 46
            let cx = unit() * Double(width), cy = unit() * Double(height)
            let level: Double = k % 13 == 0 ? 1.5 + unit() * 1.5 : (k % 5 == 0 ? -9 + unit() * 3 : -6 + unit() * 6)
            let hue = SIMD3(0.7 + unit() * 0.6, 0.7 + unit() * 0.6, 0.7 + unit() * 0.6)
            let round = generator.next() % 2 == 0
            for y in max(0, Int(cy - h / 2))..<min(height, Int(cy + h / 2)) {
                for x in max(0, Int(cx - w / 2))..<min(width, Int(cx + w / 2)) {
                    if round {
                        let dx = (Double(x) - cx) / (w / 2), dy = (Double(y) - cy) / (h / 2)
                        if dx * dx + dy * dy > 1 { continue }
                    }
                    logL[y * width + x] = level + 0.5 * Double(x - Int(cx)) / w   // a little gradient inside
                    tint[y * width + x] = hue
                }
            }
        }
        // Stretch to the asked range between the 0.5 % and 99.9 % points.
        let sorted = logL.sorted()
        let lo = sorted[Int(Double(sorted.count) * 0.005)], hi = sorted[Int(Double(sorted.count) * 0.999)]
        let scale = dynamicRange / max(hi - lo, 0.001)
        var rgb = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let stretched = min(highlightStops + 0.3, (logL[i] - hi) * scale + highlightStops)
            let luma = pow(2, stretched)
            let t = tint[i]
            let tintLuma = 0.2126 * t.x + 0.7152 * t.y + 0.0722 * t.z
            var c = t / tintLuma * luma
            // Keep the brightest channel under the stretch's ceiling, so the
            // darkest frame of a series that covers the scene really holds it.
            let ceiling = pow(2, highlightStops + 0.3)
            if c.max() > ceiling { c *= ceiling / c.max() }
            rgb[i * 3] = Float(c.x); rgb[i * 3 + 1] = Float(c.y); rgb[i * 3 + 2] = Float(c.z)
        }
        return softened(rgb)
    }

    /// A 3 × 3 box: a photograph is never sharp to the pixel.
    private func softened(_ rgb: [Float]) -> [Float] {
        var out = rgb
        for y in 0..<height { for x in 0..<width { for c in 0..<3 {
            var s: Float = 0
            for dy in -1...1 { for dx in -1...1 {
                let xx = min(width - 1, max(0, x + dx)), yy = min(height - 1, max(0, y + dy))
                s += rgb[(yy * width + xx) * 3 + c]
            } }
            out[(y * width + x) * 3 + c] = s / 9
        } } }
        return out
    }

    /// One RAW exposure `stops` from the reference: values in 0…1.
    func frame(of scene: [Float], stops: Double, seed frameSeed: UInt64) -> [Float] {
        var generator = SplitMix64(seed: seed &* 31 &+ frameSeed)
        func gaussian() -> Double {
            let u1 = max(Double(generator.next() % 1_000_000) / 1_000_000, 1e-9)
            let u2 = Double(generator.next() % 1_000_000) / 1_000_000
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }
        let gain = pow(2, stops)
        let levels = pow(2, Double(noise.bitDepth)) - 1
        return scene.map { r in
            let electrons = Double(r) * gain * noise.fullWell
            let noisy = electrons + sqrt(max(electrons, 0)) * gaussian() + noise.readNoise * gaussian()
            let v = min(1, max(0, noisy / noise.fullWell))
            return Float((v * levels).rounded() / levels)
        }
    }

    struct Series {
        var scene: [Float]
        var frames: [[Float]]
        var stops: [Double]
        var reference: Int
    }

    func series(stops: [Double]) -> Series {
        let truth = scene()
        let frames = stops.enumerated().map { frame(of: truth, stops: $1, seed: UInt64($0 + 1)) }
        return Series(scene: truth, frames: frames, stops: stops, reference: stops.firstIndex(of: 0) ?? stops.count / 2)
    }

    // MARK: Core Image

    func image(_ rgb: [Float]) -> CIImage {
        var rgba = [Float](repeating: 1, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2]
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
                       format: .RGBAf, colorSpace: Self.colorSpace)
    }

    static let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])

    /// Renders back to RGB floats, top row first.
    func pixels(_ image: CIImage) -> [Float] {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            Self.context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 16,
                                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                format: .RGBAf, colorSpace: Self.colorSpace)
        }
        var rgb = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            rgb[i * 3] = rgba[i * 4]; rgb[i * 3 + 1] = rgba[i * 4 + 1]; rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return rgb
    }

    static func luma(_ rgb: [Float], _ i: Int) -> Double {
        0.2126 * Double(rgb[i * 3]) + 0.7152 * Double(rgb[i * 3 + 1]) + 0.0722 * Double(rgb[i * 3 + 2])
    }

    /// RMS error in stops of luminance over the pixels `where` keeps.
    static func stopsError(_ estimate: [Float], _ truth: [Float], where keep: (Int) -> Bool = { _ in true }) -> Double {
        var sum = 0.0, n = 0
        for i in 0..<(truth.count / 3) where keep(i) {
            let e = log2(max(luma(estimate, i), 1e-7) / max(luma(truth, i), 1e-7))
            sum += e * e; n += 1
        }
        return n == 0 ? 0 : sqrt(sum / Double(n))
    }
}
