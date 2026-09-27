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

    /// FS-03.15 AC-1. A recipe carrying every new Lightroom-parity part, with
    /// one mask area and one retouch spot this build cannot read, loses exactly
    /// those two; Calibration, the region curve, the B&W mixer, Upright and
    /// Lens Blur come back whole.
    @Test func newParityFieldsSurviveOneBadElement() throws {
        var recipe = richRecipe()
        recipe.color.calibration.redHue = 0.3
        recipe.color.calibration.shadowTint = -0.2
        recipe.color.grayMixer.blue = -0.5
        recipe.curve.region.shadows = 0.4
        recipe.curve.region.midtoneSplit = 0.6
        recipe.upright.mode = .guided
        recipe.upright.guides = [
            PhotoUprightGuide(start: NormalizedPoint(x: 0.2, y: 0.1), end: NormalizedPoint(x: 0.22, y: 0.9)),
        ]
        recipe.upright.solved.vertical = 0.15
        recipe.lensBlur.amount = 0.6
        recipe.lensBlur.bokeh = .ring
        recipe.vignetteStyle = .paintOverlay
        recipe.redEyes = [PhotoRedEyeSpot(center: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.01)]
        recipe.healing = [
            PhotoHealingSpot(mode: .clone, center: NormalizedPoint(x: 0.3, y: 0.3), source: NormalizedPoint(x: 0.6, y: 0.3)),
            PhotoHealingSpot(mode: .heal, center: NormalizedPoint(x: 0.7, y: 0.7), source: NormalizedPoint(x: 0.5, y: 0.7)),
        ]
        #expect(!recipe.isIdentity)

        let json = try encoded(recipe)
            .replacingOccurrences(of: "\"kind\":\"sky\"", with: "\"kind\":\"someFutureKind\"")
            .replacingOccurrences(of: "\"mode\":\"clone\"", with: "\"mode\":\"someFutureMode\"")
        let result = try decoded(json)

        #expect(result.masks.map(\.name) == ["Brush"], "only the unreadable mask area goes")
        #expect(result.healing.map(\.mode) == [.heal], "only the unreadable spot goes")
        #expect(result.color.calibration == recipe.color.calibration)
        #expect(result.color.grayMixer == recipe.color.grayMixer)
        #expect(result.curve.region == recipe.curve.region)
        #expect(result.upright == recipe.upright)
        #expect(result.lensBlur == recipe.lensBlur)
        #expect(result.vignetteStyle == .paintOverlay)
        #expect(result.redEyes == recipe.redEyes)
        #expect(result.adjustments.exposure == 0.4)
    }

    /// Untouched, the new parts add no key: a plain recipe encodes as before.
    @Test func untouchedParityPartsWriteNothing() throws {
        let json = try encoded(richRecipe())
        for key in ["upright", "lensBlur", "vignetteStyle", "redEyes", "calibration", "grayMixer", "region"] {
            #expect(!json.contains("\"\(key)\""), "\(key) written for an untouched recipe")
        }
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
