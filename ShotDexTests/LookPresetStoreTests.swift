import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

@MainActor
struct LookPresetStoreTests {

    private func makeStore() -> LookPresetStore {
        let defaults = UserDefaults(suiteName: "look-presets-\(UUID().uuidString)")!
        return LookPresetStore(defaults: defaults)
    }

    /// A recipe with a look on it *and* framing/layers, so the tests can prove
    /// which parts travel.
    private func makeRecipe() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments[.exposure] = 0.6
        recipe.filter = .velvia
        recipe.filterIntensity = 0.8
        recipe.crop.aspect = .square
        recipe.masks = [PhotoMask(name: "Subject", component: PhotoMaskComponent(kind: .subject))]
        return recipe
    }

    @Test func savingKeepsTheLookAndDropsTheFraming() throws {
        let store = makeStore()
        let preset = try #require(store.save(makeRecipe(), name: "Golden Hour"))

        #expect(preset.recipe.adjustments[.exposure] == 0.6)
        #expect(preset.recipe.filter == .velvia)
        #expect(preset.recipe.filterIntensity == 0.8)
        // The two that must never travel with a preset.
        #expect(preset.recipe.crop == PhotoEditRecipe.identity.crop)
        #expect(preset.recipe.masks.isEmpty)
    }

    @Test func savedLooksSurviveAReload() {
        let defaults = UserDefaults(suiteName: "look-presets-\(UUID().uuidString)")!
        let store = LookPresetStore(defaults: defaults)
        store.save(makeRecipe(), name: "Golden Hour")

        let reopened = LookPresetStore(defaults: defaults)
        #expect(reopened.presets.count == 1)
        #expect(reopened.presets.first?.name == "Golden Hour")
        #expect(reopened.presets.first?.recipe.adjustments[.exposure] == 0.6)
    }

    /// Two tiles with the same name are two tiles the user cannot tell apart.
    @Test func savingOverAnExistingNameReplacesIt() {
        let store = makeStore()
        store.save(makeRecipe(), name: "Golden Hour")

        var second = PhotoEditRecipe.identity
        second.adjustments[.contrast] = 0.4
        store.save(second, name: "golden hour")

        #expect(store.presets.count == 1)
        #expect(store.presets.first?.recipe.adjustments[.contrast] == 0.4)
        #expect(store.presets.first?.recipe.adjustments[.exposure] == 0)
    }

    /// A preset that changes nothing is a tile that appears to be broken.
    @Test func anUntouchedRecipeIsNotSaved() {
        let store = makeStore()
        #expect(store.save(.identity, name: "Nothing") == nil)
        #expect(store.presets.isEmpty)
    }

    /// Framing-only edits are the same case: everything the preset would carry
    /// has been stripped, so there is nothing left to save.
    @Test func aCropOnlyRecipeIsNotSaved() {
        let store = makeStore()
        var recipe = PhotoEditRecipe.identity
        recipe.crop.aspect = .square
        #expect(store.save(recipe, name: "Square") == nil)
        #expect(store.presets.isEmpty)
    }

    @Test func blankNamesAreRefused() {
        let store = makeStore()
        #expect(store.save(makeRecipe(), name: "   ") == nil)
        #expect(store.presets.isEmpty)
    }

    @Test func namesAreTrimmed() throws {
        let store = makeStore()
        let preset = try #require(store.save(makeRecipe(), name: "  Dune  "))
        #expect(preset.name == "Dune")
    }

    @Test func renameAndDelete() throws {
        let store = makeStore()
        let preset = try #require(store.save(makeRecipe(), name: "Dune"))

        store.rename(preset, to: "Dune Grass")
        #expect(store.presets.first?.name == "Dune Grass")

        store.rename(preset, to: "  ")
        #expect(store.presets.first?.name == "Dune Grass", "a blank rename is refused")

        store.delete(preset)
        #expect(store.presets.isEmpty)
    }

    /// Two saves in a row must not collide with each other through the
    /// overwrite rule.
    @Test func suggestedNamesDoNotCollide() {
        let store = makeStore()
        let first = store.suggestedName()
        store.save(makeRecipe(), name: first)
        let second = store.suggestedName()

        #expect(first != second)
        store.save(makeRecipe(), name: second)
        #expect(store.presets.count == 2)
    }

    @Test func newestLookComesFirst() {
        let store = makeStore()
        store.save(makeRecipe(), name: "First")
        var other = PhotoEditRecipe.identity
        other.adjustments[.contrast] = 0.2
        store.save(other, name: "Second")

        #expect(store.presets.map(\.name) == ["Second", "First"])
    }
}
