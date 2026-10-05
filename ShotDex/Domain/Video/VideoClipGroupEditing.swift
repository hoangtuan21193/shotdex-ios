import Foundation

/// What a multi-select group of clips is and what its commands do to the
/// project (FS-12.11) — pure functions on `VideoProjectRecipe`, so every
/// rule is tested without a model, a player or a view.
enum VideoClipGroupEditing {
    /// What the pill, the footer and the play row say about a group.
    struct Summary: Equatable, Sendable {
        var count: Int
        /// The group's clips laid end to end, as the timeline shows them.
        var seconds: Double
        var videos: Int
        /// Stills: photos and held frames.
        var photos: Int

        var hasVideo: Bool { videos > 0 }
    }

    /// `ids` in the order their clips stand on the timeline, without any id
    /// the project no longer has.
    static func ordered(_ ids: [UUID], in recipe: VideoProjectRecipe) -> [UUID] {
        let wanted = Set(ids)
        return recipe.clips.map(\.id).filter { wanted.contains($0) }
    }

    /// Every clip from `anchor` to `target`, both ends in, in timeline
    /// order — what Shift-click adds to a group (FS-12.11 §4).
    static func range(from anchor: UUID, to target: UUID, in recipe: VideoProjectRecipe) -> [UUID] {
        let ids = recipe.clips.map(\.id)
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: target) else { return [] }
        return Array(ids[min(a, b)...max(a, b)])
    }

    // MARK: Transitions follow their two clips (FS-12.11 §6)

    private struct Pair: Hashable {
        let left: UUID
        let right: UUID
    }

    /// The boundaries of `clips` given the transitions `old` had: a
    /// boundary between two clips that were already neighbours keeps its
    /// transition; every boundary that is new is a straight cut. A
    /// crossfade chosen for two shots means nothing between two others.
    static func remapTransitions(from old: VideoProjectRecipe, to clips: [VideoClip]) -> [VideoBoundaryTransition] {
        var byPair: [Pair: VideoBoundaryTransition] = [:]
        for index in old.clips.indices.dropLast() where old.transitions.indices.contains(index) {
            byPair[Pair(left: old.clips[index].id, right: old.clips[index + 1].id)] = old.transitions[index]
        }
        return clips.indices.dropLast().map { index in
            byPair[Pair(left: clips[index].id, right: clips[index + 1].id)] ?? VideoBoundaryTransition()
        }
    }

    // MARK: Duplicate (FS-12.11 §5)

    /// Copies of the group, in their timeline order, right after the
    /// group's last clip; each copy has its own id and everything else of
    /// its original. Returns the copies' ids, in order — the new group.
    @discardableResult
    static func duplicate(
        _ ids: [UUID],
        in recipe: inout VideoProjectRecipe,
        makeID: () -> UUID = UUID.init
    ) -> [(original: UUID, copy: UUID)] {
        let group = ordered(ids, in: recipe)
        guard let last = recipe.clips.lastIndex(where: { group.contains($0.id) }) else { return [] }
        let old = recipe
        let copies = group.compactMap { id in recipe.clips.first { $0.id == id } }.map { ($0.id, $0.duplicated(id: makeID())) }
        recipe.clips.insert(contentsOf: copies.map(\.1), at: last + 1)
        recipe.transitions = remapTransitions(from: old, to: recipe.clips)
        return copies.map { (original: $0.0, copy: $0.1.id) }
    }

    // MARK: Speed (FS-12.11 §5)

    /// The speed every video in the group shares, or nil when they differ
    /// ("Mixed") or the group has no video.
    static func commonSpeed(of ids: [UUID], in recipe: VideoProjectRecipe) -> Double? {
        let speeds = Set(videos(ids, in: recipe).map(\.speed))
        return speeds.count == 1 ? speeds.first : nil
    }

    /// Every video in the group to one speed; stills keep their length.
    static func setSpeed(_ speed: Double, for ids: [UUID], in recipe: inout VideoProjectRecipe) {
        let value = min(max(speed, VideoClip.speedRange.lowerBound), VideoClip.speedRange.upperBound)
        let wanted = Set(ids)
        for index in recipe.clips.indices where wanted.contains(recipe.clips[index].id) && recipe.clips[index].kind == .video {
            recipe.clips[index].speed = value
        }
    }

    /// The stills of the group that Speed leaves alone, for the line under
    /// it: their count and, for one, its length.
    static func stillsSpeedLeaves(_ ids: [UUID], in recipe: VideoProjectRecipe) -> [VideoClip] {
        let wanted = Set(ids)
        return recipe.clips.filter { wanted.contains($0.id) && $0.kind != .video }
    }

    // MARK: Volume (FS-12.11 §5) — only the clips with sound: videos

    /// The speaker reads muted only when every video in the group is; a
    /// mix of muted and not draws it on, and a tap then mutes them all.
    static func isMuted(_ ids: [UUID], in recipe: VideoProjectRecipe) -> Bool {
        let sound = videos(ids, in: recipe)
        return !sound.isEmpty && sound.allSatisfy(\.isMuted)
    }

    /// The level the slider shows: the first video's.
    static func volume(_ ids: [UUID], in recipe: VideoProjectRecipe) -> Double {
        videos(ids, in: recipe).first?.volume ?? 1
    }

    static func setMuted(_ muted: Bool, for ids: [UUID], in recipe: inout VideoProjectRecipe) {
        let wanted = Set(ids)
        for index in recipe.clips.indices where wanted.contains(recipe.clips[index].id) && recipe.clips[index].kind == .video {
            recipe.clips[index].isMuted = muted
        }
    }

    static func setVolume(_ volume: Double, for ids: [UUID], in recipe: inout VideoProjectRecipe) {
        let value = min(max(volume, 0), 1)
        let wanted = Set(ids)
        for index in recipe.clips.indices where wanted.contains(recipe.clips[index].id) && recipe.clips[index].kind == .video {
            recipe.clips[index].volume = value
        }
    }

    // MARK: Fade (FS-12.11 §5)

    /// One fade for every clip, each held to half its own length.
    static func setFade(_ seconds: Double, atStart: Bool, for ids: [UUID], in recipe: inout VideoProjectRecipe) {
        let wanted = Set(ids)
        for index in recipe.clips.indices where wanted.contains(recipe.clips[index].id) {
            let value = min(max(0, seconds), recipe.clips[index].maximumFade())
            if atStart { recipe.clips[index].fadeIn = value } else { recipe.clips[index].fadeOut = value }
        }
    }

    /// The fade the group shares, or nil when the clips differ.
    static func commonFade(_ ids: [UUID], atStart: Bool, in recipe: VideoProjectRecipe) -> Double? {
        let wanted = Set(ids)
        let values = Set(recipe.clips.filter { wanted.contains($0.id) }.map { atStart ? $0.fadeIn : $0.fadeOut })
        return values.count == 1 ? values.first : nil
    }

    /// The longest fade any clip of the group can take — the slider's top.
    static func maximumFade(_ ids: [UUID], in recipe: VideoProjectRecipe) -> Double {
        let wanted = Set(ids)
        return recipe.clips.filter { wanted.contains($0.id) }.map { $0.maximumFade() }.max() ?? 0
    }

    // MARK: Motion and Look (FS-12.11 §5)

    static func setEffect(_ effect: VideoClipEffect, for ids: [UUID], in recipe: inout VideoProjectRecipe) {
        let wanted = Set(ids)
        for index in recipe.clips.indices where wanted.contains(recipe.clips[index].id) {
            recipe.clips[index].effect = effect
        }
    }

    /// The motion the group shares, or nil when the clips differ.
    static func commonEffect(_ ids: [UUID], in recipe: VideoProjectRecipe) -> VideoClipEffect? {
        let wanted = Set(ids)
        let effects = Set(recipe.clips.filter { wanted.contains($0.id) }.map(\.effect))
        return effects.count == 1 ? effects.first : nil
    }

    /// Whether every clip of the group has the same look of its own — or
    /// none, following the whole video's.
    static func sharesLook(_ ids: [UUID], in recipe: VideoProjectRecipe) -> Bool {
        let wanted = Set(ids)
        let looks = recipe.clips.filter { wanted.contains($0.id) }.map(\.look)
        guard let first = looks.first else { return true }
        return looks.allSatisfy { $0 == first }
    }

    private static func videos(_ ids: [UUID], in recipe: VideoProjectRecipe) -> [VideoClip] {
        let wanted = Set(ids)
        return recipe.clips.filter { wanted.contains($0.id) && $0.kind == .video }
    }

    static func summary(of ids: [UUID], in recipe: VideoProjectRecipe) -> Summary {
        let wanted = Set(ids)
        let clips = recipe.clips.filter { wanted.contains($0.id) }
        return Summary(
            count: clips.count,
            seconds: clips.reduce(0) { $0 + $1.effectiveDuration },
            videos: clips.filter { $0.kind == .video }.count,
            photos: clips.filter { $0.kind != .video }.count
        )
    }
}
