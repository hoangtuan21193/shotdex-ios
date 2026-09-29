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
