import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-05.01 §6, FS-03.12 AC-26 / AC-27 / AC-36 / AC-37 — Markup on the phone panel.
@MainActor
struct MarkupPhonePanelTests {
    private func makeController() -> PhotoEditorController {
        PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
    }

    /// AC-26. No layer: the chooser shows.
    @Test func noLayerShowsTheChooser() {
        #expect(EditorMarkupPhonePanel.showsChooser(controller: makeController(), chrome: EditorChromeModel()))
    }

    /// AC-27. Text makes one text layer, selected, and the chooser gives way.
    @Test func textMakesOneSelectedLayer() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addTextOverlay()
        #expect(controller.recipe.overlays.map(\.kind) == [.text])
        #expect(controller.selectedOverlayID == controller.recipe.overlays.first?.id)
        #expect(!EditorMarkupPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }

    /// AC-36. `+` then `‹` changes nothing.
    @Test func plusThenBackMakesNothing() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addShapeOverlay(.oval)
        let before = controller.recipe.overlays.map(\.id)
        chrome.isChoosingLayerKind = true
        #expect(EditorMarkupPhonePanel.showsChooser(controller: controller, chrome: chrome))
        chrome.isChoosingLayerKind = false
        #expect(controller.recipe.overlays.map(\.id) == before)
    }

    /// AC-37. Deleting the last layer brings the chooser back.
    @Test func deletingTheLastLayerShowsTheChooser() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addMagnifierOverlay()
        controller.deleteSelectedOverlay()
        #expect(controller.recipe.overlays.isEmpty)
        #expect(EditorMarkupPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }

    /// ⋯ Rename: the name wins over the content-derived one; clearing it goes back.
    @Test func renameNamesTheLayer() throws {
        let controller = makeController()
        controller.addShapeOverlay(.arrow)
        let layer = try #require(controller.selectedOverlay)
        #expect(controller.displayName(of: layer) == "Arrow")
        controller.renameSelectedOverlay("  Pointer ")
        #expect(controller.displayName(of: try #require(controller.selectedOverlay)) == "Pointer")
        controller.renameSelectedOverlay("")
        #expect(controller.displayName(of: try #require(controller.selectedOverlay)) == "Arrow")
    }

    /// AC-32. A tap on empty photo hides the box but keeps the layer — the panel
    /// does not jump; tapping the layer again brings the box back.
    @Test func tapOnEmptyPhotoKeepsThePanelLayer() throws {
        let controller = makeController()
        controller.addTextOverlay()
        let id = try #require(controller.selectedOverlayID)
        controller.isOverlayBoxHidden = true
        #expect(controller.selectedOverlayID == id)
        controller.selectOverlay(id)
        #expect(!controller.isOverlayBoxHidden)
    }

    /// AC-34 (Recent). Newest first, no duplicates, at most six — and only in the
    /// session's chrome, nothing stored.
    @Test func recentColorsAreNewestFirstAndCapped() {
        let chrome = EditorChromeModel()
        for step in 0..<8 {
            chrome.rememberRecentColor(OverlayColor(white: Double(step) / 10))
        }
        chrome.rememberRecentColor(OverlayColor(white: 0.5))
        #expect(chrome.recentColors.count == 6)
        #expect(chrome.recentColors.first == OverlayColor(white: 0.5))
        #expect(chrome.recentColors.filter { $0 == OverlayColor(white: 0.5) }.count == 1)
    }

    /// Chốt #6. Hold-and-drag on the strip: the strip is front-to-back, so
    /// dropping the back layer on the front tile brings it to the front, and
    /// dropping it back on the last tile sends it to the back again.
    @Test func dragOntoATileRestacksTheLayer() {
        let controller = makeController()
        controller.addTextOverlay()
        controller.addShapeOverlay(.rectangle)
        controller.addMagnifierOverlay()
        let back = controller.recipe.overlays[0].id
        let front = controller.recipe.overlays[2].id
        controller.moveOverlay(id: back, ontoOverlay: front)
        #expect(controller.recipe.overlays.map(\.kind) == [.shape, .magnifier, .text])
        controller.moveOverlay(id: back, ontoOverlay: controller.recipe.overlays[0].id)
        #expect(controller.recipe.overlays.map(\.kind) == [.text, .shape, .magnifier])
        controller.undo()
        #expect(controller.recipe.overlays.map(\.kind) == [.shape, .magnifier, .text])
    }
}
