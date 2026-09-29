import Foundation
import ShotDexKit

/// A look as a Lightroom `.xmp` preset (FS-03.14c §1): FS-03.14b's table run
/// backwards. Approximate by nature — what has no `crs:` home is listed in
/// `notes` so the export sheet can say it before the file leaves.
enum LookXMPWriter {
    struct Output {
        var data: Data
        /// "Film look Velvia, Brilliance" — what does not carry.
        var lostSettings: [String]
    }

    /// The two lines the export sheet always carries (14 §7).
    static let explanation = "Export presets in XMP format for use with Adobe Lightroom."
    static let notAffiliated = "ShotDex is not affiliated with or endorsed by Adobe."

    static func write(_ preset: LookPreset) -> Output {
        let recipe = EditorSyncScope.look.apply(preset.recipe, onto: .identity)
        var attributes: [(String, String)] = [
            ("PresetType", "Normal"), ("Version", "15.4"), ("ProcessVersion", "11.0"), ("HasSettings", "True"),
        ]
        var lost: [String] = []
        let defaults = PhotoAdjustments()

        // Sliders with a row in the table, backwards.
        let rows = LightroomMappingTable.adjustments.sorted { $0.key < $1.key }
        var written: Set<PhotoAdjustmentKind> = []
        for (tag, row) in rows where recipe.adjustments[row.kind] != defaults[row.kind] {
            written.insert(row.kind)
            attributes.append((tag, format(tag: tag, lightroomValue(row, recipe.adjustments[row.kind]))))
        }
        // Switches.
        if recipe.adjustments.lensCorrection >= 0.5 {
            attributes.append(("LensProfileEnable", "1"))
            attributes.append(("LensProfileSetup", "Auto"))
        }
        written.insert(.lensCorrection)
        if recipe.adjustments.blackAndWhite >= 0.5 { attributes.append(("ConvertToGrayscale", "True")) }
        written.insert(.blackAndWhite)
        if let kelvin = recipe.adjustments.rawWhiteBalanceKelvin {
            attributes.append(("WhiteBalance", "Custom"))
            attributes.append(("Temperature", String(Int(kelvin.rounded()))))
            attributes.append(("Tint", signedInteger(recipe.adjustments.rawWhiteBalanceTint ?? 0)))
        }
        // Mixer, B&W mix, calibration, grading, region curve.
        let bands: [(ColorMixerBand, String)] = [
            (.red, "Red"), (.orange, "Orange"), (.yellow, "Yellow"), (.green, "Green"),
            (.aqua, "Aqua"), (.blue, "Blue"), (.purple, "Purple"), (.magenta, "Magenta"),
        ]
        for (band, name) in bands {
            let channel = recipe.color.mixer[band]
            if channel.hue != 0 { attributes.append(("HueAdjustment\(name)", signedInteger(channel.hue * 100))) }
            if channel.saturation != 0 { attributes.append(("SaturationAdjustment\(name)", signedInteger(channel.saturation * 100))) }
            if channel.luminance != 0 { attributes.append(("LuminanceAdjustment\(name)", signedInteger(channel.luminance * 100))) }
            if recipe.color.grayMixer[band] != 0 { attributes.append(("GrayMixer\(name)", signedInteger(recipe.color.grayMixer[band] * 100))) }
        }
        let calibration = recipe.color.calibration
        for (tag, value) in [("ShadowTint", calibration.shadowTint), ("RedHue", calibration.redHue), ("RedSaturation", calibration.redSaturation),
                             ("GreenHue", calibration.greenHue), ("GreenSaturation", calibration.greenSaturation),
                             ("BlueHue", calibration.blueHue), ("BlueSaturation", calibration.blueSaturation)] where value != 0 {
            attributes.append((tag, signedInteger(value * 100)))
        }
        let grading = recipe.color.grading
        let wheels: [(ColorGradingRegion, hue: String, sat: String, lum: String)] = [
            (.shadows, "SplitToningShadowHue", "SplitToningShadowSaturation", "ColorGradeShadowLum"),
            (.highlights, "SplitToningHighlightHue", "SplitToningHighlightSaturation", "ColorGradeHighlightLum"),
            (.midtones, "ColorGradeMidtoneHue", "ColorGradeMidtoneSat", "ColorGradeMidtoneLum"),
            (.global, "ColorGradeGlobalHue", "ColorGradeGlobalSat", "ColorGradeGlobalLum"),
        ]
        for wheel in wheels where !grading[wheel.0].isIdentity {
            attributes.append((wheel.hue, String(Int(grading[wheel.0].hue.rounded()))))
            attributes.append((wheel.sat, String(Int((grading[wheel.0].saturation * 100).rounded()))))
            attributes.append((wheel.lum, signedInteger(grading[wheel.0].luminance * 100)))
        }
        if grading.blending != ColorGradingAdjustments.identity.blending {
            attributes.append(("ColorGradeBlending", String(Int((grading.blending * 100).rounded()))))
        }
        if grading.balance != 0 { attributes.append(("SplitToningBalance", signedInteger(grading.balance * 100))) }
        let region = recipe.curve.region
        if region != .identity {
            attributes += [("ParametricShadows", signedInteger(region.shadows * 100)), ("ParametricDarks", signedInteger(region.darks * 100)),
                           ("ParametricLights", signedInteger(region.lights * 100)), ("ParametricHighlights", signedInteger(region.highlights * 100)),
                           ("ParametricShadowSplit", String(Int((region.shadowSplit * 100).rounded()))),
                           ("ParametricMidtoneSplit", String(Int((region.midtoneSplit * 100).rounded()))),
                           ("ParametricHighlightSplit", String(Int((region.highlightSplit * 100).rounded())))]
        }
        if recipe.vignetteStyle != .highlightPriority {
            attributes.append(("PostCropVignetteStyle", recipe.vignetteStyle == .colorPriority ? "2" : "3"))
        }

        // What has no home in Lightroom.
        if recipe.lutID == nil, recipe.filter != .original { lost.append("Film look \(recipe.filter.displayName)") }
        if recipe.lutID != nil { lost.append("The LUT") }
        for kind in PhotoAdjustmentKind.allCases where !written.contains(kind) && !kind.isRAWOnly && recipe.adjustments[kind] != defaults[kind] {
            lost.append(kind.displayName)
        }

        let curves = ToneCurveChannel.allCases.compactMap { channel -> (String, [CurvePoint])? in
            let points = recipe.curve[channel]
            guard points != ToneCurveAdjustments.linear else { return nil }
            let tag = channel == .rgb ? "ToneCurvePV2012" : "ToneCurvePV2012\(channel.rawValue.capitalized)"
            return (tag, points)
        }
        return Output(data: Data(document(name: preset.name, attributes: attributes, curves: curves).utf8), lostSettings: lost)
    }

    private static func lightroomValue(_ row: LightroomMappingTable.AdjustmentRow, _ value: Double) -> Double {
        guard let lightroom = row.lightroom else { return value }
        let target = row.target ?? row.kind.range
        let fraction = (value - target.lowerBound) / (target.upperBound - target.lowerBound)
        return min(lightroom.upperBound, max(lightroom.lowerBound, lightroom.lowerBound + fraction * (lightroom.upperBound - lightroom.lowerBound)))
    }

    private static func format(tag: String, _ value: Double) -> String {
        switch tag {
        case "Exposure2012": String(format: "%+.2f", value)
        case "SharpenRadius": String(format: "%.1f", value)
        default: value < 0 || tag.hasPrefix("Perspective") || ["Contrast2012", "Highlights2012", "Shadows2012", "Whites2012",
            "Blacks2012", "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation", "IncrementalTemperature",
            "IncrementalTint", "PostCropVignetteAmount", "PostCropVignetteRoundness", "LensManualDistortionAmount",
            "VignetteAmount"].contains(tag) ? signedInteger(value) : String(Int(value.rounded()))
        }
    }

    private static func signedInteger(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : String(rounded)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func document(name: String, attributes: [(String, String)], curves: [(String, [CurvePoint])]) -> String {
        let attributeText = attributes.map { (pair: (String, String)) -> String in
            "\n    crs:\(pair.0)=\"\(escaped(pair.1))\""
        }.joined()
        // `-> String` spelled out: GRDB's SQL is string-interpolatable too,
        // and an unannotated closure here was inferred as SQL.
        let curveText = curves.map { (tag: String, points: [CurvePoint]) -> String in
            let items = points.map { (point: CurvePoint) -> String in
                "<rdf:li>\(Int((point.x * 255).rounded())), \(Int((point.y * 255).rounded()))</rdf:li>"
            }.joined()
            return "\n   <crs:\(tag)><rdf:Seq>\(items)</rdf:Seq></crs:\(tag)>"
        }.joined()
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="ShotDex">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"\(attributeText)>
           <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(escaped(name))</rdf:li></rdf:Alt></crs:Name>\(curveText)
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>

        """
    }
}
