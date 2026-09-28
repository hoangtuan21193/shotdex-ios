import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.16a §5–6 — what the lens correction passes do to pixels.
struct LensCorrectionRenderTests {

    /// A lens with strong barrel distortion, so the correction is plain.
    static let barrelID = "Canon|Canon EF 24-70mm f/2.8L II USM|1.0"

    static func jpeg() async throws -> (PhotoRenderSourceInfo, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lens-\(UUID().uuidString)")
        return (try await LensBlurTests.jpegSource(in: directory), directory)
    }

    /// AC-7. The one switch: on, a Lensfun profile corrects the JPEG; off,
    /// it renders as if there were no profile at all. The RAW half (Apple's
    /// correction off with the switch) is the decoder flag
    /// `isLensCorrectionEnabled = switch && usesAppleBuiltIn`, proven on a
    /// RAW file in the simulator.
    @Test func switchOffDisablesBuiltInAndProfile() async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lens = try #require(LensProfileLibrary.shared.lenses.first { !$0.distortion.isEmpty && $0.cropFactor == 1 })
        let renderer = PhotoRenderService()
        var on = PhotoEditRecipe.identity
        on.lensProfile = PhotoLensProfileChoice(lensID: lens.id, cameraCropFactor: 1, isAutomatic: true)
        var off = on
        off.adjustments.lensCorrection = 0
        let plain = try await renderer.render(source: source, recipe: .identity).image
        let corrected = try await renderer.render(source: source, recipe: on).image
        let switchedOff = try await renderer.render(source: source, recipe: off).image
        #expect(LensBlurTests.meanDifference(corrected, plain) > 1, "the profile should change the picture")
        #expect(LensBlurTests.meanDifference(switchedOff, plain) <= 1)
    }

    /// AC-6. The lens id is gone from the table: the render has no profile
    /// step (the photo as shot), and does not crash.
    @Test func missingLensIDRendersUncorrected() async throws {
        let (source, directory) = try await Self.jpeg()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderer = PhotoRenderService()
        var recipe = PhotoEditRecipe.identity
        recipe.lensProfile = PhotoLensProfileChoice(lensID: "Gone|Nothing 1mm f/1|1.0", cameraCropFactor: 1, isAutomatic: true)
        recipe.adjustments.lensDistortionScale = 2
        let stale = try await renderer.render(source: source, recipe: recipe).image
        let plain = try await renderer.render(source: source, recipe: .identity).image
        #expect(LensBlurTests.meanDifference(stale, plain) <= 1)
    }
}
