import Foundation
import Testing
@testable import ShotDex

/// What a dragged time sticks to (FS-12.05 §5, FS-12.12 §5), on FS-12.12
/// §9's project: clips end at 3.0 · 9.2 · 14.2 · 17.2 · 24.0, Morning Drive
/// at 96 BPM from 0.0 on A1.
struct TimelineSnappingTests {
    private let edits: [Double] = [0, 3.0, 9.2, 14.2, 17.2, 24.0]

    /// AC-7: at 70pt a second 8pt is 0.114s; clip 2's end (9.2) dragged to
    /// 8.8 sticks to beat 14 at 8.75 — 0.45s earlier — not to an edit.
    @Test func edgeSnapsToBeat14At70pps() {
        let tolerance = 8.0 / 70
        let target = TimelineSnapping.target(
            for: 8.8, tolerance: tolerance, edits: edits, beats: BeatGridTests.grid, excluding: 9.2
        )
        #expect(target?.time == 8.75)
        #expect(target?.beat?.number == 14)
        #expect(VideoStudioCopy.beatSnapPill(14, at: 8.75, moved: 8.75 - 9.2) == "Beat 14 · 0:08.75 · −0.45s")
        #expect(VideoStudioCopy.onBeat(14) == "on beat 14")
    }

    /// Precise trimming (FS-12.17) asks without beats: the same drag sticks
    /// to nothing.
    @Test func preciseTrimIgnoresBeats() {
        let target = TimelineSnapping.target(for: 8.8, tolerance: 8.0 / 70, edits: edits, beats: nil, excluding: 9.2)
        #expect(target == nil)
    }

    /// AC-8: Every Bar — 8.75 (beat 14) does not stick; 7.5 (bar 12) and
    /// 10.0 (bar 16) do when within 8pt.
    @Test func everyBarSkipsOffbeats() {
        let tolerance = 8.0 / 70
        let grid = BeatGridTests.grid
        #expect(TimelineSnapping.target(for: 8.8, tolerance: tolerance, edits: edits, beats: grid, division: .bar, excluding: 9.2) == nil)
        #expect(TimelineSnapping.target(for: 7.55, tolerance: tolerance, edits: edits, beats: grid, division: .bar, excluding: 9.2)?.beat?.number == 12)
        #expect(TimelineSnapping.target(for: 9.95, tolerance: tolerance, edits: edits, beats: grid, division: .bar, excluding: 9.2)?.time == 10.0)
    }
}

/// The edge drag on the model, with the beats of a real decoded file.
@MainActor
struct VideoEdgeBeatSnapTests {
    /// AC-7 end to end: Morning Drive (a generated 96 BPM WAV) snapping;
    /// clip 2's trailing edge dragged from 9.2 to 8.8 lands on beat 14 —
    /// the preview names the beat, the footer reads "5.75s · on beat 14",
    /// and the release cuts clip 2 to 5.75s.
    @Test func edgeDragStopsOnBeat14() async throws {
        let url = try MusicBeatAnalyzerTests.writeClickWAV(bpm: 96, seconds: 20)
        defer { try? FileManager.default.removeItem(at: url) }
        var bed = MusicTrack(source: .imported(url: url, displayName: "Morning Drive"))
        bed.sourceDuration = 20
        bed.trimEnd = 18.4
        bed.beatSnap.isOn = true
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.mediaSampleRecipe().clips,
            configure: { $0.musicTracks = [bed] }
        )
        model.beats.findBeats(of: url)
        for _ in 0..<400 where model.beats.isFinding { try await Task.sleep(for: .milliseconds(10)) }
        let grid = try #require(model.snapGrid)
        #expect(abs((grid.ticks.first { $0.number == 14 }?.time ?? 0) - 8.75) < 0.002)

        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        let feedback = model.edgeTrim(clip2, edge: .trailing, phase: .changed(-0.4), snapTolerance: 8.0 / 70)
        #expect(feedback.beat?.number == 14)
        #expect(model.edgeTrimPreview?.beat?.number == 14)
        #expect(model.selectionTitle?.detail.hasSuffix("on beat 14") == true)
        #expect(model.selectionTitle?.detail.hasPrefix("5.75s") == true)

        model.edgeTrim(clip2, edge: .trailing, phase: .ended(-0.4), snapTolerance: 8.0 / 70)
        #expect(abs(model.recipe.clips[1].effectiveDuration - 5.75) < 0.002)
    }
}
