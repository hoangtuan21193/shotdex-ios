import Foundation

/// Snapshot history keeps the editor's full recipe coherent across sliders,
/// crop gestures and multi-part masks. Coalescing is handled by the controller:
/// it records once at the beginning of a continuous gesture, then mutates the
/// current recipe as the gesture moves.
struct PhotoEditHistory: Sendable {
    private(set) var undoStack: [PhotoEditRecipe] = []
    private(set) var redoStack: [PhotoEditRecipe] = []
    private let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func record(_ recipe: PhotoEditRecipe) {
        guard undoStack.last != recipe else { return }
        undoStack.append(recipe)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    /// Drops the entry a gesture opened once that gesture turns out to have
    /// changed nothing — a brush stroke cancelled because a second finger landed
    /// and the touch was a pinch. Pass the recipe as it stands after the rollback:
    /// it only pops when the two match, so a real edit can never be swallowed.
    mutating func discardLast(matching recipe: PhotoEditRecipe) {
        guard undoStack.last == recipe else { return }
        undoStack.removeLast()
    }

    /// How many steps back the stack currently reaches. A modal session (Crop)
    /// remembers this on entry so it can drop its own entries if it is cancelled.
    var undoDepth: Int { undoStack.count }

    /// Rolls the stack back to the depth of `toUndoDepth`, for a session the user
    /// left without committing: the states recorded while it was open describe
    /// framing that has just been thrown away. Redo goes with them — `record` had
    /// already cleared it on the session's first edit.
    mutating func rewind(toUndoDepth depth: Int) {
        guard depth >= 0, depth < undoStack.count else { return }
        undoStack.removeLast(undoStack.count - depth)
        redoStack.removeAll(keepingCapacity: true)
    }

    mutating func undo(current: PhotoEditRecipe) -> PhotoEditRecipe? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: PhotoEditRecipe) -> PhotoEditRecipe? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    mutating func clear() {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
    }

    /// Every recorded state oldest-first, with `current` sitting at
    /// `currentIndex`. The History sheet renders this and labels each entry by
    /// diffing it against its predecessor, so no label has to be captured while
    /// a gesture is running.
    func timeline(current: PhotoEditRecipe) -> [PhotoEditRecipe] {
        undoStack + [current] + redoStack.reversed()
    }

    var currentIndex: Int { undoStack.count }

    /// Jumps straight to a step. Returns the recipe to install, or nil when the
    /// index is out of range or already current.
    mutating func jump(to index: Int, current: PhotoEditRecipe) -> PhotoEditRecipe? {
        let steps = timeline(current: current)
        guard steps.indices.contains(index), index != currentIndex else { return nil }
        undoStack = Array(steps[..<index])
        redoStack = Array(steps[(index + 1)...].reversed())
        return steps[index]
    }
}
