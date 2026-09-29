import Foundation
import ShotDexKit

/// The numbers of FS-03.14b §2 as data: which `crs:` tag lands on which
/// ShotDex setting and how its scale maps — linear between the two scales'
/// ends until measured coefficients replace them (§1).
enum LightroomMappingTable {
    struct AdjustmentRow {
        var kind: PhotoAdjustmentKind
        var title: String
        /// Lightroom's scale; nil when both speak the same units (Exposure in EV).
        var lightroom: ClosedRange<Double>?
        /// Units for the "set to" line.
        var unit: String = ""
        /// Where Lightroom's scale lands when it is not the whole ShotDex
        /// range — Sharpness 0…150 onto a slider that also goes negative.
        var target: ClosedRange<Double>?

        func map(_ value: Double) -> Double {
            guard let lightroom else { return value }
            let target = self.target ?? kind.range
            let fraction = (value - lightroom.lowerBound) / (lightroom.upperBound - lightroom.lowerBound)
            return target.lowerBound + fraction * (target.upperBound - target.lowerBound)
        }

        func clampedText(original: Double, set: Double) -> String {
            let range = kind.range
            let limit = range.lowerBound == -range.upperBound
                ? "±\(format(range.upperBound))\(unit)"
                : "\(format(range.lowerBound))…\(format(range.upperBound))\(unit)"
            return "\(title) \(signed(original)) is beyond ShotDex's \(limit) — set to \(signed(set))"
        }

        private func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
        }

        private func signed(_ value: Double) -> String {
            String(format: "%+.2f", value)
        }
    }

    /// Tags the reader sees and the report stays quiet about (14a §3).
    static let administrative: Set<String> = [
        "PresetType", "Cluster", "UUID", "SupportsAmount", "SupportsColor", "SupportsMonochrome",
        "SupportsHighDynamicRange", "SupportsNormalDynamicRange", "SupportsSceneReferred",
        "SupportsOutputReferred", "RequiresRGBTables", "ShowInPresets", "ShowInQuickActions",
        "CameraModelRestriction", "Copyright", "ContactInfo", "Version", "ProcessVersion",
        "HasSettings", "CompatibleVersion", "Group", "SortName", "Description",
        "ToneCurveName", "ToneCurveName2012", "CameraProfileDigest", "LensProfileName", "LensProfileFilename",
        "LensProfileDigest", "LensProfileSetup", "LensProfileIsEmbedded", "UprightVersion", "UprightCenterMode",
        "UprightCenterNormX", "UprightCenterNormY", "UprightFocalMode", "UprightFocalLength35mm",
        "UprightPreview", "UprightTransformCount", "UprightFourSegmentsCount", "OverrideLookVignette",
        "PerspectiveUprightMode",
    ]

    /// Groups a look never takes (14b §4), each one line however many of its
    /// tags a preset carries.
    struct SkippedGroup {
        var message: String
        var matches: (String) -> Bool
    }

    static let skippedGroups: [SkippedGroup] = [
        SkippedGroup(message: "Crop stays with each photo") { $0 == "HasCrop" || $0.hasPrefix("Crop") },
        SkippedGroup(message: "Masks stay with each photo") {
            ["MaskGroupBasedCorrections", "GradientBasedCorrections", "CircularGradientBasedCorrections",
             "PaintBasedCorrections"].contains($0)
        },
        SkippedGroup(message: "Spot fixes belong to one photo") { $0 == "RetouchAreas" || $0 == "RedEyeInfo" || $0 == "RetouchInfo" },
        SkippedGroup(message: "HDR editing isn't in ShotDex") { $0.hasPrefix("HDR") },
    ]

    static func skippedGroup(for tag: String) -> SkippedGroup? {
        skippedGroups.first { $0.matches(tag) }
    }

    private static let hundred: ClosedRange<Double> = -100...100

    static let adjustments: [String: AdjustmentRow] = [
        "Exposure2012": AdjustmentRow(kind: .exposure, title: "Exposure", lightroom: nil, unit: " EV"),
        "Contrast2012": AdjustmentRow(kind: .contrast, title: "Contrast", lightroom: hundred),
        "Highlights2012": AdjustmentRow(kind: .highlights, title: "Highlights", lightroom: hundred),
        "Shadows2012": AdjustmentRow(kind: .shadows, title: "Shadows", lightroom: hundred),
        "Whites2012": AdjustmentRow(kind: .whites, title: "Whites", lightroom: hundred),
        "Blacks2012": AdjustmentRow(kind: .blackPoint, title: "Blacks", lightroom: hundred),
        "Texture": AdjustmentRow(kind: .texture, title: "Texture", lightroom: hundred),
        "Clarity2012": AdjustmentRow(kind: .clarity, title: "Clarity", lightroom: hundred),
        "Dehaze": AdjustmentRow(kind: .dehaze, title: "Dehaze", lightroom: hundred),
        "Vibrance": AdjustmentRow(kind: .vibrance, title: "Vibrance", lightroom: hundred),
        "Saturation": AdjustmentRow(kind: .saturation, title: "Saturation", lightroom: hundred),
        "IncrementalTemperature": AdjustmentRow(kind: .warmth, title: "Temp", lightroom: hundred),
        "IncrementalTint": AdjustmentRow(kind: .tint, title: "Tint", lightroom: hundred),
        // Detail
        "Sharpness": AdjustmentRow(kind: .sharpness, title: "Sharpening", lightroom: 0...150, target: 0...1),
        "SharpenRadius": AdjustmentRow(kind: .sharpenRadius, title: "Radius", lightroom: 0.5...3),
        "SharpenDetail": AdjustmentRow(kind: .sharpenDetail, title: "Detail", lightroom: 0...100),
        "SharpenEdgeMasking": AdjustmentRow(kind: .sharpenMasking, title: "Masking", lightroom: 0...100),
        "LuminanceSmoothing": AdjustmentRow(kind: .noiseReduction, title: "Noise Reduction", lightroom: 0...100),
        "LuminanceNoiseReductionDetail": AdjustmentRow(kind: .noiseDetail, title: "Noise Detail", lightroom: 0...100),
        "LuminanceNoiseReductionContrast": AdjustmentRow(kind: .noiseContrast, title: "Noise Contrast", lightroom: 0...100),
        "ColorNoiseReduction": AdjustmentRow(kind: .colorNoiseReduction, title: "Color Noise", lightroom: 0...100),
        "ColorNoiseReductionDetail": AdjustmentRow(kind: .colorNoiseDetail, title: "Color Noise Detail", lightroom: 0...100),
        "ColorNoiseReductionSmoothness": AdjustmentRow(kind: .colorNoiseSmoothness, title: "Color Noise Smoothness", lightroom: 0...100),
        // Effects
        "PostCropVignetteAmount": AdjustmentRow(kind: .vignette, title: "Vignette", lightroom: hundred),
        "PostCropVignetteMidpoint": AdjustmentRow(kind: .vignetteMidpoint, title: "Vignette Midpoint", lightroom: 0...100),
        "PostCropVignetteFeather": AdjustmentRow(kind: .vignetteFeather, title: "Vignette Feather", lightroom: 0...100),
        "PostCropVignetteRoundness": AdjustmentRow(kind: .vignetteRoundness, title: "Vignette Roundness", lightroom: hundred),
        "PostCropVignetteHighlights": AdjustmentRow(kind: .vignetteHighlights, title: "Vignette Highlights", lightroom: 0...100),
        "GrainAmount": AdjustmentRow(kind: .grain, title: "Grain", lightroom: 0...100),
        "GrainSize": AdjustmentRow(kind: .grainSize, title: "Grain Size", lightroom: 0...100),
        "GrainFrequency": AdjustmentRow(kind: .grainRoughness, title: "Grain Roughness", lightroom: 0...100),
        // Optics
        "AutoLateralCA": AdjustmentRow(kind: .chromaticAberration, title: "Remove Chromatic Aberration", lightroom: 0...1),
        "LensProfileDistortionScale": AdjustmentRow(kind: .lensDistortionScale, title: "Lens Distortion", lightroom: 0...200),
        "LensProfileVignettingScale": AdjustmentRow(kind: .lensVignettingScale, title: "Lens Vignetting", lightroom: 0...200),
        "LensProfileChromaticAberrationScale": AdjustmentRow(kind: .lensChromaticAberrationScale, title: "Lens Chromatic Aberration", lightroom: 0...200),
        "LensManualDistortionAmount": AdjustmentRow(kind: .lensManualDistortion, title: "Manual Distortion", lightroom: hundred),
        "VignetteAmount": AdjustmentRow(kind: .lensManualVignetting, title: "Lens Vignetting Amount", lightroom: hundred),
        "VignetteMidpoint": AdjustmentRow(kind: .lensManualVignettingMidpoint, title: "Lens Vignetting Midpoint", lightroom: 0...100),
        "DefringePurpleAmount": AdjustmentRow(kind: .defringePurpleAmount, title: "Purple Defringe", lightroom: 0...20),
        "DefringePurpleHueLo": AdjustmentRow(kind: .defringePurpleHueMinimum, title: "Purple Hue", lightroom: 0...100),
        "DefringePurpleHueHi": AdjustmentRow(kind: .defringePurpleHueMaximum, title: "Purple Hue", lightroom: 0...100),
        "DefringeGreenAmount": AdjustmentRow(kind: .defringeGreenAmount, title: "Green Defringe", lightroom: 0...20),
        "DefringeGreenHueLo": AdjustmentRow(kind: .defringeGreenHueMinimum, title: "Green Hue", lightroom: 0...100),
        "DefringeGreenHueHi": AdjustmentRow(kind: .defringeGreenHueMaximum, title: "Green Hue", lightroom: 0...100),
        // Transform
        "PerspectiveVertical": AdjustmentRow(kind: .geoVertical, title: "Vertical", lightroom: hundred),
        "PerspectiveHorizontal": AdjustmentRow(kind: .geoHorizontal, title: "Horizontal", lightroom: hundred),
        "PerspectiveAspect": AdjustmentRow(kind: .geoAspect, title: "Aspect", lightroom: hundred),
        "PerspectiveRotate": AdjustmentRow(kind: .geoRotate, title: "Rotate", lightroom: -10...10),
        "PerspectiveScale": AdjustmentRow(kind: .geoScale, title: "Scale", lightroom: 50...150),
        "PerspectiveX": AdjustmentRow(kind: .geoOffsetX, title: "Offset X", lightroom: hundred),
        "PerspectiveY": AdjustmentRow(kind: .geoOffsetY, title: "Offset Y", lightroom: hundred),
    ]

    /// A setting that has a ShotDex home outside `PhotoAdjustments`.
    enum StructuredTarget {
        case grayMixer(ColorMixerBand)
        case calibration(WritableKeyPath<PhotoCalibration, Double>, key: String)
        case gradingHue(ColorGradingRegion)
        case gradingSaturation(ColorGradingRegion)
        case gradingLuminance(ColorGradingRegion)
        case gradingBlending
        case gradingBalance
        case region(WritableKeyPath<ParametricCurve, Double>, key: String, isSplit: Bool)
    }

    static func structuredTarget(_ tag: String) -> StructuredTarget? {
        if tag.hasPrefix("GrayMixer"), let band = bandNames[String(tag.dropFirst("GrayMixer".count))] {
            return .grayMixer(band)
        }
        switch tag {
        case "ShadowTint": return .calibration(\.shadowTint, key: "shadowTint")
        case "RedHue": return .calibration(\.redHue, key: "redHue")
        case "RedSaturation": return .calibration(\.redSaturation, key: "redSaturation")
        case "GreenHue": return .calibration(\.greenHue, key: "greenHue")
        case "GreenSaturation": return .calibration(\.greenSaturation, key: "greenSaturation")
        case "BlueHue": return .calibration(\.blueHue, key: "blueHue")
        case "BlueSaturation": return .calibration(\.blueSaturation, key: "blueSaturation")
        // Color Grading: the Shadows and Highlights wheels keep the legacy
        // SplitToning names for hue and saturation (câu treo 3).
        case "SplitToningShadowHue": return .gradingHue(.shadows)
        case "SplitToningShadowSaturation": return .gradingSaturation(.shadows)
        case "ColorGradeShadowLum": return .gradingLuminance(.shadows)
        case "SplitToningHighlightHue": return .gradingHue(.highlights)
        case "SplitToningHighlightSaturation": return .gradingSaturation(.highlights)
        case "ColorGradeHighlightLum": return .gradingLuminance(.highlights)
        case "ColorGradeMidtoneHue": return .gradingHue(.midtones)
        case "ColorGradeMidtoneSat": return .gradingSaturation(.midtones)
        case "ColorGradeMidtoneLum": return .gradingLuminance(.midtones)
        case "ColorGradeGlobalHue": return .gradingHue(.global)
        case "ColorGradeGlobalSat": return .gradingSaturation(.global)
        case "ColorGradeGlobalLum": return .gradingLuminance(.global)
        case "ColorGradeBlending": return .gradingBlending
        case "SplitToningBalance": return .gradingBalance
        case "ParametricShadows": return .region(\.shadows, key: "shadows", isSplit: false)
        case "ParametricDarks": return .region(\.darks, key: "darks", isSplit: false)
        case "ParametricLights": return .region(\.lights, key: "lights", isSplit: false)
        case "ParametricHighlights": return .region(\.highlights, key: "highlights", isSplit: false)
        case "ParametricShadowSplit": return .region(\.shadowSplit, key: "shadowSplit", isSplit: true)
        case "ParametricMidtoneSplit": return .region(\.midtoneSplit, key: "midtoneSplit", isSplit: true)
        case "ParametricHighlightSplit": return .region(\.highlightSplit, key: "highlightSplit", isSplit: true)
        default: return nil
        }
    }

    /// Tone curve lists: "0, 0", "128, 140"… on 0…255.
    static let curveLists: [String: ToneCurveChannel] = [
        "ToneCurvePV2012": .rgb, "ToneCurvePV2012Red": .red,
        "ToneCurvePV2012Green": .green, "ToneCurvePV2012Blue": .blue,
    ]

    /// Lightroom 3 and older (Process Version 2010) — one ✕ line (§1).
    static let legacyProcess: Set<String> = ["Exposure", "FillLight", "Recovery", "Brightness", "Contrast", "Clarity"]

    /// Settings ShotDex has no place for yet, with the ✕ line each gets (§5).
    static let notInShotDex: [String: String] = [
        "PointColors": "Point Color from Lightroom isn't in ShotDex yet",
        "PerspectiveUpright": "Upright is worked out on each photo — not carried in a look",
    ]

    private static let bandNames: [String: ColorMixerBand] = [
        "Red": .red, "Orange": .orange, "Yellow": .yellow, "Green": .green,
        "Aqua": .aqua, "Blue": .blue, "Purple": .purple, "Magenta": .magenta,
    ]

    /// `HueAdjustmentRed` … `LuminanceAdjustmentMagenta` → a mixer band and
    /// property, −100…100 onto −1…1.
    static func mixerTarget(_ tag: String) -> (ColorMixerBand, ColorMixerProperty)? {
        for (prefix, property) in [("HueAdjustment", ColorMixerProperty.hue),
                                   ("SaturationAdjustment", .saturation),
                                   ("LuminanceAdjustment", .luminance)] where tag.hasPrefix(prefix) {
            if let band = bandNames[String(tag.dropFirst(prefix.count))] { return (band, property) }
        }
        return nil
    }
}
