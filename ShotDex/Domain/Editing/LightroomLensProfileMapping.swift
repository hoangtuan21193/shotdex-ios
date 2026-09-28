import ShotDexKit

/// Lightroom's `crs:LensProfile*` tags turned into ShotDex's lens correction
/// (FS-03.16 §5). Pure: the preset importer (FS-03.14) calls it and applies
/// what it returns.
struct LightroomLensProfileMapping {

    /// What one preset's lens tags become.
    struct Result: Equatable {
        /// The one switch; nil when the preset does not say.
        var isEnabled: Bool?
        /// 0…2 (Lightroom 0–200); nil when absent.
        var distortion: Double?
        var vignetting: Double?
        var chromaticAberration: Double?
        /// A Lensfun lens the preset names (Setup Custom) and the table has;
        /// nil means each photo resolves its own lens (§3).
        var lens: LensfunLens?
        var report: ReportLine?
    }

    /// The import report's line for the lens.
    enum ReportLine: Equatable {
        /// The named lens was found.
        case matched(String)
        /// The named lens is not in the table: strengths kept, the photo
        /// resolves its own lens — "≈" in the report.
        case approximate(String)
    }

    let matcher: LensProfileMatcher

    init(matcher: LensProfileMatcher = LensProfileMatcher()) {
        self.matcher = matcher
    }

    /// `tags` keyed without the `crs:` prefix ("LensProfileEnable", …).
    func map(_ tags: [String: String]) -> Result {
        var result = Result()
        if let enable = tags["LensProfileEnable"] {
            result.isEnabled = enable == "1" || enable.lowercased() == "true"
        }
        func scale(_ key: String) -> Double? {
            tags[key].flatMap(Double.init).map { min(max($0, 0), 200) / 100 }
        }
        result.distortion = scale("LensProfileDistortionScale")
        result.vignetting = scale("LensProfileVignettingScale")
        result.chromaticAberration = scale("LensProfileChromaticAberrationScale")

        guard tags["LensProfileSetup"]?.lowercased() == "custom",
              let raw = tags["LensProfileName"], !raw.isEmpty
        else { return result }
        let name = Self.lensName(fromProfileName: raw)
        let brand = name.split(separator: " ").first.map(String.init)
        if let match = matcher.match(LensQuery(lensMake: brand, lensModel: name)) {
            result.lens = match.lens
            result.report = .matched(name)
        } else {
            result.report = .approximate(name)
        }
        return result
    }

    /// "Adobe (Canon EF 24-70mm f/2.8L II USM)" → the name inside.
    static func lensName(fromProfileName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")"),
              trimmed[..<open].trimmingCharacters(in: .whitespaces).lowercased() == "adobe"
        else { return trimmed }
        return String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
            .trimmingCharacters(in: .whitespaces)
    }
}
