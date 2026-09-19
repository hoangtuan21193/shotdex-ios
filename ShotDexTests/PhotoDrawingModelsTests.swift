import Foundation
import Testing
@testable import ShotDexKit

@testable import ShotDex

struct PhotoDrawingModelsTests {

    /// Top-level keys a recipe writes, order-independent.
    private func keys(of recipe: PhotoEditRecipe) throws -> Set<String> {
        let data = try JSONEncoder().encode(recipe)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set(object?.keys ?? [:].keys)
    }

    private func drawing(_ bytes: [UInt8] = [1, 2, 3]) -> PhotoDrawing {
        PhotoDrawing(data: Data(bytes), canvasWidth: 300, canvasHeight: 200)
    }

    @Test func emptyDrawingReadsAsIdentity() {
        #expect(PhotoDrawing(data: Data(), canvasWidth: 300, canvasHeight: 200).isEmpty)
        #expect(PhotoDrawing(data: Data([1]), canvasWidth: 0, canvasHeight: 200).isEmpty)
        #expect(!drawing().isEmpty)
    }

    @Test func recipeWithADrawingRoundTrips() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.drawing = drawing()
        #expect(!recipe.isIdentity)

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        #expect(decoded.drawing == recipe.drawing)
    }

    @Test func anEmptyDrawingAddsNoKeyAndStaysIdentity() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.drawing = PhotoDrawing(data: Data(), canvasWidth: 300, canvasHeight: 200)
        #expect(recipe.isIdentity)

        // The same keys as a recipe that never touched the drawing at all.
        //
        // Compared as parsed objects, not as bytes: `JSONEncoder` makes no
        // promise about key order, and two encodes of the same value really do
        // come out in different orders.
        let withEmpty = try keys(of: recipe)
        let untouched = try keys(of: .identity)
        #expect(withEmpty == untouched)
        #expect(!withEmpty.contains("drawing"))
    }

    @Test func aRecipeSavedBeforeDrawingExistedDecodesWithNoDrawing() throws {
        // An identity recipe never writes the `drawing` key — the same wire shape a
        // build from before the feature produced. It must decode with `drawing` nil.
        let json = try JSONEncoder().encode(PhotoEditRecipe.identity)
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(object?["drawing"] == nil)
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: json)
        #expect(decoded.drawing == nil)
    }

    @Test func addingADrawingIsNotIdentity() {
        var recipe = PhotoEditRecipe.identity
        recipe.drawing = drawing()
        #expect(!recipe.isIdentity)
        recipe.drawing = nil
        #expect(recipe.isIdentity)
    }
}
