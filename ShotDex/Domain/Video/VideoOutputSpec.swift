import CoreGraphics
import Foundation

/// What an export writes, and the arithmetic behind Video Settings
/// (FS-12.10 §5, FS-12.01 §9): the frame size from ratio and resolution.
/// One place, so the Output line, the 4K gate and the writer cannot
/// disagree. Knows nothing of presets (FS-12.16): a preset is only the
/// destination of one export.
enum VideoOutputSpec {
    /// The long edge never exceeds this (21:9 at 4K is 3840×1646).
    static let longEdgeCap: CGFloat = 3840

    /// The frame: the short edge by resolution class, the long edge by the
    /// ratio, capped at 3840 (the short edge then follows the ratio), both
    /// rounded to even pixels — H.264 and HEVC refuse odd sizes.
    static func frameSize(aspect: VideoAspect, resolution: VideoResolution) -> CGSize {
        let ratio = aspect.ratio
        var short = resolution.shortEdge
        var long = short * max(ratio, 1 / ratio)
        if long > longEdgeCap {
            long = longEdgeCap
            short = long / max(ratio, 1 / ratio)
        }
        let even = { (value: CGFloat) in (value / 2).rounded() * 2 }
        return ratio >= 1
            ? CGSize(width: even(long), height: even(short))
            : CGSize(width: even(short), height: even(long))
    }
}
