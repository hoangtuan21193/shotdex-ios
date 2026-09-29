import Foundation
import ShotDexKit

/// A camera profile's name → a ShotDex film look (FS-03.14b §3): matched by
/// name, case aside, without the "Camera " prefix or a version suffix. No
/// DCP is read.
enum CameraProfileMap {
    enum Match: Equatable {
        /// The same look by name.
        case exact(PhotoFilter)
        /// The nearest ShotDex look, said in the report.
        case near(PhotoFilter)
        /// No look for it: Original.
        case none
    }

    static func match(_ profile: String) -> Match {
        var name = profile.trimmingCharacters(in: .whitespaces)
        if name.lowercased().hasPrefix("camera ") { name = String(name.dropFirst("camera ".count)) }
        if let range = name.range(of: #"\s+v\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(range)
        }
        // Fujifilm writes MONOCHROME in capitals; other makers' "Monochrome"
        // is a different profile.
        if name.hasPrefix("MONOCHROME") || name == "SEPIA" {
            switch name.replacingOccurrences(of: " ", with: "").uppercased() {
            case "MONOCHROME": return .exact(.fujiMonochrome)
            case "MONOCHROME+YEFILTER": return .exact(.fujiMonochromeYellow)
            case "MONOCHROME+RFILTER": return .exact(.fujiMonochromeRed)
            case "MONOCHROME+GFILTER": return .exact(.fujiMonochromeGreen)
            case "SEPIA": return .exact(.fujiSepia)
            default: break
            }
        }
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        if let filter = exact[key] { return .exact(filter) }
        if key.contains("monochrome") { return .near(.mono) }
        if key == "vivid" || key == "adobevivid" { return .near(.vivid) }
        return .none
    }

    private static let exact: [String: PhotoFilter] = [
        "provia/standard": .provia, "provia": .provia,
        "velvia/vivid": .velvia, "velvia": .velvia,
        "astia/soft": .astia, "astia": .astia,
        "classicchrome": .classicChrome,
        "proneg.hi": .proNegHi, "pronegh": .proNegHi, "proneghi": .proNegHi,
        "proneg.std": .proNegStd, "pronegstd": .proNegStd,
        "classicneg.": .classicNeg, "classicneg": .classicNeg,
        "nostalgicneg.": .nostalgicNeg, "nostalgicneg": .nostalgicNeg,
        "eterna/cinema": .eterna, "eterna": .eterna,
        "eternableachbypass": .eternaBleachBypass,
        "acros": .acros, "acros+yefilter": .acrosYellow, "acros+rfilter": .acrosRed, "acros+gfilter": .acrosGreen,
    ]
}
