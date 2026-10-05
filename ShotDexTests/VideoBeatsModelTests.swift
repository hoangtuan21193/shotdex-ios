import Foundation
import Testing
@testable import ShotDex

/// The beats of a project's beds as the studio holds them (FS-12.12 §4):
/// one state per file, found off the main actor, cancelled with the bed.
@MainActor
struct VideoBeatsModelTests {
    private let url = URL(fileURLWithPath: "/tmp/morning-drive.m4a")

    private func settle(_ model: VideoBeatsModel) async {
        for _ in 0..<200 where model.isFinding { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// AC-3's other half: a file that will not decode reads "Can't read
    /// this track"; noise reads "No steady beat"; neither gives a grid.
    @Test func unreadableFileShowsCantRead() async {
        let unreadable = VideoBeatsModel(analyze: { _ in throw MusicBeatAnalyzer.Failure.unreadable })
        unreadable.findBeats(of: url)
        #expect(unreadable.state(for: url) == .finding)
        await settle(unreadable)
        #expect(unreadable.state(for: url) == .unreadable)
        #expect(unreadable.analysis(for: url) == nil)

        let noise = VideoBeatsModel(analyze: { _ in BeatAnalysis(bpm: 125, beats: [], downbeatPhase: 0, confidence: 0.05) })
        noise.findBeats(of: url)
        await settle(noise)
        #expect(noise.state(for: url) == .noSteadyBeat)
        #expect(noise.analysis(for: url) == nil)
    }

    /// Found once: asking again does not start another analysis.
    @Test func foundBeatsAreNotFoundTwice() async {
        let counter = Counter()
        let model = VideoBeatsModel(analyze: { _ in
            await counter.increment()
            return BeatGridTests.morningDrive(seconds: 10)
        })
        model.findBeats(of: url)
        await settle(model)
        model.findBeats(of: url)
        await settle(model)
        #expect(await counter.value == 1)
        #expect(model.analysis(for: url)?.bpm == 96)
    }
}

/// One bed snaps at a time (FS-12.12 §5).
@MainActor
struct VideoBeatSnapTests {
    /// Snap turned on for A2 turns A1's off — one undo step for the switch.
    @Test func snapOnA2TurnsA1Off() {
        let a1 = MusicTrack(source: .bundled(id: "a1"))
        let a2 = MusicTrack(source: .bundled(id: "a2"))
        let model = VideoStudioModelFixture.model(configure: { recipe in
            recipe.musicTracks = [a1, a2]
            recipe.musicTracks[0].beatSnap.isOn = true
        })
        #expect(model.snapSource?.id == a1.id)

        model.setBeatSnap(true, for: a2.id)
        #expect(model.recipe.musicTracks.map(\.beatSnap.isOn) == [false, true])
        #expect(model.snapSource?.id == a2.id)

        model.undo()
        #expect(model.recipe.musicTracks.map(\.beatSnap.isOn) == [true, false])
    }
}

/// Offset (FS-12.12 §5).
@MainActor
struct VideoBeatOffsetTests {
    /// AC-9: one drag of Offset to +50 ms is one undo step back to 0; values
    /// step by 5 and stay within ±250.
    @Test func offsetDragIsOneUndo() {
        let bed = MusicTrack(source: .bundled(id: "drive"))
        let model = VideoStudioModelFixture.model(configure: { $0.musicTracks = [bed] })
        model.beginUndoGroup()
        model.setBeatOffset(12, for: bed.id)
        model.setBeatOffset(33, for: bed.id)
        model.setBeatOffset(51, for: bed.id)
        model.endUndoGroup()
        #expect(model.recipe.musicTracks[0].beatSnap.offsetMs == 50)

        model.undo()
        #expect(model.recipe.musicTracks[0].beatSnap.offsetMs == 0)
        #expect(!model.canUndo)

        model.setBeatOffset(900, for: bed.id)
        #expect(model.recipe.musicTracks[0].beatSnap.offsetMs == 250)
    }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
