import Foundation
import Testing
@testable import ShotDex

struct PhotoEditingModelsTests {
    @Test func longEdgePresetNeverUpscales() {
        let result = ResizePreset.twoK.targetPixelSize(sourceWidth: 800, sourceHeight: 600)
        #expect(result.width == 800)
        #expect(result.height == 600)
    }

    @Test func exactLongEdgePresetUpscalesTo1080() {
        let result = ResizePreset.social.targetPixelSize(sourceWidth: 800, sourceHeight: 600)
        #expect(result.width == 1_080)
        #expect(result.height == 810)
    }

    @Test func longEdgePresetPreservesAspectRatio() {
        let result = ResizePreset.social.targetPixelSize(sourceWidth: 4_000, sourceHeight: 3_000)
        #expect(result.width == 1_080)
        #expect(result.height == 810)
    }

    @Test func exactPresetUsesRequestedDimensions() {
        let preset = ResizePreset(
            name: "Mercari",
            kind: .exact,
            width: 1_080,
            height: 1_350,
            cropMode: .fill
        )
        let result = preset.targetPixelSize(sourceWidth: 4_000, sourceHeight: 3_000)
        #expect(result.width == 1_080)
        #expect(result.height == 1_350)
    }

    @Test func recipeRoundTripsAllMaskData() throws {
        var component = PhotoMaskComponent(kind: .brush)
        component.brushStrokes = [
            BrushStroke(
                points: [.init(x: 0.2, y: 0.3), .init(x: 0.5, y: 0.7)],
                size: 0.12,
                feather: 0.4,
                flow: 0.8,
                isEraser: false
            )
        ]
        var recipe = PhotoEditRecipe.identity
        recipe.sourceAssetIdentifier = "asset/local-id"
        recipe.adjustments.exposure = 0.5
        recipe.masks = [PhotoMask(name: "Face", component: component)]

        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(PhotoEditRecipe.self, from: data) == recipe)
    }

    @Test func recipeSavedByAnEarlierBuildStillDecodes() throws {
        // No filterIntensity, no whites/grain, no masks: exactly what a recipe
        // written before those sliders existed looks like in adjustment data.
        let json = Data(
            """
            {"source":"raw","adjustments":{"exposure":0.5,"lensCorrection":1},"filter":"vivid"}
            """.utf8
        )
        let recipe = try JSONDecoder().decode(PhotoEditRecipe.self, from: json)
        #expect(recipe.source == .raw)
        #expect(recipe.adjustments.exposure == 0.5)
        #expect(recipe.adjustments.whites == 0)
        #expect(recipe.adjustments.grain == 0)
        #expect(recipe.adjustments.lensCorrection == 1)
        #expect(recipe.filter == .vivid)
        #expect(recipe.filterIntensity == 1)
        #expect(recipe.crop == .identity)
        #expect(recipe.masks.isEmpty)
    }

    @Test func adjustmentsOnlyEncodeWhatDiffersFromIdentity() throws {
        var adjustments = PhotoAdjustments.zero
        adjustments.grain = 0.3
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(adjustments)
        ) as? [String: Any]
        #expect(object?.keys.sorted() == ["grain"])
    }

    @Test func filterIntensityRoundTrips() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.filter = .noir
        recipe.filterIntensity = 0.42
        let decoded = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded == recipe)
        #expect(decoded.filterIntensity == 0.42)
    }

    @Test func historyUndoRedo() {
        var history = PhotoEditHistory()
        var initial = PhotoEditRecipe.identity
        var changed = initial
        changed.adjustments.exposure = 1

        history.record(initial)
        #expect(history.undo(current: changed) == initial)
        #expect(history.redo(current: initial) == changed)
    }

    @Test @MainActor func outputFilenameIndexesIncrementIndependently() {
        let suiteName = "PhotoOutputFilenameIndexStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PhotoOutputFilenameIndexStore(defaults: defaults)

        let firstEdit = store.reserve(
            sourceAssetIdentifier: "asset-1",
            suffix: "SHOTDEX_EDITED"
        )
        let secondEdit = store.reserve(
            sourceAssetIdentifier: "asset-1",
            suffix: "SHOTDEX_EDITED"
        )
        let firstCompress = store.reserve(
            sourceAssetIdentifier: "asset-1",
            suffix: "SHOTDEX_COMPRESSED"
        )

        #expect(firstEdit.index == 1)
        #expect(secondEdit.index == 2)
        #expect(firstCompress.index == 1)
    }

    @Test func outputFilenameUsesRequestedSuffixAndIndex() {
        #expect(
            PhotoOutputFilename.make(
                original: "IMG_1234.RAF",
                suffix: "SHOTDEX_EDITED",
                index: 2,
                format: .heic
            ) == "IMG_1234_SHOTDEX_EDITED_2.heic"
        )
        #expect(
            PhotoOutputFilename.make(
                original: "IMG_1234.JPG",
                suffix: "SHOTDEX_COMPRESSED",
                index: 1,
                format: .jpeg
            ) == "IMG_1234_SHOTDEX_COMPRESSED_1.jpg"
        )
    }
}
