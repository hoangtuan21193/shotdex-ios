import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.14b — Lightroom settings onto a ShotDex look.
struct LightroomMappingTests {
    private func map(_ attributes: String, body: String = "") throws -> LightroomMappingResult {
        LightroomMapping.map(try LightroomXMPReader.read(LightroomXMPReaderTests.preset(attributes, body: body)))
    }

    /// FS-03.14 AC-b3. Exposure2012 +3.00: Exposure +2.00 EV and a ≈ line
    /// that says both numbers.
    @Test func exposureBeyondRangeIsClampedAndReported() throws {
        let result = try map(#"crs:Exposure2012="+3.00""#)
        #expect(result.recipe.adjustments[.exposure] == 2)
        #expect(result.lines == [PresetReportLine(
            kind: .changed,
            text: "Exposure +3.00 is beyond ShotDex's ±2 EV — set to +2.00"
        )])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .addedWithChanges)
    }

    /// FS-03.14 AC-b4. HasCrop, a 4:5 crop and Exposure +0.30: no crop in
    /// the look, Exposure +0.30, one ✕ "Crop stays with each photo", ≈ row.
    @Test func cropIsNeverImported() throws {
        let result = try map(#"crs:HasCrop="True" crs:CropTop="0.05" crs:CropLeft="0.1" crs:CropBottom="0.95" crs:CropRight="0.86" crs:CropAngle="0" crs:CropConstrainToWarp="0" crs:Exposure2012="+0.30""#)
        #expect(result.recipe.crop == PhotoEditRecipe.identity.crop)
        #expect(result.recipe.adjustments[.exposure] == 0.3)
        #expect(result.lines == [PresetReportLine(kind: .skipped, text: "Crop stays with each photo")])
        #expect(PresetImportReport.status(applied: result.appliedCount, lines: result.lines) == .addedWithChanges)
    }
}
