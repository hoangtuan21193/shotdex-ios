import Foundation

/// Where media from the Media panel lands on the video track (FS-12.09 §5).
///
/// A tap inserts **at the playhead**: inside a clip, that clip is cut there
/// and the new media goes into the cut; on a clip's edge, or past the end,
/// nothing is cut. Several items go in together in the order given, and the
/// playhead moves to the end of the last one — so three taps in a row are
/// three clips in the order they were tapped.
///
/// Boundaries are positional (`transitions[i]` sits between clips `i` and
/// `i + 1`), so every new boundary — the cut, and each side of the new
/// clips — is inserted where it belongs as a plain cut, instead of padding
/// the end and sliding every later transition onto the wrong pair.
enum MediaInsertMath {
    struct Result: Equatable {
        var recipe: VideoProjectRecipe
        /// Index of the first new clip.
        var firstIndex: Int
        /// The clip the playhead cut, and the two halves it became.
        var split: Split?
        /// Where the playhead goes: the end of the last new clip.
        var playhead: Double
    }

    struct Split: Equatable {
        let original: UUID
        let first: UUID
        let second: UUID
    }

    /// `newClips` into `recipe` at timeline second `time`.
    static func insert(_ newClips: [VideoClip], into recipe: VideoProjectRecipe, at time: Double) -> Result {
        var recipe = recipe
        recipe.syncTransitionsWithClips()
        var index = recipe.clips.count
        var split: Split?
        let placements = placements(of: recipe)
        if let hit = VideoTimelineMath.clipIndex(at: time, placements: placements), hit < placements.count {
            let localTime = time - placements[hit].start
            if let (first, second) = VideoSplitMath.split(recipe.clips[hit], atLocalTime: localTime) {
                split = Split(original: recipe.clips[hit].id, first: first.id, second: second.id)
                recipe.clips.replaceSubrange(hit...hit, with: [first, second])
                recipe.transitions.insert(VideoBoundaryTransition(), at: hit)
                index = hit + 1
            } else {
                // On the clip's own edge: the seam is already where the
                // user is pointing.
                index = localTime <= 0 ? hit : hit + 1
            }
        }
        return insert(newClips, into: recipe, atIndex: index, split: split)
    }

    /// `newClips` into `recipe` before clip `index` — a boundary, never a
    /// cut. What a drop on the timeline does (§5: "thả … không tách clip").
    static func insert(_ newClips: [VideoClip], into recipe: VideoProjectRecipe, atIndex index: Int) -> Result {
        var recipe = recipe
        recipe.syncTransitionsWithClips()
        return insert(newClips, into: recipe, atIndex: index, split: nil)
    }

    private static func insert(
        _ newClips: [VideoClip],
        into recipe: VideoProjectRecipe,
        atIndex index: Int,
        split: Split?
    ) -> Result {
        var recipe = recipe
        let at = min(max(0, index), recipe.clips.count)
        let hadClips = !recipe.clips.isEmpty
        recipe.clips.insert(contentsOf: newClips, at: at)
        if hadClips, !newClips.isEmpty {
            // One new boundary per new clip, as plain cuts, at the place the
            // new clips open: the boundary before them keeps whatever it was.
            let boundary = min(at, recipe.transitions.count)
            recipe.transitions.insert(
                contentsOf: Array(repeating: VideoBoundaryTransition(), count: newClips.count),
                at: boundary
            )
        }
        recipe.syncTransitionsWithClips()
        let after = placements(of: recipe)
        let last = at + newClips.count - 1
        let playhead = newClips.isEmpty || !after.indices.contains(last) ? 0 : after[last].end
        return Result(recipe: recipe, firstIndex: at, split: split, playhead: playhead)
    }

    static func placements(of recipe: VideoProjectRecipe) -> [VideoTimelineMath.Placement] {
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(
            requested: recipe.transitions.map(\.requestedOverlap),
            durations: durations
        )
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }

    // MARK: Drop (FS-12.09 §5)

    /// A seam between clips: before clip `index`, or after the last when
    /// `index` is the clip count.
    struct Boundary: Equatable {
        let index: Int
        let time: Double
    }

    static func boundaries(_ placements: [VideoTimelineMath.Placement]) -> [Boundary] {
        guard let last = placements.last else { return [Boundary(index: 0, time: 0)] }
        return placements.enumerated().map { Boundary(index: $0.offset, time: $0.element.start) }
            + [Boundary(index: placements.count, time: last.end)]
    }

    /// The seam nearest a timeline second — where a dragged item would land.
    static func nearestBoundary(to time: Double, placements: [VideoTimelineMath.Placement]) -> Boundary {
        boundaries(placements).min { abs($0.time - time) < abs($1.time - time) } ?? Boundary(index: 0, time: 0)
    }

    /// How fast the timeline runs under a finger held `depth` points inside
    /// its 40pt edge, in points per second: nothing at the line, faster the
    /// deeper — squared, so the first few points nudge and the edge flies.
    static func autoscrollSpeed(depth: Double, edge: Double = 40, maximum: Double = 900) -> Double {
        guard depth > 0, edge > 0 else { return 0 }
        let fraction = min(depth, edge) / edge
        return maximum * fraction * fraction
    }
}
