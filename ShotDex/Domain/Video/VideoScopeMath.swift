import CoreGraphics
import Foundation

/// Which measurement the scope shows.
///
/// Resolve gives a colourist four and they answer different questions:
/// the waveform says where the exposure sits, the parade says which
/// channel is off, the vectorscope says how saturated and in what
/// direction, the histogram says how the tones are distributed. All four
/// read the **graded** frame, which is the only reading worth having.
enum VideoScopeKind: String, CaseIterable, Identifiable, Sendable {
    case waveform
    case parade
    case vectorscope
    case histogram

    var id: String { rawValue }

    /// The name in the segmented control. "Vectorscope" is one character
    /// too long for a quarter of a 320pt column and comes out "Vectors…",
    /// so the control says Vector and the caption underneath says the whole
    /// word — a truncated label is worse than a short one.
    var pickerName: String {
        switch self {
        case .vectorscope: String(localized: "Vector", comment: "Video Studio scope: short name for the vectorscope")
        default: displayName
        }
    }

    var displayName: String {
        switch self {
        case .waveform: String(localized: "Waveform", comment: "Video Studio scope: luma against screen position")
        case .parade: String(localized: "Parade", comment: "Video Studio scope: R, G and B waveforms side by side")
        case .vectorscope: String(localized: "Vectorscope", comment: "Video Studio scope: hue and saturation")
        case .histogram: String(localized: "Histogram", comment: "Video Studio scope: tonal distribution")
        }
    }
}

/// Counting pixels into the grids a scope draws.
///
/// Pure and integer-only so it is testable and so it can run off the main
/// actor on a downscaled frame. Everything takes tightly packed RGBA8
/// bytes — what `CIContext.render(toBitmap:)` hands back — and returns a
/// row-major grid of counts, which the renderer turns into pixels.
///
/// Nothing here normalizes: the caller divides by the peak it chooses,
/// because a scope that rescales itself every frame is a scope that lies
/// about whether the picture changed.
enum VideoScopeMath {
    /// Bytes per pixel in the buffers this takes.
    static let componentCount = 4

    /// A luma weight set. Rec.709, because that is the space the export is
    /// encoded in, so the waveform matches what the file will measure.
    static func luma(r: Int, g: Int, b: Int) -> Int {
        // 0.2126 / 0.7152 / 0.0722 in 1/1024ths, summing to exactly 1024.
        (218 * r + 732 * g + 74 * b) >> 10
    }

    /// One channel's waveform: `columns × levels` counts, column-major by
    /// row (index = level * columns + column), origin at the **bottom**
    /// (level 0 is black) because that is how a waveform is read.
    ///
    /// Columns map to horizontal screen position, so a bright window on the
    /// right of frame makes a trace on the right of the scope.
    static func waveform(
        rgba: [UInt8],
        width: Int,
        height: Int,
        columns: Int,
        levels: Int,
        channel: Channel
    ) -> [Int] {
        guard width > 0, height > 0, columns > 0, levels > 0,
              rgba.count >= width * height * componentCount
        else { return [] }
        var grid = [Int](repeating: 0, count: columns * levels)
        for y in 0..<height {
            let row = y * width * componentCount
            for x in 0..<width {
                let p = row + x * componentCount
                let value = channel.value(
                    r: Int(rgba[p]), g: Int(rgba[p + 1]), b: Int(rgba[p + 2])
                )
                let column = x * columns / width
                let level = min(levels - 1, value * levels / 256)
                grid[level * columns + column] += 1
            }
        }
        return grid
    }

    /// The vectorscope: a `size × size` grid of counts in Cb/Cr, centred on
    /// neutral. Row-major, origin top-left, so the renderer can hand it
    /// straight to a bitmap; +Cr (red) is to the right and +Cb (blue) is
    /// **down**, which puts the graticule's red/yellow/green/cyan/blue/
    /// magenta targets where a colourist expects them once the bitmap is
    /// drawn top-down.
    static func vectorscope(rgba: [UInt8], width: Int, height: Int, size: Int) -> [Int] {
        guard width > 0, height > 0, size > 0,
              rgba.count >= width * height * componentCount
        else { return [] }
        var grid = [Int](repeating: 0, count: size * size)
        let half = Double(size) / 2
        for y in 0..<height {
            let row = y * width * componentCount
            for x in 0..<width {
                let p = row + x * componentCount
                let r = Double(rgba[p]) / 255
                let g = Double(rgba[p + 1]) / 255
                let b = Double(rgba[p + 2]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                // Rec.709 chroma, each in ±0.5, scaled to fill the square.
                let cb = (b - luma) / 1.8556
                let cr = (r - luma) / 1.5748
                // Clamped, not discarded: a fully saturated Rec.709 primary
                // lands exactly on the edge of the square, and dropping it
                // would leave the scope blank on the very frames it is most
                // needed for.
                let gx = min(size - 1, max(0, Int(half + cr * Double(size))))
                let gy = min(size - 1, max(0, Int(half + cb * Double(size))))
                grid[gy * size + gx] += 1
            }
        }
        return grid
    }

    /// Per-channel counts over `buckets` tonal steps, plus luma.
    static func histogram(
        rgba: [UInt8],
        width: Int,
        height: Int,
        buckets: Int
    ) -> (red: [Int], green: [Int], blue: [Int], luma: [Int]) {
        let empty = [Int](repeating: 0, count: max(0, buckets))
        guard width > 0, height > 0, buckets > 0,
              rgba.count >= width * height * componentCount
        else { return (empty, empty, empty, empty) }
        var red = empty, green = empty, blue = empty, luma = empty
        for y in 0..<height {
            let row = y * width * componentCount
            for x in 0..<width {
                let p = row + x * componentCount
                let r = Int(rgba[p]), g = Int(rgba[p + 1]), b = Int(rgba[p + 2])
                red[min(buckets - 1, r * buckets / 256)] += 1
                green[min(buckets - 1, g * buckets / 256)] += 1
                blue[min(buckets - 1, b * buckets / 256)] += 1
                luma[min(buckets - 1, VideoScopeMath.luma(r: r, g: g, b: b) * buckets / 256)] += 1
            }
        }
        return (red, green, blue, luma)
    }

    enum Channel: Sendable {
        case luma, red, green, blue

        func value(r: Int, g: Int, b: Int) -> Int {
            switch self {
            case .luma: VideoScopeMath.luma(r: r, g: g, b: b)
            case .red: r
            case .green: g
            case .blue: b
            }
        }
    }

    /// The count a trace is drawn full-brightness at.
    ///
    /// A waveform column holds `height` pixels; if a whole column is one
    /// value it lands in a single cell. Full brightness at a fraction of
    /// that keeps ordinary detail visible instead of leaving everything
    /// near-black except flat sky.
    static func traceCeiling(sampleHeight: Int) -> Int {
        max(1, sampleHeight / 6)
    }
}
