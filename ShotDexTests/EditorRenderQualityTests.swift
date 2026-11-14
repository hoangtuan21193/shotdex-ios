import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-03.18 §1 (AC-1): the drag-time draft drops sharpening, noise reduction
/// and grain — but not the group being dragged — and nothing else.
struct EditorRenderQualityTests {
    static func heavyRecipe() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments[.exposure] = 0.4
        recipe.adjustments[.contrast] = 0.2
        recipe.adjustments[.sharpness] = 0.6
        recipe.adjustments[.noiseReduction] = 0.5
        recipe.adjustments[.colorNoiseReduction] = 0.4
        recipe.adjustments[.grain] = 0.3
        return recipe
    }

    @Test func draftDropsHeavyStages() {
        let draft = Self.heavyRecipe().interactiveDraft(editing: .exposure)
        #expect(draft.adjustments[.sharpness] == PhotoAdjustments.zero[.sharpness])
        #expect(draft.adjustments[.noiseReduction] == PhotoAdjustments.zero[.noiseReduction])
        #expect(draft.adjustments[.colorNoiseReduction] == PhotoAdjustments.zero[.colorNoiseReduction])
        #expect(draft.adjustments[.grain] == PhotoAdjustments.zero[.grain])
        // What the drag is judging stays.
        #expect(draft.adjustments[.exposure] == 0.4)
        #expect(draft.adjustments[.contrast] == 0.2)
    }

    @Test func draggedGroupStays() {
        let sharpening = Self.heavyRecipe().interactiveDraft(editing: .sharpenRadius)
        #expect(sharpening.adjustments[.sharpness] == 0.6)
        #expect(sharpening.adjustments[.noiseReduction] == 0.5)
        #expect(sharpening.adjustments[.grain] == PhotoAdjustments.zero[.grain])
        let grain = Self.heavyRecipe().interactiveDraft(editing: .grainSize)
        #expect(grain.adjustments[.grain] == 0.3)
        #expect(grain.adjustments[.sharpness] == PhotoAdjustments.zero[.sharpness])
    }

    @Test func draftNeverTouchesTheSavedRecipe() {
        let recipe = Self.heavyRecipe()
        _ = recipe.interactiveDraft(editing: .exposure)
        #expect(recipe == Self.heavyRecipe())
        #expect(PhotoEditorController.interactiveScale == 0.5)
        #expect(PhotoEditorController.minimumDraftEdge == 640)
    }
}
