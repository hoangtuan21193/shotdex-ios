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

/// The export's size before it is written (FS-12.10 §5): video at
/// width × height × fps × 0.16 bit — about 10 Mbps at 1080p30, the rate a
/// 1080p30 upload wants — HEVC at 0.6 of that, plus 128 kbps of AAC.
enum VideoExportEstimate {
    static let bitsPerPixelPerFrame = 0.16
    static let hevcFactor = 0.6
    static let audioBitsPerSecond = 128_000

    /// The video track's average bitrate — what the writer asks the encoder
    /// for, so the Output line and the file cannot disagree.
    static func videoBitrate(frame: CGSize, frameRate: VideoFrameRate, codec: VideoCodec) -> Int {
        let h264 = Double(frame.width * frame.height) * Double(frameRate.rawValue) * bitsPerPixelPerFrame
        return Int((codec == .hevc ? h264 * hevcFactor : h264).rounded())
    }

    static func bytes(frame: CGSize, frameRate: VideoFrameRate, codec: VideoCodec, duration: Double) -> Int64 {
        let bits = Double(videoBitrate(frame: frame, frameRate: frameRate, codec: codec) + audioBitsPerSecond)
            * max(0, duration)
        return Int64((bits / 8).rounded())
    }

    static func bytes(for recipe: VideoProjectRecipe, duration: Double) -> Int64 {
        bytes(frame: recipe.canvasSize(), frameRate: recipe.frameRate, codec: recipe.codec, duration: duration)
    }

    /// "~30 MB", rounded to the megabyte; "~1.2 GB" from 1000 MB on.
    /// Decimal units, as the Files app counts them.
    static func label(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 1000 {
            return String(format: "~%.1f GB", megabytes / 1000)
        }
        return "~\(Int(megabytes.rounded())) MB"
    }
}

/// How the writer encodes — one value built from the same numbers as the
/// estimate (plan T-5).
struct VideoEncodingSettings: Equatable {
    let size: CGSize
    let frameRate: VideoFrameRate
    let codec: VideoCodec
    let bitrate: Int

    static func make(for recipe: VideoProjectRecipe) -> VideoEncodingSettings {
        let size = recipe.canvasSize()
        return VideoEncodingSettings(
            size: size,
            frameRate: recipe.frameRate,
            codec: recipe.codec,
            bitrate: VideoExportEstimate.videoBitrate(frame: size, frameRate: recipe.frameRate, codec: recipe.codec)
        )
    }
}
