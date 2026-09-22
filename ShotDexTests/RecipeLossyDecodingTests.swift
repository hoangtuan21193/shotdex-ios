import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// One piece of a saved edit that this build cannot read must cost that piece,
/// not the photo's whole edit. Before this, a single unknown mask kind failed
/// the recipe, every caller's `try?` turned that into `nil`, and the editor
/// opened the photo as if it had never been touched.
struct RecipeLossyDecodingTests {

    /// A recipe with work in every part that matters, and two masks.
    private func richRecipe() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe()
        recipe.adjustments.exposure = 0.4
        recipe.crop.aspect = .square
        recipe.filter = PhotoFilter.allCases.first { $0 != .original } ?? .original
        recipe.masks = [
            PhotoMask(name: "Sky", component: PhotoMaskComponent(kind: .sky)),
            PhotoMask(name: "Brush", component: PhotoMaskComponent(kind: .brush)),
        ]
        return recipe
    }

    private func encoded(_ recipe: PhotoEditRecipe) throws -> String {
        try #require(String(data: JSONEncoder().encode(recipe), encoding: .utf8))
    }

    private func decoded(_ json: String) throws -> PhotoEditRecipe {
        try JSONDecoder().decode(PhotoEditRecipe.self, from: Data(json.utf8))
    }

    @Test func anUnknownMaskKindDropsThatMaskAndNothingElse() throws {
        let recipe = richRecipe()
        // The sky mask's only component becomes a kind no build has heard of.
        let json = try encoded(recipe).replacingOccurrences(
            of: "\"kind\":\"sky\"",
            with: "\"kind\":\"someFutureKind\""
        )
        let result = try decoded(json)

        #expect(result.masks.map(\.name) == ["Brush"])
        #expect(result.adjustments.exposure == 0.4)
        #expect(result.crop.aspect == .square)
        #expect(result.filter == recipe.filter)
    }

    @Test func anUnknownComponentLeavesTheRestOfItsMask() throws {
        var recipe = richRecipe()
        var mixed = PhotoMask(name: "Mixed", component: PhotoMaskComponent(kind: .radialGradient))
        mixed.components.append(PhotoMaskComponent(kind: .luminanceRange))
        recipe.masks = [mixed]

        let json = try encoded(recipe).replacingOccurrences(
            of: "\"kind\":\"luminanceRange\"",
            with: "\"kind\":\"someFutureKind\""
        )
        let result = try decoded(json)

        #expect(result.masks.count == 1)
        #expect(result.masks.first?.components.map(\.kind) == [.radialGradient])
    }

    @Test func anUnknownLookFallsBackToNoLookAndKeepsTheEdit() throws {
        let recipe = richRecipe()
        let json = try encoded(recipe).replacingOccurrences(
            of: "\"filter\":\"\(recipe.filter.rawValue)\"",
            with: "\"filter\":\"someFutureLook\""
        )
        let result = try decoded(json)

        #expect(result.filter == .original)
        #expect(result.adjustments.exposure == 0.4)
        #expect(result.masks.count == 2)
    }

    @MainActor @Test func oneUnreadablePresetDoesNotEmptyMyLooks() throws {
        let suite = "RecipeLossyDecodingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let keep = LookPreset(name: "Keep", recipe: richRecipe())
        let lose = LookPreset(name: "Lose", recipe: richRecipe())
        let encodedPresets = try #require(
            String(data: JSONEncoder().encode([keep, lose]), encoding: .utf8)
        )
        // Break only the second preset: its id is no longer a UUID.
        let broken = encodedPresets.replacingOccurrences(
            of: lose.id.uuidString,
            with: "not-a-uuid"
        )
        defaults.set(Data(broken.utf8), forKey: SettingsKeys.lookPresets)

        let store = LookPresetStore(defaults: defaults)
        #expect(store.presets.map(\.name) == ["Keep"])
    }
}
