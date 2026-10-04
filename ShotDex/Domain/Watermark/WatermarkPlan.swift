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

    mutating func record(_ decision: WatermarkDecision, filename: String) {
        switch decision {
        case .stamp: stamped += 1
        case .nothingToStamp: nothingToStamp.append(filename)
        }
    }

    /// Whether the summary has anything to say about the watermark.
    var isWorthReporting: Bool { !nothingToStamp.isEmpty }
}
