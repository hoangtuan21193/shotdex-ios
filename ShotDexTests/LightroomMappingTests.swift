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

    /// FS-03.14 AC-b8 (D37). An adaptive preset: a Sky mask with Exposure
    /// −0.70 inside it and Vibrance +20 on the whole photo. The look has
    /// Vibrance +20, no mask, no Exposure among its settings; ✕ "Masks stay
    /// with each photo"; ≈ row.
    @Test func masksAreNeverImported() throws {
        let body = """
        <crs:MaskGroupBasedCorrections>
         <rdf:Seq>
          <rdf:li>
           <rdf:Description crs:What="Correction" crs:CorrectionAmount="1" crs:LocalExposure2012="-0.70">
            <crs:CorrectionMasks>
             <rdf:Seq><rdf:li crs:What="Mask/Image" crs:MaskSubType="2"/></rdf:Seq>
            </crs:CorrectionMasks>
           </rdf:Description>
          </rdf:li>
         </rdf:Seq>
        </crs:MaskGroupBasedCorrections>
        """
        let result = try map(#"crs:Vibrance="+20""#, body: body)
        #expect(result.recipe.masks.isEmpty)
        #expect(abs(result.recipe.adjustments[.vibrance] - 0.2) < 1e-9)
        #expect(result.recipe.adjustments[.exposure] == 0)
        #expect(!result.namedSettings.contains(.adjustment(.exposure)))
        #expect(result.lines == [PresetReportLine(kind: .skipped, text: "Masks stay with each photo")])
    }

    /// FS-03.14 AC-b7. Point Color and Clarity +15: Clarity +15, and one ✕
    /// "Point Color from Lightroom isn't in ShotDex yet" (FS-03.15 shipped
    /// first, so the tone-curve regions this AC once used now land).
    @Test func missingTargetsAreSkippedWithAReason() throws {
        let body = "<crs:PointColors><rdf:Seq><rdf:li>12.5, 0.4, 0.6, 0, 0, 0, 0.1, 0.2, 0.3</rdf:li></rdf:Seq></crs:PointColors>"
        let result = try map(#"crs:Clarity2012="+15" crs:ParametricShadows="-20""#, body: body)
        #expect(abs(result.recipe.adjustments[.clarity] - 0.15) < 1e-9)
        #expect(abs(result.recipe.curve.region.shadows + 0.2) < 1e-9, "the regions have a home now")
        #expect(result.lines == [PresetReportLine(kind: .skipped, text: "Point Color from Lightroom isn't in ShotDex yet")])
    }

    /// The table's scales, spot-checked across groups: Sharpness 0…150,
    /// Color Grading's split-toning names and 0…360 hue, the point curve on
    /// 0…255, B&W Mix, calibration, lens scale 0…200 and PV2010 tags.
    @Test func everyGroupLandsOnItsSlider() throws {
        let body = """
        <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>128, 153</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
        """
        let attributes = [
            #"crs:Sharpness="150""#, #"crs:SplitToningShadowHue="200""#, #"crs:SplitToningShadowSaturation="30""#,
            #"crs:ColorGradeShadowLum="-10""#, #"crs:ColorGradeBlending="50""#, #"crs:GrayMixerRed="-40""#,
            #"crs:RedHue="+12""#, #"crs:LensProfileDistortionScale="200""#, #"crs:ConvertToGrayscale="True""#,
            #"crs:PostCropVignetteStyle="2""#, #"crs:DefringePurpleAmount="10""#, #"crs:FillLight="20""#,
        ].joined(separator: " ")
        let result = try map(attributes, body: body)
        let recipe = result.recipe
        #expect(recipe.adjustments[.sharpness] == 1)
        #expect(recipe.color.grading.shadows.hue == 200)
        #expect(abs(recipe.color.grading.shadows.saturation - 0.3) < 1e-9)
        #expect(abs(recipe.color.grading.shadows.luminance + 0.1) < 1e-9)
        #expect(abs(recipe.color.grayMixer[.red] + 0.4) < 1e-9)
        #expect(abs(recipe.color.calibration.redHue - 0.12) < 1e-9)
        #expect(recipe.adjustments[.lensDistortionScale] == 2)
        #expect(recipe.adjustments[.blackAndWhite] == 1)
        #expect(recipe.vignetteStyle == .colorPriority)
        #expect(abs(recipe.adjustments[.defringePurpleAmount] - 0.5) < 1e-9)
        #expect(recipe.curve.rgb.count == 3)
        #expect(abs(recipe.curve.rgb[1].y - 0.6) < 1e-9)
        #expect(result.lines.contains(PresetReportLine(kind: .skipped, text: "Settings from Lightroom 3 or older")))
    }

    /// FS-03.14 AC-b5 (E7). WhiteBalance Custom, Temperature 5500, Tint +10:
    /// the look carries the absolute pair — not an offset from As Shot — and
    /// on a RAW the decoder's neutral is exactly 5500 K / +10 whatever the
    /// file's As Shot; ✓. (A JPEG ignores the pair:
    /// `RawWhiteBalanceTests.jpegIgnoresAbsoluteWhiteBalance`.)
    @Test func absoluteWhiteBalanceIsRAWOnly() throws {
        let result = try map(#"crs:WhiteBalance="Custom" crs:Temperature="5500" crs:Tint="+10""#)
        #expect(result.recipe.adjustments.rawWhiteBalanceKelvin == 5_500)
        #expect(result.recipe.adjustments.rawWhiteBalanceTint == 10)
        #expect(result.recipe.adjustments.rawTemperature == 0)
        #expect(result.lines.isEmpty)
        #expect(result.namedSettings == [.rawWhiteBalance])
        for asShot in [4_800.0, 6_500.0] {
            let neutral = RAWWhiteBalance.neutral(asShotKelvin: asShot, asShotTint: 3, adjustments: result.recipe.adjustments)
            #expect(neutral.kelvin == 5_500 && neutral.tint == 10)
        }
        let asShot = try map(#"crs:WhiteBalance="As Shot" crs:Temperature="5500""#)
        #expect(asShot.recipe.adjustments.rawWhiteBalanceKelvin == nil)
        var look = LookPreset(name: "WB", recipe: result.recipe)
        look.namedSettings = result.namedSettings
        let applied = look.applied(onto: .identity)
        #expect(applied.adjustments.rawWhiteBalanceKelvin == 5_500)
    }
}
