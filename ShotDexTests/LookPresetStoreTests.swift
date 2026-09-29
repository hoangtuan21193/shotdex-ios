import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

@MainActor
struct LookPresetStoreTests {

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(directory: URL? = nil) -> LookPresetStore {
        let defaults = UserDefaults(suiteName: "look-presets-\(UUID().uuidString)")!
        return LookPresetStore(directory: directory ?? makeDirectory(), defaults: defaults)
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
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        store.save(makeRecipe(), name: "Golden Hour")

        let reopened = makeStore(directory: directory)
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

        #expect(store.rename(preset, to: "  ") == .emptyName)
        #expect(store.presets.first?.name == "Dune Grass", "a blank rename is refused")

        store.delete(preset)
        #expect(store.presets.isEmpty)
    }

    /// FS-03.14 AC-c6 (E8). Renaming to a name another look has — any case —
    /// is refused, offering the first free "(n)"; its own name in a new case
    /// is fine.
    @Test func renameRefusesATakenName() throws {
        let store = makeStore()
        let dune = try #require(store.save(makeRecipe(), name: "Dune"))
        var other = makeRecipe()
        other.adjustments[.exposure] = -0.4
        let forest = try #require(store.save(other, name: "Forest"))
        var third = makeRecipe()
        third.adjustments[.contrast] = 0.3
        _ = try #require(store.save(third, name: "Dune (2)"))

        #expect(store.rename(forest, to: "dune") == .nameTaken(suggestion: "dune (3)"))
        #expect(store.presets.contains { $0.id == forest.id && $0.name == "Forest" }, "nothing renamed")
        #expect(store.rename(dune, to: "DUNE") == nil, "its own name in another case")
        #expect(store.presets.first { $0.id == dune.id }?.name == "DUNE")
    }

    /// FS-03.14c §3. A built-in film look renames on the panel only: another
    /// built-in's name is refused, its own name puts it back.
    @Test func builtInRenamesOnThePanelOnly() {
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        #expect(store.rename(.velvia, to: "Punchy") == nil)
        #expect(store.displayName(of: .velvia) == "Punchy")
        #expect(makeStore(directory: directory).displayName(of: .velvia) == "Punchy", "kept across launches")
        let taken = PhotoFilter.mono.displayName.uppercased()
        #expect(store.rename(.velvia, to: taken) == .nameTaken(suggestion: "\(taken) (2)"))
        #expect(store.rename(.velvia, to: PhotoFilter.velvia.displayName) == nil)
        #expect(store.presetNames.isEmpty)
    }

    /// FS-03.14 AC-a12 (D35). An imported look keeps the preset file it came
    /// from byte for byte beside it; deleting the look deletes the copy.
    @Test func keepsOriginalPresetBesideLook() throws {
        let store = makeStore()
        let bytes = Data((0..<3000).map { UInt8($0 % 251) })
        var look = LookPreset(name: "Golden", recipe: makeRecipe())
        look.source = .imported
        store.insert(look, original: (bytes, "xmp"))
        let stored = try #require(store.presets.first)
        let url = try #require(store.originalPresetURL(for: stored))
        #expect(try Data(contentsOf: url) == bytes)
        store.delete(stored)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.presets.isEmpty)
    }

    /// Looks a development phone kept in `UserDefaults` move into the file
    /// once, and the key goes.
    @Test func legacyLooksMoveIntoTheFileOnce() throws {
        let suite = "look-presets-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = [LookPreset(name: "Old", recipe: makeRecipe())]
        defaults.set(try JSONEncoder().encode(legacy), forKey: SettingsKeys.lookPresets)
        let directory = makeDirectory()
        let store = LookPresetStore(directory: directory, defaults: defaults)
        #expect(store.presets.map(\.name) == ["Old"])
        #expect(defaults.data(forKey: SettingsKeys.lookPresets) == nil)
        #expect(LookPresetStore(directory: directory, defaults: defaults).presets.map(\.name) == ["Old"])
    }

    /// FS-03.14 AC-a9 (D50). With the user's own "Golden", importing a
    /// "golden" adds "golden (2)" marked Imported and leaves "Golden" as it
    /// was; importing the same file again adds nothing.
    @Test func importNeverOverwritesAUserLook() throws {
        let store = makeStore()
        let golden = try #require(store.save(makeRecipe(), name: "Golden"))
        var preset = PhotoEditRecipe.identity
        preset.adjustments[.exposure] = 0.3
        guard case let .added(first) = store.addImported(preset, name: "golden") else {
            Issue.record("the first import adds a look"); return
        }
        #expect(first.name == "golden (2)")
        #expect(first.source == .imported)
        #expect(store.presets.first { $0.id == golden.id }?.recipe == golden.recipe)
        let count = store.presets.count
        #expect(store.addImported(preset, name: "golden") == .alreadyInMyLooks)
        #expect(LookPresetStore.isName("Golden (12)", aVariantOf: "golden"))
        #expect(!LookPresetStore.isName("Golden Hour", aVariantOf: "golden"))
        #expect(store.presets.count == count)
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
