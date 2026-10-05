import Foundation
import os
import Testing
@testable import ShotDex

/// FS-12.14 §9's project: Falls photo 0–3.0 · Coast video 3.0–9.2 · Lake
/// video 9.2–14.2 · Night photo 14.2–17.2 · Forest video 17.2–24.0; and the
/// captions the plan's ACs name, in source seconds of their clips.
enum CaptionFixture {
    static func recipe() -> VideoProjectRecipe {
        VideoStudioModelFixture.mediaSampleRecipe()
    }

    /// Words Coast and Lake say (source seconds).
    static let coastWords: [CaptionWord] = [
        .init(text: "The", start: 0.2, end: 0.4), .init(text: "road", start: 0.42, end: 0.7),
        .init(text: "to", start: 0.72, end: 0.8), .init(text: "Vík", start: 0.82, end: 1.2),
        .init(text: "starts", start: 3.0, end: 3.38), .init(text: "right", start: 3.4, end: 3.7),
        .init(text: "here.", start: 3.72, end: 4.4),
    ]
    static let lakeWords: [CaptionWord] = [
        .init(text: "Listen", start: 1.6, end: 2.0), .init(text: "to", start: 2.02, end: 2.4),
        .init(text: "that", start: 2.8, end: 3.1), .init(text: "water.", start: 3.12, end: 3.9),
    ]

    /// The lane as recognition leaves it for Coast and Lake.
    static func lane(in recipe: VideoProjectRecipe) -> VideoCaptionLane {
        var lane = VideoCaptionLane()
        lane.cues = CaptionChunker.cues(from: coastWords, clipID: recipe.clips[1].id)
            + CaptionChunker.cues(from: lakeWords, clipID: recipe.clips[2].id)
        lane.recognition = CaptionRecognitionState(
            plannedClipIDs: [recipe.clips[1].id, recipe.clips[2].id, recipe.clips[4].id],
            finishedClipIDs: [recipe.clips[1].id, recipe.clips[2].id, recipe.clips[4].id]
        )
        return lane
    }
}

/// A permission that answers as told and counts how often it was asked.
final class CountingAuthorizer: SpeechAuthorizing, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(status: SpeechAuthorization, answer: SpeechAuthorization, asked: Int)>
    init(status: SpeechAuthorization = .notDetermined, answer: SpeechAuthorization = .authorized) {
        state = OSAllocatedUnfairLock(initialState: (status, answer, 0))
    }
    var asked: Int { state.withLock { $0.asked } }
    func status() -> SpeechAuthorization { state.withLock { $0.status } }
    func request() async -> SpeechAuthorization {
        state.withLock { value in
            value.asked += 1
            value.status = value.answer
            return value.answer
        }
    }
}

/// A recogniser over fixed words by asset, with an optional pause per clip
/// and clips that cannot be read.
@MainActor
enum FakeCaptions {
    static func session(
        authorizer: CountingAuthorizer = CountingAuthorizer(),
        words: [String: [CaptionWord]] = ["Coast": CaptionFixture.coastWords, "Lake": CaptionFixture.lakeWords, "Forest": []],
        unreadable: Set<String> = [],
        delay: Duration = .zero,
        log: OSAllocatedUnfairLock<[UUID]> = OSAllocatedUnfairLock(initialState: []),
        assetOf: @escaping @Sendable (UUID) -> String = { _ in "" },
        languages: [String] = ["en-US", "de-DE", "vi-VN"],
        available: Set<String> = ["en-US", "de-DE"]
    ) -> VideoCaptionSession {
        VideoCaptionSession(
            authorizer: authorizer,
            transcribe: { clip, _ in
                log.withLock { $0.append(clip.id) }
                if delay > .zero { try await Task.sleep(for: delay) }
                let asset = assetOf(clip.id)
                if unreadable.contains(asset) { return .unreadable }
                return .words(words[asset] ?? [])
            },
            isAvailable: { available.contains($0) },
            supportedLanguages: { languages }
        )
    }

    /// The model over §9's project with `session`.
    static func model(_ make: (VideoProjectRecipe) -> VideoCaptionSession, configure: (inout VideoProjectRecipe) -> Void = { _ in }) -> VideoStudioModel {
        var recipe = CaptionFixture.recipe()
        configure(&recipe)
        let session = make(recipe)
        return VideoStudioModelFixture.model(clips: recipe.clips, configure: { stored in
            stored = recipe
        }, captions: session)
    }

    static func assets(_ recipe: VideoProjectRecipe) -> @Sendable (UUID) -> String {
        let map = Dictionary(recipe.clips.map { ($0.id, $0.assetID) }, uniquingKeysWith: { first, _ in first })
        return { map[$0] ?? "" }
    }

    static func settle(_ model: VideoStudioModel) async {
        await model.captions.waitUntilDone()
        for _ in 0..<50 where model.captions.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

// MARK: - Task 3 · AC-1

@MainActor
struct CaptionRecognitionPlanTests {
    /// Photos, freeze frames and muted clips are never read.
    @Test func skipsPhotosFreezesAndMutedClips() {
        var recipe = CaptionFixture.recipe()
        recipe.clips[4].isMuted = true
        var freeze = VideoClip(assetID: "Coast", kind: .freeze)
        freeze.photoDuration = 2
        recipe.clips.append(freeze)
        #expect(CaptionRecognitionPlan.clipIDs(in: recipe) == [recipe.clips[1].id, recipe.clips[2].id])
        // The trim window, in source seconds.
        recipe.clips[1].trimStart = 1
        #expect(CaptionRecognitionPlan.sourceWindow(of: recipe.clips[1]) == 1...6.2)
    }

    /// Progress runs by the planned clips' length: Coast 6.2 of 18.0 s.
    @Test func progressCountsClips() {
        let recipe = CaptionFixture.recipe()
        var state = CaptionRecognitionState(plannedClipIDs: [recipe.clips[1].id, recipe.clips[2].id, recipe.clips[4].id])
        #expect(CaptionRecognitionPlan.progress(state, in: recipe) == 0)
        state.finishedClipIDs = [recipe.clips[1].id]
        #expect(abs(CaptionRecognitionPlan.progress(state, in: recipe) - 6.2 / 18) < 1e-9)
        let halfway = CaptionRecognitionPlan.progress(state, in: recipe, current: (recipe.clips[2].id, 0.5))
        #expect(abs(halfway - 8.7 / 18) < 1e-9)
        #expect(CaptionRecognitionPlan.percent(0.999, isComplete: false) == 99)
        #expect(CaptionRecognitionPlan.percent(1, isComplete: true) == 100)
    }
}

@MainActor
struct VideoCaptionSessionTests {
    /// AC-1: the system is asked once; the lane comes as one undo step and
    /// fills clip by clip — Coast and Lake, Forest silent.
    @Test func asksPermissionOnce() async {
        let authorizer = CountingAuthorizer()
        let model = FakeCaptions.model { recipe in FakeCaptions.session(authorizer: authorizer, assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        #expect(authorizer.asked == 1)
        model.clearSelection()
        // Undone and asked again: the answer is known, no second prompt.
        model.undo()
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        #expect(authorizer.asked == 1)
        #expect(model.recipe.captions != nil)
    }

    @Test func laneAppearsAsOneUndoStep() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(assetOf: FakeCaptions.assets(recipe)) }
        let before = model.history.undoEntries.count
        await model.startAutoCaptions()
        #expect(model.inspectorTarget == .caption)
        await FakeCaptions.settle(model)
        #expect(model.history.undoEntries.count == before + 1)
        let lane = try! #require(model.recipe.captions)
        #expect(lane.cues.map(\.text) == ["The road to Vík", "starts right here.", "Listen to", "that water."])
        #expect(lane.recognition.isComplete)
        #expect(model.placedCaptions.map { ($0.start * 10).rounded() / 10 } == [3.2, 6.0, 10.8, 12.0])
        // Undo takes the lane — and nothing else.
        model.undo()
        #expect(model.recipe.captions == nil)
        #expect(model.recipe.clips.count == 5)
    }

    /// What arrives while the user edits reaches the snapshots Undo brings
    /// back, and adds no step (plan K4).
    @Test func resultsReachTheUndoSnapshots() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(delay: .milliseconds(60), assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        // An edit while the first clip is being read.
        model.pushUndo()
        model.setVideoVolume(0.5)
        await FakeCaptions.settle(model)
        let steps = model.history.undoEntries.count
        model.undo()
        #expect(model.history.undoEntries.count == steps - 1)
        #expect(model.recipe.captions?.cues.count == 4, "the volume step's snapshot has every cue")
    }

    // MARK: Task 4 · AC-2

    @Test func deniedShowsCardNoLaneNoUndo() async {
        let model = FakeCaptions.model { recipe in
            FakeCaptions.session(authorizer: CountingAuthorizer(answer: .denied), assetOf: FakeCaptions.assets(recipe))
        }
        let before = model.history.undoEntries.count
        await model.startAutoCaptions()
        #expect(model.captionCard == .denied)
        #expect(model.recipe.captions == nil)
        #expect(model.history.undoEntries.count == before)
        #expect(model.inspectorTarget == .caption, "the panel says why")
    }

    @Test func restrictedHasNoSettingsButton() async {
        let model = FakeCaptions.model { recipe in
            FakeCaptions.session(authorizer: CountingAuthorizer(status: .restricted), assetOf: FakeCaptions.assets(recipe))
        }
        await model.startAutoCaptions()
        #expect(model.captionCard == .restricted)
        #expect(model.recipe.captions == nil)
    }

    /// §8: no model for any language — the row is dimmed and does nothing.
    @Test func noModelDimsTheRow() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(assetOf: FakeCaptions.assets(recipe), available: []) }
        #expect(model.canAutoCaption == false)
        await model.startAutoCaptions()
        #expect(model.recipe.captions == nil)
        #expect(model.inspectorTarget == .none)
    }

    // MARK: Task 5 · AC-4

    @Test func languageChangeIsOneUndoStep() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        let before = model.history.undoEntries.count
        model.changeCaptionLanguage("vi-VN")
        #expect(model.recipe.captions?.language == "en-US", "not on this device: nothing changes")
        #expect(model.history.undoEntries.count == before)
        model.changeCaptionLanguage("de-DE")
        await FakeCaptions.settle(model)
        #expect(model.recipe.captions?.language == "de-DE")
        #expect(model.recipe.captions?.cues.count == 4)
        #expect(model.history.undoEntries.count == before + 1)
        model.undo()
        #expect(model.recipe.captions?.language == "en-US")
    }

    @Test func editedCuesTriggerConfirmation() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        #expect(model.editedCaptionCount == 0)
        let id = model.recipe.captions!.cues[1].id
        model.setCaptionText("starts right there.", for: id)
        #expect(model.editedCaptionCount == 1)
        #expect(model.recipe.captions!.cues[1].words == nil)
    }

    // MARK: Task 10 · AC-16

    @Test func burnToggleIsOneUndoStep() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        let before = model.history.undoEntries.count
        model.setCaptionBurnsIn(false)
        #expect(model.recipe.captions?.burnsIn == false)
        #expect(model.history.undoEntries.count == before + 1)
        model.setCaptionBurnsIn(false)
        #expect(model.history.undoEntries.count == before + 1, "no change, no step")
        model.undo()
        #expect(model.recipe.captions?.burnsIn == true)
    }

    // MARK: Task 12 · AC-11

    /// ✕ at 40 % stops within a second, the lane goes, and the undo depth
    /// is what it was when the panel opened.
    @Test func cancelRemovesLaneAndRestoresUndoDepth() async throws {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(delay: .seconds(2), assetOf: FakeCaptions.assets(recipe)) }
        let before = model.history.undoEntries.count
        await model.startAutoCaptions()
        #expect(model.captions.isRunning)
        let started = ContinuousClock.now
        model.cancelSession()
        await model.captions.waitUntilDone()
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(model.captions.isRunning == false)
        #expect(model.recipe.captions == nil)
        #expect(model.history.undoEntries.count == before)
        #expect(model.inspectorTarget == .none)
    }

    @Test func cancelStopsWithinOneSecond() async {
        let log = OSAllocatedUnfairLock<[UUID]>(initialState: [])
        let model = FakeCaptions.model { recipe in FakeCaptions.session(delay: .seconds(3), log: log, assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        try? await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        model.captions.cancel()
        await model.captions.waitUntilDone()
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(log.withLock { $0.count } == 1, "the next clip is never started")
    }

    /// ✓ while it runs: the panel closes, the lane goes on filling.
    @Test func doneKeepsRecognising() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(delay: .milliseconds(80), assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        model.commitSession()
        #expect(model.inspectorTarget == .none)
        await FakeCaptions.settle(model)
        #expect(model.recipe.captions?.cues.count == 4)
    }

    // MARK: Task 13 · AC-12

    @Test func continueTranscribesOnlyRemainingClips() async {
        let log = OSAllocatedUnfairLock<[UUID]>(initialState: [])
        var assets: (@Sendable (UUID) -> String)?
        let model = FakeCaptions.model { recipe in
            assets = FakeCaptions.assets(recipe)
            return FakeCaptions.session(log: log, assetOf: assets!)
        } configure: { recipe in
            var lane = VideoCaptionLane()
            lane.cues = CaptionChunker.cues(from: CaptionFixture.coastWords, clipID: recipe.clips[1].id)
            lane.recognition = CaptionRecognitionState(
                plannedClipIDs: [recipe.clips[1].id, recipe.clips[2].id, recipe.clips[4].id],
                finishedClipIDs: [recipe.clips[1].id],
                stoppedAtPercent: 58
            )
            recipe.captions = lane
        }
        #expect(model.captionCard == .stopped(percent: 58))
        model.continueCaptions()
        await FakeCaptions.settle(model)
        #expect(log.withLock { $0 } == [model.recipe.clips[2].id, model.recipe.clips[4].id])
        #expect(model.recipe.captions?.recognition.stoppedAtPercent == nil)
        #expect(model.recipe.captions?.cues.count == 4)
    }

    @Test func stoppedStateSurvivesEncodeDecode() async throws {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(delay: .milliseconds(200), assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        try await Task.sleep(for: .milliseconds(300))
        model.stopCaptionsForLeaving()
        let lane = try #require(model.recipe.captions)
        #expect(lane.recognition.stoppedAtPercent != nil)
        let reopened = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONEncoder().encode(model.recipe))
        #expect(reopened.captions == lane)
        #expect(reopened.captions?.recognition.remainingClipIDs.isEmpty == false)
    }

    // MARK: Task 14 · AC-13

    @Test func unreadableClipIsSkippedWithRetry() async {
        let model = FakeCaptions.model { recipe in FakeCaptions.session(unreadable: ["Lake"], assetOf: FakeCaptions.assets(recipe)) }
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        #expect(model.captions.unreadableClipIDs == [model.recipe.clips[2].id])
        #expect(model.recipe.captions?.cues.map(\.text) == ["The road to Vík", "starts right here."])
        #expect(model.captions.isRunning == false, "no spinner left running")
        #expect(model.recipe.captions?.recognition.isComplete == true)
        #expect(VideoStudioCopy.clipsUnreadable(1) == "1 clip couldn't be read — it's in iCloud.")
    }

    // MARK: Task 15 · AC-14

    @Test func noSpeechCreatesNoLane() async {
        let model = FakeCaptions.model { recipe in
            FakeCaptions.session(words: [:], assetOf: FakeCaptions.assets(recipe))
        }
        let before = model.history.undoEntries.count
        await model.startAutoCaptions()
        await FakeCaptions.settle(model)
        #expect(model.recipe.captions == nil)
        #expect(model.captionCard == .noSpeech)
        #expect(model.history.undoEntries.count == before)
        #expect(VideoStudioCopy.noSpeechFound == "No speech found in these clips.")
    }
}

// MARK: - Task 5 · AC-4

struct CaptionLanguagesTests {
    @Test func unavailableIsDimAndInert() {
        let options = CaptionLanguages.options(supported: ["en-US", "vi-VN", "en-GB"], isAvailable: { $0 == "en-US" })
        let english = try! #require(options.first { $0.id == "en-US" })
        let vietnamese = try! #require(options.first { $0.id == "vi-VN" })
        #expect(english.name == "English (US)" && english.isAvailable)
        #expect(vietnamese.name == "Tiếng Việt" && !vietnamese.isAvailable)
        #expect(VideoStudioCopy.notOnThisDevice == "Not on this iPhone")
    }

    @Test func defaultIsDeviceLanguageIfModelElseEnUS() {
        #expect(CaptionLanguages.defaultLanguage(preferred: ["de-DE"], isAvailable: { ["de-DE", "en-US"].contains($0) }) == "de-DE")
        #expect(CaptionLanguages.defaultLanguage(preferred: ["vi-VN"], isAvailable: { $0 == "en-US" }) == "en-US")
        #expect(CaptionLanguages.defaultLanguage(preferred: ["vi"], isAvailable: { $0 == "vi-VN" }) == "vi-VN")
        #expect(CaptionLanguages.defaultLanguage(preferred: ["vi-VN"], isAvailable: { _ in false }) == nil)
    }
}

// MARK: - Task 6 · AC-6

@MainActor
struct CaptionTimelineTests {
    private func project() -> VideoProjectRecipe {
        var recipe = CaptionFixture.recipe()
        recipe.captions = CaptionFixture.lane(in: recipe)
        return recipe
    }

    private func span(_ text: String, in recipe: VideoProjectRecipe) -> [Double]? {
        CaptionTimeline.placed(recipe.captions, in: recipe).first { $0.cue.text == text }.map { [($0.start * 10).rounded() / 10, ($0.end * 10).rounded() / 10] }
    }

    /// AC-6: one more second off clip 2's head moves "starts right here."
    /// from 6.0–7.4 to 5.0–6.4, words unchanged.
    @Test func trimHeadShiftsCue() {
        var recipe = project()
        #expect(span("starts right here.", in: recipe) == [6.0, 7.4])
        recipe.clips[1].trimStart = 1
        #expect(span("starts right here.", in: recipe) == [5.0, 6.4])
    }

    /// A cue whose words fall inside the trimmed second hides — and comes
    /// back with the trim.
    @Test func cueInsideTrimmedSecondHides() {
        var recipe = project()
        #expect(span("The road to Vík", in: recipe) != nil)
        recipe.clips[1].trimStart = 1.3
        #expect(span("The road to Vík", in: recipe) == nil)
        #expect(recipe.captions?.cues.contains { $0.text == "The road to Vík" } == true, "hidden, not deleted")
        recipe.clips[1].trimStart = 0
        #expect(span("The road to Vík", in: recipe) != nil)
    }

    /// One Undo brings back both the trim and where the captions were.
    @Test func oneUndoRestoresBoth() {
        let model = VideoStudioModelFixture.model(clips: project().clips, configure: { $0 = self.project() })
        let clip = model.recipe.clips[1]
        model.pushUndo()
        model.setTrim(start: 1, end: clip.trimEnd ?? 6.2, for: clip.id)
        #expect(model.placedCaptions.first { $0.cue.text == "starts right here." }.map { ($0.start * 10).rounded() / 10 } == 5.0)
        model.undo()
        #expect(model.recipe.clips[1].trimStart == 0)
        #expect(model.placedCaptions.first { $0.cue.text == "starts right here." }.map { ($0.start * 10).rounded() / 10 } == 6.0)
    }

    @Test func deleteClipDeletesItsCues() {
        let model = VideoStudioModelFixture.model(clips: project().clips, configure: { $0 = self.project() })
        let lake = model.recipe.clips[2].id
        model.deleteClip(lake)
        #expect(model.recipe.captions?.cues.contains { $0.clipID == lake } == false)
        #expect(model.recipe.captions?.cues.count == 2)
        #expect(model.canUndo)
        model.undo()
        #expect(model.recipe.clips.count == 5)
        #expect(model.recipe.captions?.cues.count == 4, "\(String(describing: model.recipe.captions?.cues.map(\.text)))")
    }

    /// A split clip's cues go to the piece whose source holds their start.
    @Test func splitClipReassignsBySourceTime() {
        let model = VideoStudioModelFixture.model(clips: project().clips, configure: { $0 = self.project() })
        model.seek(to: 5.0) // Coast, source 2.0
        model.splitClipUnderPlayhead()
        let pieces = model.recipe.clips.filter { $0.assetID == "Coast" }
        #expect(pieces.count == 2)
        let cues = model.recipe.captions!.cues
        #expect(cues.first { $0.text == "The road to Vík" }?.clipID == pieces[0].id)
        #expect(cues.first { $0.text == "starts right here." }?.clipID == pieces[1].id)
        #expect(model.placedCaptions.map { ($0.start * 10).rounded() / 10 } == [3.2, 6.0, 10.8, 12.0])
    }

    /// A duplicated clip carries copies of its captions, under new ids.
    @Test func duplicateClipCopiesCues() {
        let model = VideoStudioModelFixture.model(clips: project().clips, configure: { $0 = self.project() })
        model.selectClip(model.recipe.clips[2].id)
        model.duplicateSelectedClip()
        let copies = model.recipe.captions!.cues.filter { $0.clipID == model.recipe.clips[3].id }
        #expect(copies.map(\.text) == ["Listen to", "that water."])
        #expect(Set(copies.map(\.id)).isDisjoint(with: Set(model.recipe.captions!.cues.filter { $0.clipID == model.recipe.clips[2].id }.map(\.id))))
    }

    /// Twice the speed: a cue plays in half the time.
    @Test func speedScalesCue() {
        var recipe = project()
        recipe.clips[1].speed = 2
        #expect(span("starts right here.", in: recipe) == [4.5, 5.2])
    }

    /// Dragged on C1, a block never overlaps the one beside it nor leaves
    /// its clip.
    @Test func dragNeverOverlapsNeighbour() {
        let recipe = project()
        let lake = recipe.captions!.cues.first { $0.text == "Listen to" }!
        let moved = try! #require(CaptionTimeline.dragged(lake.id, edge: .body, by: 5, in: recipe))
        // "that water." starts at 12.0: "Listen to" (0.8 s) ends there at most.
        var after = recipe
        after.captions!.cues[after.captions!.cues.firstIndex { $0.id == lake.id }!] = moved
        #expect(span("Listen to", in: after) == [11.2, 12.0])
        let back = CaptionTimeline.dragged(lake.id, edge: .body, by: -5, in: recipe)!
        after.captions!.cues[after.captions!.cues.firstIndex { $0.id == lake.id }!] = back
        #expect(span("Listen to", in: after) == [9.2, 10.0], "never before its clip starts")
        let stretched = CaptionTimeline.dragged(lake.id, edge: .end, by: 3, in: recipe)!
        after.captions!.cues[after.captions!.cues.firstIndex { $0.id == lake.id }!] = stretched
        #expect(span("Listen to", in: after) == [10.8, 12.0])
    }

    /// AC-17: the overview's marks are the cues, where they play.
    @Test func overviewMarksMatchCues() {
        let recipe = project()
        let placed = CaptionTimeline.placed(recipe.captions, in: recipe)
        #expect(placed.count == recipe.captions!.cues.count)
        #expect(placed.map(\.start) == placed.map(\.start).sorted())
    }
}

// MARK: - Tasks 7 · 8 · AC-7, AC-8

@MainActor
struct CaptionEditingTests {
    private func model() -> VideoStudioModel {
        var recipe = CaptionFixture.recipe()
        recipe.captions = CaptionFixture.lane(in: recipe)
        return VideoStudioModelFixture.model(clips: recipe.clips, configure: { $0 = recipe })
    }

    /// AC-7: "starts right here." split at 6.7 s is "starts right" 6.0–6.7
    /// and "here." 6.7–7.4; one Undo makes it one block again.
    @Test func splitAtNearestWordBoundary() {
        let model = model()
        let cue = model.recipe.captions!.cues.first { $0.text == "starts right here." }!
        model.selectCaption(cue.id)
        model.seek(to: 6.7)
        #expect(model.isItemCommandEnabled(.split))
        model.splitSelectedCaption()
        let parts = model.placedCaptions.filter { $0.clipIndex == 1 && $0.start >= 6 }
        #expect(parts.map(\.cue.text) == ["starts right", "here."])
        #expect(parts.map { [($0.start * 10).rounded() / 10, ($0.end * 10).rounded() / 10] } == [[6.0, 6.7], [6.7, 7.4]])
        model.undo()
        #expect(model.recipe.captions!.cues.contains { $0.text == "starts right here." })
    }

    @Test func splitDisabledOutsideCue() {
        let model = model()
        let cue = model.recipe.captions!.cues.first { $0.text == "starts right here." }!
        model.selectCaption(cue.id)
        model.seek(to: 8.5)
        #expect(model.isItemCommandEnabled(.split) == false)
    }

    /// AC-8: "Listen to" + "that water." is "Listen to that water." 10.8–13.1.
    @Test func mergeJoinsTextAndUnionsTime() {
        let model = model()
        let cue = model.recipe.captions!.cues.first { $0.text == "Listen to" }!
        model.selectCaption(cue.id)
        #expect(model.isItemCommandEnabled(.merge))
        model.mergeSelectedCaption()
        let merged = model.placedCaptions.first { $0.cue.id == cue.id }!
        #expect(merged.cue.text == "Listen to that water.")
        #expect([(merged.start * 10).rounded() / 10, (merged.end * 10).rounded() / 10] == [10.8, 13.1])
        #expect(model.recipe.captions!.cues.count == 3)
    }

    @Test func mergeDisabledOnLast() {
        let model = model()
        let last = model.placedCaptions.last!.cue
        model.selectCaption(last.id)
        #expect(model.isItemCommandEnabled(.merge) == false)
    }

    /// Delete with no cue selected — the lane chosen by C1's label — takes
    /// the whole lane, one undo step.
    @Test func deleteLaneFromLabel() {
        let model = model()
        model.openCaptions(cue: nil)
        let before = model.history.undoEntries.count
        model.deleteSelectedCaption()
        #expect(model.recipe.captions == nil)
        #expect(model.history.undoEntries.count == before + 1)
        model.undo()
        #expect(model.recipe.captions?.cues.count == 4)
    }

    /// The Edit list's time: selects the cue and moves the playhead to it.
    @Test func editListTimeSeeks() {
        let model = model()
        let cue = model.recipe.captions!.cues.first { $0.text == "Listen to" }!
        model.selectCaption(cue.id, seeks: true)
        #expect(model.selectedCaptionID == cue.id)
        #expect(abs(model.currentTime - 10.8) < 0.01)
        #expect(model.sessionFooterTitle?.name == "Caption 3")
        #expect(model.sessionFooterTitle?.detail == "0:10.8 → 0:11.6")
    }
}

// MARK: - Task 9 · AC-9

struct CaptionLayoutTests {
    /// AC-9: Box, 6 %, Bottom on 1080×1920 — text 65 ± 3 px, centred on
    /// y 1632 ± 19.
    @Test func boxSixPercentBottomOn1080x1920() {
        var lane = VideoCaptionLane()
        lane.style = .box
        let frame = CGSize(width: 1080, height: 1920)
        #expect(abs(CaptionLayout.textHeight(frame: frame, sizePercent: 6) - 64.8) < 0.01)
        let typeset = VideoCaptionRenderer.typeset("starts right here.", lane: lane, frame: frame)
        #expect(abs(typeset.textHeight - 64.8) < 3)
        #expect(abs(typeset.plate.midY - 1632) < 19)
        #expect(abs(typeset.plate.midX - 540) < 1)
    }

    /// Word by Word shows each word from when it is said.
    @Test func wordByWordRevealsAtWordTimes() {
        let cue = CaptionLayout.Cue(id: UUID(), start: 6.0, end: 7.4, text: "starts right here.", words: [
            .init(text: "starts", start: 6.0, end: 6.38), .init(text: "right", start: 6.4, end: 6.7), .init(text: "here.", start: 6.72, end: 7.4),
        ])
        #expect(CaptionLayout.visibleWordCount(cue, at: 6.1) == 1)
        #expect(CaptionLayout.visibleWordCount(cue, at: 6.5) == 2)
        #expect(CaptionLayout.visibleWordCount(cue, at: 7.0) == 3)
    }

    /// A cue typed over has no word times: its words share its time evenly.
    @Test func editedCueSpreadsWordsEvenly() {
        let cue = CaptionCue(clipID: UUID(), sourceStart: 2, sourceEnd: 3.2, text: "one two three", isEdited: true)
        let words = CaptionEditing.evenWords(cue)
        #expect(zip(words.map(\.start), [2, 2.4, 2.8]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(abs(words.last!.end - 3.2) < 1e-9)
    }
}
