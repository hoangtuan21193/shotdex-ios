import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.05 §2–3, FS-03.12 AC-17…AC-25 — the Mask tab inside the phone panel.
@MainActor
struct MaskPhonePanelTests {

    private func makeController() -> PhotoEditorController {
        PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
    }

    /// AC-17. The three chooser rows hold every kind exactly once, in catalog
    /// order — no kind the old sheet offered is missing from the panel.
    @Test func chooserRowsCoverEveryKindOnce() {
        let rows = EditorNewMaskOption.Row.allCases.flatMap(EditorNewMaskOption.options(in:))
        #expect(rows.count == EditorNewMaskOption.allCases.count)
        #expect(Set(rows) == Set(EditorNewMaskOption.allCases))
        #expect(EditorNewMaskOption.options(in: .detect) == [.subject, .object, .people, .sky, .background, .faceSkin, .eyes, .lips])
        #expect(EditorNewMaskOption.options(in: .draw) == [.brush, .radialGradient, .linearGradient])
        #expect(EditorNewMaskOption.options(in: .range) == [.colorRange, .luminanceRange, .depthRange])
    }

    /// FS-03.15d AC-52. The phone grid is 4 columns and 14 tiles, every kind
    /// once, in §3's order; Face Skin, Eyes and Lips are tiles of their own,
    /// outside People.
    @Test func chooserGridIsFourByFourInOrder() {
        let grid = EditorNewMaskOption.gridOrder
        #expect(EditorNewMaskOption.gridColumns == 4)
        #expect(grid.count == 14)
        #expect(Set(grid) == Set(EditorNewMaskOption.allCases))
        #expect(grid.map(\.shortTitle) == [
            "Subject", "Sky", "Background", "Object",
            "People", "Face Skin", "Eyes", "Lips",
            "Brush", "Radial", "Linear", "Color",
            "Luminance", "Depth",
        ])
    }

    /// FS-03.13 AC-25. Four columns, every kind once with the three face
    /// tiles their own; a 264 panel shows two whole rows and a 344 panel
    /// three, the rest scrolling vertically — never sideways.
    @Test func chooserTilesCoverEveryKindOnce() {
        let grid = EditorNewMaskOption.gridOrder
        #expect(grid.count == EditorNewMaskOption.allCases.count)
        #expect(Set(grid) == Set(EditorNewMaskOption.allCases))
        #expect([.faceSkin, .eyes, .lips].allSatisfy(grid.contains))
        let rows = (grid.count + EditorNewMaskOption.gridColumns - 1) / EditorNewMaskOption.gridColumns
        func zone(_ panel: CGFloat) -> CGFloat {
            EditorLayoutMetrics.paramZoneHeight(panel: panel) - EditorLayoutMetrics.editorParamZoneTopInset
        }
        #expect(EditorMaskChooser.visibleRows(in: zone(EditorLayoutMetrics.phonePanelShort)) == 2)
        #expect(EditorMaskChooser.visibleRows(in: zone(EditorLayoutMetrics.phonePanelTall)) == 3)
        #expect(rows > 3, "the last rows are reached by scrolling")
    }

    /// AC-17 / AC-18. With no mask the chooser shows; one tap on Radial makes
    /// exactly one mask, "Mask 1" with "Radial" under it (FS-03.13c §2, E4),
    /// selected, and the chooser gives way.
    @Test func oneTapOnRadialMakesOneShortNamedMask() throws {
        let controller = makeController()
        let chrome = EditorChromeModel()
        #expect(EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))

        controller.addMask(option: .radialGradient)
        let mask = try #require(controller.recipe.masks.first)
        #expect(controller.recipe.masks.count == 1)
        #expect(mask.name == "Mask 1")
        #expect(MaskAreaSummary.subtitle(for: mask) == "Radial")
        #expect(controller.selectedMaskID == mask.id)
        #expect(!EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }

    /// FS-03.13 AC-26. One tap on Brush and a 100pt drag: one mask, one
    /// stroke, nothing else tapped in between; the row reads "Mask 1" over
    /// "Brush".
    @Test func brushTileDrawsImmediately() throws {
        let controller = makeController()
        controller.addMask(option: .brush)
        controller.editSelectedMaskAdjustments()
        #expect(controller.selectedComponent?.kind == .brush)
        #expect(controller.editingMaskAdjustments, "the paint layer is up at once")
        controller.beginBrushStroke(at: NormalizedPoint(x: 0.3, y: 0.5))
        controller.continueBrushStroke(at: NormalizedPoint(x: 0.55, y: 0.5))
        controller.endBrushStroke()
        let mask = try #require(controller.recipe.masks.first)
        #expect(controller.recipe.masks.count == 1)
        #expect(mask.components.first?.brushStrokes.count == 1)
        #expect(mask.name == "Mask 1")
        #expect(MaskAreaSummary.subtitle(for: mask) == "Brush")
    }

    /// FS-03.13 AC-28. Mask 1 = Sky − Brush, Mask 2 = Radial, Mask 1
    /// selected: Mask 1 · Sky · Brush · Add / Subtract / Intersect area ·
    /// Mask 2 · New Mask.
    @Test func listPutsAreaActionsUnderTheSelectedMask() throws {
        let controller = makeController()
        controller.addMask(option: .sky)
        controller.addMaskArea(option: .brush, operation: .subtract)
        controller.addMask(option: .radialGradient)
        let first = try #require(controller.recipe.masks.first)
        let second = try #require(controller.recipe.masks.last)
        controller.selectMask(first.id)
        let rows = EditorMaskListRow.rows(masks: controller.recipe.masks, selected: controller.selectedMaskID)
        #expect(rows == [
            .mask(first.id),
            .area(mask: first.id, component: first.components[0].id),
            .area(mask: first.id, component: first.components[1].id),
            .addArea(.add), .addArea(.subtract), .addArea(.intersect),
            .mask(second.id),
            .newMask,
        ])
        #expect(first.components.map(MaskAreaSummary.name(of:)) == ["Sky", "Brush"])
        #expect(first.components.map(\.operation) == [.add, .subtract])
        #expect(MaskAreaSummary.subtitle(for: first) == "Sky − Brush")
        #expect(MaskBlendOperation.allCases.map(EditorMaskListRow.title(of:)) == ["Add area", "Subtract area", "Intersect area"])
    }

    /// FS-03.13 AC-29. Subtract area → Brush on Mask 1 = Sky: the grid is
    /// titled "Subtract from Mask 1" and offers every kind; Mask 1 then has
    /// two areas, the second subtracting and selected, so the top row reads
    /// "Subtracting". Background as an area is Subject inverted.
    @Test func subtractAreaAddsASubtractingBrush() throws {
        let controller = makeController()
        controller.addMask(option: .sky)
        #expect(EditorMaskListRow.chooserTitle(for: .subtract, maskName: "Mask 1") == "Subtract from Mask 1")
        #expect(Set(EditorNewMaskOption.gridOrder) == Set(EditorNewMaskOption.allCases), "the area grid is the chooser grid")
        controller.addMaskArea(option: .brush, operation: .subtract)
        let mask = try #require(controller.recipe.masks.first)
        #expect(controller.recipe.masks.count == 1)
        #expect(mask.components.map(\.operation) == [.add, .subtract])
        #expect(controller.selectedComponentID == mask.components[1].id)
        #expect(MaskAreaSummary.topRowSubtitle(for: mask, selectedComponent: controller.selectedComponentID) == "Subtracting")

        controller.addMaskArea(option: .background, operation: .subtract)
        let background = try #require(controller.recipe.masks.first?.components.last)
        #expect(background.kind == .subject && background.isInverted)
    }

    /// AC-19. Depth on a photo without a depth map is refused with the reason
    /// the title shows — the reason text is the one the old sheet used.
    @Test func depthWithoutADepthMapGivesItsReason() {
        #expect(
            EditorNewMaskOption.depthRange.unavailableReason(hasDepth: false)
                == "This photo has no depth map. Portrait mode photos do."
        )
        #expect(EditorNewMaskOption.depthRange.unavailableReason(hasDepth: true) == nil)
    }

    /// AC-20. Hide turns the mask's effect off; Show turns it back on.
    @Test func hideAndShowToggleTheEffect() throws {
        let controller = makeController()
        controller.addMask(option: .sky)
        controller.toggleSelectedMaskVisibility()
        #expect(try #require(controller.recipe.masks.first).isVisible == false)
        controller.toggleSelectedMaskVisibility()
        #expect(try #require(controller.recipe.masks.first).isVisible)
    }

    /// AC-21. Duplicate keeps its place: the copy lands right after the mask it
    /// copies and becomes the selection the strip scrolls to.
    @Test func duplicateLandsRightAfterItsSource() throws {
        let controller = makeController()
        controller.addMask(option: .radialGradient)
        controller.addMask(option: .linearGradient)
        let first = try #require(controller.recipe.masks.first)
        controller.selectMask(first.id)
        controller.duplicateSelectedMask()
        #expect(controller.recipe.masks.count == 3)
        #expect(controller.recipe.masks[1].id == controller.selectedMaskID)
        #expect(controller.recipe.masks[1].name == "Mask 1 Copy")
    }

    /// AC-22, and FS-03.13 AC-27. `+` then `‹` leaves the masks as they
    /// were — still one, the same one selected: the chooser makes nothing
    /// until a kind is tapped.
    @Test func plusThenBackMakesNothing() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addMask(option: .sky)
        let before = controller.recipe.masks.map(\.id)
        let selected = controller.selectedMaskID
        chrome.isChoosingMaskKind = true
        #expect(EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))
        chrome.isChoosingMaskKind = false
        #expect(controller.recipe.masks.map(\.id) == before)
        #expect(controller.selectedMaskID == selected)
        #expect(!EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }

    /// AC-24. One Undo after making a mask leaves no mask, so the chooser is back.
    @Test func undoAfterCreatingReturnsToTheChooser() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addMask(option: .sky)
        controller.undo()
        #expect(controller.recipe.masks.isEmpty)
        #expect(EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }

    /// AC-25. Deleting the last mask returns to the chooser too.
    @Test func deletingTheLastMaskReturnsToTheChooser() {
        let controller = makeController()
        let chrome = EditorChromeModel()
        controller.addMask(option: .brush)
        controller.deleteSelectedMask()
        #expect(controller.recipe.masks.isEmpty)
        #expect(EditorMaskPhonePanel.showsChooser(controller: controller, chrome: chrome))
    }
}
