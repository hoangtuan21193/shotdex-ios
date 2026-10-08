import Foundation

/// The frame trim (FS-12.17 §3–5): a session nested inside a clip's
/// selection that moves one edge of the clip a frame of the project at a
/// time. The recipe does not change until ✓ — the session keeps the clip as
/// it was when the trim began, how many frames each edge has moved, and
/// answers everything the chrome shows: where the edge is now, how the
/// clip would end up, whether another step fits, and which source frames
/// the loupe and the viewer draw.
///
/// The edge is **virtual**: on a lane with no gaps the clip after it only
/// closes up at ✓, so until then the edge's time is where it started plus
/// the frames it moved — for the leading edge too (plan decision 2).
struct FrameTrimSession: Equatable, Sendable {
    let clipID: UUID
    /// The clip when the trim began: ✕ goes back to it, every step is
    /// measured from it.
    let clip: VideoClip
    /// Where the clip sat on the timeline when the trim began.
    let placement: VideoTimelineMath.Placement
    let grid: VideoFrameGrid
    /// The edge the steps move. Tapping the other handle switches it; each
    /// edge keeps the frames it already moved.
    private(set) var edge: VideoEdgeTrimMath.Edge
    private(set) var leadingFrames = 0
    private(set) var trailingFrames = 0

    init(
        clipID: UUID,
        clip: VideoClip,
        placement: VideoTimelineMath.Placement,
        grid: VideoFrameGrid,
        edge: VideoEdgeTrimMath.Edge
    ) {
        self.clipID = clipID
        self.clip = clip
        self.placement = placement
        self.grid = grid
        self.edge = edge
    }

    /// Frames the active edge moved since the trim began — "−4 frames":
    /// negative is earlier.
    var frames: Int { frames(of: edge) }

    func frames(of edge: VideoEdgeTrimMath.Edge) -> Int {
        edge == .leading ? leadingFrames : trailingFrames
    }

    /// Where `edge` sat on the timeline when the trim began.
    func originTime(of edge: VideoEdgeTrimMath.Edge) -> Double {
        edge == .leading ? placement.start : placement.end
    }

    /// Where `edge` is now: its origin walked `frames` along the project's
    /// grid (from an origin between two lines the first step lands on the
    /// next line).
    func edgeTime(of edge: VideoEdgeTrimMath.Edge) -> Double {
        grid.step(from: originTime(of: edge), by: frames(of: edge))
    }

    /// The active edge's time — the read-out "0:09.07", where the playhead
    /// stands.
    var edgeTime: Double { edgeTime(of: edge) }

    /// The clip as the trim would leave it, both edges applied.
    var trimmedClip: VideoClip { trimmedClip(leading: leadingFrames, trailing: trailingFrames).clip }

    /// Whether ✓ would change the recipe.
    var changesClip: Bool { trimmedClip != clip }

    /// The active edge stepped by `count` frames would still be inside the
    /// clip's limits — the source's ends, a clip's 0.1 s, a still's
    /// 0.5–10 s. A button whose step does not fit is dimmed (§5).
    func canStep(by count: Int) -> Bool {
        guard count != 0 else { return true }
        let next = frames + count
        let leading = edge == .leading ? next : leadingFrames
        let trailing = edge == .trailing ? next : trailingFrames
        return !trimmedClip(leading: leading, trailing: trailing).hitLimit
    }

    /// One step of `count` frames, when it fits. Returns whether it moved.
    @discardableResult
    mutating func step(by count: Int) -> Bool {
        guard count != 0, canStep(by: count) else { return false }
        set(frames + count)
        return true
    }

    /// A drag on the held edge (§5): the edge goes to `target` frames from
    /// where the trim began, or as far toward it as the limits let it.
    /// Returns how many frame lines it crossed — one haptic each — and
    /// whether it stopped on a limit short of the finger.
    @discardableResult
    mutating func move(toFrames target: Int) -> (crossed: Int, hitLimit: Bool) {
        var crossed = 0
        let direction = target > frames ? 1 : -1
        while frames != target {
            guard step(by: direction) else { return (crossed, true) }
            crossed += 1
        }
        return (crossed, false)
    }

    mutating func switchEdge(to edge: VideoEdgeTrimMath.Edge) {
        self.edge = edge
    }

    /// The recipe with the trimmed clip in place — what ✓ writes as one
    /// undo step.
    func applied(to recipe: VideoProjectRecipe) -> VideoProjectRecipe {
        var recipe = recipe
        guard let index = recipe.clips.firstIndex(where: { $0.id == clipID }) else { return recipe }
        recipe.clips[index] = trimmedClip
        return recipe
    }

    // MARK: Frames to draw

    /// One project frame of the timeline, in source seconds: a 2× clip's
    /// window moves 2/fps of its source per frame (§5).
    var sourceStep: Double {
        grid.frameDuration * max(clip.speed, VideoClip.speedRange.lowerBound)
    }

    /// Where the cut falls in the source for the active edge: the trimmed
    /// clip's in-point for the leading edge, its out-point for the
    /// trailing one. Nil for a still — every frame of it is the same.
    var cutSourceTime: Double? {
        guard clip.kind == .video else { return nil }
        let trimmed = trimmedClip
        return edge == .leading
            ? trimmed.trimStart
            : (trimmed.trimEnd ?? trimmed.sourceDuration ?? trimmed.trimStart)
    }

    /// The frame the viewer shows: the clip's **first** frame for the
    /// leading edge, its **last** for the trailing one (§4).
    var viewerSourceTime: Double? {
        guard let cut = cutSourceTime else { return nil }
        let time = edge == .leading ? cut : cut - sourceStep
        return clampedSourceTime(time)
    }

    /// The loupe's ten frames, five each side of the cut (§5): the five
    /// before it, then the five from it on. Nil where the source has no
    /// frame — before its start, past its end. Empty for a still.
    var loupeSourceTimes: [Double?] {
        guard let cut = cutSourceTime else { return [] }
        return (-5..<5).map { offset in
            let time = cut + Double(offset) * sourceStep
            return clampedSourceTime(time, allowsOutside: false)
        }
    }

    private func clampedSourceTime(_ time: Double, allowsOutside: Bool = true) -> Double? {
        let end = clip.sourceDuration ?? clip.trimEnd ?? time
        let last = max(0, end - sourceStep / 2)
        if time < -0.000_1 || time > end - 0.000_1 {
            return allowsOutside ? min(max(time, 0), last) : nil
        }
        return min(max(time, 0), last)
    }

    // MARK: Private

    private mutating func set(_ frames: Int) {
        if edge == .leading { leadingFrames = frames } else { trailingFrames = frames }
    }

    /// Applies both edges to the clip as it was at entry, each through the
    /// same arithmetic as a drag of the handle (FS-12.05), so both ways of
    /// cutting meet the same limits.
    private func trimmedClip(leading: Int, trailing: Int) -> (clip: VideoClip, hitLimit: Bool) {
        var result = clip
        var hitLimit = false
        let leadingDelta = grid.step(from: originTime(of: .leading), by: leading) - originTime(of: .leading)
        if leading != 0 {
            let drag = VideoEdgeTrimMath.drag(result, edge: .leading, by: leadingDelta)
            hitLimit = hitLimit || drag.hitLimit
            apply(drag, to: &result)
        }
        let trailingDelta = grid.step(from: originTime(of: .trailing), by: trailing) - originTime(of: .trailing)
        if trailing != 0 {
            // Each edge moves its own end of the window: on a gapless lane
            // the clip keeps its start, and its length changes by what both
            // edges moved.
            let drag = VideoEdgeTrimMath.drag(result, edge: .trailing, by: trailingDelta)
            hitLimit = hitLimit || drag.hitLimit
            apply(drag, to: &result)
        }
        return (result, hitLimit)
    }

    private func apply(_ drag: VideoEdgeTrimMath.Result, to clip: inout VideoClip) {
        clip.trimStart = drag.trimStart
        clip.trimEnd = drag.trimEnd
        clip.photoDuration = drag.photoDuration
    }
}
