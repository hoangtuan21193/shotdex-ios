import CoreGraphics
import Foundation

/// Where a video is going (FS-12.16 §3): five built-in presets — constants
/// of the app, not user data — each the ratio, size, frame rate and codec
/// that place wants. A preset is the destination of one export; it never
/// changes the project's ratio or its Video Settings (§4).
enum VideoExportPreset: String, CaseIterable, Identifiable, Sendable {
    case reels, youTube4K, youTube, instagram, square

    var id: String { rawValue }

    var name: String {
        switch self {
        case .reels: "Reels / TikTok"
        case .youTube4K: "YouTube 4K"
        case .youTube: "YouTube"
        case .instagram: "Instagram 4:5"
        case .square: "Square"
        }
    }

    var aspect: VideoAspect {
        switch self {
        case .reels: .r9x16
        case .youTube4K, .youTube: .r16x9
        case .instagram: .r4x5
        case .square: .r1x1
        }
    }

    var resolution: VideoResolution { self == .youTube4K ? .uhd4K : .p1080 }
    var frameRate: VideoFrameRate { .fps30 }
    var codec: VideoCodec { self == .youTube4K ? .hevc : .h264 }

    /// 1080×1920, 3840×2160, 1920×1080, 1080×1350, 1080×1080.
    var frameSize: CGSize { VideoOutputSpec.frameSize(aspect: aspect, resolution: resolution) }

    /// "1080×1920 · 30 fps", "· HEVC" when it is not H.264 (§3).
    var specLine: String {
        let base = "\(Int(frameSize.width))×\(Int(frameSize.height)) · \(frameRate.rawValue) fps"
        return codec == .h264 ? base : "\(base) · \(codec.displayName)"
    }

    /// The preset a project of `aspect` starts on — and what an id this
    /// build cannot read falls back to (§4, §6): 16:9 → YouTube, 9:16 →
    /// Reels / TikTok, 4:5 → Instagram 4:5, 1:1 → Square; nil (Custom) for
    /// 4:3 and 21:9.
    static func matching(_ aspect: VideoAspect) -> VideoExportPreset? {
        switch aspect {
        case .r16x9: .youTube
        case .r9x16: .reels
        case .r4x5: .instagram
        case .r1x1: .square
        case .r4x3, .r21x9: nil
        }
    }

    /// Whether a window lists Custom (§3): the phone and the iPad do; the
    /// Duo's Video Settings button is its Custom.
    static func listsCustom(on windowClass: VideoStudioWindowClass) -> Bool {
        windowClass != .duoInner && windowClass != .duoCover
    }
}

/// What the project exports to: a preset, or Custom — its own Video
/// Settings. Stored as a string id so a preset this build does not know
/// costs nothing but itself (§6, AC-12).
enum VideoExportTarget: Equatable, Hashable, Sendable {
    case preset(VideoExportPreset)
    case custom

    static let customID = "custom"

    var storedID: String {
        switch self {
        case .preset(let preset): preset.rawValue
        case .custom: Self.customID
        }
    }

    /// The stored id read back: an unknown or missing one is the preset of
    /// the project's ratio, else Custom — never an error.
    static func resolve(storedID: String?, aspect: VideoAspect) -> VideoExportTarget {
        if storedID == customID { return .custom }
        if let storedID, let preset = VideoExportPreset(rawValue: storedID) { return .preset(preset) }
        return VideoExportPreset.matching(aspect).map(VideoExportTarget.preset) ?? .custom
    }
}

/// One export as the writer will make it (FS-12.16 §4): the frame, rate and
/// codec, and — when the frame's ratio is not the project's — how the
/// project sits in it.
struct VideoExportSpec: Equatable, Sendable {
    let size: CGSize
    let frameRate: VideoFrameRate
    let codec: VideoCodec
    /// Nil when the ratios match; Fit on Background or Fill (Crop) when not.
    let framing: VideoFraming?

    /// The spec of `target` for `recipe`. Custom is the project's own.
    static func make(target: VideoExportTarget, framing: VideoFraming, recipe: VideoProjectRecipe) -> VideoExportSpec {
        switch target {
        case .custom:
            return VideoExportSpec(size: recipe.canvasSize(), frameRate: recipe.frameRate, codec: recipe.codec, framing: nil)
        case .preset(let preset):
            return VideoExportSpec(
                size: preset.frameSize, frameRate: preset.frameRate, codec: preset.codec,
                framing: preset.aspect == recipe.aspect ? nil : framing
            )
        }
    }

    /// The project's frame as laid out for this export: as large as the
    /// export frame needs — covering it (Fill) or inside it (Fit) — so the
    /// clips are drawn at the export's own resolution, never upscaled from
    /// the project's.
    func layoutCanvas(project: CGSize) -> CGSize {
        guard let framing, project.width > 0, project.height > 0 else { return size }
        let scale = framing == .fill
            ? max(size.width / project.width, size.height / project.height)
            : min(size.width / project.width, size.height / project.height)
        let even = { (value: CGFloat) in max(2, (value / 2).rounded() * 2) }
        return CGSize(width: even(project.width * scale), height: even(project.height * scale))
    }

    /// The bytes it will be (FS-12.10 §5's formula with this spec).
    func estimatedBytes(duration: Double) -> Int64 {
        VideoExportEstimate.bytes(frame: size, frameRate: frameRate, codec: codec, duration: duration)
    }
}

/// The preview while Export Video is open (§4): Fill — the export's frame,
/// its ratio inside the project frame, the outside dimmed; Fit — the
/// project frame drawn smaller inside the export's frame, bands around it.
enum VideoExportFraming {
    /// The crop of Fill in the preview's project frame: 9:16 in a 402×226
    /// frame is 127×226 at x 137.5 (AC-2).
    static func fillCrop(in frame: CGRect, output: CGSize) -> CGRect {
        let aspect = output.width / max(output.height, 1)
        var size = CGSize(width: frame.height * aspect, height: frame.height)
        if size.width > frame.width { size = CGSize(width: frame.width, height: frame.width / aspect) }
        return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Fit: the export's frame as large as it fits in the preview's frame,
    /// and the project's frame inside it.
    static func fit(in frame: CGRect, output: CGSize, project: CGSize) -> (output: CGRect, project: CGRect) {
        let outer = fillCrop(in: frame, output: output)
        let scale = min(outer.width / max(project.width, 1), outer.height / max(project.height, 1))
        let inner = CGSize(width: project.width * scale, height: project.height * scale)
        return (outer, CGRect(x: outer.midX - inner.width / 2, y: outer.midY - inner.height / 2, width: inner.width, height: inner.height))
    }

    /// "9:16 · Fill" — the pill at the crop's corner.
    static func pill(_ preset: VideoExportPreset, framing: VideoFraming) -> String {
        "\(preset.aspect.displayName) · \(framing == .fill ? "Fill" : "Fit")"
    }
}
