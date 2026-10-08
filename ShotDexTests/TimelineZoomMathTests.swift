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

extension TimelineZoomMathTests {
    /// FS-12.17 AC-7: spread as far as it goes, the pinch stops at 12pt a
    /// frame — 360 pt/s at 30 fps.
    @Test func ceilingIs360At30() {
        let ceiling = TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 30)
        #expect(ceiling == 360)
        #expect(TimelineZoomMath.clampedPPS(55 * 40, ceiling: ceiling) == 360)
        #expect(TimelineZoomMath.isFrameZoom(360, fps: 30))
        #expect(!TimelineZoomMath.isFrameZoom(300, fps: 30))
    }

    @Test func ceilingIs288At24() {
        #expect(TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 24) == 288)
    }

    @Test func ceilingIs720At60() {
        #expect(TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 60) == 720)
    }

    /// FS-12.17 AC-9 with the switch: "Frame zoom on pinch" off stops at 160.
    @Test func switchOffStopsAt160() {
        let ceiling = TimelineZoomMath.ceiling(frameZoomOnPinch: false, fps: 30)
        #expect(ceiling == 160)
        #expect(TimelineZoomMath.clampedPPS(55 * 40, ceiling: ceiling) == 160)
        #expect(!TimelineZoomMath.isFrameZoom(160, fps: 30))
    }

    /// FS-12.17 §6: at Frame zoom the ruler is labelled every 6 frames —
    /// 72pt apart — "8:12f", "8:18f", "8:24f", "9:00f".
    @Test func rulerLabelsEvery72pt() {
        let step = CGFloat(TimelineZoomMath.framesPerRulerLabel) * TimelineZoomMath.pointsPerFrame
        #expect(step == 72)
        let labels = stride(from: 252, through: 270, by: 6).map { TimelineZoomMath.rulerFrameLabel(frame: $0, fps: 30) }
        #expect(labels == ["8:12f", "8:18f", "8:24f", "9:00f"])
    }
}
