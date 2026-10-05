import Foundation

/// Where captions sit on the timeline (FS-12.14 §4). A cue is anchored to
/// its clip and to source seconds, so the timeline position is always
/// computed from the clip as it is now: through its placement, its trim and
/// its speed. A cue whose words fall outside the trim is hidden, not
/// deleted — giving the trim back brings it back.
enum CaptionTimeline {
    /// A cue as it plays: timeline seconds of the part inside its clip's trim.
    struct Placed: Equatable, Sendable {
        let cue: CaptionCue
        let start: Double
        let end: Double
        /// The clip's place on the track.
        let clipIndex: Int

        var duration: Double { end - start }
    }

    /// Every visible cue of `lane`, in timeline order.
    static func placed(_ lane: VideoCaptionLane?, in recipe: VideoProjectRecipe) -> [Placed] {
        guard let lane, !lane.cues.isEmpty else { return [] }
        let placements = placements(recipe)
        var indexByClip: [UUID: Int] = [:]
        for (index, clip) in recipe.clips.enumerated() { indexByClip[clip.id] = index }
        return lane.cues.compactMap { cue -> Placed? in
            guard let index = indexByClip[cue.clipID], index < placements.count else { return nil }
            guard let span = timelineSpan(sourceStart: cue.sourceStart, sourceEnd: cue.sourceEnd, clip: recipe.clips[index], placement: placements[index])
            else { return nil }
            return Placed(cue: cue, start: span.start, end: span.end, clipIndex: index)
        }
        .sorted { ($0.start, $0.clipIndex) < ($1.start, $1.clipIndex) }
    }

    /// Source seconds of one clip → timeline seconds, clamped to the trim;
    /// nil when nothing of it is inside.
    static func timelineSpan(
        sourceStart: Double,
        sourceEnd: Double,
        clip: VideoClip,
        placement: VideoTimelineMath.Placement
    ) -> (start: Double, end: Double)? {
        guard clip.kind == .video else { return nil }
        let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
        let windowStart = clip.trimStart
        let windowEnd = clip.trimStart + placement.duration * speed
        let start = max(sourceStart, windowStart)
        let end = min(sourceEnd, windowEnd)
        guard end - start > 0.001 else { return nil }
        return (placement.start + (start - windowStart) / speed, placement.start + (end - windowStart) / speed)
    }

    /// Timeline seconds → the source second of clip `index`, for edits that
    /// start from the playhead (Split) or from a drag on C1.
    static func sourceTime(atTimeline time: Double, clip: VideoClip, placement: VideoTimelineMath.Placement) -> Double {
        let speed = max(clip.speed, VideoClip.speedRange.lowerBound)
        return clip.trimStart + (time - placement.start) * speed
    }

    /// The cue playing at `time`, if any — the later one where two touch.
    static func cue(at time: Double, in placed: [Placed]) -> Placed? {
        placed.last { time >= $0.start && time < $0.end }
    }

    /// "Caption n" for a cue: its place among the visible cues.
    static func name(of cueID: UUID, in placed: [Placed]) -> String? {
        placed.firstIndex { $0.cue.id == cueID }.map(CaptionChunker.name(at:))
    }

    /// The lane after the clips changed (plan K7), so captions stay with
    /// their words:
    /// - a clip **split** into pieces of the same media: each cue goes to
    ///   the piece whose source holds its start;
    /// - a clip **duplicated**: the copy gets a copy of every cue (new ids);
    /// - a clip **deleted**, or **replaced** by other media: its cues go.
    /// Trims, moves and speed changes need nothing — a cue is anchored to
    /// source time, and the timeline is worked out from the clip.
    static func reconciled(_ lane: VideoCaptionLane, from old: [VideoClip], to new: [VideoClip]) -> VideoCaptionLane {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let added = new.filter { oldByID[$0.id] == nil }
        var result = lane
        var cues: [CaptionCue] = []
        for cue in lane.cues {
            if let clip = newByID[cue.clipID] {
                // Replaced in place: other media under the same id.
                if let before = oldByID[cue.clipID], before.assetID != clip.assetID { continue }
                cues.append(cue)
                continue
            }
            guard let before = oldByID[cue.clipID] else {
                // A clip already gone before this change (left out at load):
                // keep the cue, it is hidden until the clip comes back.
                cues.append(cue)
                continue
            }
            // Split: pieces of the same video, inside its window.
            let pieces = added.filter { $0.kind == .video && $0.assetID == before.assetID && before.kind == .video }
            if let piece = pieces.first(where: { cue.sourceStart >= $0.trimStart - 0.000_1 && cue.sourceStart < ($0.trimEnd ?? .infinity) }) {
                var moved = cue
                moved.clipID = piece.id
                cues.append(moved)
            }
            // Otherwise deleted or replaced: the cue goes with its clip.
        }
        // Duplicates: a new clip with the same media and trim as a clip that
        // is still here, and no cues of its own yet.
        for copy in added where copy.kind == .video && !cues.contains(where: { $0.clipID == copy.id }) {
            guard let original = new.first(where: {
                $0.id != copy.id && oldByID[$0.id] != nil && $0.assetID == copy.assetID
                    && $0.trimStart == copy.trimStart && $0.trimEnd == copy.trimEnd && $0.speed == copy.speed
            }) else { continue }
            // A split leaves no original behind, so this is a true copy.
            let copied = cues.filter { $0.clipID == original.id }.map { cue in
                CaptionCue(clipID: copy.id, sourceStart: cue.sourceStart, sourceEnd: cue.sourceEnd, text: cue.text, words: cue.words, isEdited: cue.isEdited)
            }
            cues.append(contentsOf: copied)
        }
        result.cues = cues
        // A clip planned for recognition and gone is no longer waited for.
        result.recognition.plannedClipIDs = lane.recognition.plannedClipIDs.compactMap { id in
            if newByID[id] != nil { return id }
            return nil
        } + added.filter { piece in
            lane.recognition.plannedClipIDs.contains { id in
                newByID[id] == nil && oldByID[id]?.assetID == piece.assetID && oldByID[id]?.kind == .video
            }
        }.map(\.id)
        result.recognition.finishedClipIDs = lane.recognition.finishedClipIDs.filter { newByID[$0] != nil }
            + added.filter { piece in
                lane.recognition.finishedClipIDs.contains { id in
                    newByID[id] == nil && oldByID[id]?.assetID == piece.assetID && oldByID[id]?.kind == .video
                }
            }.map(\.id)
        return result
    }

    /// Which part of a block a drag on C1 holds.
    enum DragEdge: Sendable { case body, start, end }

    /// A cue dragged on C1 by `delta` timeline seconds (§5): the body moves
    /// it, an edge changes its span; it never overlaps the blocks beside it
    /// and never leaves its clip — its words are that clip's sound. The
    /// result is in source time again, the words shifted with a moved body.
    static func dragged(_ cueID: UUID, edge: DragEdge, by delta: Double, in recipe: VideoProjectRecipe) -> CaptionCue? {
        let placed = placed(recipe.captions, in: recipe)
        guard let index = placed.firstIndex(where: { $0.cue.id == cueID }) else { return nil }
        let item = placed[index]
        let placements = placements(recipe)
        let clip = recipe.clips[item.clipIndex]
        let placement = placements[item.clipIndex]
        let floor = max(placement.start, index > 0 ? placed[index - 1].end : -.infinity)
        let ceiling = min(placement.end, index + 1 < placed.count ? placed[index + 1].start : .infinity)
        let shortest = CaptionEditing.shortestCue * 2
        var start = item.start
        var end = item.end
        switch edge {
        case .body:
            let length = end - start
            start = min(max(start + delta, floor), max(floor, ceiling - length))
            end = start + length
        case .start:
            start = min(max(start + delta, floor), end - shortest)
        case .end:
            end = max(min(end + delta, ceiling), start + shortest)
        }
        var cue = item.cue
        let sourceStart = sourceTime(atTimeline: start, clip: clip, placement: placement)
        let sourceEnd = sourceTime(atTimeline: end, clip: clip, placement: placement)
        if edge == .body, let words = cue.words {
            let shift = sourceStart - cue.sourceStart
            cue.words = words.map { CaptionWord(text: $0.text, start: $0.start + shift, end: $0.end + shift) }
        }
        cue.sourceStart = sourceStart
        cue.sourceEnd = sourceEnd
        return cue
    }

    static func placements(_ recipe: VideoProjectRecipe) -> [VideoTimelineMath.Placement] {
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: recipe.transitions.map(\.requestedOverlap), durations: durations)
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }
}
