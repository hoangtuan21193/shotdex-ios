import Foundation
import ShotDexKit

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

/// The keyboard's shortcut list on the phone and the Duo (FS-12.17b §4).
extension VideoStudioModel {
    /// A key from a hardware keyboard reached the studio: the first one
    /// ever shows the list, once per install. The iPad has the system's
    /// list and never shows one of its own.
    func noteHardwareKey(isIPad: Bool, preferences: VideoInputPreferences? = nil) {
        let preferences = preferences ?? .shared
        guard !isIPad, !preferences.hasShownKeyboardList else { return }
        preferences.hasShownKeyboardList = true
        isShortcutListFromHold = false
        isShortcutListShown = true
    }

    /// ⌘ held for 0.6 s: the list again.
    func commandHoldBegan() {
        guard !isShortcutListShown else { return }
        isShortcutListFromHold = true
        isShortcutListShown = true
    }

    /// ⌘ let go: the inner display's card goes with it when the hold
    /// opened it; the phone's and the cover's list stay until ✕ or Esc —
    /// they cover nothing (§4).
    func commandHoldEnded() {
        guard isShortcutListFromHold, shortcutListIsOverlay else { return }
        closeShortcutList()
    }

    /// ✕, Esc, a tap outside the inner display's card, the keyboard
    /// unplugged.
    func closeShortcutList() {
        isShortcutListShown = false
        isShortcutListFromHold = false
    }
}

/// The Text panel (FS-12.04 §3, FS-12.14 §3): what it adds closes it and
/// opens a session of its own.
extension VideoStudioModel {
    /// Add Text, or a font row: the panel goes — kept, it changed nothing —
    /// and the new block is selected with Edit open, as Text used to do in
    /// one tap. ✕ then takes the block away.
    @discardableResult
    func addTextFromPanel(font: OverlayFontChoice? = nil) -> UUID {
        if activeToolPanel == .text { showToolPanel(nil) }
        if let font { rememberFont(font) }
        return addTextBlock(font: font)
    }

    /// Auto Captions, or Edit Captions once there is a lane: the panel goes
    /// and the caption lane's opens.
    func startAutoCaptionsFromPanel() async {
        if activeToolPanel == .text { showToolPanel(nil) }
        await startAutoCaptions()
    }
}
