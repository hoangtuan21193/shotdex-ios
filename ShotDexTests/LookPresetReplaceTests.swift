import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// The Mac's Update with Current Settings and Duplicate write a look back
/// whole (FS-18.03 §1g): an imported look keeps its source and named settings.
@MainActor
struct LookPresetReplaceTests {
    private func store() -> LookPresetStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LookReplace-\(UUID().uuidString)", isDirectory: true)
        return LookPresetStore(directory: folder, defaults: UserDefaults(suiteName: "LookReplace-\(UUID().uuidString)")!)
    }

    @Test func replaceKeepsAnImportedLooksFields() {
        let looks = store()
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.5
        var imported = LookPreset(name: "From Lightroom", recipe: recipe)
        imported.source = .imported
        imported.namedSettings = [.adjustment(.exposure)]
        looks.insert(imported)

        var updated = imported
        updated.recipe.adjustments.exposure = 0.8
        looks.replace(updated)

        #expect(looks.presets.count == 1)
        let kept = looks.presets[0]
        #expect(kept.id == imported.id)
        #expect(kept.source == .imported)
        #expect(kept.namedSettings == [.adjustment(.exposure)])
        #expect(kept.recipe.adjustments.exposure == 0.8)
    }

    @Test func replaceWithANewIDAddsTheCopy() {
        let looks = store()
        let original = LookPreset(name: "Harbour", recipe: .identity)
        looks.insert(original)
        var copy = original
        copy.id = UUID()
        copy.name = "Harbour (2)"
        looks.replace(copy)
        #expect(looks.presets.map(\.name).sorted() == ["Harbour", "Harbour (2)"])
    }
}
