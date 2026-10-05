import CoreGraphics
import Foundation
import ShotDexKit

/// Video Studio project state. Stored as JSON in the `creations` table — as a
/// draft while it is being edited and beside the exported video afterwards —
/// and read back **leniently** (see the decoders at the end of this file): a
/// key an older build wrote is ignored, a key a newer build added is
/// defaulted, and one unreadable clip, caption or music bed costs that
/// element only. The app is unreleased, so nothing here migrates old values;
/// lenient reading is robustness, not compatibility.

enum VideoClipKind: String, Codable, Sendable {
    case photo, video
    /// A single frame lifted out of a source video and held on screen, like a
    /// photo clip. `VideoClip.freezeSourceTime` says which frame; the frame is
    /// extracted once at load and drawn as a still (no track samples).
    case freeze
}

/// The output canvas shape (FS-12.10 §4): six ratios, in the order Video
/// Settings lists them. The frame size comes from the ratio and the
/// resolution (`VideoOutputSpec.frameSize`), so portrait and square exports
/// are true canvases — the compositor fits or fills each clip on it — not a
/// 16:9 frame with bars baked in.
enum VideoAspect: String, CaseIterable, Identifiable, Codable, Sendable {
    case r16x9, r9x16, r1x1, r4x5, r4x3, r21x9

    var id: String { rawValue }

    /// Width ÷ height.
    var ratio: CGFloat {
        switch self {
        case .r16x9: 16.0 / 9.0
        case .r9x16: 9.0 / 16.0
        case .r1x1: 1
        case .r4x5: 4.0 / 5.0
        case .r4x3: 4.0 / 3.0
        case .r21x9: 21.0 / 9.0
        }
    }

    var displayName: String {
        switch self {
        case .r16x9: "16:9"
        case .r9x16: "9:16"
        case .r1x1: "1:1"
        case .r4x5: "4:5"
        case .r4x3: "4:3"
        case .r21x9: "21:9"
        }
    }

    /// The ratio nearest a clip's shape, on a log scale so 2:1 and 1:2 are
    /// equally far from square; a tie goes to 16:9 (FS-12.10 §5: a new
    /// project takes the shape of its first clip).
    static func nearest(to ratio: CGFloat) -> VideoAspect {
        guard ratio.isFinite, ratio > 0 else { return .r16x9 }
        let target = log(Double(ratio))
        var best = VideoAspect.r16x9
        var bestDistance = abs(log(Double(best.ratio)) - target)
        for candidate in allCases where candidate != .r16x9 {
            let distance = abs(log(Double(candidate.ratio)) - target)
            if distance < bestDistance - 1e-9 {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }
}

/// The export's resolution class, by the frame's **short** edge (FS-12.10 §5).
enum VideoResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case p720, p1080, uhd4K

    var id: String { rawValue }

    var shortEdge: CGFloat {
        switch self {
        case .p720: 720
        case .p1080: 1080
        case .uhd4K: 2160
        }
    }

    var displayName: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .uhd4K: "4K"
        }
    }
}

/// Frames a second of the export. The preview always runs at 30 (FS-12.01 §8).
enum VideoFrameRate: Int, CaseIterable, Identifiable, Codable, Sendable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
}

enum VideoCodec: String, CaseIterable, Identifiable, Codable, Sendable {
    case h264, hevc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

/// How a clip sits in the frame (FS-12.10 §4): all of it on a background,
/// or the frame filled and the rest cropped from the middle.
enum VideoFraming: String, CaseIterable, Identifiable, Codable, Sendable {
    case fit, fill

    var id: String { rawValue }
}

/// What shows around a fitted clip (FS-12.10 §5, FS-12.01 §7b).
struct VideoBackground: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Codable, Sendable {
        /// The clip's own frame, filled and blurred.
        case blur
        /// One colour.
        case colour
        /// A library photo, filled, not blurred.
        case image

        var id: String { rawValue }
    }

    var kind: Kind = .colour
    var colour: OverlayColor = .black
    /// 0…100.
    var blurAmount: Double = 50
    /// The library photo behind an Image background.
    var imageAssetID: String?

    static let blurRange: ClosedRange<Double> = 0...100

    init(kind: Kind = .colour, colour: OverlayColor = .black, blurAmount: Double = 50, imageAssetID: String? = nil) {
        self.kind = kind
        self.colour = colour
        self.blurAmount = blurAmount
        self.imageAssetID = imageAssetID
    }

    init(from decoder: any Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        kind = ((try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? nil) ?? .colour
        colour = ((try? container.decodeIfPresent(OverlayColor.self, forKey: .colour)) ?? nil) ?? .black
        blurAmount = ((try? container.decodeIfPresent(Double.self, forKey: .blurAmount)) ?? nil) ?? 50
        imageAssetID = (try? container.decodeIfPresent(String.self, forKey: .imageAssetID)) ?? nil
    }
}

/// A per-clip look/motion effect, evaluated over the clip's own placement
/// time by the frame compositor. Motion effects are affine-only so they read
/// identically at preview (1280) and export resolution.
enum VideoClipEffect: String, CaseIterable, Identifiable, Codable, Sendable {
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

    /// Chip glyph in the clip inspector's Animate row.
    var systemImage: String {
        switch self {
        case .none: "circle.slash"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .panLeft: "arrow.left"
        case .panRight: "arrow.right"
        case .shake: "waveform.path"
        case .blurIn: "aqi.medium"
        case .blurOut: "aqi.low"
        case .softGlow: "sun.haze"
        case .vignettePulse: "circle.dotted.circle"
        }
    }
}

struct VideoClip: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let assetID: String
    let kind: VideoClipKind
    /// Photo clips: how long the still stays on screen.
    var photoDuration: Double = VideoClip.defaultPhotoDuration
    /// Video clips: trim window in source seconds. `trimEnd` is nil until the
    /// source's duration resolves at load.
    var trimStart: Double = 0
    var trimEnd: Double?
    /// The clip's own level, 0…1, times the project's Video sound
    /// (FS-12.08 §2): a Volume slider in one clip's panel changes that clip.
    var volume: Double = 1
    var isMuted = false
    /// Seconds of fade from the project background at the clip's head, and
    /// back to it at its tail. Zero means a hard cut, which is the default
    /// and what most cuts should be.
    ///
    /// Separate from a *transition*, which is a deal between two neighbours
    /// and lives on the boundary. A fade is one clip's own business: it is
    /// what opens a film and what closes it.
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var effect: VideoClipEffect = .none
    /// Playback speed multiplier for video clips (1 = real time). Photo and
    /// freeze clips ignore it — their length is `photoDuration` directly.
    var speed: Double = 1
    /// Freeze clips: the source-video time (seconds) the held frame came from.
    var freezeSourceTime: Double?
    /// Resolved at load, not user state.
    var sourceDuration: Double?
    /// The clip's own look (FS-12.06c): nil follows the whole video's;
    /// anything else — Original included — replaces it for this clip.
    var look: VideoLook?

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

    /// How much of a clip a fade may take. Half each end, so the two can
    /// never cross and leave a clip that is never fully visible.
    func maximumFade() -> Double { max(0, effectiveDuration / 2) }

    /// Opacity at one second into this clip, from its own fades.
    func fadeOpacity(atLocalTime seconds: Double) -> Double {
        let length = effectiveDuration
        guard length > 0 else { return 1 }
        var opacity = 1.0
        if fadeIn > 0, seconds < fadeIn {
            opacity = min(opacity, max(0, seconds / fadeIn))
        }
        if fadeOut > 0, seconds > length - fadeOut {
            opacity = min(opacity, max(0, (length - seconds) / fadeOut))
        }
        return opacity
    }

    static let defaultPhotoDuration: Double = 3
    static let photoDurationRange: ClosedRange<Double> = 0.5...10
    static let minimumClipDuration: Double = 0.1
    static let speedRange: ClosedRange<Double> = 0.25...4
}

/// How one clip hands over to the next. Every kind but `.none` overlaps the
/// two clips by `duration` and blends them in the compositor.
enum VideoTransitionKind: String, CaseIterable, Identifiable, Codable, Sendable {
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
struct VideoBoundaryTransition: Equatable, Codable, Sendable {
    var kind: VideoTransitionKind = .none
    var duration: Double = 0.5

    /// Overlap the timeline math should carve out for this boundary.
    var requestedOverlap: Double {
        kind == .none ? 0 : max(0, duration)
    }

    static let defaultCrossfade = VideoBoundaryTransition(kind: .crossfade, duration: 0.5)
    static let durationRange: ClosedRange<Double> = 0.2...2
}

/// A note pinned to a point on the timeline.
///
/// Resolve's Cut page keeps markers on the ruler, attached to the **timeline
/// position** rather than to a clip, so trimming one shot does not drag every
/// note with it. Same here: a marker is a time, not a child of a clip.
///
/// Markers never reach the compositor — they are something the editor looks
/// at, not something the export writes.
struct TimedMarker: Equatable, Codable, Sendable, Identifiable {
    var id = UUID()
    /// Timeline seconds.
    var time: Double
    /// Index into `TimedMarker.palette`, so the stored value survives a
    /// palette change and a colour never has to be encoded as a hex string.
    var colorIndex: Int = 0
    var note: String = ""

    /// Resolve offers a fixed set of marker colours; so does this, for the
    /// same reason — a marker colour is a category, and a colour picker turns
    /// a category into a decision.
    static let palette: [String] = ["blue", "green", "yellow", "red", "purple"]

    var clampedColorIndex: Int { min(max(0, colorIndex), Self.palette.count - 1) }
}

/// A text overlay with the window it is visible in. `duration` nil means
/// "until the end of the video" and stays nil until the user resizes it.
struct TimedOverlay: Equatable, Codable, Sendable, Identifiable {
    var overlay: PhotoOverlay
    var start: Double = 0
    var duration: Double?
    /// How the layer appears at the top of its window and disappears at the end.
    /// The durations are the ramp lengths, clamped to the window at render time.
    var animateIn: OverlayAnimation = .none
    var animateOut: OverlayAnimation = .none
    var inDuration: Double = 0.4
    var outDuration: Double = 0.4

    var id: UUID { overlay.id }

    /// Active window is start-inclusive, end-exclusive.
    func isActive(at time: Double, total: Double) -> Bool {
        let end = duration.map { start + $0 } ?? total
        return time >= start && time < end
    }

    /// The animated deviation from the resting pose at `time` — identity outside
    /// the in/out ramps. Shared by the export bake and the preview proxy.
    func animationTransform(at time: Double, total: Double) -> OverlayAnimationMath.Transform {
        let end = duration.map { start + $0 } ?? total
        let window = max(0.01, end - start)
        var transform = OverlayAnimationMath.Transform.identity
        if animateIn != .none {
            let ramp = min(inDuration, window)
            if ramp > 0, time < start + ramp {
                transform = transform.combined(
                    with: OverlayAnimationMath.enter(animateIn, progress: (time - start) / ramp)
                )
            }
        }
        if animateOut != .none {
            let ramp = min(outDuration, window)
            let outStart = end - ramp
            if ramp > 0, time > outStart {
                transform = transform.combined(
                    with: OverlayAnimationMath.exit(animateOut, progress: (time - outStart) / ramp)
                )
            }
        }
        return transform
    }
}

enum MusicSource: Equatable, Codable, Sendable {
    case bundled(id: String)
    case imported(url: URL, displayName: String)
}

/// One music bed on the timeline. A project can hold several, each with its own
/// placement, trim and envelope; overlapping tracks stack into lanes below the
/// video track and mix together at export.
struct MusicTrack: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var source: MusicSource
    /// Timeline second the trimmed audio begins at.
    var start: Double = 0
    /// Trim window in source seconds. `trimEnd` is nil until the source's
    /// duration resolves at load, mirroring `VideoClip`.
    var trimStart: Double = 0
    var trimEnd: Double?
    /// Resolved at load, not user state.
    var sourceDuration: Double?
    var volume: Double = 1
    /// Silenced from the speaker at the head of its Volume row (FS-12.04b
    /// §5). Apart from `volume`, so unmuting returns exactly the old level.
    var isMuted = false
    var fadeIn: Double = 2
    var fadeOut: Double = 2
    /// Snap to this bed's beats (FS-12.12 §5) — off, every beat, no offset
    /// for a new bed and for a stored one that lacks the keys.
    var beatSnap = MusicBeatSnap()

    init(source: MusicSource, id: UUID = UUID()) {
        self.id = id
        self.source = source
    }

    /// How long the track occupies the timeline, before the video's own end
    /// clips it — that final clamp lives in `VideoTimelineMath.musicPlacement`.
    var effectiveDuration: Double {
        max(MusicTrack.minimumDuration, (trimEnd ?? sourceDuration ?? 0) - trimStart)
    }

    var end: Double { start + effectiveDuration }

    var displayName: String {
        switch source {
        case let .imported(_, displayName): displayName
        case let .bundled(id): id
        }
    }

    static let minimumDuration: Double = 0.1
    static let fadeRange: ClosedRange<Double> = 0...10
}

/// A bed's snap to its beats (FS-12.12 §5, §7): on or off, every beat or
/// only the bar's first, and the grid's Offset in milliseconds (±250,
/// step 5). One bed of a project snaps at most.
struct MusicBeatSnap: Equatable, Codable, Sendable {
    var isOn = false
    var division: BeatGrid.Division = .beat
    var offsetMs = 0

    static let offsetRange: ClosedRange<Int> = -250...250
    static let offsetStep = 5

    var offsetSeconds: Double { Double(offsetMs) / 1000 }

    init(isOn: Bool = false, division: BeatGrid.Division = .beat, offsetMs: Int = 0) {
        self.isOn = isOn
        self.division = division
        self.offsetMs = offsetMs
    }

    /// Each key on its own: one that is missing or will not read is its
    /// default, and the bed — and the project — still opens.
    init(from decoder: any Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        isOn = ((try? container.decodeIfPresent(Bool.self, forKey: .isOn)) ?? nil) ?? false
        division = ((try? container.decodeIfPresent(BeatGrid.Division.self, forKey: .division)) ?? nil) ?? .beat
        let offset = ((try? container.decodeIfPresent(Int.self, forKey: .offsetMs)) ?? nil) ?? 0
        offsetMs = min(max(offset, Self.offsetRange.lowerBound), Self.offsetRange.upperBound)
    }
}

enum VideoStudioMode: Sendable {
    /// Selection → Create → Video: any mix of photos and videos.
    case multiClip
    /// Edit on a video in the detail viewer: one clip, plus Rotate.
    case singleVideo
}

/// One correction in the grade, and the order they run in is the order they
/// are in.
///
/// This is Resolve's **serial node chain**, which is what a grade is most of
/// the time: balance on one node, a look on the next, a window on a third.
/// Three nodes each doing one thing is a grade you can reason about and turn
/// off a piece of; one node doing three things is a pile of sliders.
///
/// What is deliberately not here is the rest of Resolve's node graph —
/// parallel and layer mixers, outside nodes, keys routed between nodes. Those
/// need a DAG with named inputs and outputs, and a canvas to wire it on; a
/// serial chain needs a list. The chain covers the common grade honestly
/// rather than covering the whole feature badly.
struct ColorNode: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    /// What the node is called. Defaults to its position, renameable,
    /// because "Node 2" tells a colourist nothing a week later and
    /// "Skin" does.
    var name: String
    /// Bypassed nodes stay in the chain and do nothing — the whole point of
    /// splitting a grade up is being able to switch one part off and look.
    var isEnabled: Bool
    var adjustments: PhotoAdjustments
    var color: PhotoColorRecipe
    var curve: ToneCurveAdjustments
    /// Power windows and qualifiers that limit **this node** to part of the
    /// frame. A node with no mask grades everything.
    var masks: [PhotoMask]
    /// Where each tracked window is over time, by mask id. A window with no
    /// entry stays where it was drawn.
    var tracks: [MaskTrack]

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        adjustments: PhotoAdjustments = .zero,
        color: PhotoColorRecipe = PhotoColorRecipe(),
        curve: ToneCurveAdjustments = ToneCurveAdjustments(),
        masks: [PhotoMask] = [],
        tracks: [MaskTrack] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.adjustments = adjustments
        self.color = color
        self.curve = curve
        self.masks = masks
        self.tracks = tracks
    }

    /// Nothing dialled in. A chain of these renders exactly as no chain at
    /// all, which is what makes adding a node free.
    var isIdentity: Bool {
        adjustments.isIdentity && color.isIdentity && curve == .identity && masks.isEmpty
    }

    /// The windows, moved to where their tracks say they are at `time`.
    /// An untracked window comes back untouched, so a node with no tracks
    /// costs one array pass and nothing else.
    func trackedMasks(at time: Double) -> [PhotoMask] {
        guard !tracks.isEmpty else { return masks }
        return masks.map { mask in
            guard let track = tracks.first(where: { $0.maskID == mask.id }) else { return mask }
            return MaskTrackMath.tracked(mask, by: track.keyframe(at: time))
        }
    }

    /// The track for one window, if it has been tracked.
    func track(for maskID: UUID) -> MaskTrack? {
        tracks.first { $0.maskID == maskID }
    }

    /// The name to show when the user has not given it one.
    func displayName(at index: Int) -> String {
        name.isEmpty
            ? String(
                localized: "Node \(index + 1)",
                comment: "Video Studio colour: the default name of a grading node, by its position in the chain"
            )
            : name
    }
}

/// One look slot (FS-12.06c §6): the whole video has one, each clip may
/// have its own. A look is one of three things the photo editor already
/// has — a film look, one of My Looks, an imported LUT — plus how much of
/// it to mix in.
struct VideoLook: Equatable, Codable, Sendable {
    enum Source: Equatable, Codable, Sendable {
        /// A built-in film look, by its preset. `.original` is "no look" —
        /// on a clip it still replaces the whole video's look.
        case preset(PhotoFilter)
        /// One of My Looks, **copied** when chosen (§6): the look part of
        /// its recipe, the id of the look it came from — so the tile of
        /// that look is drawn chosen, and a tap takes the newer version —
        /// its name, and whether it was imported from a preset file.
        case myLook(sourceID: UUID, name: String, isImported: Bool, recipe: PhotoEditRecipe)
        /// An imported LUT, by `ImportedLUTStore` id. The name is kept here
        /// too, so a project whose file has gone can still say which LUT is
        /// missing.
        case lut(id: String, name: String)
    }

    var source: Source
    /// 0…1: how much of the **whole** look is mixed over the frame before
    /// it (§4) — tone, colour, film, LUT, grain, vignette alike.
    var amount: Double = 1

    init(_ source: Source, amount: Double = 1) {
        self.source = source
        self.amount = amount
    }

    static let original = VideoLook(.preset(.original))

    /// Original: nothing to render.
    var isOriginal: Bool { source == .preset(.original) }

    /// The editor recipe this look renders as: the film look or the LUT at
    /// full strength, or the copied My Look as it was saved.
    var recipe: PhotoEditRecipe {
        switch source {
        case let .preset(filter):
            var recipe = PhotoEditRecipe.identity
            recipe.filter = filter
            recipe.filterIntensity = 1
            return recipe
        case let .myLook(_, _, _, recipe):
            return recipe
        case let .lut(id, _):
            var recipe = PhotoEditRecipe.identity
            recipe.lutID = id
            recipe.filterIntensity = 1
            return recipe
        }
    }

    /// The LUT the look reads from disk — chosen directly, or inside a My
    /// Look — whose file can go missing (§6).
    var lutID: String? {
        switch source {
        case .preset: nil
        case let .myLook(_, _, _, recipe): recipe.lutID
        case let .lut(id, _): id
        }
    }
}

struct VideoProjectRecipe: Equatable, Codable, Sendable {
    var clips: [VideoClip]
    /// One entry per boundary between adjacent clips: `transitions[i]` sits
    /// between `clips[i]` and `clips[i + 1]`. Kept sized via
    /// `syncTransitionsWithClips()` whenever clips are added or removed.
    var transitions: [VideoBoundaryTransition] = []
    /// Music beds, each independently placed and trimmed. Overlapping tracks
    /// stack into lanes on the timeline and mix together at export.
    var musicTracks: [MusicTrack] = []
    /// "Video sound": the clips' own audio, for the whole project — the one
    /// project-wide level there is (FS-12.08 §2). Music beds have their own.
    var videoVolume: Double = 1
    /// Notes on the ruler.
    var markers: [TimedMarker] = []
    /// Undoing the camera's encoding, before anything else touches the
    /// picture.
    var inputTransform: VideoInputTransform = .none
    /// The whole video's look (FS-12.06c): film look, My Look or LUT, and
    /// its Amount. Nil is none. A clip with a look of its own uses that
    /// instead (`VideoClip.look`).
    var look: VideoLook?
    /// The grade, as a chain of corrections rather than one flat set.
    ///
    /// Every stage the photo editor has — exposure and the rest of the
    /// adjustments, primaries, the HSL mixer, point colour, the tone curve,
    /// power windows and qualifiers — belongs to a node, and the chain runs
    /// in order. A project always has at least one; deleting the last one
    /// puts a fresh empty node back, because a grade with no node is a state
    /// with no controls.
    var nodes: [ColorNode] = [ColorNode()]
    var overlays: [TimedOverlay] = []
    /// Single-video mode: user rotation in quarter turns (0–3).
    var quarterTurns = 0
    /// Video Settings (FS-12.10): the frame's shape, how clips sit in it,
    /// what shows around them, and what the export writes.
    var aspect: VideoAspect = .r16x9
    var framing: VideoFraming = .fit
    var background = VideoBackground()
    var resolution: VideoResolution = .p1080
    var frameRate: VideoFrameRate = .fps30
    var codec: VideoCodec = .h264
    /// Where the playhead was when the draft was written (FS-12.18 §3).
    /// Only in what is stored: the model takes it out on open and puts the
    /// current one in on each save, so it is never part of an edit or undo.
    var playhead: Double?

    /// The export's frame: the ratio at the resolution (FS-12.10 §5).
    func canvasSize() -> CGSize {
        VideoOutputSpec.frameSize(aspect: aspect, resolution: resolution)
    }
}

extension VideoClip {
    /// This clip again under a new id — same media, trim, speed, fades,
    /// motion and look (Duplicate, FS-12.04b, FS-12.11 §5).
    func duplicated(id: UUID) -> VideoClip {
        var copy = VideoClip(assetID: assetID, kind: kind, id: id)
        copy.photoDuration = photoDuration
        copy.trimStart = trimStart
        copy.trimEnd = trimEnd
        copy.volume = volume
        copy.isMuted = isMuted
        copy.fadeIn = fadeIn
        copy.fadeOut = fadeOut
        copy.effect = effect
        copy.speed = speed
        copy.freezeSourceTime = freezeSourceTime
        copy.sourceDuration = sourceDuration
        copy.look = look
        return copy
    }
}

extension VideoProjectRecipe {
    /// The node at `id`, or the first one — a recipe is never without a node,
    /// so this never has to answer nil.
    func node(_ id: UUID?) -> ColorNode {
        guard let id, let found = nodes.first(where: { $0.id == id }) else {
            return nodes.first ?? ColorNode()
        }
        return found
    }

    /// Where `id` sits in the chain, for naming it and for reordering.
    func nodeIndex(_ id: UUID?) -> Int {
        guard let id, let index = nodes.firstIndex(where: { $0.id == id }) else { return 0 }
        return index
    }

    /// Whether any node would change a pixel. The compositor asks before it
    /// spends a Core Image pass on a chain of identities.
    var hasGrade: Bool {
        nodes.contains { $0.isEnabled && !$0.isIdentity }
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

// MARK: - Lenient decoding

// Every field but an element's identity reads with `try?` and a default, so a
// value this build cannot read (an effect added later, an aspect removed)
// costs that field, not the clip. Arrays go through `LossyArray`, so a broken
// element costs that element, not the project. Encoding stays synthesized.

extension VideoBoundaryTransition {
    /// Boundaries are positional: one that cannot be read must not be
    /// dropped (every later one would slide a boundary earlier), so a field
    /// that will not read falls back to its default and the element stays.
    init(from decoder: any Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        kind = ((try? container.decodeIfPresent(VideoTransitionKind.self, forKey: .kind)) ?? nil) ?? .none
        duration = ((try? container.decodeIfPresent(Double.self, forKey: .duration)) ?? nil) ?? 0.5
    }
}

extension TimedMarker {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(time: try container.decode(Double.self, forKey: .time))
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        colorIndex = ((try? container.decodeIfPresent(Int.self, forKey: .colorIndex)) ?? nil) ?? 0
        note = ((try? container.decodeIfPresent(String.self, forKey: .note)) ?? nil) ?? ""
    }
}

extension VideoClip {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            assetID: try container.decode(String.self, forKey: .assetID),
            kind: try container.decode(VideoClipKind.self, forKey: .kind),
            id: try container.decode(UUID.self, forKey: .id)
        )
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        photoDuration = value(.photoDuration, VideoClip.defaultPhotoDuration)
        trimStart = value(.trimStart, 0)
        trimEnd = value(.trimEnd, Double?.none)
        volume = value(.volume, 1)
        isMuted = value(.isMuted, false)
        fadeIn = value(.fadeIn, 0)
        fadeOut = value(.fadeOut, 0)
        effect = value(.effect, VideoClipEffect.none)
        speed = value(.speed, 1)
        freezeSourceTime = value(.freezeSourceTime, Double?.none)
        sourceDuration = value(.sourceDuration, Double?.none)
        look = value(.look, VideoLook?.none)
    }
}

extension TimedOverlay {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init(
            overlay: try container.decode(PhotoOverlay.self, forKey: .overlay),
            start: value(.start, 0),
            duration: value(.duration, Double?.none),
            animateIn: value(.animateIn, OverlayAnimation.none),
            animateOut: value(.animateOut, OverlayAnimation.none),
            inDuration: value(.inDuration, 0.4),
            outDuration: value(.outDuration, 0.4)
        )
    }
}

extension MusicTrack {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try container.decode(MusicSource.self, forKey: .source),
            id: try container.decode(UUID.self, forKey: .id)
        )
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        start = value(.start, 0)
        trimStart = value(.trimStart, 0)
        trimEnd = value(.trimEnd, Double?.none)
        sourceDuration = value(.sourceDuration, Double?.none)
        volume = value(.volume, 1)
        isMuted = value(.isMuted, false)
        fadeIn = value(.fadeIn, 2)
        fadeOut = value(.fadeOut, 2)
        beatSnap = value(.beatSnap, MusicBeatSnap())
    }
}

extension VideoProjectRecipe {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        func list<T: Decodable>(_ key: CodingKeys) -> [T] {
            ((try? container.decodeLossyArrayIfPresent(T.self, forKey: key)) ?? nil) ?? []
        }
        self.init(clips: list(.clips))
        transitions = list(.transitions)
        musicTracks = list(.musicTracks)
        videoVolume = value(.videoVolume, 1)
        markers = list(.markers)
        inputTransform = value(.inputTransform, VideoInputTransform.none)
        look = value(.look, VideoLook?.none)
        let decodedNodes: [ColorNode] = list(.nodes)
        nodes = decodedNodes.isEmpty ? [ColorNode()] : decodedNodes
        overlays = list(.overlays)
        quarterTurns = value(.quarterTurns, 0)
        aspect = value(.aspect, VideoAspect.r16x9)
        framing = value(.framing, VideoFraming.fit)
        background = value(.background, VideoBackground())
        resolution = value(.resolution, VideoResolution.p1080)
        frameRate = value(.frameRate, VideoFrameRate.fps30)
        codec = value(.codec, VideoCodec.h264)
        playhead = value(.playhead, Double?.none)
        // A dropped clip leaves one boundary too many; boundaries are
        // positional, so trimming the tail is the honest repair.
        syncTransitionsWithClips()
    }
}
