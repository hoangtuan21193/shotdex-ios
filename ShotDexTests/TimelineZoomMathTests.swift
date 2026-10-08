import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// The timeline's zoom bounds (FS-12.17 §6, FS-12.17b §3).
struct TimelineZoomMathTests {
    /// FS-12.17 AC-9: with Frame zoom on pinch off, a pinch spread as far
    /// as it goes stops at 160pt a second.
    @Test func pinchStopsAt160WhenFrameZoomOff() {
        #expect(TimelineZoomMath.clampedPPS(55 * 40) == 160)
        #expect(TimelineZoomMath.clampedPPS(160.5) == 160)
        #expect(TimelineZoomMath.clampedPPS(.infinity) == TimelineZoomMath.floor)
    }

    /// Below the ceiling a pinch is the finger's, and pinched in it stops
    /// at the floor (18, the Duo cover's group zoom).
    @Test func noFrameZoomStateBelowCeiling() {
        #expect(TimelineZoomMath.clampedPPS(55) == 55)
        #expect(TimelineZoomMath.clampedPPS(159.9) == 159.9)
        #expect(TimelineZoomMath.clampedPPS(3) == 18)
        #expect(TimelineZoomMath.clampedPPS(-1) == 18)
    }
}
