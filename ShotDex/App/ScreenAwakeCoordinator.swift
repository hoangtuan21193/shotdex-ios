import SwiftUI
import UIKit

/// Keeps the display awake while indexing runs (when the setting is on) and
/// while a save the user is watching holds it.
///
/// It never touches the screen brightness. An earlier version lowered it after
/// a minute with no touch, but "no touch" is not "not in use": typing, a share
/// sheet (another process), a playing video or a slideshow all read as idle,
/// so the screen went dark under someone who was looking at it. The user who
/// turned the setting on asked for an awake screen at the brightness they chose.
@MainActor
@Observable
final class ScreenAwakeCoordinator {
    /// One coordinator, because there is one screen.
    ///
    /// The indexing view owns the setting side of it and a save holds it
    /// awake from somewhere else entirely; two instances would each write
    /// `isIdleTimerDisabled` and the last one to speak would win, which is how
    /// a screen locks in the middle of a save.
    static let shared = ScreenAwakeCoordinator()

    private var isEnabled = false
    private var isIndexing = false
    /// How many pieces of work are holding the screen awake regardless of the
    /// setting.
    ///
    /// The setting is about *indexing*, which runs on its own and can be
    /// turned off by someone who would rather have the battery. A save the
    /// user started and is watching is a different thing: the screen going
    /// dark mid-way looks like the app stopped, and the auto-lock that
    /// follows suspends the work (FS-14.01 §6). A count rather than a flag,
    /// because two of them can overlap.
    private var holds = 0

    private var isActive: Bool { (isEnabled && isIndexing) || holds > 0 }

    /// Holds the screen awake until the matching `endHold`, whatever the
    /// setting says.
    func beginHold() {
        holds += 1
        apply()
    }

    func endHold() {
        holds = max(0, holds - 1)
        apply()
    }

    /// Recompute active state from the setting toggle and the indexing flag.
    func update(enabled: Bool, indexing: Bool) {
        isEnabled = enabled
        isIndexing = indexing
        apply()
    }

    /// App left the foreground. A hold outlives a trip to the background: the
    /// save is still running and the user is coming back to it.
    func handleBackground() {
        UIApplication.shared.isIdleTimerDisabled = holds > 0
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = isActive
    }
}
