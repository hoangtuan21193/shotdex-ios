import Foundation
import ShotDexKit

/// What happens to one photo of a stamped export (FS-05.04 §3, §5).
enum WatermarkDecision: Equatable, Sendable {
    /// Stamped with this — the preset's layers with the photo's own tokens.
    case stamp(WatermarkStamp)
    /// Every token came out empty and nothing else is left to draw: the photo
    /// goes without the stamp and is named in the summary, never silently.
    case nothingToStamp
}

/// Per-photo decisions of a stamped export, pure so the rules are tested
/// without a library.
enum WatermarkPlan {
    /// Whether a photo's saved edit already has a layer pasted from this
    /// preset — then it is not stamped again. A layer from another preset, or
    /// a caption made by hand, does not count (FS-05.04 §5).
    static func alreadyStamped(savedLayers: [PhotoOverlay]?, presetID: UUID) -> Bool {
        savedLayers?.contains { $0.signaturePresetID == presetID && $0.isVisible } ?? false
    }

    /// `template` is the form's stamp before tokens; `values` the photo's.
    static func decide(_ template: WatermarkStamp, values: OverlayTokenValues) -> WatermarkDecision {
        let stamp = template.resolved(with: values)
        return stamp.hasVisibleLayers ? .stamp(stamp) : .nothingToStamp
    }
}

/// What a stamped run tells its summary.
struct WatermarkTally: Equatable, Sendable {
    /// The preset's name, for the reasons.
    var presetName = ""
    /// Photos stamped.
    var stamped = 0
    /// Photos that went without the stamp, by file name, in order.
    var nothingToStamp: [String] = []
    /// Photos whose edit already had a layer from the preset.
    var alreadyStamped = 0

    mutating func record(_ decision: WatermarkDecision, filename: String, wasAlreadyThere: Bool = false) {
        switch decision {
        case .stamp where wasAlreadyThere: alreadyStamped += 1
        case .stamp: stamped += 1
        case .nothingToStamp: nothingToStamp.append(filename)
        }
    }

    /// Whether the summary has anything to say about the watermark.
    var isWorthReporting: Bool { !nothingToStamp.isEmpty || alreadyStamped > 0 }
}
