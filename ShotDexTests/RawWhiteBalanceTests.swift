import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.14b E7 and FS-03.04 §2 — the RAW white balance handed to the decoder.
struct RawWhiteBalanceTests {
    /// An absolute Kelvin and Tint are taken as they are; the As Shot
    /// offsets are ignored while they are set.
    @Test func absoluteKelvinOverridesTheAsShotOffset() {
        var adjustments = PhotoAdjustments()
        adjustments.rawTemperature = 0.5
        adjustments.rawTint = -0.2
        let offset = RAWWhiteBalance.neutral(asShotKelvin: 5_200, asShotTint: 4, adjustments: adjustments)
        // Measured: a higher neutral temperature warms, so the warm half of
        // the slider adds.
        #expect(offset.kelvin == 5_200 + 2_000)
        #expect(offset.tint == 4 - 30)
        adjustments.rawWhiteBalanceKelvin = 5_500
        adjustments.rawWhiteBalanceTint = 10
        let absolute = RAWWhiteBalance.neutral(asShotKelvin: 5_200, asShotTint: 4, adjustments: adjustments)
        #expect(absolute.kelvin == 5_500)
        #expect(absolute.tint == 10)
        adjustments.rawWhiteBalanceKelvin = 90_000
        #expect(RAWWhiteBalance.neutral(asShotKelvin: 5_200, asShotTint: 4, adjustments: adjustments).kelvin == 50_000)
    }

    /// The pair survives a save and a reload, and a recipe without it
    /// encodes no key for it.
    @Test func theAbsolutePairRoundTrips() throws {
        var recipe = PhotoEditRecipe.identity
        #expect(!(String(data: try JSONEncoder().encode(recipe), encoding: .utf8) ?? "").contains("rawWhiteBalance"))
        recipe.adjustments.rawWhiteBalanceKelvin = 5_500
        recipe.adjustments.rawWhiteBalanceTint = 10
        let decoded = try JSONDecoder().decode(PhotoEditRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded.adjustments.rawWhiteBalanceKelvin == 5_500)
        #expect(decoded.adjustments.rawWhiteBalanceTint == 10)
    }

    /// A JPEG has no decoder white balance: the absolute pair changes none
    /// of its pixels.
    @Test func jpegIgnoresAbsoluteWhiteBalance() throws {
        let photo = CIImage(color: CIColor(red: 0.6, green: 0.45, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        var with = PhotoAdjustments()
        with.rawWhiteBalanceKelvin = 3_000
        with.rawWhiteBalanceTint = 60
        let plain = PhotoRenderService.applyAdjustments(PhotoAdjustments(), to: photo, appliesExposure: true)
        let changed = PhotoRenderService.applyAdjustments(with, to: photo, appliesExposure: true)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        func pixel(_ image: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 16, y: 16, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return bytes
        }
        #expect(pixel(plain) == pixel(changed))
    }
}
