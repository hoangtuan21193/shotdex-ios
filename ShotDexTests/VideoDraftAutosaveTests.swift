import Foundation
import Testing
@testable import ShotDex

/// Records every draft write, from whichever thread makes it.
final class DraftWriteLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(creation: Creation, at: Date)] = []
    /// Throws this instead of writing while set — a full disk, say.
    var failure: (any Error)? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }
    private var storedFailure: (any Error)?

    var writes: [Creation] { lock.withLock { entries.map(\.creation) } }
    var times: [Date] { lock.withLock { entries.map(\.at) } }

    func write(_ creation: Creation) throws {
        try lock.withLock {
            if let storedFailure { throw storedFailure }
            entries.append((creation, Date()))
        }
    }

    struct DiskFull: Error {}
}

/// FS-12.18 §2: the project writes itself about a second after the last
/// change, once per burst.
@MainActor
struct VideoDraftAutosaveTests {
    /// Waits for `condition`, polling, up to `seconds`.
    static func eventually(_ seconds: Double = 3, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// FS-12.18 AC-1: Speed 2× on clip 2 is in the stored row 1.0 s ±0.3 s
    /// after the change — not before, not much later.
    @Test func savesOneSecondAfterTheLastChange() async throws {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) })
        let clip2 = model.recipe.clips[1].id

        let changed = Date()
        model.setSpeed(2, for: clip2)
        try await Task.sleep(for: .milliseconds(500))
        #expect(log.writes.isEmpty)
        #expect(await Self.eventually { !log.writes.isEmpty })

        let elapsed = try #require(log.times.first).timeIntervalSince(changed)
        #expect(elapsed >= 0.7 && elapsed <= 1.3)
        let stored = try #require(log.writes.first?.videoRecipe)
        #expect(stored.clips[1].speed == 2)
        #expect(log.writes.first?.isDraft == true)
    }

    /// FS-12.18 AC-1: three changes inside half a second make one write,
    /// carrying the last of them.
    @Test func threeQuickChangesWriteOnce() async throws {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        // A twentieth of the real wait: the rule under test is "once per
        // burst", not the length of the wait.
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { try await Task.sleep(for: $0 / 20) })
        let clip2 = model.recipe.clips[1].id

        model.setSpeed(2, for: clip2)
        model.setSpeed(3, for: clip2)
        model.setSpeed(4, for: clip2)
        #expect(await Self.eventually { !log.writes.isEmpty })
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.writes.count == 1)
        #expect(log.writes.first?.videoRecipe?.clips[1].speed == 4)
    }

    /// A change that leaves the project as it was is not a change.
    @Test func settingTheSameValueWritesNothing() async throws {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { try await Task.sleep(for: $0 / 20) })
        model.setSpeed(1, for: model.recipe.clips[1].id)
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.writes.isEmpty)
    }
}

/// FS-12.18 §2: what is written at once, without waiting for the project to
/// sit still.
@MainActor
struct VideoDraftSaveNowTests {
    /// FS-12.18 AC-11: three photos, the studio opens, Back at once — Video
    /// Projects has a draft of those three clips, though nothing was edited.
    @Test func aNewProjectWithNoEditsIsKept() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(3), creationStore: store)
        #expect(try store.count(kind: .video) == 0)

        #expect(await model.saveDraftNow())

        let rows = try store.fetchOrdered(kind: .video)
        #expect(rows.count == 1)
        #expect(rows.first?.isDraft == true)
        #expect(rows.first?.videoRecipe?.clips.count == 3)
        #expect(rows.first?.id == model.creationID)
    }
}

/// FS-12.18 §2: Back never asks; it saves and closes.
@MainActor
struct VideoDraftBackTests {
    /// FS-12.18 AC-2: an edited project that was never exported — Back
    /// closes with no question, and the draft carries the edit.
    @Test func backSavesWithoutAsking() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let model = VideoStudioModelFixture.model(creationStore: store)
        let clip2 = model.recipe.clips[1].id
        model.selectClip(clip2)
        model.setSpeed(2, for: clip2)

        #expect(await model.back() == .close)

        #expect(model.selectedClipID == nil)
        let row = try #require(try store.fetch(id: model.creationID))
        #expect(row.isDraft)
        #expect(row.videoRecipe?.clips[1].speed == 2)
        #expect(model.drafts?.isSavePending == false)
    }

    /// FS-12.18 §2: a project of server photos has no draft — Back with
    /// edits still asks, as FS-17.06 says, and nothing is written.
    @Test func serverProjectHasNoDraft() async throws {
        let model = VideoStudioModelFixture.model(serverWorkDirectory: FileManager.default.temporaryDirectory)
        #expect(model.isServerRun)
        #expect(model.drafts == nil)
        #expect(await model.back() == .close)
        model.setSpeed(2, for: model.recipe.clips[1].id)
        #expect(await model.back() == .confirmDiscard)
    }
}
