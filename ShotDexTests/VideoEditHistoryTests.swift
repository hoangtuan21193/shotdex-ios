import Foundation
import Testing
@testable import ShotDex

/// Undo and redo with numbered steps (FS-12.04 §5).
struct VideoEditHistoryTests {
    private func recipe(speed: Double) -> VideoProjectRecipe {
        var clips = VideoStudioModelFixture.videoClips(1)
        clips[0].speed = speed
        return VideoProjectRecipe(clips: clips)
    }

    @Test func undoAndRedoWalkTheSnapshots() {
        var history = VideoEditHistory()
        history.push(recipe(speed: 1))
        let back = history.undo(from: recipe(speed: 2))
        #expect(back?.clips[0].speed == 1)
        #expect(history.canRedo)
        let forward = history.redo(from: recipe(speed: 1))
        #expect(forward?.clips[0].speed == 2)
        #expect(!history.canRedo)
    }

    @Test func theCapKeepsTheNewestForty() {
        var history = VideoEditHistory()
        for step in 0..<45 { history.push(recipe(speed: Double(step))) }
        #expect(history.undoEntries.count == VideoEditHistory.depth)
        #expect(history.undoEntries.first?.snapshot.clips[0].speed == 5)
        #expect(history.undoEntries.first?.sequence == 6)
    }

    @Test func aGroupIsOneStep() {
        var history = VideoEditHistory()
        history.beginGroup(recipe(speed: 1))
        history.push(recipe(speed: 2))
        history.push(recipe(speed: 3))
        history.endGroup()
        #expect(history.undoEntries.count == 1)
        #expect(history.undoEntries[0].snapshot.clips[0].speed == 1)
    }

    /// A rollback forgets exactly the session's steps, even past the cap
    /// and after an undo-redo round trip, and leaves no redo.
    @Test func rollbackForgetsOnlyStepsAfterTheCheckpoint() {
        var history = VideoEditHistory()
        history.push(recipe(speed: 1))
        history.push(recipe(speed: 2))
        let checkpoint = history.checkpoint
        for step in 0..<50 { history.push(recipe(speed: Double(10 + step))) }
        _ = history.undo(from: recipe(speed: 99))
        _ = history.redo(from: recipe(speed: 59))
        history.rollback(to: checkpoint)
        // Fifty session steps pushed the two older ones out past the cap:
        // nothing older is left, and nothing from the session survives.
        #expect(history.undoEntries.allSatisfy { $0.sequence < checkpoint })
        #expect(!history.canRedo)

        var short = VideoEditHistory()
        short.push(recipe(speed: 1))
        let mark = short.checkpoint
        short.push(recipe(speed: 2))
        short.push(recipe(speed: 3))
        _ = short.undo(from: recipe(speed: 4))
        short.rollback(to: mark)
        #expect(short.undoEntries.map(\.sequence) == [1])
        #expect(!short.canRedo)
    }

    @Test func redoKeepsTheStepsNumber() {
        var history = VideoEditHistory()
        history.push(recipe(speed: 1))
        let number = history.newestSequence
        _ = history.undo(from: recipe(speed: 2))
        _ = history.redo(from: recipe(speed: 1))
        #expect(history.newestSequence == number)
    }
}
