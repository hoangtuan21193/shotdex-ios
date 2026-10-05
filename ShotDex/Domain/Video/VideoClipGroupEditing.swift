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
