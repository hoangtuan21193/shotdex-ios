import Foundation
import Testing
@testable import ShotDex

/// The frame trim (FS-12.17 §3–5) on the sample project of §12: Clip 1 a
/// 3.0 s photo, Clip 2 a video cut 0.0–6.2 of 12.0 s (3.0–9.2 on the
/// timeline), Clip 3 a 5.0 s video; 30 fps.
struct FrameTrimSessionTests {
    static let clips = VideoStudioModelFixture.frameTrimSampleClips()

    static func session(
        clip index: Int = 1,
        edge: VideoEdgeTrimMath.Edge = .trailing,
        fps: VideoFrameRate = .fps30,
        speed: Double? = nil
    ) -> FrameTrimSession {
        var clips = clips
        if let speed { clips[index].speed = speed }
        let placements = VideoTimelineMath.placements(durations: clips.map(\.effectiveDuration), overlaps: Array(repeating: 0, count: clips.count - 1))
        return FrameTrimSession(
            clipID: clips[index].id, clip: clips[index], placement: placements[index],
            grid: VideoFrameGrid(fps), edge: edge
        )
    }

    /// FS-12.17 AC-1: held at Clip 2's end the trim opens there — 9.20 s,
    /// "Last frame · 0:09.20", no frame moved, nothing changed yet.
    @Test func entersAtTrailingEdge() {
        let trim = Self.session()
        #expect(abs(trim.edgeTime - 9.2) < 1e-9)
        #expect(trim.frames == 0)
        #expect(!trim.changesClip)
        #expect(VideoFrameGrid.hundredths(trim.edgeTime) == "0:09.20")
        #expect(VideoStudioCopy.edgeFrameLabel(trailing: true, at: VideoFrameGrid.hundredths(trim.edgeTime)) == "Last frame · 0:09.20")
        // The viewer shows the clip's last frame, one frame before the cut.
        #expect(abs((trim.viewerSourceTime ?? -1) - (6.2 - 1.0 / 30)) < 1e-9)
        // The loupe: five frames before the cut, five from it on.
        let loupe = trim.loupeSourceTimes
        #expect(loupe.count == 10)
        #expect(abs((loupe[4] ?? -1) - (6.2 - 1.0 / 30)) < 1e-9)
        #expect(abs((loupe[5] ?? -1) - 6.2) < 1e-9)
        // The leading edge opens at the clip's start, "First frame".
        let leading = Self.session(edge: .leading)
        #expect(abs(leading.edgeTime - 3) < 1e-9)
        #expect(leading.viewerSourceTime == 0)
        #expect(leading.loupeSourceTimes[4] == nil)  // nothing before the source's start
    }

    /// Through the model: the hold opens the trim on the selected clip,
    /// the playhead stands on the edge, the footer names the mode, and the
    /// recipe is untouched; a locked lane opens nothing.
    @MainActor
    @Test func theModelOpensTheTrimOnTheEdge() {
        let model = VideoStudioModelFixture.model(clips: Self.clips)
        let clip2 = model.recipe.clips[1].id
        let before = model.recipe
        model.selectClip(clip2)
        #expect(model.beginFrameTrim(clip2, edge: .trailing))
        #expect(model.isFrameTrimming)
        #expect(abs(model.currentTime - 9.2) < 1e-9)
        #expect(model.frameTrimTitle() == VideoItemTitle.Lines(name: "Trim · Clip 2", detail: "0:09.20 · 0 frames"))
        #expect(model.recipe == before)
        #expect(!model.canUndo)

        let locked = VideoStudioModelFixture.model(clips: Self.clips)
        locked.toggleLaneLock(.video)
        #expect(!locked.beginFrameTrim(locked.recipe.clips[1].id, edge: .trailing))
        #expect(!locked.isFrameTrimming)
    }
}

extension FrameTrimSessionTests {
    /// FS-12.17 AC-2: −1 Frame four times — the edge at 9.0667
    /// ("0:09.07 · −4 frames"), Clip 3 still starts at 9.20, the recipe
    /// exactly as it was.
    @MainActor
    @Test func fourFramesEarlier() {
        var trim = Self.session()
        for _ in 0..<4 {
            let moved = trim.step(by: -1)
            #expect(moved)
        }
        #expect(trim.frames == -4)
        #expect(abs(trim.edgeTime - (9.2 - 4.0 / 30)) < 1e-9)
        #expect(VideoFrameGrid.hundredths(trim.edgeTime) == "0:09.07")
        #expect(VideoStudioCopy.frameCount(trim.frames) == "−4 frames")
        #expect(VideoStudioCopy.frameCount(trim.frames, compact: true) == "−4 f")
        #expect(abs((trim.trimmedClip.trimEnd ?? 0) - (6.2 - 4.0 / 30)) < 1e-9)

        let model = VideoStudioModelFixture.model(clips: Self.clips)
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.beginFrameTrim(clip2, edge: .trailing)
        let before = model.recipe
        for _ in 0..<4 { #expect(model.stepFrameTrim(-1)) }
        #expect(model.recipe == before)
        #expect(abs(model.clipPlacements[2].start - 9.2) < 1e-9)
        #expect(abs(model.currentTime - (9.2 - 4.0 / 30)) < 1e-9)
        #expect(model.frameTrimTitle() == VideoItemTitle.Lines(name: "Trim · Clip 2", detail: "0:09.07 · −4 frames"))
        #expect(!model.canUndo)
        // +1 Frame walks back; one frame is "1 frame".
        #expect(model.stepFrameTrim(1))
        #expect(VideoStudioCopy.frameCount(1) == "+1 frame")
    }
}
