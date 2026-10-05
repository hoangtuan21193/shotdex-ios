import Foundation
import UIKit
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

/// The autosave's wait, held by the test: it records what was asked for
/// and returns only when `open()` is called.
final class SleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [Duration] = []
    private var isOpen = false

    var requested: [Duration] { lock.withLock { durations } }

    func open() { lock.withLock { isOpen = true } }

    func sleep(_ duration: Duration) async throws {
        lock.withLock { durations.append(duration) }
        while !lock.withLock({ isOpen }) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// FS-12.18 §2: the project writes itself about a second after the last
/// change, once per burst.
@MainActor
struct VideoDraftAutosaveTests {
    /// Waits for `condition`, polling, up to `seconds`.
    static func eventually(_ seconds: Double = 10, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// FS-12.18 AC-1: Speed 2× on clip 2 is in the stored row a second
    /// after the change — not before. The wait is the autosave's own: it
    /// asks for exactly one second, and nothing is written until that wait
    /// ends. (Timing the write against the wall clock failed whenever a
    /// parallel run kept the main actor busy, without the code being wrong.)
    @Test func savesOneSecondAfterTheLastChange() async throws {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        let gate = SleepGate()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { try await gate.sleep($0) })
        let clip2 = model.recipe.clips[1].id

        model.setSpeed(2, for: clip2)
        #expect(await Self.eventually { gate.requested == [.seconds(1)] })
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.writes.isEmpty, "written before the second was up")

        gate.open()
        #expect(await Self.eventually { !log.writes.isEmpty })
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

/// FS-12.18 §2: leaving the app writes at once.
@MainActor
struct VideoDraftBackgroundTests {
    /// FS-12.18 AC-3: Speed changed, then Home — the draft has the change
    /// long before the autosave would have run. The autosave here waits a
    /// minute, so a write inside the window can only be the immediate one;
    /// the test does not race a wall clock, which a parallel run starves.
    /// The post goes to the model's own center: on the default one it
    /// reached every other test's model, and its main-queue delivery hung
    /// the host (now `queue: nil`, `onMain`).
    @Test func backgroundingSavesImmediately() async throws {
        let center = NotificationCenter()
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let model = VideoStudioModelFixture.model(creationStore: store, appNotifications: center)
        defer { model.close() }
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        model.setSpeed(2, for: model.recipe.clips[1].id)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(await VideoDraftAutosaveTests.eventually(10) {
            log.writes.last?.videoRecipe?.clips[1].speed == 2
        })
        #expect(model.drafts?.isSavePending == false)
    }
}

/// FS-12.18 §2: the scene changing writes at once.
@MainActor
struct VideoDraftSceneTests {
    /// FS-12.18 AC-4 (model half): Speed changed, then the scene changes —
    /// the Duo folding, a window closing — and the draft has the change
    /// before the autosave (here a minute away, as above). The fold itself
    /// is measured by hand.
    @Test func sceneChangeSavesImmediately() async throws {
        let model = VideoStudioModelFixture.model()
        defer { model.close() }
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        model.setSpeed(2, for: model.recipe.clips[1].id)

        model.sceneDidChange()

        #expect(await VideoDraftAutosaveTests.eventually(10) {
            log.writes.last?.videoRecipe?.clips[1].speed == 2
        })
    }
}

/// FS-12.18 §3: what comes back when a draft is opened again.
@MainActor
struct VideoDraftReopenTests {
    /// FS-12.18 AC-5: playhead 8.4 s, clip 2 selected, Back; opened again
    /// from Video Projects — the playhead is at 8.4 s, nothing is selected,
    /// no panel is open, and there is nothing to undo or redo.
    @Test func reopenRestoresPlayheadOnly() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let first = VideoStudioModelFixture.model(creationStore: store)
        first.seek(to: 8.4)
        first.selectClip(first.recipe.clips[1].id)
        first.pushUndo()
        first.setSpeed(2, for: first.recipe.clips[1].id)
        #expect(await first.back() == .close)
        first.close()

        let row = try #require(try store.fetch(id: first.creationID))
        let dependencies = AppDependencies.preview()
        let reopened = VideoStudioModel(
            photos: [], mode: .multiClip, service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary, overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages, creationStore: store, restoring: row
        )
        defer { reopened.close() }
        #expect(abs(reopened.currentTime - 8.4) < 0.0001)
        #expect(reopened.inspectorTarget == .none)
        #expect(!reopened.presentsSheet)
        #expect(!reopened.canUndo)
        #expect(!reopened.canRedo)
        #expect(reopened.recipe.clips[1].speed == 2)
        // The stored playhead is not part of the project being edited.
        #expect(reopened.recipe.playhead == nil)
    }
}

/// FS-12.18 §2: the draft and the export are one row.
@MainActor
struct VideoDraftExportTests {
    /// Export marks the draft row exported — the same row, not a new one.
    @Test func exportMarksTheDraftRowExported() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let model = VideoStudioModelFixture.model(creationStore: store)
        defer { model.close() }
        #expect(await model.saveDraftNow())
        #expect(try store.fetch(id: model.creationID)?.isDraft == true)

        model.recordExport(assetID: "exported-video", now: 500)

        let rows = try store.fetchOrdered(kind: .video)
        #expect(rows.count == 1)
        #expect(rows.first?.id == model.creationID)
        #expect(rows.first?.exportedAt == 500)
        #expect(rows.first?.assetId == "exported-video")
        #expect(rows.first?.isDraft == false)
    }

    /// FS-12.18 AC-12: exported once, opened, Speed changed, Back — the row
    /// carries the new Speed, is still exported (no Draft label) and is
    /// still the only row; exporting again updates that row.
    @Test func editAfterExportKeepsOneRow() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        let first = VideoStudioModelFixture.model(creationStore: store)
        first.recordExport(assetID: "v1", now: 500)
        first.close()

        let row: Creation = try #require(try store.fetch(id: first.creationID))
        let dependencies = AppDependencies.preview()
        let reopened = VideoStudioModel(
            photos: [], mode: .multiClip, service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary, overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages, creationStore: store, restoring: row
        )
        defer { reopened.close() }
        reopened.setSpeed(2, for: reopened.recipe.clips[1].id)
        #expect(await reopened.back() == .close)

        var rows = try store.fetchOrdered(kind: .video)
        #expect(rows.count == 1)
        #expect(rows.first?.videoRecipe?.clips[1].speed == 2)
        #expect(rows.first?.isDraft == false)
        #expect(rows.first?.assetId == "v1")

        reopened.recordExport(assetID: "v2", now: 900)
        rows = try store.fetchOrdered(kind: .video)
        #expect(rows.count == 1)
        #expect(rows.first?.assetId == "v2")
        #expect(rows.first?.exportedAt == 900)
    }
}

/// FS-12.18 §6: a write that fails.
@MainActor
struct VideoDraftFailureTests {
    private func failingModel() -> (VideoStudioModel, DraftWriteLog) {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        log.failure = DraftWriteLog.DiskFull()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) }, sleep: { try await Task.sleep(for: $0 / 20) })
        return (model, log)
    }

    /// FS-12.18 AC-8: the disk is full — the banner comes up, and the
    /// project in memory keeps the edit and takes the next one.
    @Test func failedSaveShowsBannerAndKeepsEditing() async throws {
        let (model, _) = failingModel()
        let clip2 = model.recipe.clips[1].id
        model.setSpeed(2, for: clip2)
        #expect(await VideoDraftAutosaveTests.eventually { model.hasFailedDraftSave })
        #expect(model.recipe.clips[1].speed == 2)
        model.setSpeed(3, for: clip2)
        #expect(model.recipe.clips[1].speed == 3)
    }

    /// FS-12.18 AC-8: once the disk has room, Try Again writes every
    /// change and the banner goes.
    @Test func tryAgainClearsTheBanner() async throws {
        let (model, log) = failingModel()
        let clip2 = model.recipe.clips[1].id
        model.setSpeed(2, for: clip2)
        #expect(await VideoDraftAutosaveTests.eventually { model.hasFailedDraftSave })
        model.setEffect(.zoomIn, for: clip2)

        log.failure = nil
        model.retryDraftSave()

        #expect(await VideoDraftAutosaveTests.eventually { !model.hasFailedDraftSave })
        let stored = try #require(log.writes.last?.videoRecipe)
        #expect(stored.clips[1].speed == 2)
        #expect(stored.clips[1].effect == .zoomIn)
    }
}

/// FS-12.18 §6: Back when the write fails.
@MainActor
struct VideoDraftBackFailureTests {
    /// FS-12.18 AC-9: the write still fails — Back keeps the studio open
    /// (the screen asks Try Again · Leave Without Saving), and the stored
    /// row is the last write that worked.
    @Test func backWithAFailedSaveStaysOpen() async throws {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) })
        let clip2 = model.recipe.clips[1].id
        model.setSpeed(2, for: clip2)
        #expect(await model.saveDraftNow())

        log.failure = DraftWriteLog.DiskFull()
        model.setSpeed(3, for: clip2)
        #expect(await model.back() == .saveFailed)
        #expect(model.hasFailedDraftSave)
        #expect(log.writes.count == 1)
        #expect(log.writes.last?.videoRecipe?.clips[1].speed == 2)

        // Try Again once there is room: Back goes through.
        log.failure = nil
        #expect(await model.back() == .close)
        #expect(log.writes.last?.videoRecipe?.clips[1].speed == 3)
    }
}

/// Review findings on the draft path (data-migration, 2026-10-04).
@MainActor
struct VideoDraftRobustnessTests {
    /// A clip `load()` could not find this session goes back into the
    /// stored draft at its place — the stored project never shrinks.
    @Test func clipsLeftOutAtLoadStayInTheDraft() throws {
        let clips = VideoStudioModelFixture.photoClips(3)
        let model = VideoStudioModelFixture.model(clips: [clips[0], clips[2]])
        model.clipsLeftOutAtLoad = [(index: 1, clip: clips[1])]
        let row = try model.draftSnapshot()
        #expect(row.videoRecipe?.clips.map(\.id) == clips.map(\.id))
        #expect(row.videoRecipe?.transitions.count == 2)
    }

    /// A recipe that will not encode is a failed save: the banner comes up
    /// and Back does not close on nothing.
    @Test func aRecipeThatWillNotEncodeFailsTheSave() async {
        let model = VideoStudioModelFixture.model()
        let log = DraftWriteLog()
        model.drafts = VideoDraftAutosave(write: { try log.write($0) })
        model.recipe.videoVolume = .nan
        #expect(await model.saveDraftNow() == false)
        #expect(model.hasFailedDraftSave)
        #expect(log.writes.isEmpty)
    }

    /// A boundary that cannot be read keeps its place with defaults; the
    /// ones after it do not slide.
    @Test func aBrokenTransitionKeepsItsPlace() throws {
        let ids = (1...4).map { "0000000\($0)-0000-0000-0000-000000000000" }
        let clips = ids.map { "{\"id\":\"\($0)\",\"assetID\":\"a\",\"kind\":\"photo\"}" }.joined(separator: ",")
        let json = """
        {"clips":[\(clips)],
         "transitions":[{"kind":"crossfade","duration":0.5},{"kind":"teleport"},{"kind":"wipe","duration":1}],
         "markers":[{"time":3}]}
        """
        let recipe = try JSONDecoder().decode(VideoProjectRecipe.self, from: Data(json.utf8))
        #expect(recipe.transitions.map(\.kind) == [.crossfade, .none, .wipe])
        #expect(recipe.transitions[2].duration == 1)
        #expect(recipe.markers.map(\.time) == [3])
    }
}

extension VideoDraftRobustnessTests {
    /// Opening a draft is not editing it: the init's own recipe writes —
    /// taking the stored playhead out — schedule no write, so the row's
    /// edit date does not move.
    @Test func openingADraftWritesNothing() async throws {
        let store = CreationStore(database: try AppDatabase.makeEmpty())
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(2))
        recipe.playhead = 2
        try store.saveDraft(try Creation.video(recipe: recipe, assetId: nil, id: "draft", createdAt: 1, now: 100))
        let row: Creation = try #require(try store.fetch(id: "draft"))
        let dependencies = AppDependencies.preview()
        let model = VideoStudioModel(
            photos: [], mode: .multiClip, service: dependencies.videoStudio,
            photoLibrary: dependencies.photoLibrary, overlayFontRecents: dependencies.overlayFontRecents,
            overlayImages: dependencies.overlayImages, creationStore: store, restoring: row
        )
        defer { model.close() }
        #expect(model.drafts?.isSavePending == false)
        #expect(model.currentTime == 2)
    }
}
