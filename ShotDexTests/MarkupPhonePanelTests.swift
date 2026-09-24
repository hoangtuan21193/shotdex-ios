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
}
