import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// The looks the FS-12.06c tests use.
enum VideoLookSamples {
    /// A My Look as the tests use it: Night Teal is cool and teal, Moody
    /// Coast the spec's sample (Exposure +0.3 · Contrast +20 · Velvia ·
    /// Grain 25 · Vignette −20).
    static var nightTeal: VideoLook {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.warmth = -0.35
        recipe.adjustments.tint = -0.2
        recipe.adjustments.contrast = 0.15
        recipe.color.mixer.aqua.saturation = 0.4
        return VideoLook(.myLook(sourceID: nightTealID, name: "Night Teal", isImported: false, recipe: recipe))
    }

    static var moodyCoast: PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.3
        recipe.adjustments.contrast = 0.2
        recipe.filter = .velvia
        recipe.filterIntensity = 1
        recipe.adjustments.grain = 0.25
        recipe.adjustments.vignette = -0.2
        return recipe
    }

    static var velvia: VideoLook { VideoLook(.preset(.velvia)) }

    static let nightTealID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!
}

/// FS-12.06c §4, §6: the look slots' rules, apart from any pixel.
@MainActor
struct VideoLookEditingTests {
    static var nightTeal: VideoLook { VideoLookSamples.nightTeal }
    static var moodyCoast: PhotoEditRecipe { VideoLookSamples.moodyCoast }
    static var velvia: VideoLook { VideoLookSamples.velvia }

    /// AC-3: the clip's own look replaces the video's — never both.
    @Test func clipLookReplacesVideoLook() {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(3))
        recipe.look = Self.velvia
        recipe.clips[1].look = Self.nightTeal
        #expect(VideoLookEditing.effectiveLook(for: recipe.clips[0], in: recipe) == Self.velvia)
        #expect(VideoLookEditing.effectiveLook(for: recipe.clips[1], in: recipe) == Self.nightTeal)
        #expect(VideoLookEditing.effectiveLook(for: recipe.clips[2], in: recipe) == Self.velvia)
    }

    /// Original on a clip is a look of its own: that clip has none, the
    /// rest keep the video's.
    @Test func originalOnClipBeatsVideoLook() {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(2))
        recipe.look = Self.velvia
        recipe.clips[0].look = .original
        #expect(VideoLookEditing.effectiveLook(for: recipe.clips[0], in: recipe) == nil)
        #expect(VideoLookEditing.effectiveLook(for: recipe.clips[1], in: recipe) == Self.velvia)
        // And the compositor reads it the same way.
        let render = VideoRenderRecipe(recipe: recipe, renderSize: CGSize(width: 64, height: 36), totalDuration: 1, bakesOverlays: false)
        #expect(render.lookPlan(for: recipe.clips[0].id) == nil)
        #expect(render.lookPlan(for: recipe.clips[1].id) != nil)
        #expect(render.lookPlan(for: nil) != nil)
    }

    /// AC-3: only the clip with a look of its own wears a pill.
    @Test func pillOnlyOnClipsWithOwnLook() {
        let model = VideoStudioModelFixture.model(configure: { recipe in
            recipe.look = Self.velvia
            recipe.clips[1].look = Self.nightTeal
        })
        let pills = model.recipe.clips.map { model.lookPillText(for: $0) }
        #expect(pills == [nil, "Night Teal", nil])
    }

    /// A renamed preset's pill reads the name the editor shows for it.
    @Test func presetPillUsesTheEditorsName() {
        var clip = VideoClip(assetID: "a", kind: .photo)
        clip.look = Self.velvia
        #expect(VideoLookEditing.pillText(for: clip) == PhotoFilter.velvia.displayName)
        #expect(VideoLookEditing.pillText(for: clip, presetName: { _ in "My Velvia" }) == "My Velvia")
    }

    /// A project with looks survives the trip through its stored JSON, and
    /// a look this build cannot read costs that look, not the clip.
    @Test func looksSurviveTheRecipeRoundTrip() throws {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(2))
        recipe.look = VideoLook(.lut(id: "kodak", name: "Kodak 2383"), amount: 0.4)
        recipe.clips[1].look = Self.nightTeal
        let decoded = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.look == recipe.look)
        #expect(decoded.clips[1].look == recipe.clips[1].look)

        var json = try #require(String(data: JSONEncoder().encode(recipe), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"lut\"", with: "\"hologram\"")
        let lenient = try JSONDecoder().decode(VideoProjectRecipe.self, from: Data(json.utf8))
        #expect(lenient.look == nil)
        #expect(lenient.clips.count == 2)
    }

    /// AC-5 (model half): one drag of Amount is one undo step, and a new
    /// look starts at 100 while the chosen one keeps its Amount.
    @Test func amountDragIsOneUndoStep() {
        let model = VideoStudioModelFixture.model()
        model.setVideoLook(VideoLookEditing.chosen(VideoLookSamples.nightTeal.source, replacing: nil))
        #expect(model.recipe.look?.amount == 1)
        let before = model.history.undoEntries.count
        model.beginUndoGroup()
        for value in [0.9, 0.8, 0.7, 0.6, 0.5, 0.4] { model.setVideoLookAmount(value) }
        model.endUndoGroup()
        #expect(model.history.undoEntries.count == before + 1)
        #expect(abs((model.recipe.look?.amount ?? 0) - 0.4) < 0.001)
        model.undo()
        #expect(model.recipe.look?.amount == 1)

        let kept = VideoLookEditing.chosen(VideoLookSamples.nightTeal.source, replacing: VideoLook(VideoLookSamples.nightTeal.source, amount: 0.4))
        #expect(kept.amount == 0.4)
        let fresh = VideoLookEditing.chosen(VideoLookSamples.velvia.source, replacing: VideoLook(VideoLookSamples.nightTeal.source, amount: 0.4))
        #expect(fresh.amount == 1)
        #expect(!VideoLookEditing.showsAmount(nil))
        #expect(!VideoLookEditing.showsAmount(.original))
        #expect(VideoLookEditing.showsAmount(fresh))
    }

    /// AC-12: clip 2 in Night Teal; Look with All Clips, tap Velvia — all
    /// three clips are Velvia and clip 2's pill is gone, in one step.
    @Test func allClipsClearsClipLooksInOneStep() {
        let model = VideoStudioModelFixture.model(configure: { $0.clips[1].look = VideoLookSamples.nightTeal })
        model.toggleToolPanel(.look)
        model.lookTarget = .allClips
        let steps = model.history.undoEntries.count
        model.chooseLook(VideoLookSamples.velvia.source)
        #expect(model.history.undoEntries.count == steps + 1)
        #expect(model.recipe.look == VideoLookSamples.velvia)
        #expect(model.recipe.clips.allSatisfy { $0.look == nil })
        #expect(model.recipe.clips.allSatisfy { VideoLookEditing.effectiveLook(for: $0, in: model.recipe) == VideoLookSamples.velvia })
        #expect(model.recipe.clips.allSatisfy { model.lookPillText(for: $0) == nil })
    }

    /// AC-12: one Undo gives clip 2 its Night Teal back (and the video no look).
    @Test func undoBringsBackNightTeal() {
        let model = VideoStudioModelFixture.model(configure: { $0.clips[1].look = VideoLookSamples.nightTeal })
        model.toggleToolPanel(.look)
        model.chooseLook(VideoLookSamples.velvia.source)
        model.undo()
        #expect(model.recipe.clips[1].look == VideoLookSamples.nightTeal)
        #expect(model.recipe.look == nil)
        #expect(model.lookPillText(for: model.recipe.clips[1]) == "Night Teal")
    }

    /// AC-11: the playhead at 7.0 s is in clip 2 (5 s clips); Look with This
    /// Clip, tap Warm Fjord — only clip 2 has a look, the title's second
    /// line is "Clip 2", and the whole video's look does not move.
    @Test func thisClipTargetsClipUnderPlayhead() {
        let model = VideoStudioModelFixture.model(
            clips: VideoStudioModelFixture.videoClips(3, seconds: 5),
            configure: { $0.look = VideoLookSamples.velvia }
        )
        model.seek(to: 7)
        model.toggleToolPanel(.look)
        #expect(model.lookSubtitle == VideoStudioCopy.wholeVideo)
        model.lookTarget = .thisClip
        #expect(model.lookSubtitle == "Clip 2")
        #expect(model.lookSlot == nil)
        let warmFjord = VideoLook.Source.myLook(sourceID: UUID(), name: "Warm Fjord", isImported: false, recipe: {
            var recipe = PhotoEditRecipe.identity
            recipe.adjustments.warmth = 0.3
            return recipe
        }())
        let steps = model.history.undoEntries.count
        model.chooseLook(warmFjord)
        #expect(model.history.undoEntries.count == steps + 1)
        #expect(model.recipe.clips.map { $0.look?.source } == [nil, warmFjord, nil])
        #expect(model.recipe.look == VideoLookSamples.velvia)
        #expect(model.lookSlot?.source == warmFjord)
        // Amount now moves clip 2's look, not the video's.
        model.setLookAmount(0.5)
        #expect(model.recipe.clips[1].look?.amount == 0.5)
        #expect(model.recipe.look?.amount == 1)
    }

    /// The subtitle names a still the way the viewer header does.
    @Test func subtitleNamesTheClip() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(3))
        model.seek(to: 4)
        model.lookTarget = .thisClip
        #expect(model.lookSubtitle == "Photo 2")
        #expect(VideoLookEditing.targetClipIDs(.thisClip, selectedClipIDs: [], clipUnderPlayhead: nil).isEmpty)
    }

    // MARK: AC-7

    private func myLookTile(_ store: LookPresetStore, named name: String) -> VideoLookTile? {
        VideoLookTile.tiles(shelf: .myLooks, includesOriginal: false, looks: store, luts: ImportedLUTStore())
            .first { $0.name { $0.displayName } == name }
    }

    private func makeStore() -> LookPresetStore {
        LookPresetStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID().uuidString)", isDirectory: true),
            defaults: UserDefaults(suiteName: "video-looks-\(UUID().uuidString)")!
        )
    }

    /// AC-7: the project holds a **copy** of Moody Coast. Saved over in the
    /// photo editor at Contrast 60, the reopened project still renders
    /// Contrast 20, and the tile of the look it came from wears the ring; a
    /// tap on that tile takes the new version — one undo step.
    @Test func copyIgnoresLaterEditUntilRetaken() throws {
        let store = makeStore()
        var moody = VideoLookSamples.moodyCoast
        store.save(moody, name: "Moody Coast")
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.look)
        let tile = try #require(myLookTile(store, named: "Moody Coast"))
        model.chooseLook(tile.look.source)
        model.commitSession()

        moody.adjustments.contrast = 0.6
        store.save(moody, name: "Moody Coast")
        // As reopening a project does: the recipe through its stored JSON.
        let reopened = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONEncoder().encode(model.recipe))
        #expect(reopened.look?.recipe.adjustments.contrast == 0.2)

        let edited = try #require(myLookTile(store, named: "Moody Coast"))
        #expect(edited.isChosen(in: model.recipe.look))
        model.toggleToolPanel(.look)
        let steps = model.history.undoEntries.count
        model.chooseLook(edited.look.source)
        #expect(model.recipe.look?.recipe.adjustments.contrast == 0.6)
        #expect(model.history.undoEntries.count == steps + 1)
        // Tapping it again, with nothing new to take, is not a step.
        model.chooseLook(edited.look.source)
        #expect(model.history.undoEntries.count == steps + 1)
    }

    /// Taking the new version keeps the Amount the look had.
    @Test func retakeKeepsAmount() throws {
        let store = makeStore()
        var moody = VideoLookSamples.moodyCoast
        store.save(moody, name: "Moody Coast")
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.look)
        model.chooseLook(try #require(myLookTile(store, named: "Moody Coast")).look.source)
        model.setLookAmount(0.4)
        moody.adjustments.contrast = 0.6
        store.save(moody, name: "Moody Coast")
        model.chooseLook(try #require(myLookTile(store, named: "Moody Coast")).look.source)
        #expect(model.recipe.look?.amount == 0.4)
        #expect(model.recipe.look?.recipe.adjustments.contrast == 0.6)
    }

    /// The look it came from deleted, the video still renders its copy.
    @Test func deletedSourceStillRenders() throws {
        let store = makeStore()
        store.save(VideoLookSamples.moodyCoast, name: "Moody Coast")
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.look)
        model.chooseLook(try #require(myLookTile(store, named: "Moody Coast")).look.source)
        store.delete(try #require(store.presets.first))
        #expect(myLookTile(store, named: "Moody Coast") == nil)
        let look = try #require(model.recipe.look)
        #expect(VideoLookPlan(look, lutExists: { _ in true }) != nil)
        #expect(VideoLookEditing.pillText(for: { var clip = model.recipe.clips[0]; clip.look = look; return clip }()) == "Moody Coast")
    }

    /// The cache holds 24 tables and lets the least recently used one go.
    @Test func cacheEvictsBeyond24Tables() {
        let cache = VideoLookTableCache()
        #expect(cache.capacity == 24)
        let looks: [PhotoEditRecipe] = (0..<25).map { index in
            var look = PhotoEditRecipe.identity
            look.adjustments.exposure = Double(index + 1) * 0.04
            return look
        }
        for look in looks { _ = cache.table(.whole, of: look) }
        #expect(cache.count == 24)
        #expect(!cache.contains(.init(.whole, of: looks[0])))
        #expect(cache.contains(.init(.whole, of: looks[24])))
        // A look with Clarity costs two tables.
        var clarity = PhotoEditRecipe.identity
        clarity.adjustments.exposure = 1.5
        clarity.filter = .velvia
        clarity.adjustments.clarity = 0.2
        for part in VideoLookBaker.parts(of: clarity) { _ = cache.table(part, of: clarity) }
        #expect(cache.count == 24)
        #expect(!cache.contains(.init(.whole, of: looks[1])))
        #expect(!cache.contains(.init(.whole, of: looks[2])))
    }
}

/// FS-12.06c AC-13: Import Look… is the photo editor's import, and what it
/// adds is chosen for the slot being edited.
@MainActor
struct VideoLookImportTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(in folder: URL) -> LookPresetStore {
        LookPresetStore(directory: folder.appendingPathComponent("store"), defaults: UserDefaults(suiteName: "vimport-\(UUID().uuidString)")!)
    }

    /// The report carries what was added, in file order.
    @Test func applyReturnsAddedIDsInFileOrder() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("A.xmp"), b = folder.appendingPathComponent("B.xmp")
        try LightroomXMPReaderTests.preset(#"crs:Exposure2012="+0.20""#).write(to: a)
        try LightroomXMPReaderTests.preset(#"crs:Exposure2012="+0.40""#).write(to: b)
        let looks = store(in: folder)
        let report = PresetImporter.apply(try PresetImporter.read([a, b]), looks: looks, luts: nil)
        #expect(report.addedLookIDs.count == 2)
        #expect(report.addedLookIDs.compactMap { id in looks.presets.first { $0.id == id }?.name } == ["A", "B"])
    }

    /// AC-13: an .xmp goes to the top of My Looks, wears the XMP badge, and
    /// is the slot's look; a .cube goes to LUTs and is the slot's look.
    @Test func importSelectsFirstAddedForTarget() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let xmp = folder.appendingPathComponent("Golden.xmp")
        try LightroomXMPReaderTests.preset(#"crs:Exposure2012="+0.50""#).write(to: xmp)
        let looks = store(in: folder)
        let luts = ImportedLUTStore()
        let model = VideoStudioModelFixture.model()
        model.toggleToolPanel(.look)
        model.lookTarget = .allClips

        let report = PresetImporter.apply(try PresetImporter.read([xmp]), looks: looks, luts: luts)
        model.lookImported(report, looks: looks, luts: luts)
        let first = try #require(looks.presets.first)
        #expect(model.lookShelf == .myLooks)
        #expect(model.recipe.look?.source == .myLook(sourceID: first.id, name: first.name, isImported: true, recipe: first.applied(onto: .identity)))
        let tile = try #require(VideoLookTile.tiles(shelf: .myLooks, includesOriginal: true, looks: looks, luts: luts).dropFirst().first)
        #expect(tile.isImported)
        #expect(tile.isChosen(in: model.recipe.look))

        let cube = folder.appendingPathComponent("Teal.cube")
        try "LUT_3D_SIZE 2\n0 0.05 0.1\n0.9 0.05 0.1\n0 0.95 1\n0.9 0.95 1\n0 0.1 0.9\n0.9 0.1 0.9\n0 1 1\n0.9 1 1\n".write(to: cube, atomically: true, encoding: .utf8)
        let cubeReport = PresetImporter.apply(try PresetImporter.read([cube]), looks: looks, luts: luts)
        defer { for id in cubeReport.addedLUTIDs { if let lut = luts.luts.first(where: { $0.id == id }) { luts.delete(lut) } } }
        model.lookImported(cubeReport, looks: looks, luts: luts)
        #expect(model.lookShelf == .luts)
        #expect(model.recipe.look?.lutID == cubeReport.addedLUTIDs.first)

        // Cancelling the picker reports nothing, and nothing changes.
        let before = model.recipe
        model.lookImported(PresetImportReport(), looks: looks, luts: luts)
        #expect(model.recipe == before)
    }
}
