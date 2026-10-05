import Foundation
import Testing
@testable import ShotDex

/// A bed's beats on the timeline (FS-12.12 §4): FS-12.12 §9's "Morning
/// Drive", 96 BPM from 0.0 s, placed 0.0–18.4 s on A1.
struct BeatGridTests {
    static func morningDrive(seconds: Double = 60) -> BeatAnalysis {
        let period = 60.0 / 96
        let beats = stride(from: 0.0, to: seconds, by: period).map { $0 }
        return BeatAnalysis(bpm: 96, beats: beats, downbeatPhase: 0, confidence: 1)
    }

    static var grid: BeatGrid {
        BeatGrid(analysis: morningDrive(), start: 0, trimStart: 0, trimEnd: 18.4)
    }

    /// AC-4: 30 beats in the 18.4s window; at 55pt a second the bars stand
    /// 137.5pt apart and the beats 34.375; beat 14 is at 8.75s; beats 0, 4,
    /// 8… start bars.
    @Test func ticksAt55pps() {
        let ticks = Self.grid.ticks
        #expect(ticks.count == 30)
        #expect(ticks.map(\.number) == Array(0..<30))
        #expect(abs((ticks[4].time - ticks[0].time) * 55 - 137.5) < 1e-9)
        #expect(abs((ticks[1].time - ticks[0].time) * 55 - 34.375) < 1e-9)
        #expect(ticks[14].time == 8.75)
        #expect(ticks.filter(\.isBar).map(\.number) == stride(from: 0, to: 30, by: 4).map { $0 })
        #expect(VideoStudioCopy.beatsMarked(ticks.count, lane: "A1", device: "iPhone") == "30 beats marked on A1 · found on this iPhone")
        #expect(VideoStudioCopy.bpmLine(96) == "96 BPM · 4/4")
    }

    /// A bed placed later and trimmed: numbering starts again at its first
    /// beat on the timeline, and only beats inside the trim count.
    @Test func placementAndTrimShiftTheGrid() {
        let grid = BeatGrid(analysis: Self.morningDrive(), start: 2, trimStart: 1.25, trimEnd: 3.75)
        #expect(grid.ticks.map(\.time) == [2, 2.625, 3.25, 3.875, 4.5])
        #expect(grid.ticks.first?.isBar == false)
        #expect(grid.ticks[2].isBar)
    }

    /// Under 6pt between beats the band would turn into a stripe: only bars
    /// are drawn then.
    @Test func denseBeatsDrawOnlyBars() {
        let grid = Self.grid
        #expect(grid.visibleTicks(pointsPerSecond: 55).count == 30)
        #expect(grid.visibleTicks(pointsPerSecond: 8).allSatisfy { $0.isBar })
    }
}
