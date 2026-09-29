import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

struct CameraProfileMapTests {
    /// FS-03.14 AC-b1 (E6). A preset with only "Camera CLASSIC CHROME": a
    /// look of Classic Chrome at 100% naming just the film look, ✓; put on a
    /// photo at Exposure +0.50, the photo keeps +0.50 and every other slider.
    @Test func fujiNamesMapToTheSameLook() throws {
        for name in ["Camera CLASSIC CHROME", "classic chrome", "Camera Classic Chrome v2"] {
            #expect(CameraProfileMap.match(name) == .exact(.classicChrome), "\(name)")
        }
        #expect(CameraProfileMap.match("Camera MONOCHROME+Ye FILTER") == .exact(.fujiMonochromeYellow))
        #expect(CameraProfileMap.match("Camera Monochrome") == .near(.mono))

        let settings = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(#"crs:CameraProfile="Camera CLASSIC CHROME""#))
        let result = LightroomMapping.map(settings)
        #expect(result.recipe.filter == .classicChrome)
        #expect(result.recipe.filterIntensity == 1)
        #expect(result.namedSettings == [.filter])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .added)

        var look = LookPreset(name: "Chrome", recipe: result.recipe)
        look.namedSettings = result.namedSettings
        var photo = PhotoEditRecipe.identity
        photo.adjustments[.exposure] = 0.5
        photo.adjustments[.clarity] = 0.2
        photo.color.mixer[.red] = .init()
        let applied = look.applied(onto: photo)
        #expect(applied.filter == .classicChrome)
        #expect(applied.adjustments == photo.adjustments)
        #expect(applied.color == photo.color)
        #expect(applied.curve == photo.curve)
    }

    /// FS-03.14 AC-b2. "Adobe Color" with Vibrance +10: film look Original,
    /// Vibrance +10, a ≈ line naming the profile.
    @Test func unknownProfileFallsBackToOriginal() throws {
        #expect(CameraProfileMap.match("Adobe Color") == .none)
        let settings = try LightroomXMPReader.read(LightroomXMPReaderTests.preset(
            #"crs:CameraProfile="Adobe Color" crs:Vibrance="+10""#
        ))
        let result = LightroomMapping.map(settings)
        #expect(result.recipe.filter == .original)
        #expect(abs(result.recipe.adjustments[.vibrance] - 0.1) < 1e-9)
        #expect(result.lines == [PresetReportLine(kind: .changed, text: "No ShotDex look for profile 'Adobe Color' — Original used")])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .addedWithChanges)
    }
}
