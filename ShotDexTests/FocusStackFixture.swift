import CoreGraphics
import Foundation
@testable import ShotDexKit

/// A synthetic focus bracket whose true geometry and true all-in-focus
/// picture are known (FS-01.10 §7, spike §1): a scene of seeded rectangles
/// and discs, each frame sharp only in its own band of rows, the band moving
/// down as focus racks and the picture growing as the lens breathes.
struct FocusStackFixture {
    let width: Int
    let height: Int
    var seed: UInt64 = 1

    /// The scene, sharp everywhere.
    func scene() -> [UInt8] {
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

    func blurred(_ pixels: [UInt8], radius: Int) -> [UInt8] {
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

    struct Bracket {
        var frames: [CGImage]
        /// Frame pixel → scene pixel, top-left origin.
        var sceneFromFrame: [CGAffineTransform]
        /// The scene as frame 0 sees it, sharp everywhere: the answer.
        var truth: [UInt8]
        /// Top row of each frame's sharp band, in scene rows.
        var bandTops: [Double]
        var bandHeight: Double
    }

    func bracket(count: Int, breathing: Double) -> Bracket {
        let sharp = scene()
        let soft = blurred(sharp, radius: 3)
        var generator = SplitMix64(seed: seed &+ 99)
        func jitter(_ amount: Double) -> Double { (Double(generator.next() % 10_000) / 10_000 * 2 - 1) * amount }
        var frames: [CGImage] = [], maps: [CGAffineTransform] = [], tops: [Double] = []
        let bandHeight = Double(height) * 0.35
        func sample(_ source: [UInt8], _ map: CGAffineTransform, band: ClosedRange<Double>?) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height { for x in 0..<width {
                let p = CGPoint(x: x, y: y).applying(map)
                let xi = Int(p.x.rounded()), yi = Int(p.y.rounded())
                guard xi >= 0, yi >= 0, xi < width, yi < height else { continue }
                let inBand = band.map { $0.contains(Double(yi)) } ?? true
                bytes[y * width + x] = (inBand ? source : soft)[yi * width + xi]
            } }
            return bytes
        }
        for k in 0..<count {
            let t = Double(k) / Double(max(1, count - 1))
            let s = 1 / (1 + breathing * t)            // the picture grows: frame pixels sample a smaller scene region
            let angle = jitter(0.15) * .pi / 180
            let cx = Double(width) / 2, cy = Double(height) / 2
            let map = CGAffineTransform(translationX: cx + jitter(2), y: cy + jitter(2))
                .rotated(by: angle).scaledBy(x: s, y: s).translatedBy(x: -cx, y: -cy)
            let bandTop = Double(height) * (t * 0.8)
            let bytes = sample(sharp, map, band: bandTop...(bandTop + bandHeight))
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            frames.append(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
            maps.append(map)
            tops.append(bandTop)
        }
        return Bracket(frames: frames, sceneFromFrame: maps, truth: sample(sharp, maps[0], band: nil),
                       bandTops: tops, bandHeight: bandHeight)
    }

    // MARK: Depth bracket (spike §1)

    struct DepthBracket {
        var frames: [CGImage]
        /// The scene as frame 0 sees it, sharp everywhere.
        var truth: [UInt8]
        /// True where the scene's depth jumps within 6 px — the "depth
        /// edges" where a stacker has to switch frames sharply.
        var isDepthEdge: [Bool]
    }

    /// Like the spike's bracket: a band-limited scene with a depth map — far
    /// background, a middle band, two near discs — each frame focused at its
    /// own distance and blurred by how far each point is from it in
    /// dioptres, sampled bilinearly through a breathing, jittered map.
    func depthBracket(count: Int, breathing: Double) -> DepthBracket {
        // Band-limited: a hard-edged synthetic scene resampled once already
        // costs more than any stacker loses, and a photograph is never that
        // sharp at the pixel.
        let sharp = blurred(scene(), radius: 1)
        let levels = [sharp] + (1...4).map { blurred(sharp, radius: $0) }
        let w = Double(width), h = Double(height)
        // Dioptres (1 / metres) per scene pixel.
        var dioptre = [Double](repeating: 1 / 12.0, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let fx = Double(x), fy = Double(y)
            var d = 1 / 12.0
            if fy >= h * 0.35 && fy < h * 0.6 { d = 1 / 5.0 }
            if hypot(fx - w * 0.7, fy - h * 0.3) < h * 0.1 { d = 1 / 1.2 }
            if hypot(fx - w * 0.3, fy - h * 0.7) < h * 0.12 { d = 1 / 0.6 }
            dioptre[y * width + x] = d
        } }
        // Depth edges: pixels where the depth changes to the right or below,
        // grown by 6 px each way.
        var step = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let d = dioptre[y * width + x]
            if (x + 1 < width && dioptre[y * width + x + 1] != d) || (y + 1 < height && dioptre[(y + 1) * width + x] != d) {
                step[y * width + x] = true
            }
        } }
        var rowsGrown = step
        for y in 0..<height { for x in 0..<width where step[y * width + x] {
            for dx in -6...6 where x + dx >= 0 && x + dx < width { rowsGrown[y * width + x + dx] = true }
        } }
        var edge = rowsGrown
        for y in 0..<height { for x in 0..<width where rowsGrown[y * width + x] {
            for dy in -6...6 where y + dy >= 0 && y + dy < height { edge[(y + dy) * width + x] = true }
        } }

        func bilinear(_ source: [UInt8], _ p: CGPoint) -> Double? {
            let x0 = Int(floor(p.x)), y0 = Int(floor(p.y))
            guard x0 >= 0, y0 >= 0, x0 + 1 < width, y0 + 1 < height else { return nil }
            let fx = Double(p.x) - Double(x0), fy = Double(p.y) - Double(y0)
            func v(_ x: Int, _ y: Int) -> Double { Double(source[y * width + x]) }
            return (v(x0, y0) * (1 - fx) + v(x0 + 1, y0) * fx) * (1 - fy) + (v(x0, y0 + 1) * (1 - fx) + v(x0 + 1, y0 + 1) * fx) * fy
        }

        var generator = SplitMix64(seed: seed &+ 99)
        func jitter(_ amount: Double) -> Double { (Double(generator.next() % 10_000) / 10_000 * 2 - 1) * amount }
        var frames: [CGImage] = []
        var firstMap = CGAffineTransform.identity
        for k in 0..<count {
            let t = Double(k) / Double(max(1, count - 1))
            let s = 1 / (1 + breathing * t)
            let angle = jitter(0.15) * .pi / 180
            let cx = w / 2, cy = h / 2
            let map = CGAffineTransform(translationX: cx + jitter(2), y: cy + jitter(2))
                .rotated(by: angle).scaledBy(x: s, y: s).translatedBy(x: -cx, y: -cy)
            if k == 0 { firstMap = map }
            // Focus sweeps from 0.55 m to 14 m, evenly in dioptres.
            let focus = 1 / 0.55 + (1 / 14.0 - 1 / 0.55) * t
            var bytes = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height { for x in 0..<width {
                let p = CGPoint(x: x, y: y).applying(map)
                let xi = min(width - 1, max(0, Int(p.x.rounded()))), yi = min(height - 1, max(0, Int(p.y.rounded())))
                let level = min(4, Int((abs(dioptre[yi * width + xi] - focus) * 6).rounded()))
                if let value = bilinear(levels[level], p) {
                    bytes[y * width + x] = UInt8(max(0, min(255, value.rounded())))
                }
            } }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            frames.append(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
        }
        var truth = [UInt8](repeating: 0, count: width * height)
        var truthEdge = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let p = CGPoint(x: x, y: y).applying(firstMap)
            truth[y * width + x] = UInt8(max(0, min(255, (bilinear(sharp, p) ?? 0).rounded())))
            let xi = min(width - 1, max(0, Int(p.x.rounded()))), yi = min(height - 1, max(0, Int(p.y.rounded())))
            truthEdge[y * width + x] = edge[yi * width + xi]
        } }
        return DepthBracket(frames: frames, truth: truth, isDepthEdge: truthEdge)
    }
}
