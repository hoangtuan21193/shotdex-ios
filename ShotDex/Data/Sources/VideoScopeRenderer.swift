import CoreGraphics
import CoreImage
import Foundation

/// Turns one frame into the picture a scope shows.
///
/// Two steps, both off the main actor: read the graded frame down to a
/// small RGBA8 buffer, then count it into a grid and write that grid out
/// as a bitmap. A bitmap rather than a `Canvas`: a waveform is 256 × 128
/// cells, and thirty-two thousand draw calls a refresh is not a drawing
/// strategy.
enum VideoScopeRenderer {
    /// The frame is sampled this wide. Small on purpose — a scope reads a
    /// distribution, and 240 × 135 is 32,400 pixels, which is enough of a
    /// sample for one and cheap enough to redo whenever the grade changes.
    static let sampleWidth = 240

    /// Grid sizes, chosen so every scope comes out 256 px wide and scales
    /// to the panel without resampling artefacts in the trace.
    static let waveformColumns = 256
    static let waveformLevels = 128
    static let paradeColumns = 84
    static let vectorscopeSize = 160
    static let histogramBuckets = 128
    static let histogramHeight = 128

    /// Reads `image` into tightly packed RGBA8. Returns the bytes and the
    /// size actually sampled, which keeps the frame's aspect.
    static func sample(
        _ image: CIImage,
        context: CIContext
    ) -> (rgba: [UInt8], width: Int, height: Int)? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0,
              extent.width.isFinite, extent.height.isFinite
        else { return nil }
        let scale = CGFloat(sampleWidth) / extent.width
        let width = sampleWidth
        let height = max(1, Int((extent.height * scale).rounded()))
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let rowBytes = width * VideoScopeMath.componentCount
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                scaled,
                toBitmap: base,
                rowBytes: rowBytes,
                bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                format: .RGBA8,
                colorSpace: space
            )
        }
        return (bytes, width, height)
    }

    /// The scope bitmap for one sampled frame, or nil if the sample is empty.
    static func image(
        kind: VideoScopeKind,
        rgba: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        switch kind {
        case .waveform:
            return waveformImage(rgba: rgba, width: width, height: height, channels: [(.luma, white)])
        case .parade:
            return paradeImage(rgba: rgba, width: width, height: height)
        case .vectorscope:
            return vectorscopeImage(rgba: rgba, width: width, height: height)
        case .histogram:
            return histogramImage(rgba: rgba, width: width, height: height)
        }
    }

    // MARK: - Trace colours

    private typealias Tint = (r: Double, g: Double, b: Double)
    private static let white: Tint = (0.86, 0.92, 0.88)
    private static let red: Tint = (1.0, 0.31, 0.31)
    private static let green: Tint = (0.36, 0.92, 0.45)
    private static let blue: Tint = (0.38, 0.62, 1.0)

    // MARK: - Scopes

    private static func waveformImage(
        rgba: [UInt8],
        width: Int,
        height: Int,
        channels: [(VideoScopeMath.Channel, Tint)]
    ) -> CGImage? {
        let columns = waveformColumns
        let levels = waveformLevels
        var canvas = Canvas(width: columns, height: levels)
        let ceiling = VideoScopeMath.traceCeiling(sampleHeight: height)
        for (channel, tint) in channels {
            let grid = VideoScopeMath.waveform(
                rgba: rgba, width: width, height: height,
                columns: columns, levels: levels, channel: channel
            )
            guard !grid.isEmpty else { continue }
            canvas.addTrace(grid, columns: columns, rows: levels, tint: tint, ceiling: ceiling)
        }
        return canvas.makeImage()
    }

    /// R, G and B side by side, each a third of the width — the reading that
    /// says *which* channel is lifted, which a single waveform cannot.
    private static func paradeImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        let columns = paradeColumns
        let levels = waveformLevels
        var canvas = Canvas(width: columns * 3 + 4, height: levels)
        let ceiling = VideoScopeMath.traceCeiling(sampleHeight: height)
        let lanes: [(VideoScopeMath.Channel, Tint)] = [(.red, red), (.green, green), (.blue, blue)]
        for (index, lane) in lanes.enumerated() {
            let grid = VideoScopeMath.waveform(
                rgba: rgba, width: width, height: height,
                columns: columns, levels: levels, channel: lane.0
            )
            guard !grid.isEmpty else { continue }
            canvas.addTrace(
                grid, columns: columns, rows: levels,
                tint: lane.1, ceiling: ceiling, xOffset: index * (columns + 2)
            )
        }
        return canvas.makeImage()
    }

    private static func vectorscopeImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        let size = vectorscopeSize
        let grid = VideoScopeMath.vectorscope(rgba: rgba, width: width, height: height, size: size)
        guard !grid.isEmpty else { return nil }
        var canvas = Canvas(width: size, height: size)
        // The vectorscope grid is already top-down, so it is written row for
        // row rather than flipped the way a waveform is.
        let ceiling = max(1, (width * height) / (size * size) * 3)
        for y in 0..<size {
            for x in 0..<size {
                let count = grid[y * size + x]
                guard count > 0 else { continue }
                canvas.add(x: x, y: y, tint: green, weight: min(1, Double(count) / Double(ceiling)))
            }
        }
        canvas.drawVectorscopeGraticule(size: size)
        return canvas.makeImage()
    }

    private static func histogramImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        let buckets = histogramBuckets
        let rows = histogramHeight
        let counts = VideoScopeMath.histogram(
            rgba: rgba, width: width, height: height, buckets: buckets
        )
        let peak = max(
            1,
            [counts.red, counts.green, counts.blue].flatMap { $0 }.max() ?? 1
        )
        var canvas = Canvas(width: buckets, height: rows)
        for (values, tint) in [(counts.red, red), (counts.green, green), (counts.blue, blue)] {
            for x in 0..<buckets {
                let bar = min(rows, values[x] * rows / peak)
                guard bar > 0 else { continue }
                for y in 0..<bar {
                    canvas.add(x: x, y: rows - 1 - y, tint: tint, weight: 0.62)
                }
            }
        }
        return canvas.makeImage()
    }

    // MARK: - Bitmap

    /// An additive RGBA8 buffer. Traces add rather than replace, so a parade
    /// lane crossing another reads as the mix instead of whichever was drawn
    /// last — which is what a scope on a desk does.
    private struct Canvas {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int) {
            self.width = max(1, width)
            self.height = max(1, height)
            // Opaque black: the scope has its own background so the panel
            // behind it never shows through a trace.
            var seed = [UInt8](repeating: 0, count: self.width * self.height * 4)
            for index in stride(from: 3, to: seed.count, by: 4) { seed[index] = 255 }
            self.pixels = seed
        }

        mutating func add(x: Int, y: Int, tint: Tint, weight: Double) {
            guard x >= 0, x < width, y >= 0, y < height, weight > 0 else { return }
            let p = (y * width + x) * 4
            let w = min(1, weight)
            pixels[p] = saturate(Int(pixels[p]) + Int(tint.r * w * 255))
            pixels[p + 1] = saturate(Int(pixels[p + 1]) + Int(tint.g * w * 255))
            pixels[p + 2] = saturate(Int(pixels[p + 2]) + Int(tint.b * w * 255))
        }

        /// Writes one waveform grid, flipping it: the grid's level 0 is black
        /// and belongs at the **bottom** of the picture.
        mutating func addTrace(
            _ grid: [Int],
            columns: Int,
            rows: Int,
            tint: Tint,
            ceiling: Int,
            xOffset: Int = 0
        ) {
            for level in 0..<rows {
                let y = rows - 1 - level
                for column in 0..<columns {
                    let count = grid[level * columns + column]
                    guard count > 0 else { continue }
                    add(
                        x: column + xOffset, y: y, tint: tint,
                        weight: min(1, Double(count) / Double(ceiling))
                    )
                }
            }
        }

        /// The circle and the 75 % colour targets, dim, so the trace can be
        /// read against something. Skin tone's I-line is the one a colourist
        /// actually looks for, and it is the long diagonal.
        mutating func drawVectorscopeGraticule(size: Int) {
            let centre = Double(size) / 2
            let radius = Double(size) * 0.44
            let dim: Tint = (0.22, 0.24, 0.26)
            for step in 0..<720 {
                let angle = Double(step) * .pi / 360
                add(
                    x: Int(centre + cos(angle) * radius),
                    y: Int(centre + sin(angle) * radius),
                    tint: dim, weight: 1
                )
            }
            // I-line: 33° off vertical, where correctly balanced skin sits.
            let skin = 123.0 * .pi / 180
            for step in 0..<Int(radius) {
                let distance = Double(step)
                add(
                    x: Int(centre + cos(skin) * distance),
                    y: Int(centre - sin(skin) * distance),
                    tint: dim, weight: 1
                )
            }
        }

        func makeImage() -> CGImage? {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var buffer = pixels
            return buffer.withUnsafeMutableBytes { raw -> CGImage? in
                guard let base = raw.baseAddress,
                      let provider = CGDataProvider(
                        dataInfo: nil, data: base, size: raw.count, releaseData: { _, _, _ in }
                      )
                else { return nil }
                return CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )?.copy()
            }
        }

        private func saturate(_ value: Int) -> UInt8 {
            UInt8(min(255, max(0, value)))
        }
    }
}
