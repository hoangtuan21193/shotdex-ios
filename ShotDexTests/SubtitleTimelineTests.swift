import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

private func cue(_ start: Int64, _ end: Int64, _ text: String, top: Bool = false) -> SubtitleCue {
    SubtitleCue(startMs: start, endMs: end, lines: [[SubtitleRun(text: text)]], placement: top ? .top : .bottom)
}

/// FS-23.03 §2 Sync, §4 overlapping cues.
@Suite struct SubtitleTimelineTests {
    /// AC-20 (logic): subtitles 2.0 s early, Sync +2.0 s — the cue timed
    /// 00:01:05,000 shows from movie time 1:07.0, not before.
    @Test func delayShiftsCues() {
        let document = SubtitleDocument(cues: [cue(65_000, 67_000, "now"), cue(68_000, 70_000, "next")])
        let timeline = SubtitleTimeline(document: document, delayMs: 2_000)
        #expect(timeline.cues(atMs: 66_000).isEmpty)
        #expect(timeline.cues(atMs: 66_999).isEmpty)
        #expect(timeline.cues(atMs: 67_000).map(\.plainText) == ["now"])
        #expect(timeline.cues(atMs: 68_999).map(\.plainText) == ["now"])
        #expect(timeline.cues(atMs: 69_000).isEmpty)
        #expect(timeline.cues(atMs: 70_000).map(\.plainText) == ["next"])

        let late = SubtitleTimeline(document: document, delayMs: -1_500)
        #expect(late.cues(atMs: 63_500).map(\.plainText) == ["now"])
    }

    @Test func overlappingCuesBothShowInStartOrder() {
        let document = SubtitleDocument(cues: [
            cue(0, 60_000, "long sign"), cue(10_000, 12_000, "a"), cue(11_000, 13_000, "b"), cue(30_000, 31_000, "c"),
        ])
        let timeline = SubtitleTimeline(document: document)
        #expect(timeline.cues(atMs: 11_500).map(\.plainText) == ["long sign", "a", "b"])
        #expect(timeline.cues(atMs: 30_500).map(\.plainText) == ["long sign", "c"])
        #expect(timeline.cues(atMs: 60_000).isEmpty)
    }

    /// A feature-length file: lookups stay cheap.
    @Test func thousandsOfCues() {
        let document = SubtitleDocument(cues: (0..<3_000).map { cue(Int64($0) * 2_400, Int64($0) * 2_400 + 2_000, "\($0)") })
        let timeline = SubtitleTimeline(document: document)
        #expect(timeline.cues(atMs: 1_200_000 + 100).map(\.plainText) == ["500"])
        #expect(timeline.cues(atMs: 1_200_000 + 2_100).isEmpty)
    }
}

/// The subtitle clock between VLC's time reports.
@Suite struct PlaybackClockTests {
    private func playing(at ms: Int64 = 0, host: TimeInterval = 100) -> PlaybackClock {
        var clock = PlaybackClock()
        clock.seek(to: ms, at: host)
        clock.setRunning(true, at: host)
        return clock
    }

    @Test func runsBetweenReports() {
        var clock = playing(at: 60_000)
        #expect(clock.timeMs(at: 100.5) == 60_500)
        clock.report(60_500, at: 100.5)
        #expect(clock.timeMs(at: 101.0) == 61_000)
    }

    @Test func twiceSpeed() {
        var clock = playing(at: 10_000)
        clock.setRate(2, at: 100)
        #expect(clock.timeMs(at: 101) == 12_000)
        clock.setRate(1, at: 101)
        #expect(clock.timeMs(at: 102) == 13_000)
    }

    @Test func pauseAndBufferingFreeze() {
        var clock = playing(at: 0)
        clock.setRunning(false, at: 101)  // pause
        #expect(clock.timeMs(at: 110) == 1_000)
        clock.setRunning(true, at: 110)
        #expect(clock.timeMs(at: 111) == 2_000)
        clock.setRunning(false, at: 111)  // stalled for buffering
        clock.report(2_000, at: 115)
        #expect(clock.timeMs(at: 120) == 2_000)
    }

    @Test func seekBackwardsJumpsBack() {
        var clock = playing(at: 600_000)
        #expect(clock.timeMs(at: 101) == 601_000)
        clock.seek(to: 30_000, at: 101)
        #expect(clock.timeMs(at: 101) == 30_000)
        #expect(clock.timeMs(at: 102) == 31_000)
    }

    /// VLC's reports lag and jitter by tens of ms: folded in, time never
    /// runs backwards on screen, and the clock converges.
    @Test func jitterNeverRunsBackwards() {
        var clock = playing(at: 0)
        var host: TimeInterval = 100
        var shown: Int64 = -1
        for step in 1...40 {
            host += 0.25
            let truth = Int64(step) * 250
            clock.report(truth - (step % 2 == 0 ? 80 : 0), at: host)
            for sub in 0..<5 {
                let value = clock.timeMs(at: host + Double(sub) * 0.05)
                #expect(value >= shown)
                shown = value
            }
        }
        // Read after the last frame drawn (+0.2 s): time never runs back to `host`.
        #expect(abs(clock.timeMs(at: host + 0.25) - 10_250) <= 100)
    }

    /// A report far from the clock (the player skipped) re-anchors at once.
    @Test func bigDriftReanchors() {
        var clock = playing(at: 0)
        clock.report(5_000, at: 101)
        #expect(clock.timeMs(at: 101) == 5_000)
    }
}

/// FS-23.03 §2 Position, §4.
@Suite struct SubtitleLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 874, height: 402)
    private let frame = CGRect(x: 80, y: 0, width: 714, height: 402)  // Fit, pillarboxed 16:9
    private let en = DualSubtitleLayout.Block(size: CGSize(width: 400, height: 40))
    private let vi = DualSubtitleLayout.Block(size: CGSize(width: 360, height: 34))

    /// AC-18 (logic): the three positions, 8 pt apart, never overlapping.
    @Test func threePositions() throws {
        let topBottom = DualSubtitleLayout.place(primary: en, secondary: vi, position: .primaryBottomSecondaryTop, frame: frame, bounds: bounds)
        let topVI = try #require(topBottom.secondary)
        let bottomEN = try #require(topBottom.primary)
        #expect(topVI.minY < 30)
        #expect(bottomEN.maxY > 360)

        let above = DualSubtitleLayout.place(primary: en, secondary: vi, position: .bothBottomSecondaryAbove, frame: frame, bounds: bounds)
        let aboveVI = try #require(above.secondary)
        let aboveEN = try #require(above.primary)
        #expect(aboveEN.minY - aboveVI.maxY == 8)
        #expect(!aboveVI.intersects(aboveEN))

        let below = DualSubtitleLayout.place(primary: en, secondary: vi, position: .bothBottomSecondaryBelow, frame: frame, bounds: bounds)
        let belowVI = try #require(below.secondary)
        let belowEN = try #require(below.primary)
        #expect(belowVI.minY - belowEN.maxY == 8)
        #expect(belowVI.maxY == aboveEN.maxY)

        for placement in [topBottom, above, below] {
            for rect in [placement.primary, placement.secondary].compactMap({ $0 }) {
                #expect(frame.contains(rect))
                #expect(abs(rect.midX - frame.midX) < 0.5)
            }
        }
    }

    /// AC-19 (logic): with the chrome up the stack sits ≥ 8 pt above the
    /// glass; with it hidden it comes back down.
    @Test func liftsAboveChrome() throws {
        let chromeTop: CGFloat = 300
        let up = DualSubtitleLayout.place(primary: en, secondary: vi, position: .bothBottomSecondaryAbove, frame: frame, bounds: bounds, chromeTop: chromeTop)
        let lifted = try #require(up.primary)
        #expect(lifted.maxY <= chromeTop - 8)
        let down = DualSubtitleLayout.place(primary: en, secondary: vi, position: .bothBottomSecondaryAbove, frame: frame, bounds: bounds)
        #expect(try #require(down.primary).maxY > lifted.maxY)
    }

    /// A subtitle at the top stays below the top bar while it shows.
    @Test func topLineClearsTopBar() throws {
        let up = DualSubtitleLayout.place(primary: en, secondary: vi, position: .primaryBottomSecondaryTop, frame: frame, bounds: bounds, chromeTop: 300, chromeBottom: 60)
        #expect(try #require(up.secondary).minY >= 68)
        let down = DualSubtitleLayout.place(primary: en, secondary: vi, position: .primaryBottomSecondaryTop, frame: frame, bounds: bounds)
        #expect(try #require(down.secondary).minY < 30)
    }

    /// Fill crops the frame: lines stay inside what is on screen.
    @Test func fillUsesVisiblePart() throws {
        let filled = CGRect(x: 0, y: -45, width: 874, height: 492)
        let placed = DualSubtitleLayout.place(primary: en, secondary: nil, position: .bothBottomSecondaryAbove, frame: filled, bounds: bounds)
        let rect = try #require(placed.primary)
        #expect(bounds.contains(rect))
        #expect(rect.maxY > 360)
    }

    /// An `\an8` primary goes up; the secondary keeps the bottom.
    @Test func topCueGoesUp() throws {
        var sign = en
        sign.wantsTop = true
        let placed = DualSubtitleLayout.place(primary: sign, secondary: vi, position: .bothBottomSecondaryAbove, frame: frame, bounds: bounds)
        #expect(try #require(placed.primary).minY < 30)
        #expect(try #require(placed.secondary).maxY > 360)
    }

    @Test func sizeAndWidth() {
        #expect(DualSubtitleLayout.fontSize(frameHeight: 402, scale: 1) == 20.1)
        #expect(DualSubtitleLayout.maxWidth(frame: frame, bounds: bounds) == 714 * 0.9)
        let wide = DualSubtitleLayout.Block(size: CGSize(width: 2_000, height: 40))
        let placed = DualSubtitleLayout.place(primary: wide, secondary: nil, position: .bothBottomSecondaryAbove, frame: frame, bounds: bounds)
        #expect(placed.primary?.width == 714 * 0.9)
    }
}
