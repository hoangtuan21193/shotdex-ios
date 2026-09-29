import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct LookExportXMPTests {
    /// FS-03.14 AC-c3. Exposure +0.50, Lens Correction on, film look Velvia:
    /// crs:Exposure2012 "+0.50", LensProfileEnable "1" with Setup "Auto", no
    /// film look tag; the sheet's line names Velvia. The file reads back
    /// through ShotDex's own reader to the same Exposure.
    @Test func writesCrsAndDropsFilmLook() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments[.exposure] = 0.5
        recipe.adjustments[.lensCorrection] = 1
        recipe.filter = .velvia
        let output = LookXMPWriter.write(LookPreset(name: "Golden", recipe: recipe))
        let xmp = String(decoding: output.data, as: UTF8.self)
        #expect(xmp.contains(#"crs:Exposure2012="+0.50""#))
        #expect(xmp.contains(#"crs:LensProfileEnable="1""#))
        #expect(xmp.contains(#"crs:LensProfileSetup="Auto""#))
        #expect(!xmp.contains("CameraProfile"))
        #expect(output.lostSettings == ["Film look \(PhotoFilter.velvia.displayName)"])
        #expect(LookExport.lostLine(output.lostSettings, into: "an .xmp")
            == "Film look \(PhotoFilter.velvia.displayName) doesn't carry into an .xmp")
        #expect(LookExport.lostLine(["A", "B", "C"], into: "a .cube") == "A, B and C don't carry into a .cube")
        #expect(LookExport.lostLine([], into: "an .xmp") == nil)
        #expect(LookXMPWriter.notAffiliated == "ShotDex is not affiliated with or endorsed by Adobe.")

        let back = LightroomMapping.map(try LightroomXMPReader.read(output.data))
        #expect(back.recipe.adjustments[.exposure] == 0.5)
        #expect(try LightroomXMPReader.read(output.data).name == "Golden")
    }

    /// The table round-trips: contrast, a mixer band, grading and a curve
    /// written out come back as they were.
    @Test func theTableRunsBackwards() throws {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments[.contrast] = -0.3
        recipe.adjustments[.sharpness] = 0.4
        recipe.color.mixer[.blue].saturation = 0.25
        recipe.color.grading.shadows.hue = 210
        recipe.color.grading.shadows.saturation = 0.2
        recipe.curve.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 128.0 / 255, y: 153.0 / 255), CurvePoint(x: 1, y: 1)]
        let written = LookXMPWriter.write(LookPreset(name: "Round", recipe: recipe)).data
        let back = LightroomMapping.map(try LightroomXMPReader.read(written)).recipe
        #expect(abs(back.adjustments[.contrast] + 0.3) < 0.006)
        #expect(abs(back.adjustments[.sharpness] - 0.4) < 0.006)
        #expect(abs(back.color.mixer[.blue].saturation - 0.25) < 0.006)
        #expect(back.color.grading.shadows.hue == 210)
        #expect(abs(back.curve.rgb[1].y - 0.6) < 0.003)
    }
}
