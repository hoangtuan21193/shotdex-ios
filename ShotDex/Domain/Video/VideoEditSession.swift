import Foundation

/// One selection session (FS-12.04 §5): it opens when an item is selected —
/// or a tool panel opened — and ends at ✓ (keep every step) or ✕ (put the
/// project back as it was when the session began and forget its steps).
///
/// The session keeps its own copy of the project at the start rather than
/// replaying undo: the 40-step cap can trim the steps away, the snapshot
/// cannot be trimmed.
struct VideoEditSession: Equatable, Sendable {
    enum Target: Equatable, Hashable, Sendable {
        case clip(UUID)
        case overlay(UUID)
        case music(UUID)
        /// A multi-select group of clips (FS-12.11): ✕ puts back the
        /// project as it was when the group was entered, every step of it.
        case clipGroup
        /// A tool's panel — Look, Music, Media, Video Settings — by name.
        case tool(String)

        /// A clip, caption, sticker or music bed — something on the timeline.
        var isItem: Bool {
            if case .tool = self { return false }
            return true
        }
    }

    let target: Target
    /// The project when the session began: what ✕ restores.
    let startRecipe: VideoProjectRecipe
    /// `VideoEditHistory.checkpoint` when the session began: every step from
    /// it on belongs to the session.
    let checkpoint: Int
    /// The panel pulled down to its 78pt strip (FS-12.07 §3). Session state:
    /// a new session opens the panel full again.
    var isCollapsed = false

    /// Whether any step was made since the session began.
    func hasSteps(in history: VideoEditHistory) -> Bool {
        guard let newest = history.newestSequence else { return false }
        return newest >= checkpoint
    }
}
