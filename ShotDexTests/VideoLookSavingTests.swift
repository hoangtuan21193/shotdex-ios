import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-12.06c §6b: Save as Look… — the whole video's look and grade, cut to
/// what a photo look holds, into the My Looks the photo editor uses.
@MainActor
struct VideoLookSavingTests {
    private func makeStore() -> LookPresetStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("video-looks-\(UUID().uuidString)", isDirectory: true)
        return LookPresetStore(directory: directory, defaults: UserDefaults(suiteName: "video-looks-\(UUID().uuidString)")!)
    }

    private func node(_ configure: (inout ColorNode) -> Void) -> ColorNode {
        var node = ColorNode()
        configure(&node)
        return node
    }

    private var window: PhotoMask { PhotoMask(name: "Face", component: PhotoMaskComponent(kind: .radialGradient)) }

    /// AC-17: Velvia at Amount 60 and one node (Exposure +0.3, Contrast +20)
    /// become one photo look — Velvia at 60, the node's settings — saved at
    /// the front of My Looks under its name. Nothing is left out; the
    /// project and its undo steps do not change; My Looks comes up.
    @Test func filmLookAndOneNodeBecomeOneLook() throws {
        let model = VideoStudioModelFixture.model { recipe in
            recipe.look = VideoLook(.preset(.velvia), amount: 0.6)
            recipe.nodes = [self.node { $0.adjustments.exposure = 0.3; $0.adjustments.contrast = 0.2 }]
        }
        let store = makeStore()
        store.save(VideoLookSamples.moodyCoast, name: "Moody Coast")
        let before = model.recipe
        let undoSteps = model.history.undoEntries.count

        let cut = model.photoLookCut
        #expect(cut.notSaved.isEmpty)
        #expect(cut.recipe.filter == .velvia)
        #expect(cut.recipe.filterIntensity == 0.6)
        #expect(cut.recipe.adjustments.exposure == 0.3)
        #expect(cut.recipe.adjustments.contrast == 0.2)
        #expect(VideoStudioCopy.saveLookMessage(notSaved: cut.notSaved) == "Saves the whole video's look, Adjust and Color into My Looks, for photos and videos.")

        let saved = try #require(model.saveVideoLook(named: "  Reel Velvia ", into: store))
        #expect(store.presets.map(\.name) == ["Reel Velvia", "Moody Coast"])
        #expect(saved.recipe == cut.recipe)
        #expect(model.recipe == before)
        #expect(model.history.undoEntries.count == undoSteps)
        #expect(model.lookShelf == .myLooks)
    }

    /// A LUT goes in as a LUT at its Amount.
    @Test func lutKeepsItsAmount() {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(2))
        recipe.look = VideoLook(.lut(id: "kodak-2383", name: "Kodak 2383"), amount: 0.75)
        let cut = VideoLookSaving.photoLook(of: recipe)
        #expect(cut.recipe.lutID == "kodak-2383")
        #expect(cut.recipe.filterIntensity == 0.75)
        #expect(cut.notSaved.isEmpty)
    }

    /// AC-18: everything a photo look cannot hold is named, in order — the
    /// Input Transform, a My Look's Amount under 100, a setting the look
    /// already sets, the nodes after the first, a node limited to a
    /// window, and clips' own looks — and the rest is kept.
    @Test func whatStaysInTheVideoIsNamed() {
        let moody = VideoLookSamples.moodyCoast
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(3))
        recipe.inputTransform = .sLog3
        recipe.look = VideoLook(.myLook(sourceID: UUID(), name: "Moody Coast", isImported: false, recipe: moody), amount: 0.4)
        recipe.nodes = [
            node { $0.adjustments.exposure = 0.2; $0.adjustments.warmth = 0.1 },
            node { $0.adjustments.saturation = 0.15 },
            node { $0.adjustments.contrast = 0.1; $0.masks = [window] },
        ]
        recipe.clips[1].look = VideoLookSamples.nightTeal

        let cut = VideoLookSaving.photoLook(of: recipe)
        #expect(cut.notSaved == ["Input Transform", "Amount", "Exposure in Node 1", "Node 2", "Node 3", "clips' own looks"])
        var expected = EditorSyncScope.look.apply(moody, onto: .identity)
        expected.adjustments.warmth = 0.1
        #expect(cut.recipe == expected)
        #expect(VideoStudioCopy.saveLookMessage(notSaved: cut.notSaved).hasSuffix(
            "Not saved: Input Transform, Amount, Exposure in Node 1, Node 2, Node 3, and clips' own looks."
        ))
    }

    /// A node limited to a window is left out even when it comes first;
    /// the first node without one is the grade that travels.
    @Test func aWindowedNodeIsLeftOut() {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.videoClips(1))
        recipe.nodes = [
            node { $0.adjustments.exposure = 0.5; $0.masks = [window] },
            node { $0.adjustments.contrast = 0.3; $0.color.mixer.aqua.saturation = 0.4 },
        ]
        let cut = VideoLookSaving.photoLook(of: recipe)
        #expect(cut.notSaved == ["Node 1"])
        #expect(cut.recipe.adjustments.exposure == 0)
        #expect(cut.recipe.adjustments.contrast == 0.3)
        #expect(cut.recipe.color == recipe.nodes[1].color)
    }

    /// AC-19: no look and no grade — only an Input Transform, an Original
    /// look, a node that is all window — is nothing a photo would show:
    /// the row is dimmed and saving does nothing.
    @Test func nothingToSave() {
        let cases: [(inout VideoProjectRecipe) -> Void] = [
            { _ in },
            { $0.inputTransform = .sLog3 },
            { $0.look = .original },
            { $0.nodes = [self.node { $0.masks = [self.window] }] },
            { $0.nodes = [self.node { $0.adjustments.exposure = 0.4; $0.isEnabled = false }] },
        ]
        for configure in cases {
            let model = VideoStudioModelFixture.model(configure: configure)
            let store = makeStore()
            #expect(model.photoLookCut.isEmpty)
            #expect(model.saveVideoLook(named: "Look 1", into: store) == nil)
            #expect(store.presets.isEmpty)
            #expect(model.lookShelf == .presets)
        }
    }

    /// AC-20: a blank name saves nothing and leaves the panel where it was.
    @Test func blankNameSavesNothing() {
        let model = VideoStudioModelFixture.model { $0.look = VideoLookSamples.velvia }
        let store = makeStore()
        #expect(model.saveVideoLook(named: "   ", into: store) == nil)
        #expect(model.saveVideoLook(named: "", into: store) == nil)
        #expect(store.presets.isEmpty)
        #expect(model.lookShelf == .presets)
    }

    /// AC-21: a name already in My Looks, any case, is saved over — one
    /// look, the same id, the new settings — and a video that chose the
    /// old version keeps its copy until its tile is tapped again (§6).
    @Test func takenNameIsSavedOver() throws {
        let store = makeStore()
        let golden = try #require(store.save(VideoLookSamples.moodyCoast, name: "Golden"))
        let earlier = VideoStudioModelFixture.model { recipe in
            recipe.look = VideoLook(.myLook(sourceID: golden.id, name: "Golden", isImported: false, recipe: golden.recipe))
        }
        let model = VideoStudioModelFixture.model { recipe in
            recipe.look = VideoLook(.preset(.acros))
            recipe.nodes = [self.node { $0.adjustments.contrast = 0.4 }]
        }
        let saved = try #require(model.saveVideoLook(named: "golden", into: store))
        #expect(store.presets.count == 1)
        #expect(saved.id == golden.id)
        #expect(store.presets[0].name == "golden")
        #expect(store.presets[0].recipe.filter == .acros)
        #expect(earlier.recipe.look?.recipe == golden.recipe)
    }
}
