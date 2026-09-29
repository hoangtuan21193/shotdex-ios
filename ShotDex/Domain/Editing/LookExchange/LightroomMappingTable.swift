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

        func map(_ value: Double) -> Double {
            guard let lightroom else { return value }
            let target = kind.range
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
    ]

    static let adjustments: [String: AdjustmentRow] = [
        "Exposure2012": AdjustmentRow(kind: .exposure, title: "Exposure", lightroom: nil, unit: " EV"),
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
