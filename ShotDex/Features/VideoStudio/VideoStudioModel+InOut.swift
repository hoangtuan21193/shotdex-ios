import Foundation

/// The In–Out range (FS-12.17b §5): I, O and ⌥X. Where the user is
/// watching, like the playhead — not an undo step, saved with the draft
/// like every other field of the project, never read by the export.
extension VideoStudioModel {
    func markIn() {
        recipe.inOutRange = recipe.inOutRange.markingIn(at: currentTime, totalDuration: totalDuration)
        syncLoopBoundary()
    }

    func markOut() {
        recipe.inOutRange = recipe.inOutRange.markingOut(at: currentTime, totalDuration: totalDuration)
        syncLoopBoundary()
    }

    func clearInOut() {
        guard !recipe.inOutRange.isEmpty else { return }
        recipe.inOutRange = VideoInOutRange()
        syncLoopBoundary()
    }
}
