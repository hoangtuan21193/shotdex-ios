import Foundation
import Testing
@testable import ShotDex

/// "hold to move freely" (FS-12.12 §5): a finger that stops half a second
/// in the middle of a drag lets go of the beats until it lifts.
struct BeatSliderLogicTests {

    /// AC-6: a drag that pauses 0.5 s and moves on is free from then on —
    /// so dragged to 3.25 s it stays 3.25 s, no snap, no haptic.
    @Test func holdHalfSecondReleasesSnap() {
        var hold = BeatSliderHold()
        let r1 = hold.update(x: 100, at: 0)
        #expect(!r1)
        let r2 = hold.update(x: 110, at: 0.1)
        #expect(!r2)
        // Still for 0.6 s — under 2pt of jitter.
        let r3 = hold.update(x: 111, at: 0.4)
        #expect(!r3)
        let r4 = hold.update(x: 110.5, at: 0.7)
        #expect(!r4)
        // Moves again: the pause counted.
        let r5 = hold.update(x: 116, at: 0.72)
        #expect(r5)
        let r6 = hold.update(x: 140, at: 0.8)
        #expect(r6)

        let grid = BeatGridTests.grid
        let proposed = 3.25
        let duration = hold.isFree
            ? proposed
            : grid.snappedDuration(proposed, clipStart: 14.2, division: .beat, tolerance: 0.2, range: VideoClip.photoDurationRange).duration
        #expect(duration == 3.25)
    }

    /// A drag that never stops never lets go; neither does a pause under
    /// half a second.
    @Test func aSteadyDragKeepsSnapping() {
        var hold = BeatSliderHold()
        for step in 0..<40 {
            let free = hold.update(x: Double(step) * 3, at: Double(step) * 0.05)
            #expect(!free)
        }
        var short = BeatSliderHold()
        _ = short.update(x: 0, at: 0)
        let r7 = short.update(x: 5, at: 0.45)
        #expect(!r7)
    }
}
