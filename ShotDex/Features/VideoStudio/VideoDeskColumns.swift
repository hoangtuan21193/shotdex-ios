import Foundation

/// The wide layouts' side columns as session state (FS-12.03 §5): whether
/// the pool and the inspector are open, and the Quick Adjust strip. Plain
/// values, so the rules are tested without a view.
///
/// It belongs to the screen, not to a layout: a window changing class —
/// rotating, a Stage Manager resize, the Duo folding — keeps it as it was.
struct VideoDeskColumns: Equatable {
    /// Nil until the user opens or shuts the pool: it then follows the
    /// window's default (open from 1100pt wide).
    var isPoolOpen: Bool?
    var isInspectorOpen = true
    /// Off until asked for: on a short window it is 44pt off the frame.
    var isQuickAdjustOpen = false

    /// Something was selected, or a tool opened: the inspector opens if it
    /// was shut, because its foot carries ✕ · ✓ — hidden, the session
    /// would have no way to end.
    mutating func selectionDidBegin() {
        isInspectorOpen = true
    }

    /// Ending the session leaves the column as it is: the user shut it once
    /// and may want it back for the next item; reopening is theirs.
    mutating func selectionDidEnd() {}

    /// The selection changed from `old` to `new` presenting state.
    mutating func presentsSheetChanged(from old: Bool, to new: Bool) {
        if new, !old { selectionDidBegin() }
        if old, !new { selectionDidEnd() }
    }
}
