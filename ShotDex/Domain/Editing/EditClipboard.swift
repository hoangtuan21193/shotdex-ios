import Foundation
import ShotDexKit

/// The "copy edits / paste edits" clipboard: one recipe, kept between photos
/// and across launches.
///
/// What travels is deliberately **not** the whole recipe. Tone, colour, the
/// curve, the filter and its strength describe a *look*, and a look is the
/// thing worth carrying from one photo to the next. Crop, masks, the drawing
/// and the overlay layers are about one particular frame: pasting a crop would
/// reframe a photo the user never framed, and pasting a mask would brighten a
/// region that on this photo is somebody's face.
///
/// That split is also what Photos and Lightroom settled on, for the same
/// reason.
@MainActor
@Observable
final class EditClipboard {
    private enum Key {
        static let recipe = "edits.clipboard"
    }

    private let defaults: UserDefaults
    private(set) var recipe: PhotoEditRecipe?

    /// Something worth pasting. A copied identity recipe is not offered: the
    /// paste would do nothing and the row would look broken.
    var hasContent: Bool {
        guard let recipe else { return false }
        return !recipe.isIdentity
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recipe) {
            recipe = try? JSONDecoder().decode(PhotoEditRecipe.self, from: data)
        }
    }

    /// Keeps the look out of `source`, and nothing else.
    func copy(from recipe: PhotoEditRecipe) {
        let look = Self.look(of: recipe)
        self.recipe = look
        defaults.set(try? JSONEncoder().encode(look), forKey: Key.recipe)
    }

    /// Lays the copied look over `recipe`, leaving its framing and its layers
    /// alone.
    func paste(onto recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        guard let copied = self.recipe else { return recipe }
        return EditorSyncScope.look.apply(copied, onto: recipe)
    }

    func clear() {
        recipe = nil
        defaults.removeObject(forKey: Key.recipe)
    }

    /// Everything about how the photo looks, with nothing about which photo it
    /// is or how it is framed — `EditorSyncScope.look` laid over nothing.
    static func look(of recipe: PhotoEditRecipe) -> PhotoEditRecipe {
        EditorSyncScope.look.apply(recipe, onto: .identity)
    }
}


/// How much of one photo's edit travels to another.
///
/// The same line `EditClipboard` draws, made explicit because Sync has a second
/// option the clipboard does not: a run shot on a tripod really does want the
/// crop and the masks to come along, and only the user knows which run that is.
enum EditorSyncScope {
    /// Tone, colour, curve and film look. Never the crop, the masks, the markup
    /// or the drawing — a portrait's face mask and 4:5 crop landing on thirty-nine
    /// landscapes is a destructive surprise, and one nobody sees until the batch
    /// has been saved.
    case look
    /// The whole recipe, framing and layers included.
    case everything

    func apply(_ source: PhotoEditRecipe, onto target: PhotoEditRecipe) -> PhotoEditRecipe {
        switch self {
        case .everything:
            // Everything but the lens profile: B may have been shot on another
            // lens, and A's profile would correct it wrongly (FS-03.16 §4,
            // E18). The strengths and the switch come along in `adjustments`.
            var result = source
            result.lensProfile = target.lensProfile
            return result
        case .look:
            // The one place the look is cut — Copy Edits, Paste, Sync Look and
            // My Looks all come through here (FS-03.15 AC-2).
            var result = target
            result.adjustments = source.adjustments
            // Mixer, point colour, grading, B&W mixer and Calibration.
            result.color = source.color
            // Point curves and the region curve.
            result.curve = source.curve
            result.filter = source.filter
            result.lutID = source.lutID
            result.filterIntensity = source.filterIntensity
            result.vignetteStyle = source.vignetteStyle
            // Upright travels as a mode, solved again on this photo; the guides
            // and the solved transform were drawn for the other frame.
            if source.upright.mode != target.upright.mode {
                result.upright = .identity
                result.upright.mode = source.upright.mode
            }
            // Retouch, Red Eye, Lens Blur, crop, masks and layers stay with the frame.
            return result
        }
    }
}

extension EditorSyncScope {
    /// A look imported from a preset changes only the settings the preset
    /// named (FS-03.14b §1, E6); everything else on the photo stays. `named`
    /// nil is a look made in ShotDex: the whole look cut, as `apply` does.
    static func applyLook(_ source: PhotoEditRecipe, named: Set<LookSettingKey>?, onto target: PhotoEditRecipe) -> PhotoEditRecipe {
        guard let named else { return EditorSyncScope.look.apply(source, onto: target) }
        var result = target
        for key in named {
            let parts = key.rawValue.split(separator: ".").map(String.init)
            guard let head = parts.first else { continue }
            switch head {
            case "adjustment":
                if parts.count == 2, let kind = PhotoAdjustmentKind(rawValue: parts[1]) {
                    result.adjustments[kind] = source.adjustments[kind]
                }
            case "mixer":
                if parts.count == 3, let band = ColorMixerBand(rawValue: parts[1]),
                   let property = ColorMixerProperty(rawValue: parts[2]) {
                    var channel = result.color.mixer[band]
                    channel[property] = source.color.mixer[band][property]
                    result.color.mixer[band] = channel
                }
            case "grayMixer":
                if parts.count == 2, let band = ColorMixerBand(rawValue: parts[1]) {
                    result.color.grayMixer[band] = source.color.grayMixer[band]
                }
            case "calibration":
                result.color.calibration = Self.copyCalibration(parts.last ?? "", from: source.color.calibration, onto: result.color.calibration)
            case "grading":
                if parts.count == 2 {
                    if parts[1] == "blending" { result.color.grading.blending = source.color.grading.blending }
                    if parts[1] == "balance" { result.color.grading.balance = source.color.grading.balance }
                } else if parts.count == 3, let region = ColorGradingRegion(rawValue: parts[1]) {
                    switch parts[2] {
                    case "hue": result.color.grading[region].hue = source.color.grading[region].hue
                    case "saturation": result.color.grading[region].saturation = source.color.grading[region].saturation
                    case "luminance": result.color.grading[region].luminance = source.color.grading[region].luminance
                    default: break
                    }
                }
            case "curve":
                if parts.count == 3, parts[1] == "region" {
                    result.curve.region = Self.copyRegion(parts[2], from: source.curve.region, onto: result.curve.region)
                } else if parts.count == 2, let channel = ToneCurveChannel(rawValue: parts[1]) {
                    result.curve[channel] = source.curve[channel]
                }
            case "vignetteStyle":
                result.vignetteStyle = source.vignetteStyle
            case "rawWhiteBalance":
                result.adjustments.rawWhiteBalanceKelvin = source.adjustments.rawWhiteBalanceKelvin
                result.adjustments.rawWhiteBalanceTint = source.adjustments.rawWhiteBalanceTint
            case "filter":
                result.filter = source.filter
                result.lutID = source.lutID
                result.filterIntensity = source.filterIntensity
            default:
                break
            }
        }
        return result
    }

    private static func copyCalibration(_ key: String, from source: PhotoCalibration, onto target: PhotoCalibration) -> PhotoCalibration {
        var result = target
        switch key {
        case "shadowTint": result.shadowTint = source.shadowTint
        case "redHue": result.redHue = source.redHue
        case "redSaturation": result.redSaturation = source.redSaturation
        case "greenHue": result.greenHue = source.greenHue
        case "greenSaturation": result.greenSaturation = source.greenSaturation
        case "blueHue": result.blueHue = source.blueHue
        case "blueSaturation": result.blueSaturation = source.blueSaturation
        default: break
        }
        return result
    }

    private static func copyRegion(_ key: String, from source: ParametricCurve, onto target: ParametricCurve) -> ParametricCurve {
        var result = target
        switch key {
        case "shadows": result.shadows = source.shadows
        case "darks": result.darks = source.darks
        case "lights": result.lights = source.lights
        case "highlights": result.highlights = source.highlights
        case "shadowSplit": result.shadowSplit = source.shadowSplit
        case "midtoneSplit": result.midtoneSplit = source.midtoneSplit
        case "highlightSplit": result.highlightSplit = source.highlightSplit
        default: break
        }
        return result
    }
}
