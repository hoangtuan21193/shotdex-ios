import Foundation

/// Cut to Beat (FS-12.12 §6): every cut between two clips moved to the
/// nearest bar — every bar, every 2nd or every 4th — of the snapping bed's
/// grid. A still before a cut stretches or shrinks; a video moves the end
/// of its trim. A cut whose clip cannot reach its bar — the video has no
/// more picture, the still would drop under 0.5s — keeps its clip as it is
/// and is counted as "can't move". A cut with no bar of the grid near it
/// (outside the bed's window) is left alone and not counted (D-9).
enum CutToBeatMath {
    /// How many bars apart the targets are: Every Bar · 2 Bars · 4 Bars.
    enum Spacing: Int, CaseIterable, Sendable {
        case everyBar = 1, twoBars = 2, fourBars = 4
    }

    struct Cut: Equatable, Sendable {
        /// The boundary after `clipIndex`.
        var clipIndex: Int
        /// Where the cut is now, and the bar it aims for.
        var time: Double
        var target: Double?
        /// The cut's clip can reach the target.
        var canMove: Bool
        /// Signed seconds to the target; zero when it does not move.
        var shift: Double { canMove ? (target ?? time) - time : 0 }
        /// Counted as moving: reachable and more than a frame away.
        var moves: Bool { canMove && abs(shift) > CutToBeatMath.frame }
    }

    struct Preview: Equatable, Sendable {
        var cuts: [Cut]
        /// The project with every reachable cut on its bar.
        var applied: VideoProjectRecipe

        var movingCount: Int { cuts.filter(\.moves).count }
        var cannotMoveCount: Int { cuts.filter { $0.target != nil && !$0.canMove }.count }
        /// The largest move, signed — "+0.8s".
        var largestShift: Double {
            cuts.filter(\.moves).map(\.shift).max { abs($0) < abs($1) } ?? 0
        }
        /// How many clips Apply changes — "Apply to 5 Clips".
        var clipCount: Int { applied.clips.count }
    }

    /// One frame at 30 fps: a cut this close to its bar is already on it.
    static let frame: Double = 1.0 / 30

    /// The bars of `grid` that are targets at `spacing`.
    static func targets(_ grid: BeatGrid, spacing: Spacing) -> [Double] {
        grid.ticks.filter(\.isBar).enumerated()
            .filter { $0.offset % spacing.rawValue == 0 }
            .map(\.element.time)
    }

    static func preview(_ recipe: VideoProjectRecipe, grid: BeatGrid, spacing: Spacing) -> Preview {
        let bars = targets(grid, spacing: spacing)
        var edited = recipe
        var cuts: [Cut] = []
        guard recipe.clips.count > 1, !bars.isEmpty else { return Preview(cuts: [], applied: recipe) }
        // Each cut aims at the bar nearest where it is *now*, in the
        // project as it stands; the clips are then fitted cut by cut.
        let original = placements(recipe)
        let window = (bars.first ?? 0)...(bars.last ?? 0)
        let half = (bars.count > 1 ? (bars[1] - bars[0]) : 2.5) / 2
        for index in 0..<(recipe.clips.count - 1) {
            let time = boundary(index, original)
            let nearest = bars.min { abs($0 - time) < abs($1 - time) }
            // Outside the bed's grid there is no bar to go to.
            let target = nearest.flatMap { bar in
                window.contains(time) || abs(bar - time) <= half ? bar : nil
            }
            guard let target else {
                cuts.append(Cut(clipIndex: index, time: time, target: nil, canMove: false))
                continue
            }
            let now = boundary(index, placements(edited))
            let wanted = edited.clips[index].effectiveDuration + (target - now)
            let reached = fit(&edited.clips[index], duration: wanted)
            cuts.append(Cut(clipIndex: index, time: time, target: target, canMove: reached))
        }
        return Preview(cuts: cuts, applied: edited)
    }

    private static func placements(_ recipe: VideoProjectRecipe) -> [VideoTimelineMath.Placement] {
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: recipe.transitions.map(\.requestedOverlap), durations: durations)
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }

    /// Cut `index` (after clip `index`): mid-overlap when a transition
    /// joins the two clips.
    private static func boundary(_ index: Int, _ placements: [VideoTimelineMath.Placement]) -> Double {
        (placements[index].end + placements[index + 1].start) / 2
    }

    /// Gives a clip `duration` on the timeline if it can take it: a still
    /// between 0.5 and 10s, a video as far as its source has picture.
    private static func fit(_ clip: inout VideoClip, duration: Double) -> Bool {
        switch clip.kind {
        case .photo, .freeze:
            guard VideoClip.photoDurationRange.contains(duration) else { return false }
            clip.photoDuration = duration
            return true
        case .video:
            let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
            let end = clip.trimStart + duration * speed
            guard let source = clip.sourceDuration, duration >= VideoClip.minimumClipDuration,
                  end <= source + 1e-6
            else { return false }
            clip.trimEnd = min(end, source)
            return true
        }
    }
}
