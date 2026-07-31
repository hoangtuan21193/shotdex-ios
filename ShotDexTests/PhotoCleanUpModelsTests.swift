import Foundation
import Testing
@testable import ShotDex

struct PhotoCleanUpModelsTests {
    @Test func freshRecipeHasNoCleanUpStrokes() {
        #expect(PhotoEditRecipe.identity.cleanUpStrokes.isEmpty)
        #expect(PhotoEditRecipe.identity.isIdentity)
    }

    @Test func anyCleanUpStrokeBreaksRecipeIdentity() {
        var recipe = PhotoEditRecipe.identity
        recipe.cleanUpStrokes = [stroke(.remove)]
        #expect(!recipe.isIdentity)
    }

    @Test func allThreeModesRoundTrip() throws {
        var recipe = PhotoEditRecipe.identity
        var clone = stroke(.clone)
        clone.sourceOffsetX = -0.12
        clone.sourceOffsetY = 0.34
        clone.opacity = 0.6
        var heal = stroke(.heal)
        heal.sourceOffsetX = 0.05
        var remove = stroke(.remove)
        remove.usesModel = true
        recipe.cleanUpStrokes = [clone, heal, remove]

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(decoded.cleanUpStrokes == recipe.cleanUpStrokes)
        #expect(decoded.cleanUpStrokes.map(\.mode) == [.clone, .heal, .remove])
        #expect(decoded.cleanUpStrokes[2].usesModel)
        #expect(decoded.cleanUpStrokes[0].opacity == 0.6)
    }

    @Test func untouchedCleanUpEncodesNoKeyAtAll() throws {
        let data = try JSONEncoder().encode(PhotoEditRecipe.identity)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["cleanUpStrokes"] == nil)
    }

    @Test func recipeSavedByAnEarlierBuildDecodesWithNoStrokes() throws {
        let json = """
        {"source":"automatic","filter":"original","filterIntensity":1,
         "adjustments":{},"crop":{"rect":{"x":0,"y":0,"width":1,"height":1},
         "aspect":"free","quarterTurns":0,"straightenDegrees":0,
         "flippedHorizontally":false},"masks":[]}
        """
        let recipe = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: Data(json.utf8)
        )
        #expect(recipe.cleanUpStrokes.isEmpty)
        #expect(recipe.isIdentity)
    }

    @Test func centroidAveragesEveryPaintedPoint() {
        var single = stroke(.remove)
        single.points = [NormalizedPoint(x: 0.25, y: 0.75)]
        #expect(single.centroid.x == 0.25)
        #expect(single.centroid.y == 0.75)

        var path = stroke(.remove)
        path.points = [
            NormalizedPoint(x: 0.2, y: 0.2),
            NormalizedPoint(x: 0.4, y: 0.6),
            NormalizedPoint(x: 0.6, y: 0.4),
        ]
        #expect(abs(path.centroid.x - 0.4) < 0.0001)
        #expect(abs(path.centroid.y - 0.4) < 0.0001)

        var empty = stroke(.remove)
        empty.points = []
        #expect(empty.centroid == NormalizedPoint.center)
        #expect(!empty.hasVisibleEffect)
    }

    @Test func fillSignatureTracksTheFillAndIgnoresCompositing() {
        let base = stroke(.remove)

        var moved = base
        moved.points = [NormalizedPoint(x: 0.5, y: 0.5)]
        #expect(moved.fillSignature != base.fillSignature)

        var resized = base
        resized.size = base.size + 0.05
        #expect(resized.fillSignature != base.fillSignature)

        var feathered = base
        feathered.feather = base.feather + 0.1
        #expect(feathered.fillSignature != base.fillSignature)

        var ai = base
        ai.usesModel = true
        #expect(ai.fillSignature != base.fillSignature)

        var healed = base
        healed.mode = .heal
        #expect(healed.fillSignature != base.fillSignature)

        // Opacity only affects how the finished fill is blended, so it must not
        // invalidate the cache — fading a removal should never re-run PatchMatch.
        var faded = base
        faded.opacity = 0.3
        #expect(faded.fillSignature == base.fillSignature)

        // Remove has no source, so nudging the unused offset changes nothing.
        var nudged = base
        nudged.sourceOffsetX = 0.2
        #expect(nudged.fillSignature == base.fillSignature)

        // Clone does read from the offset, so there it matters.
        var clone = stroke(.clone)
        var clonePushed = clone
        clonePushed.sourceOffsetX = 0.2
        #expect(clonePushed.fillSignature != clone.fillSignature)
        clone.opacity = 0.1
        #expect(clone.fillSignature != clonePushed.fillSignature)
    }

    @Test func fillSeedIsStableAndPerStroke() {
        let one = stroke(.remove)
        let two = stroke(.remove)
        // Derived from the UUID string rather than `hashValue`, which Swift
        // re-seeds every process — a per-process seed would fill the preview and
        // the exported file differently.
        #expect(one.fillSeed == one.fillSeed)
        #expect(one.fillSeed != two.fillSeed)
        #expect(one.fillSeed != 0)
    }

    @Test func onlyCloneAndHealReadASource() {
        #expect(CleanUpMode.clone.usesSourceOffset)
        #expect(CleanUpMode.heal.usesSourceOffset)
        #expect(!CleanUpMode.remove.usesSourceOffset)
        #expect(CleanUpMode.allCases.count == 3)
    }

    private func stroke(_ mode: CleanUpMode) -> CleanUpStroke {
        CleanUpStroke(
            mode: mode,
            points: [NormalizedPoint(x: 0.3, y: 0.4), NormalizedPoint(x: 0.35, y: 0.45)],
            size: 0.12,
            feather: 0.35
        )
    }
}
