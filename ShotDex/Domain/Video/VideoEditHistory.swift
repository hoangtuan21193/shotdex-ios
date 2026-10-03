import Foundation

/// The Video Studio's undo and redo (FS-12.04 §5): whole-recipe snapshots,
/// each numbered when it is first pushed, so a selection session can say
/// "everything from step N on is mine" and take exactly that back — however
/// far the 40-step cap has trimmed the oldest end, and however many times
/// the user has undone and redone in between.
///
/// A value type in Domain: it knows nothing of the model, the player or the
/// views, and every rule here is tested on its own.
struct VideoEditHistory: Sendable {
    struct Entry: Equatable, Sendable {
        /// When the step was first made. Survives undo and redo, so a step
        /// that went to the redo stack and came back is still the same step.
        let sequence: Int
        /// The project **before** the step (on the undo stack) or **after**
        /// it (on the redo stack).
        let snapshot: VideoProjectRecipe
    }

    /// Steps kept; the oldest go first.
    static let depth = 40

    private(set) var undoEntries: [Entry] = []
    private(set) var redoEntries: [Entry] = []
    private var nextSequence = 1
    /// One gesture — a slider drag, a pinch — is one step: only the first
    /// push of a group lands.
    private(set) var isGrouping = false

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }

    /// The number the next step will carry. A session takes it when it
    /// starts: every step at or after it belongs to the session.
    var checkpoint: Int { nextSequence }

    /// The newest undoable step's number, if any.
    var newestSequence: Int? { undoEntries.last?.sequence }

    /// Records the project as it was before a discrete edit. Starts a new
    /// branch: whatever could be redone is gone.
    mutating func push(_ before: VideoProjectRecipe) {
        guard !isGrouping else { return }
        undoEntries.append(Entry(sequence: nextSequence, snapshot: before))
        nextSequence += 1
        if undoEntries.count > Self.depth {
            undoEntries.removeFirst(undoEntries.count - Self.depth)
        }
        redoEntries.removeAll()
    }

    mutating func beginGroup(_ before: VideoProjectRecipe) {
        guard !isGrouping else { return }
        push(before)
        isGrouping = true
    }

    mutating func endGroup() {
        isGrouping = false
    }

    /// Steps back from `current`; returns the project to restore.
    mutating func undo(from current: VideoProjectRecipe) -> VideoProjectRecipe? {
        isGrouping = false
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(Entry(sequence: entry.sequence, snapshot: current))
        return entry.snapshot
    }

    /// Steps forward from `current`; returns the project to restore.
    mutating func redo(from current: VideoProjectRecipe) -> VideoProjectRecipe? {
        isGrouping = false
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(Entry(sequence: entry.sequence, snapshot: current))
        return entry.snapshot
    }

    /// Takes the step numbered `sequence` back out of the history — only
    /// when it is still the newest undoable step — and returns the project
    /// as it was before it, for the caller to restore. An add whose media
    /// never arrived is not a step to undo (FS-12.09 §5).
    mutating func takeBack(_ sequence: Int) -> VideoProjectRecipe? {
        guard let newest = undoEntries.last, newest.sequence == sequence else { return nil }
        undoEntries.removeLast()
        return newest.snapshot
    }

    /// ✕: forgets every step made since `checkpoint` — undoable or undone —
    /// so neither Undo nor Redo can bring any of them back. Steps from before
    /// the checkpoint stay exactly as they were.
    mutating func rollback(to checkpoint: Int) {
        isGrouping = false
        undoEntries.removeAll { $0.sequence >= checkpoint }
        redoEntries.removeAll()
    }
}
