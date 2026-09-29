import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct LookFileCodecTests {
    /// Classic Chrome at 70%, a three-point curve, the Shadows wheel at hue
    /// 200.
    private func richLook() -> LookPreset {
        var recipe = PhotoEditRecipe.identity
        recipe.filter = .classicChrome
        recipe.filterIntensity = 0.7
        recipe.curve.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.58), CurvePoint(x: 1, y: 1)]
        recipe.color.grading.shadows.hue = 200
        recipe.color.grading.shadows.saturation = 0.3
        recipe.adjustments[.exposure] = 0.25
        return LookPreset(name: "Teal Chrome", recipe: recipe, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    /// FS-03.14 AC-c1. Export, decode: the recipe comes back equal field by
    /// field, with the name, source and date.
    @Test func roundTripIsExact() throws {
        let look = richLook()
        let file = try LookFileCodec.decode(LookFileCodec.encode(look))
        #expect(file.look == look.recipe)
        #expect(file.name == "Teal Chrome")
        #expect(file.source == .shotdex)
        #expect(file.createdAt == look.createdAt)
        #expect(file.format == "com.hoangtuan.shotdex.look")
        #expect(file.schemaVersion == 1)
    }

    /// A look on an imported LUT carries the LUT's text; one without a LUT
    /// carries none.
    @Test func anImportedLUTTravelsInsideTheFile() throws {
        var look = richLook()
        let cube = LookFile.EmbeddedLUT(name: "Teal", cube: "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n")
        #expect(try LookFileCodec.decode(LookFileCodec.encode(look, lut: cube)).lut == nil)
        look.recipe.lutID = "teal-id"
        #expect(try LookFileCodec.decode(LookFileCodec.encode(look, lut: cube)).lut == cube)
    }

    /// FS-03.14 AC-c2. Schema 2 is refused with the reason, before its body
    /// is read.
    @Test func newerSchemaIsRefusedWithReason() throws {
        var json = try #require(String(data: LookFileCodec.encode(richLook()), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        #expect(throws: LookFileError.newerSchema) { try LookFileCodec.decode(Data(json.utf8)) }
        #expect(LookFileError.newerSchema.message == "Made with a newer ShotDex — update the app to add it")
        #expect(throws: LookFileError.notALook) { try LookFileCodec.decode(Data("{\"a\":1}".utf8)) }
    }

    /// FS-03.14 AC-c12. The shared file carries no image — no key that names
    /// one, no base64 blob — and stays under 10 KB.
    @Test func sharedFileCarriesNoImage() throws {
        let data = try LookFileCodec.encode(richLook())
        #expect(data.count < 10_000)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        for key in ["thumbnail", "preview", "image", "jpeg", "png", "heic"] {
            #expect(!json.contains("\"\(key)"), "no \(key) key")
        }
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["format", "schemaVersion", "name", "source", "createdAt", "look"])
    }
}
