import CoreGraphics
import Foundation

/// Video Studio project state. In-memory only for now — a project lives one
/// editing session and its output is a flat new video asset, so nothing here
/// carries the Codable compatibility burden of the photo recipes.

enum VideoClipKind: String, Sendable {
    case photo, video
    /// A single frame lifted out of a source video and held on screen, like a
    /// photo clip. `VideoClip.freezeSourceTime` says which frame; the frame is
    /// extracted once at load and drawn as a still (no track samples).
    case freeze
}

/// The output canvas shape. renderSize derives from the render preset's pixel
/// budget fitted to this aspect, so portrait/square exports are true canvases
/// (the compositor letterboxes/pillarboxes over the recipe background), not a
/// 16:9 frame with bars baked in.
enum VideoAspect: String, CaseIterable, Identifiable, Sendable {
    case r16x9, r9x16, r1x1, r4x5

    var id: String { rawValue }

    /// Width ÷ height.
    var ratio: CGFloat {
        switch self {
        case .r16x9: 16.0 / 9.0
        case .r9x16: 9.0 / 16.0
        case .r1x1: 1
        case .r4x5: 4.0 / 5.0
        }
    }

    var displayName: String {
        switch self {
        case .r16x9: "16:9"
        case .r9x16: "9:16"
        case .r1x1: "1:1"
        case .r4x5: "4:5"
        }
    }

    /// The canvas for a given long edge (the preset's larger dimension), rounded
    /// to even pixels so H.264 never chokes on an odd dimension.
    func canvasSize(longEdge: CGFloat) -> CGSize {
        let width: CGFloat
        let height: CGFloat
        if ratio >= 1 {
            width = longEdge
            height = longEdge / ratio
        } else {
            height = longEdge
            width = longEdge * ratio
        }
        return CGSize(
            width: (width / 2).rounded() * 2,
            height: (height / 2).rounded() * 2
        )
    }
}

/// A per-clip look/motion effect, evaluated over the clip's own placement
/// time by the frame compositor. Motion effects are affine-only so they read
/// identically at preview (1280) and export resolution.
enum VideoClipEffect: String, CaseIterable, Identifiable, Sendable {
    case none
    case zoomIn, zoomOut, panLeft, panRight, shake
    case blurIn, blurOut, softGlow, vignettePulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: String(localized: "None")
        case .zoomIn: String(localized: "Zoom In")
        case .zoomOut: String(localized: "Zoom Out")
        case .panLeft: String(localized: "Pan Left")
        case .panRight: String(localized: "Pan Right")
        case .shake: String(localized: "Shake")
        case .blurIn: String(localized: "Blur In")
        case .blurOut: String(localized: "Blur Out")
        case .softGlow: String(localized: "Soft Glow")
        case .vignettePulse: String(localized: "Vignette Pulse")
        }
    }
}

struct VideoClip: Identifiable, Equatable, Sendable {
    let id: UUID
    let assetID: String
    let kind: VideoClipKind
    /// Photo clips: how long the still stays on screen.
    var photoDuration: Double = VideoClip.defaultPhotoDuration
    /// Video clips: trim window in source seconds. `trimEnd` is nil until the
    /// source's duration resolves at load.
    var trimStart: Double = 0
    var trimEnd: Double?
    var isMuted = false
    var effect: VideoClipEffect = .none
    /// Playback speed multiplier for video clips (1 = real time). Photo and
    /// freeze clips ignore it — their length is `photoDuration` directly.
    var speed: Double = 1
    /// Freeze clips: the source-video time (seconds) the held frame came from.
    var freezeSourceTime: Double?
    /// Resolved at load, not user state.
    var sourceDuration: Double?

    init(assetID: String, kind: VideoClipKind, id: UUID = UUID()) {
        self.id = id
        self.assetID = assetID
        self.kind = kind
    }

    var effectiveDuration: Double {
        switch kind {
        case .photo, .freeze:
            photoDuration
        case .video:
            max(
                VideoClip.minimumClipDuration,
                ((trimEnd ?? sourceDuration ?? 0) - trimStart) / max(speed, VideoClip.speedRange.lowerBound)
            )
        }
    }

    static let defaultPhotoDuration: Double = 3
    static let photoDurationRange: ClosedRange<Double> = 0.5...10
    static let minimumClipDuration: Double = 0.1
    static let speedRange: ClosedRange<Double> = 0.25...4
}

/// How one clip hands over to the next. Every kind but `.none` overlaps the
/// two clips by `duration` and blends them in the compositor.
enum VideoTransitionKind: String, CaseIterable, Identifiable, Sendable {
    case none, crossfade, fadeBlack, slideLeft, slideRight, wipe, zoom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: String(localized: "None")
        case .crossfade: String(localized: "Crossfade")
        case .fadeBlack: String(localized: "Fade Black")
        case .slideLeft: String(localized: "Slide Left")
        case .slideRight: String(localized: "Slide Right")
        case .wipe: String(localized: "Wipe")
        case .zoom: String(localized: "Zoom")
        }
    }
}

/// The transition at one boundary between adjacent clips.
/// `recipe.transitions[i]` sits between `clips[i]` and `clips[i + 1]`.
struct VideoBoundaryTransition: Equatable, Sendable {
    var kind: VideoTransitionKind = .none
    var duration: Double = 0.5

    /// Overlap the timeline math should carve out for this boundary.
    var requestedOverlap: Double {
        kind == .none ? 0 : max(0, duration)
    }

    static let defaultCrossfade = VideoBoundaryTransition(kind: .crossfade, duration: 0.5)
    static let durationRange: ClosedRange<Double> = 0.2...2
}

/// A text overlay with the window it is visible in. `duration` nil means
/// "until the end of the video" and stays nil until the user resizes it.
struct TimedOverlay: Equatable, Sendable, Identifiable {
    var overlay: PhotoOverlay
    var start: Double = 0
    var duration: Double?

    var id: UUID { overlay.id }

    /// Active window is start-inclusive, end-exclusive.
    func isActive(at time: Double, total: Double) -> Bool {
        let end = duration.map { start + $0 } ?? total
        return time >= start && time < end
    }
}

enum MusicSource: Equatable, Sendable {
    case bundled(id: String)
    case imported(url: URL, displayName: String)
}

struct MusicSelection: Equatable, Sendable {
    var source: MusicSource
    var volume: Double = 1
    var fadeIn: Double = 2
    var fadeOut: Double = 2
    /// When true the bed tiles to fill the whole video; when false it plays
    /// once and stops.
    var loops = true
}

enum VideoRenderPreset: String, CaseIterable, Identifiable, Sendable {
    case hd1080
    case uhd4K

    var id: String { rawValue }

    /// Landscape canvas; portrait sources letterbox into it (v1).
    var renderSize: CGSize {
        switch self {
        case .hd1080: CGSize(width: 1920, height: 1080)
        case .uhd4K: CGSize(width: 3840, height: 2160)
        }
    }

    var displayName: String {
        switch self {
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }
}

enum VideoStudioMode: Sendable {
    /// Selection → Create → Video: any mix of photos and videos.
    case multiClip
    /// Edit on a video in the detail viewer: one clip, plus Rotate.
    case singleVideo
}

struct VideoProjectRecipe: Equatable, Sendable {
    var clips: [VideoClip]
    /// One entry per boundary between adjacent clips: `transitions[i]` sits
    /// between `clips[i]` and `clips[i + 1]`. Kept sized via
    /// `syncTransitionsWithClips()` whenever clips are added or removed.
    var transitions: [VideoBoundaryTransition] = []
    var music: MusicSelection?
    /// Global volume for the clips' own audio (music has its own).
    var videoVolume: Double = 1
    /// One look for the whole video (deliberately not per-clip).
    var filter: PhotoFilter = .original
    var filterIntensity: Double = 1
    var adjustments = PhotoAdjustments.zero
    var overlays: [TimedOverlay] = []
    /// Single-video mode: user rotation in quarter turns (0–3).
    var quarterTurns = 0
    var renderPreset: VideoRenderPreset = .hd1080
    /// Output canvas shape. renderSize = preset long edge fitted to this.
    var aspect: VideoAspect = .r16x9
    /// Overall output gain applied on top of clip-audio and music volumes.
    var masterVolume: Double = 1
    /// Letterbox / pillarbox fill behind aspect-fitted frames.
    var background = OverlayColor.black

    /// The render canvas: the preset's pixel budget fitted to the aspect.
    func canvasSize() -> CGSize {
        let preset = renderPreset.renderSize
        let longEdge = max(preset.width, preset.height)
        return aspect.canvasSize(longEdge: longEdge)
    }
}

extension VideoProjectRecipe {
    /// Resize `transitions` to `max(0, clips.count - 1)`, preserving the
    /// existing prefix and padding new boundaries with `.none`. Boundaries are
    /// positional, so reordering clips keeps the array untouched.
    mutating func syncTransitionsWithClips() {
        let target = max(0, clips.count - 1)
        if transitions.count > target {
            transitions.removeLast(transitions.count - target)
        } else if transitions.count < target {
            transitions.append(contentsOf: Array(
                repeating: VideoBoundaryTransition(),
                count: target - transitions.count
            ))
        }
    }
}
