import CoreGraphics
import Foundation

/// New Source (FS-03.15c §3): where else a spot could be filled from, best
/// first. A candidate is scored by how well the ground around it — the ring
/// just outside where the copy would sit — matches the ground around the
/// spot, in mean colour and in texture (the spread of the ring's values).
/// Candidates that would overlap the spot, or leave the frame, are dropped.
public enum HealingSourceFinder {

    /// A small RGB picture of the photo to score against: row-major, top
    /// row first, three floats a pixel, 0…1.
    public struct Picture: Sendable {
        public let width: Int
        public let height: Int
        public let rgb: [Float]

        public init(width: Int, height: Int, rgb: [Float]) {
            self.width = width
            self.height = height
            self.rgb = rgb
        }

        /// Reads a CGImage down to at most `side` pixels on its long edge.
        public init?(_ image: CGImage, side: Int = 192) {
            let scale = min(1, Double(side) / Double(max(image.width, image.height)))
            let width = max(8, Int((Double(image.width) * scale).rounded()))
            let height = max(8, Int((Double(image.height) * scale).rounded()))
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: &bytes, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var rgb = [Float](repeating: 0, count: width * height * 3)
            for index in 0..<(width * height) {
                rgb[index * 3] = Float(bytes[index * 4]) / 255
                rgb[index * 3 + 1] = Float(bytes[index * 4 + 1]) / 255
                rgb[index * 3 + 2] = Float(bytes[index * 4 + 2]) / 255
            }
            self.init(width: width, height: height, rgb: rgb)
        }
    }

    /// Source positions for `spot`, best match first.
    public static func candidates(for spot: PhotoHealingSpot, in picture: Picture) -> [NormalizedPoint] {
        let aspect = Double(picture.width) / Double(picture.height)
        let shortOverWidth = aspect >= 1 ? 1 / aspect : 1
        let shortOverHeight = aspect >= 1 ? 1 : aspect
        let shape = spot.stroke ?? [NormalizedPoint(x: 0, y: 0)]
        guard let target = ringStatistics(around: spot.center, shape: shape, radius: spot.radius, in: picture)
        else { return [] }

        var scored: [(point: NormalizedPoint, score: Double)] = []
        for distance in [2.6, 3.4, 4.4, 5.8] {
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                let offset = spot.radius * distance
                let candidate = NormalizedPoint(
                    x: spot.center.x + cos(angle) * offset * shortOverWidth,
                    y: spot.center.y + sin(angle) * offset * shortOverHeight
                )
                guard fits(candidate, shape: shape, radius: spot.radius, shortOverWidth: shortOverWidth,
                           shortOverHeight: shortOverHeight),
                      !overlaps(candidate, spot: spot, shape: shape, shortOverWidth: shortOverWidth,
                                shortOverHeight: shortOverHeight),
                      let stats = ringStatistics(around: candidate, shape: shape, radius: spot.radius, in: picture)
                else { continue }
                let colour = zip(stats.mean, target.mean).map { abs($0 - $1) }.reduce(0, +)
                let texture = abs(stats.spread - target.spread)
                // Nearer is a slight tie-breaker: the ground changes with distance.
                scored.append((candidate, Double(colour + texture * 2) + distance * 0.002))
            }
        }
        return scored.sorted { $0.score < $1.score }.map(\.point)
    }

    private static func fits(
        _ point: NormalizedPoint, shape: [NormalizedPoint], radius: Double,
        shortOverWidth: Double, shortOverHeight: Double
    ) -> Bool {
        shape.allSatisfy { p in
            let x = point.x + p.x, y = point.y + p.y
            return x - radius * shortOverWidth >= 0 && x + radius * shortOverWidth <= 1
                && y - radius * shortOverHeight >= 0 && y + radius * shortOverHeight <= 1
        }
    }

    /// Whether the copy laid at `point` would cover any of the spot itself.
    private static func overlaps(
        _ point: NormalizedPoint, spot: PhotoHealingSpot, shape: [NormalizedPoint],
        shortOverWidth: Double, shortOverHeight: Double
    ) -> Bool {
        let clearance = spot.radius * 2
        for a in shape {
            for b in shape {
                let dx = (point.x + a.x - spot.center.x - b.x) / shortOverWidth
                let dy = (point.y + a.y - spot.center.y - b.y) / shortOverHeight
                if (dx * dx + dy * dy).squareRoot() < clearance { return true }
            }
        }
        return false
    }

    /// Mean colour and spread of the ring r…1.7r around the shape laid at
    /// `anchor` — the ground a heal would match.
    private static func ringStatistics(
        around anchor: NormalizedPoint, shape: [NormalizedPoint], radius: Double, in picture: Picture
    ) -> (mean: [Float], spread: Float)? {
        let shortEdge = Double(min(picture.width, picture.height))
        let inner = radius * shortEdge, outer = radius * shortEdge * 1.7
        var sums: [Float] = [0, 0, 0], squares: Float = 0, count: Float = 0
        let points = shape.map { p in
            (x: (anchor.x + p.x) * Double(picture.width), y: (anchor.y + p.y) * Double(picture.height))
        }
        let minX = max(0, Int((points.map(\.x).min() ?? 0) - outer)), maxX = min(picture.width - 1, Int((points.map(\.x).max() ?? 0) + outer))
        let minY = max(0, Int((points.map(\.y).min() ?? 0) - outer)), maxY = min(picture.height - 1, Int((points.map(\.y).max() ?? 0) + outer))
        guard minX <= maxX, minY <= maxY else { return nil }
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let d = points.map { hypot(px - $0.x, py - $0.y) }.min() ?? .infinity
                guard d >= inner, d <= outer else { continue }
                let index = (y * picture.width + x) * 3
                let r = picture.rgb[index], g = picture.rgb[index + 1], b = picture.rgb[index + 2]
                sums[0] += r; sums[1] += g; sums[2] += b
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                squares += luma * luma
                count += 1
            }
        }
        guard count >= 4 else { return nil }
        let mean = sums.map { $0 / count }
        let lumaMean = 0.2126 * mean[0] + 0.7152 * mean[1] + 0.0722 * mean[2]
        let spread = max(0, squares / count - lumaMean * lumaMean).squareRoot()
        return (mean, spread)
    }
}
