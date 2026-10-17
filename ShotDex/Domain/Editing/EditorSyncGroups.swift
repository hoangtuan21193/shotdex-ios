import Foundation
import ShotDexKit

/// One tick in the Sync sheet (FS-03.09b, FS-18 03 §3): a named slice of the
/// recipe that travels to the other photos or stays.
///
/// Two columns. **The Look** is everything about how a photo looks, on by
/// default; **This Frame Only** is what was placed on one frame — a crop, a
/// mask, a healed spot — off by default, because it lands at the same place
/// in every photo whether or not that place still holds the same thing.
enum EditorSyncGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    // The Look
    case look
    case light
    case toneCurve
    case whiteBalanceAndPresence
    case blackAndWhite
    case colorMixer
    case pointColor
    case grading
    case effects
    case lensBlur
    case detail
    case optics
    case geometry
    case uprightMode
    case calibration
    // This Frame Only
    case cropAndStraighten
    case masks
    case healAndClone
    case redEye
    case markupLayers
    case uprightGuides

    var id: String { rawValue }

    var isFrameOnly: Bool {
        switch self {
        case .cropAndStraighten, .masks, .healAndClone, .redEye, .markupLayers, .uprightGuides: true
        default: false
        }
    }

    static let lookColumn = allCases.filter { !$0.isFrameOnly }
    static let frameColumn = allCases.filter(\.isFrameOnly)

    var title: String {
        switch self {
        case .look: String(localized: "Look", comment: "Sync sheet group: the film look or LUT and its amount")
        case .light: String(localized: "Light", comment: "Sync sheet group")
        case .toneCurve: String(localized: "Tone Curve", comment: "Sync sheet group")
        case .whiteBalanceAndPresence: String(localized: "White Balance and Presence", comment: "Sync sheet group")
        case .blackAndWhite: String(localized: "Black and White", comment: "Sync sheet group")
        case .colorMixer: String(localized: "Color Mixer", comment: "Sync sheet group")
        case .pointColor: String(localized: "Point Color", comment: "Sync sheet group")
        case .grading: String(localized: "Grading", comment: "Sync sheet group")
        case .effects: String(localized: "Effects", comment: "Sync sheet group")
        case .lensBlur: String(localized: "Lens Blur", comment: "Sync sheet group")
        case .detail: String(localized: "Detail", comment: "Sync sheet group")
        case .optics: String(localized: "Optics", comment: "Sync sheet group: lens corrections and defringe")
        case .geometry: String(localized: "Geometry", comment: "Sync sheet group")
        case .uprightMode: String(localized: "Upright Mode", comment: "Sync sheet group: solved again on each photo")
        case .calibration: String(localized: "Calibration", comment: "Sync sheet group")
        case .cropAndStraighten: String(localized: "Crop and Straighten", comment: "Sync sheet group")
        case .masks: String(localized: "Masks", comment: "Sync sheet group")
        case .healAndClone: String(localized: "Heal and Clone Spots", comment: "Sync sheet group")
        case .redEye: String(localized: "Red Eye", comment: "Sync sheet group")
        case .markupLayers: String(localized: "Markup Layers", comment: "Sync sheet group")
        case .uprightGuides: String(localized: "Upright Guides", comment: "Sync sheet group")
        }
    }

    /// The sliders of `PhotoAdjustments` this group carries.
    var adjustmentFields: [WritableKeyPath<PhotoAdjustments, Double>] {
        switch self {
        case .light:
            [\.exposure, \.brilliance, \.highlights, \.shadows, \.whites, \.contrast, \.brightness, \.blackPoint]
        case .whiteBalanceAndPresence:
            [\.warmth, \.tint, \.saturation, \.vibrance, \.rawTemperature, \.rawTint, \.maskHue]
        case .blackAndWhite:
            [\.blackAndWhite]
        case .effects:
            [\.texture, \.clarity, \.dehaze, \.definition, \.vignette, \.vignetteMidpoint, \.vignetteFeather,
             \.vignetteRoundness, \.vignetteHighlights, \.grain, \.grainSize, \.grainRoughness]
        case .detail:
            [\.sharpness, \.sharpenRadius, \.sharpenDetail, \.sharpenMasking, \.noiseReduction, \.noiseDetail,
             \.noiseContrast, \.colorNoiseReduction, \.colorNoiseDetail, \.colorNoiseSmoothness, \.maskMoire,
             \.rawLuminanceNoise, \.rawColorNoise, \.rawSharpness]
        case .optics:
            [\.chromaticAberration, \.lensDistortionScale, \.lensVignettingScale, \.lensChromaticAberrationScale,
             \.lensManualDistortion, \.lensManualVignetting, \.lensManualVignettingMidpoint, \.lensCorrection,
             \.defringePurpleAmount, \.defringePurpleHueMinimum, \.defringePurpleHueMaximum,
             \.defringeGreenAmount, \.defringeGreenHueMinimum, \.defringeGreenHueMaximum, \.maskDefringe]
        case .geometry:
            [\.geoVertical, \.geoHorizontal, \.geoRotate, \.geoAspect, \.geoScale, \.geoOffsetX, \.geoOffsetY,
             \.geoConstrainCrop]
        default:
            []
        }
    }

    /// Copies this group from `source` into `result`.
    func copy(from source: PhotoEditRecipe, into result: inout PhotoEditRecipe) {
        for field in adjustmentFields {
            result.adjustments[keyPath: field] = source.adjustments[keyPath: field]
        }
        switch self {
        case .look:
            result.filter = source.filter
            result.lutID = source.lutID
            result.filterIntensity = source.filterIntensity
        case .whiteBalanceAndPresence:
            result.adjustments.rawWhiteBalanceKelvin = source.adjustments.rawWhiteBalanceKelvin
            result.adjustments.rawWhiteBalanceTint = source.adjustments.rawWhiteBalanceTint
        case .toneCurve: result.curve = source.curve
        case .blackAndWhite: result.color.grayMixer = source.color.grayMixer
        case .colorMixer: result.color.mixer = source.color.mixer
        case .pointColor: result.color.points = source.color.points
        case .grading: result.color.grading = source.color.grading
        case .calibration: result.color.calibration = source.color.calibration
        case .effects: result.vignetteStyle = source.vignetteStyle
        case .lensBlur: result.lensBlur = source.lensBlur
        case .uprightMode:
            // Travels as a mode, solved again on this photo; the guides and
            // the solved transform were drawn for the other frame.
            if source.upright.mode != result.upright.mode {
                result.upright = .identity
                result.upright.mode = source.upright.mode
            }
        case .uprightGuides: result.upright = source.upright
        case .cropAndStraighten: result.crop = source.crop
        case .masks: result.masks = source.masks
        case .healAndClone: result.healing = source.healing
        case .redEye: result.redEyes = source.redEyes
        case .markupLayers: result.overlays = source.overlays
        case .light, .detail, .optics, .geometry: break
        }
    }
}

/// The ticks of one Sync (FS-03.09b §2): which groups travel. Remembered
/// between syncs; the lens profile never travels — the other photo may be
/// from another lens (FS-03.16 §4, E18) — and neither does which photo the
/// recipe belongs to.
struct EditorSyncGroups: Codable, Equatable, Sendable {
    var groups: Set<EditorSyncGroup>

    /// The Look column on, This Frame Only off.
    static let look = EditorSyncGroups(groups: Set(EditorSyncGroup.lookColumn))
    static let everything = EditorSyncGroups(groups: Set(EditorSyncGroup.allCases))

    /// The menu's two commands, as ticks.
    init(_ scope: EditorSyncScope) {
        self = scope == .everything ? .everything : .look
    }

    init(groups: Set<EditorSyncGroup>) {
        self.groups = groups
    }

    func contains(_ group: EditorSyncGroup) -> Bool { groups.contains(group) }

    func apply(_ source: PhotoEditRecipe, onto target: PhotoEditRecipe) -> PhotoEditRecipe {
        var result = target
        // Upright Guides after Upright Mode: with both ticked the guides win.
        for group in EditorSyncGroup.allCases where groups.contains(group) {
            group.copy(from: source, into: &result)
        }
        return result
    }

    /// Lossy: an unknown group name is dropped, not the whole set.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let names = (try? container.decode([String].self, forKey: .groups)) ?? []
        groups = Set(names.compactMap(EditorSyncGroup.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groups.map(\.rawValue).sorted(), forKey: .groups)
    }

    private enum CodingKeys: String, CodingKey { case groups }
}
