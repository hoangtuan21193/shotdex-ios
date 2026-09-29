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

    /// FS-03.13 AC-35. A text layer set left, then the middle alignment: the
    /// text is centred, and the three buttons are one radio — exactly one lit,
    /// each read by name.
    @Test func alignmentGroupIsARadio() throws {
        let controller = makeController()
        controller.addTextOverlay()
        controller.updateSelectedOverlay { $0.alignment = .leading }
        controller.updateSelectedOverlay { $0.alignment = .center }
        let overlay = try #require(controller.recipe.overlays.first)
        #expect(overlay.alignment == .center)
        #expect(OverlayTextAlignment.allCases.filter { $0 == overlay.alignment }.count == 1)
        #expect(OverlayTextAlignment.allCases.map(\.accessibilityName) == ["Align left", "Align center", "Align right"])
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

    /// FS-03.13 AC-34 (replaces the strip's hold-and-drag, chốt #6). Three
    /// layers, Text 1 · Drawing 1 · Logo front to back: dragging Logo's ≡
    /// two rows up puts it first — on top of the photo — in one Undo.
    @Test func verticalListRestacksTheLayer() throws {
        let controller = makeController()
        controller.addMagnifierOverlay()          // back: "Logo"
        controller.addShapeOverlay(.rectangle)    // "Drawing 1"
        controller.addTextOverlay()               // front: "Text 1"
        let logo = controller.recipe.overlays[0].id
        let displayed = { controller.recipe.overlays.reversed().map(\.id) }
        let before = displayed()
        #expect(before.last == logo)
        let start = 2
        let destination = EditorLayerOrder.destination(from: start, offset: -80, rowHeight: 40, count: 3)
        #expect(destination == 0)
        controller.moveOverlays(
            fromDisplay: IndexSet(integer: start),
            toDisplay: EditorLayerOrder.moveOffset(from: start, to: destination)
        )
        #expect(displayed() == [logo, before[0], before[1]])
        #expect(controller.recipe.overlays.last?.id == logo, "drawn last, so on top")
        controller.undo()
        #expect(displayed() == before)
        // Downwards the drop slot counts past the row itself.
        #expect(EditorLayerOrder.moveOffset(from: 0, to: 2) == 3)
        #expect(EditorLayerOrder.destination(from: 0, offset: 500, rowHeight: 40, count: 3) == 2)
    }
}
