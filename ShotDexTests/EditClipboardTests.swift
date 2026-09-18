import Foundation
import Testing
@testable import ShotDex

@MainActor
struct EditClipboardTests {

    private func makeClipboard() -> EditClipboard {
        let defaults = UserDefaults(suiteName: "EditClipboardTests-\(UUID().uuidString)")!
        return EditClipboard(defaults: defaults)
    }

    private func lookRecipe() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.4
        recipe.adjustments.contrast = -0.2
        recipe.filter = .original
        recipe.filterIntensity = 0.6
        return recipe
    }

    @Test func copyingCarriesTheLook() {
        let clipboard = makeClipboard()
        clipboard.copy(from: lookRecipe())

        let pasted = clipboard.paste(onto: .identity)
        #expect(pasted.adjustments.exposure == 0.4)
        #expect(pasted.adjustments.contrast == -0.2)
        #expect(pasted.filterIntensity == 0.6)
    }

    /// Crop, masks, the drawing and the overlays belong to one frame. Pasting a
    /// crop would reframe a photo the user never framed; pasting a mask would
    /// brighten a region that on this photo is somebody's face.
    @Test func pastingLeavesFramingAndLayersAlone() {
        let clipboard = makeClipboard()
        var copied = lookRecipe()
        copied.crop.rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        copied.overlays = [PhotoOverlay.shape(.oval)]
        clipboard.copy(from: copied)

        var target = PhotoEditRecipe.identity
        target.crop.rect = NormalizedRect(x: 0, y: 0, width: 0.8, height: 0.8)
        let pasted = clipboard.paste(onto: target)

        #expect(pasted.crop.rect == target.crop.rect)
        #expect(pasted.overlays.isEmpty)
        #expect(pasted.adjustments.exposure == 0.4)
    }

    /// A copied identity is not worth offering: the paste would do nothing.
    @Test func copyingNothingOffersNothing() {
        let clipboard = makeClipboard()
        clipboard.copy(from: .identity)
        #expect(!clipboard.hasContent)

        clipboard.copy(from: lookRecipe())
        #expect(clipboard.hasContent)
    }

    @Test func theClipboardSurvivesALaunch() {
        let suite = "EditClipboardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        EditClipboard(defaults: defaults).copy(from: lookRecipe())

        let reopened = EditClipboard(defaults: defaults)
        #expect(reopened.hasContent)
        #expect(reopened.paste(onto: .identity).adjustments.exposure == 0.4)
    }

    @Test func pastingWithAnEmptyClipboardChangesNothing() {
        let clipboard = makeClipboard()
        var target = PhotoEditRecipe.identity
        target.adjustments.exposure = 1
        #expect(clipboard.paste(onto: target) == target)
    }
}
