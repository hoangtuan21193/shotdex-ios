import CoreGraphics
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.10 AC-1, AC-2, AC-4 at the aligner: a synthetic bracket whose true
/// geometry is known, with the sharp band moving down the frame as focus racks
/// and the picture growing as the lens breathes.
struct FocusStackAlignmentTests {

    let width = 480, height = 360

    // MARK: Fixture

    /// A scene with plenty of corners: seeded rectangles and discs on noise.
    private func scene(seed: UInt64) -> [UInt8] {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        var generator = SplitMix64(seed: seed)
        func unit() -> CGFloat { CGFloat(generator.next() % 10_000) / 10_000 }
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for _ in 0..<180 {
            context.setFillColor(gray: unit(), alpha: 1)
            let rect = CGRect(x: unit() * CGFloat(width), y: unit() * CGFloat(height), width: 6 + unit() * 40, height: 6 + unit() * 40)
            if generator.next() % 2 == 0 { context.fill(rect) } else { context.fillEllipse(in: rect) }
        }
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: width * height))
    }

    private func blurred(_ pixels: [UInt8], radius: Int) -> [UInt8] {
        var a = pixels.map(Float.init), b = a
        for _ in 0..<3 {
            for y in 0..<height { for x in 0..<width {
                var s: Float = 0
                for d in -radius...radius { s += a[y * width + min(width - 1, max(0, x + d))] }
                b[y * width + x] = s / Float(2 * radius + 1)
            } }
            for y in 0..<height { for x in 0..<width {
                var s: Float = 0
                for d in -radius...radius { s += b[min(height - 1, max(0, y + d)) * width + x] }
                a[y * width + x] = s / Float(2 * radius + 1)
            } }
        }
        return a.map { UInt8(max(0, min(255, $0.rounded()))) }
    }

    /// Frame k shows the scene at `sceneFromFrame[k]` (frame pixel → scene
    /// pixel), sharp only in its own band of rows.
    private func bracket(count: Int, breathing: Double, seed: UInt64 = 1)
        -> (frames: [CGImage], sceneFromFrame: [CGAffineTransform]) {
        let sharp = scene(seed: seed)
        let soft = blurred(sharp, radius: 3)
        var generator = SplitMix64(seed: seed &+ 99)
        func jitter(_ amount: Double) -> Double { (Double(generator.next() % 10_000) / 10_000 * 2 - 1) * amount }
        var frames: [CGImage] = [], maps: [CGAffineTransform] = []
        for k in 0..<count {
            let t = Double(k) / Double(max(1, count - 1))
            let s = 1 / (1 + breathing * t)            // the picture grows: frame pixels sample a smaller scene region
            let angle = jitter(0.15) * .pi / 180
            let cx = Double(width) / 2, cy = Double(height) / 2
            let map = CGAffineTransform(translationX: cx + jitter(2), y: cy + jitter(2))
                .rotated(by: angle).scaledBy(x: s, y: s).translatedBy(x: -cx, y: -cy)
            let bandTop = Double(height) * (t * 0.8), bandBottom = bandTop + Double(height) * 0.35
            var bytes = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height { for x in 0..<width {
                let p = CGPoint(x: x, y: y).applying(map)
                let xi = Int(p.x.rounded()), yi = Int(p.y.rounded())
                guard xi >= 0, yi >= 0, xi < width, yi < height else { continue }
                let inBand = Double(yi) >= bandTop && Double(yi) < bandBottom
                bytes[y * width + x] = (inBand ? sharp : soft)[yi * width + xi]
            } }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            frames.append(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
            maps.append(map)
        }
        return (frames, maps)
    }

    /// Mean distance, over a grid inside the frame, between where the aligner
    /// sends a frame pixel and where it truly belongs in frame 0.
    private func error(_ estimated: CGAffineTransform, truth: CGAffineTransform) -> Double {
        var total = 0.0, n = 0.0
        for gy in 1..<8 { for gx in 1..<8 {
            let p = CGPoint(x: Double(gx) / 8 * Double(width), y: Double(gy) / 8 * Double(height))
            let a = p.applying(estimated), b = p.applying(truth)
            total += hypot(a.x - b.x, a.y - b.y); n += 1
        } }
        return total / n
    }

    private func truth(_ maps: [CGAffineTransform], _ k: Int) -> CGAffineTransform {
        // frame k pixel → scene → frame 0 pixel
        maps[k].concatenating(maps[0].inverted())
    }

    // MARK: Tests

    @Test(arguments: [0.0, 0.02, 0.05])
    func breathingBracketLinesUpWithinAPixel(breathing: Double) {
        let (frames, maps) = bracket(count: 6, breathing: breathing)
        let result = FocusStackAligner.align(frames)
        #expect(result.count == frames.count)
        for k in frames.indices {
            guard let estimated = result[k] else {
                Issue.record("frame \(k) did not line up at \(breathing)")
                continue
            }
            #expect(error(estimated, truth: truth(maps, k)) <= 1.0, "frame \(k), breathing \(breathing)")
        }
    }

    @Test func aFrameFromAnotherSceneIsLeftOutAndTheChainGoesOn() {
        var (frames, maps) = bracket(count: 6, breathing: 0.02)
        let stranger = bracket(count: 1, breathing: 0, seed: 777).frames[0]
        frames.insert(stranger, at: 3)
        maps.insert(.identity, at: 3)
        let result = FocusStackAligner.align(frames)
        #expect(result[3] == nil)
        for k in frames.indices where k != 3 {
            guard let estimated = result[k] else { Issue.record("frame \(k) lost"); continue }
            #expect(error(estimated, truth: truth(maps, k)) <= 1.0, "frame \(k)")
        }
    }

    @Test func theFirstFrameIsTheReference() {
        let result = FocusStackAligner.align(bracket(count: 3, breathing: 0.02).frames)
        #expect(result.first == .identity)
    }

    @Test func aSimilarityIsRecoveredExactlyFromTwoPoints() {
        let t = CGAffineTransform(a: 1.03 * cos(0.01), b: 1.03 * sin(0.01), c: -1.03 * sin(0.01), d: 1.03 * cos(0.01), tx: 4, ty: -2)
        let src: [SIMD2<Double>] = [SIMD2(10, 20), SIMD2(300, 180)]
        let dst = src.map { p -> SIMD2<Double> in
            let q = CGPoint(x: p.x, y: p.y).applying(t); return SIMD2(q.x, q.y)
        }
        let fit = FocusStackAligner.similarity(src: src, dst: dst)!
        #expect(abs(fit.a - t.a) < 1e-9 && abs(fit.b - t.b) < 1e-9 && abs(fit.tx - t.tx) < 1e-6 && abs(fit.ty - t.ty) < 1e-6)
    }
}
