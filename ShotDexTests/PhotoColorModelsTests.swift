import Foundation
import Testing

@testable import ShotDex

struct PhotoColorModelsTests {
    @Test func freshColorRecipeIsIdentity() {
        #expect(PhotoColorRecipe.identity.isIdentity)
        #expect(PhotoEditRecipe.identity.isIdentity)
    }

    @Test func anyColorEditBreaksRecipeIdentity() {
        var recipe = PhotoEditRecipe.identity
        recipe.color.mixer.red.hue = 0.2
        #expect(!recipe.isIdentity)

        var grading = PhotoEditRecipe.identity
        grading.color.grading.shadows.saturation = 0.3
        #expect(!grading.isIdentity)
    }

    @Test func fullColorRecipeRoundTrips() throws {
        var color = PhotoColorRecipe.identity
        for band in ColorMixerBand.allCases {
            color.mixer[band].hue = 0.1
            color.mixer[band].saturation = -0.2
            color.mixer[band].luminance = 0.3
        }
        color.points = [
            PointColorAdjustment(
                referenceHue: 210,
                referenceSaturation: 0.7,
                referenceValue: 0.5,
                hueShift: 0.4,
                saturationShift: -0.1,
                luminanceShift: 0.2,
                range: 0.8
            ),
            PointColorAdjustment(
                referenceHue: 30,
                referenceSaturation: 0.9,
                referenceValue: 0.9
            ),
        ]
        color.grading.shadows = .init()
        color.grading.shadows.hue = 220
        color.grading.shadows.saturation = 0.4
        color.grading.highlights.hue = 45
        color.grading.highlights.saturation = 0.25
        color.grading.midtones.luminance = -0.3
        color.grading.blending = 0.65
        color.grading.balance = -0.4

        var recipe = PhotoEditRecipe.identity
        recipe.color = color
        let decoded = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded == recipe)
        #expect(decoded.color == color)
    }

    @Test func untouchedColorEncodesNoKeyAtAll() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.5
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(recipe)
        ) as? [String: Any]
        #expect(object?["color"] == nil)
    }

    @Test func mixerOnlyEncodesTouchedBands() throws {
        var mixer = ColorMixerAdjustments.identity
        mixer.aqua.saturation = -0.5
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(mixer)
        ) as? [String: Any]
        #expect(object?.keys.sorted() == ["aqua"])
        let aqua = object?["aqua"] as? [String: Any]
        #expect(aqua?.keys.sorted() == ["saturation"])
    }

    @Test func gradingSkipsIdentityWheelsAndDefaults() throws {
        var grading = ColorGradingAdjustments.identity
        grading.midtones.hue = 120
        grading.midtones.saturation = 0.5
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(grading)
        ) as? [String: Any]
        #expect(object?.keys.sorted() == ["midtones"])
    }

    @Test func recipeSavedByAnEarlierBuildDecodesWithIdentityColor() throws {
        let json = Data(
            """
            {"source":"raw","adjustments":{"exposure":0.5},"filter":"vivid"}
            """.utf8
        )
        let recipe = try JSONDecoder().decode(PhotoEditRecipe.self, from: json)
        #expect(recipe.color == .identity)
        #expect(recipe.adjustments.exposure == 0.5)
        #expect(recipe.filter == .vivid)
    }

    @Test func bandCentersAreDistinctAndOrderedOnTheWheel() {
        let centers = ColorMixerBand.allCases.map(\.centerDegrees)
        #expect(centers == centers.sorted())
        #expect(Set(centers).count == centers.count)
        #expect(centers.allSatisfy { $0 >= 0 && $0 < 360 })
    }

    @Test func pointColorCapIsEight() {
        #expect(PointColorAdjustment.maximumCount == 8)
    }
}
