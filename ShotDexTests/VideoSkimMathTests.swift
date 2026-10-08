import Foundation
import Testing
@testable import ShotDex

/// Skimming a library video with the pointer (FS-12.17b §6).
struct VideoSkimMathTests {
    /// FS-12.17b AC-12: 46% across a 0:05 video is 0:02.3; the header
    /// reads "Skimming · Lake · 0:02.3 / 0:05".
    @Test func fortySixPercentOfFiveSeconds() {
        let time = VideoSkimMath.time(fraction: 0.46, duration: 5)
        #expect(time == 2.3)
        let detail = VideoSkimMath.detail(name: "Lake", time: time, duration: 5, notDownloaded: false, notDownloadedText: "Not downloaded")
        #expect(detail == "· Lake · 0:02.3 / 0:05")
        #expect(VideoSkimMath.time(fraction: 1.4, duration: 5) == 5)
        #expect(VideoSkimMath.time(fraction: -0.2, duration: 5) == 0)
        // A photo: the name only.
        #expect(VideoSkimMath.detail(name: "Lake", time: nil, duration: nil, notDownloaded: false, notDownloadedText: "") == "· Lake")
    }

    /// No more than thirty frames a second.
    @Test func throttlesToThirtyPerSecond() {
        var throttle = VideoSkimMath.Throttle()
        var asked = 0
        // A pointer reporting 120 times a second for one second.
        for step in 0..<120 {
            let clock = Double(step) / 120
            if throttle.offer(Double(step), at: clock) != nil { asked += 1 }
            if throttle.flush(at: clock) != nil { asked += 1 }
        }
        #expect(asked <= 31)
        #expect(asked >= 29)
    }

    /// While waiting, the newest position replaces the older: the one the
    /// pointer has left is never decoded.
    @Test func newestReplaces() {
        var throttle = VideoSkimMath.Throttle()
        #expect(throttle.offer(1.0, at: 0) == 1.0)
        #expect(throttle.offer(1.1, at: 0.01) == nil)
        #expect(throttle.offer(1.2, at: 0.02) == nil)
        #expect(throttle.pending == 1.2)
        #expect(throttle.flush(at: 0.025) == nil)
        #expect(throttle.flush(at: 0.034) == 1.2)
        #expect(throttle.pending == nil)
    }
}

/// The skim in the model (FS-12.17b §6).
@MainActor
struct VideoSkimModelTests {
    /// FS-12.17b AC-13: the pointer leaves — the line is the clip under
    /// the playhead's again and the viewer the project's, at once; the
    /// playhead never moved.
    @Test func leavingRestoresPlayheadTitle() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.seek(to: 8.4)
        model.skimMedia(assetID: "lake", name: "Lake", isVideo: true, duration: 5, fraction: 0.46, thumbnail: nil)
        #expect(model.skim?.detail == "· Lake · 0:02.3 / 0:05")
        #expect(model.currentTime == 8.4)
        model.endSkim()
        #expect(model.skim == nil)
        #expect(model.skimImage == nil)
        #expect(model.currentTime == 8.4)
    }

    /// A photo: its name only; while playing, nothing is skimmed.
    @Test func photoShowsNameAndPlayingSkimsNothing() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.frameTrimSampleClips())
        model.skimMedia(assetID: "falls", name: "Falls", isVideo: false, duration: 0, fraction: 0.5, thumbnail: nil)
        #expect(model.skim?.detail == "· Falls")
        #expect(model.skim?.time == nil)
    }
}
