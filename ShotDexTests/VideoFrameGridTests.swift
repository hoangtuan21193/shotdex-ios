import Foundation
import Testing
@testable import ShotDex

/// The project's frame grid (FS-12.17 §5, FS-12.17b §3).
struct VideoFrameGridTests {
    /// FS-12.17b AC-1: a 24 fps project at 2.000 s, ⇧→ → 2.0417 s (±1 ms).
    @Test func stepAt24fps() {
        let grid = VideoFrameGrid(.fps24)
        #expect(abs(grid.step(from: 2.0, by: 1) - 2.041_666_7) < 0.001)
        #expect(abs(grid.step(from: 2.0, by: -1) - 1.958_333_3) < 0.001)
    }

    @Test func stepAt60fps() {
        let grid = VideoFrameGrid(.fps60)
        #expect(abs(grid.step(from: 2.0, by: 1) - 2.016_666_7) < 1e-6)
        #expect(abs(grid.step(from: 9.2, by: -4) - (9.2 - 4.0 / 60)) < 1e-6)
    }

    /// Between two lines, the first step lands on the next line in its
    /// direction; later steps are whole frames from there.
    @Test func offGridStepsToNextLine() {
        let grid = VideoFrameGrid(.fps30)
        #expect(abs(grid.step(from: 2.01, by: 1) - 61.0 / 30) < 1e-9)
        #expect(abs(grid.step(from: 2.01, by: -1) - 60.0 / 30) < 1e-9)
        #expect(abs(grid.step(from: 2.01, by: 3) - 63.0 / 30) < 1e-9)
        #expect(grid.isOnGrid(9.2))
        #expect(!grid.isOnGrid(2.01))
        // Many additions of a frame stay on the grid.
        var time = 0.0
        for _ in 0..<300 { time = grid.step(from: time, by: 1) }
        #expect(abs(time - 10) < 1e-9)
    }

    /// FS-12.17 §5: "0:09.07", "0:09.20", "0:08.87" — hundredths, rounded.
    @Test func formatsHundredths() {
        #expect(VideoFrameGrid.hundredths(9.2 - 4.0 / 30) == "0:09.07")
        #expect(VideoFrameGrid.hundredths(9.2) == "0:09.20")
        #expect(VideoFrameGrid.hundredths(8.9 - 1.0 / 30) == "0:08.87")
        #expect(VideoFrameGrid.hundredths(9.2 - 1.0 / 30) == "0:09.17")
        #expect(VideoFrameGrid.hundredths(75.5) == "1:15.50")
        #expect(VideoFrameGrid.hundredths(-1) == "0:00.00")
    }

    @Test func countsFramesBetweenTwoTimes() {
        let grid = VideoFrameGrid(.fps30)
        #expect(grid.frameCount(from: 9.2, to: 9.2 - 4.0 / 30) == -4)
        #expect(grid.frameCount(from: 8.9, to: 8.8) == -3)
    }
}

extension VideoFrameGridTests {
    /// FS-12.17b AC-1 through the model — the call ⇧→ and both transports'
    /// Forward a Frame make — and the read-out counting the same grid.
    @MainActor
    @Test func shiftRightStepsOneProjectFrame() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.frameTrimSampleClips(),
            configure: { $0.frameRate = .fps24 }
        )
        model.seek(to: 2)
        model.stepFrames(1)
        #expect(abs(model.currentTime - 2.041_666_7) < 0.001)
        #expect(VideoStudioMetrics.timecode(model.currentTime, fps: 24) == "00:00:02:01")
        model.stepFrames(-1)
        #expect(abs(model.currentTime - 2) < 1e-9)
        #expect(VideoStudioMetrics.timecode(model.currentTime, fps: 24) == "00:00:02:00")
    }
}

extension VideoFrameGridTests {
    /// FS-12.17 AC-17: the footers' second line — "0:09.07 · −4 frames" on
    /// the iPad, "0:09.07 · −4 f" on the Duo's inner display.
    @MainActor
    @Test func compactFrameLabel() {
        let time = VideoFrameGrid.hundredths(9.2 - 4.0 / 30)
        #expect(time + " · " + VideoStudioCopy.frameCount(-4) == "0:09.07 · −4 frames")
        #expect(time + " · " + VideoStudioCopy.frameCount(-4, compact: true) == "0:09.07 · −4 f")
        #expect(VideoStudioCopy.frameCount(-1) == "−1 frame")
        #expect(VideoStudioCopy.frameCount(0) == "0 frames")
    }
}
