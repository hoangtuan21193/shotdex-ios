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

    /// Go to Start: In when there is one (FS-12.17b §5).
    func goToStart() {
        seek(to: recipe.inOutRange.goToStartTarget)
    }

    /// Go to End: Out when there is one.
    func goToEnd() {
        seek(to: recipe.inOutRange.goToEndTarget(totalDuration: totalDuration))
    }

    func clearInOut() {
        guard !recipe.inOutRange.isEmpty else { return }
        recipe.inOutRange = VideoInOutRange()
        syncLoopBoundary()
    }
}
