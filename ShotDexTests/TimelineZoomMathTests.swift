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

extension TimelineZoomMathTests {
    /// FS-12.17 AC-8: at Frame zoom (360 pt/s), the playhead at 8.90 s, the
    /// timeline dragged 36pt right — the playhead goes back exactly three
    /// frames to 8.80 s, three lines crossed (three ticks), the badge reads
    /// "−3 f · 0:08.80", and the scroll rests on that frame.
    @Test func drag36ptIsThreeFrames() {
        let pps = TimelineZoomMath.frameZoomPPS(fps: 30)
        let start = 8.9
        let time = start - Double(36 / pps)
        #expect(abs(time - 8.8) < 1e-9)
        let frames = TimelineZoomMath.scrubFrames(from: start, to: time, fps: 30)
        #expect(frames == -3)
        #expect(TimelineZoomMath.framesCrossed(from: start, to: time, fps: 30) == 3)
        #expect(TimelineZoomMath.scrubBadge(frames: frames, time: time) == "−3 f · 0:08.80")
        // A release between two frames rests on the nearer one.
        let inset: CGFloat = 186
        let resting = TimelineZoomMath.restingOffset(CGFloat(8.8) * pps - inset + 5, inset: inset, pps: pps, fps: 30)
        #expect(abs(resting - (CGFloat(8.8) * pps - inset)) < 0.001)
        let past = TimelineZoomMath.restingOffset(CGFloat(8.8) * pps - inset + 7, inset: inset, pps: pps, fps: 30)
        #expect(abs(past - (CGFloat(8.8) * pps - inset + 12)) < 0.001)
    }
}

/// ⌘+ / ⌘− (FS-12.17b §3, AC-7).
extension TimelineZoomMathTests {
    /// FS-12.17b AC-7: 55 pt/s, ⌘+ twice — 220 (Frame zoom on pinch on,
    /// 30 fps: the ceiling is 360).
    @Test func commandPlusTwiceFrom55Is220() {
        let ceiling = TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 30)
        let once = TimelineZoomMath.keyboardStep(55, zoomsIn: true, ceiling: ceiling)
        let twice = TimelineZoomMath.keyboardStep(once, zoomsIn: true, ceiling: ceiling)
        #expect(once == 110)
        #expect(twice == 220)
    }

    /// …and ⌘− twice brings it back to 55; it stops at 20.
    @Test func minusBack() {
        let ceiling = TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 30)
        let once = TimelineZoomMath.keyboardStep(220, zoomsIn: false, ceiling: ceiling)
        #expect(TimelineZoomMath.keyboardStep(once, zoomsIn: false, ceiling: ceiling) == 55)
        #expect(TimelineZoomMath.keyboardStep(30, zoomsIn: false, ceiling: ceiling) == 20)
        #expect(TimelineZoomMath.keyboardStep(20, zoomsIn: false, ceiling: ceiling) == 20)
    }

    /// Frame zoom on pinch off: ⌘+ stops where a pinch does, at 160; on, at
    /// Frame zoom (360 at 30 fps).
    @Test func ceilingWithFrameZoomOff() {
        let off = TimelineZoomMath.ceiling(frameZoomOnPinch: false, fps: 30)
        #expect(TimelineZoomMath.keyboardStep(110, zoomsIn: true, ceiling: off) == 160)
        let on = TimelineZoomMath.ceiling(frameZoomOnPinch: true, fps: 30)
        #expect(TimelineZoomMath.keyboardStep(220, zoomsIn: true, ceiling: on) == 360)
    }
}
