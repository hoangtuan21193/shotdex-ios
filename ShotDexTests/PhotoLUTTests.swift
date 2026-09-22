import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-03.11 AC-7…AC-9 — imported `.cube` LUTs as a photo look.
///
/// Serialized: the LUT files live in the one Application Support folder the
/// renderer resolves ids against, so two tests writing there at once would
/// see each other's files.
@Suite(.serialized)
struct PhotoLUTTests {
    /// A 2³ cube that swaps red and blue — red varies fastest.
    private var swapRedAndBlue: String {
        var lines = ["LUT_3D_SIZE 2"]
        for blue in 0...1 {
            for green in 0...1 {
                for red in 0...1 {
                    lines.append("\(blue).0 \(green).0 \(red).0")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func install(_ text: String) throws -> String {
        let id = "test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            at: ImportedLUTFiles.directory(),
            withIntermediateDirectories: true
        )
        try text.write(to: ImportedLUTFiles.fileURL(for: id), atomically: true, encoding: .utf8)
        return id
    }

    private func remove(_ id: String) {
        try? FileManager.default.removeItem(at: ImportedLUTFiles.fileURL(for: id))
        LUTTableCache.shared.forget(id)
    }

    private func pixel(_ image: CIImage) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    private var red: CIImage {
        CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// AC-7. The recipe's LUT is the look, at the look's intensity.
    @Test func recipeLUTIsAppliedAtItsIntensity() throws {
        let id = try install(swapRedAndBlue)
        defer { remove(id) }
        var recipe = PhotoEditRecipe()
        recipe.lutID = id

        let full = pixel(PhotoRenderService.applyLook(of: recipe, to: red))
        #expect(full.r < 5 && full.b > 250, "full strength swaps red into blue")

        recipe.filterIntensity = 0
        let none = pixel(PhotoRenderService.applyLook(of: recipe, to: red))
        #expect(none.r > 250 && none.b < 5, "zero strength leaves the photo alone")
    }

    /// AC-7. The recipe stores the id, and it survives a save and reload.
    @Test func lutIDRoundTrips() throws {
        var recipe = PhotoEditRecipe()
        recipe.lutID = "abc"
        let decoded = try JSONDecoder().decode(
            PhotoEditRecipe.self,
            from: JSONEncoder().encode(recipe)
        )
        #expect(decoded.lutID == "abc")
        #expect(!decoded.isIdentity)
        #expect(PhotoEditRecipe().lutID == nil)
    }

    /// AC-7. A LUT and a film look are one choice: picking either clears the
    /// other, so two looks never stack.
    @MainActor @Test func lutAndFilmLookReplaceEachOther() {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.chooseFilter(.vivid)
        controller.chooseLUT("pack")
        #expect(controller.recipe.lutID == "pack")
        #expect(controller.recipe.filter == .original)

        controller.chooseFilter(.vivid)
        #expect(controller.recipe.lutID == nil)
        #expect(controller.recipe.filter == .vivid)
    }

    /// AC-8. A broken `.cube` says what is wrong with it.
    @Test func brokenCubeNamesTheProblem() {
        let missingSize = LUTImportMessage.text(for: CubeLUTParser.Failure.noSize)
        #expect(missingSize.contains("LUT_3D_SIZE"))
        let short = LUTImportMessage.text(
            for: CubeLUTParser.Failure.wrongRowCount(expected: 35_937, found: 12)
        )
        #expect(short.contains("35937") || short.contains("35,937"))
        #expect(short.contains("12"))
    }

    /// AC-8. And it is refused before it is kept: no empty entry in the list.
    @MainActor @Test func brokenCubeIsNotAdded() throws {
        let store = ImportedLUTStore()
        let before = store.luts.map(\.id)
        let picked = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).cube")
        try "0.0 0.0 0.0\n1.0 1.0 1.0\n".write(to: picked, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: picked) }

        #expect(throws: CubeLUTParser.Failure.noSize) {
            try store.add(from: picked)
        }
        store.reload()
        #expect(store.luts.map(\.id) == before)
    }

    /// AC-9. The LUT's file is deleted: the recipe keeps its id and the render
    /// runs without a look — not with the film look it replaced.
    @Test func deletedLUTRendersWithoutALook() throws {
        let id = try install(swapRedAndBlue)
        var recipe = PhotoEditRecipe()
        recipe.filter = .original
        recipe.lutID = id
        _ = PhotoRenderService.applyLook(of: recipe, to: red)
        remove(id)

        let rendered = pixel(PhotoRenderService.applyLook(of: recipe, to: red))
        #expect(rendered.r > 250 && rendered.b < 5)
        #expect(recipe.lutID == id)
    }
}
