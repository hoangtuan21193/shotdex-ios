import Foundation
import Photos
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-05.04 §5: a layer pasted from a preset remembers it, and a photo whose
/// saved edit has such a layer is not stamped with that preset again.
@MainActor
struct WatermarkAlreadyStampedTests {
    @Test func applySignatureRecordsPreset() {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        let credit = WatermarkFixture.credit(logo: UUID())
        controller.applySignature(credit)
        #expect(controller.recipe.overlays.count == 2)
        #expect(controller.recipe.overlays.allSatisfy { $0.signaturePresetID == credit.id })
        #expect(Set(controller.recipe.overlays.map(\.id)).isDisjoint(with: credit.layers.map(\.id)))
    }

    @Test func thePresetIdRoundTripsAndIsOptional() throws {
        var layer = PhotoOverlay.text()
        layer.signaturePresetID = UUID()
        let decoded = try JSONDecoder().decode(PhotoOverlay.self, from: JSONEncoder().encode(layer))
        #expect(decoded.signaturePresetID == layer.signaturePresetID)
        let plain = try JSONEncoder().encode(PhotoOverlay.text())
        #expect(!String(decoding: plain, as: UTF8.self).contains("signaturePresetID"))
    }

    @Test func samePresetIsNotStampedTwice() {
        let preset = UUID()
        var pasted = PhotoOverlay.text()
        pasted.signaturePresetID = preset
        #expect(WatermarkPlan.alreadyStamped(savedLayers: [pasted], presetID: preset))
    }

    /// A layer from another preset, a caption made by hand, or no edit at all
    /// does not count — those photos are stamped.
    @Test func otherPresetStillStamps() {
        let preset = UUID()
        var other = PhotoOverlay.text()
        other.signaturePresetID = UUID()
        #expect(!WatermarkPlan.alreadyStamped(savedLayers: [other, PhotoOverlay.text()], presetID: preset))
        #expect(!WatermarkPlan.alreadyStamped(savedLayers: nil, presetID: preset))
        var hidden = PhotoOverlay.text()
        hidden.signaturePresetID = preset
        hidden.isVisible = false
        #expect(!WatermarkPlan.alreadyStamped(savedLayers: [hidden], presetID: preset), "a hidden layer stamps nothing")
    }

    /// The adjustment resource of a photo ShotDex edited: Photos' property
    /// list around the recipe's JSON. Another app's edit is no edit of ours.
    @Test func savedRecipeReadsTheAdjustmentResource() throws {
        var recipe = PhotoEditRecipe.identity
        var pasted = PhotoOverlay.text()
        pasted.signaturePresetID = UUID()
        recipe.overlays = [pasted]
        func plist(_ identifier: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                "adjustmentFormatIdentifier": identifier,
                "adjustmentFormatVersion": PhotoEditRecipe.formatVersion,
                "adjustmentData": try JSONEncoder().encode(recipe),
            ], format: .binary, options: 0)
        }
        let ours = PhotoEditingService.recipe(fromAdjustmentResource: try plist(PhotoEditRecipe.formatIdentifier))
        #expect(ours?.overlays.first?.signaturePresetID == pasted.signaturePresetID)
        #expect(PhotoEditingService.recipe(fromAdjustmentResource: try plist("com.example.other")) == nil)
    }
}
