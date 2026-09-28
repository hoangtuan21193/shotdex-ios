import Foundation

/// Where one aspect of a photo's lens correction comes from (FS-03.16 §3),
/// in the order the resolver tries them.
public enum LensCorrectionSource: String, Codable, CaseIterable, Sendable {
    /// The maker's correction data written into the file, read by ShotDex.
    case embedded
    /// A Lensfun profile, matched from EXIF or chosen by the user.
    case lensfun
    /// Apple's own correction inside the RAW decoder — on or off only.
    case appleBuiltIn
    /// Nothing corrects this aspect.
    case none
}

/// Which lens profile corrects this photo, where each aspect's correction
/// comes from, and the body's crop factor the profile has to be scaled by.
/// Resolved in the app — matching an EXIF lens string to a Lensfun row is the
/// app's job — and stored resolved, so a refresh of the data never quietly
/// changes a photo already edited, and the renderer only looks the lens up by
/// id.
public struct PhotoLensProfileChoice: Codable, Equatable, Sendable {
    /// `LensfunLens.id` — "maker|model|crop". Nil when no aspect uses Lensfun.
    public var lensID: String?
    public var cameraCropFactor: Double
    /// True when ShotDex matched it from EXIF, false when the user picked it.
    public var isAutomatic: Bool
    public var distortionSource: LensCorrectionSource
    public var vignettingSource: LensCorrectionSource
    public var chromaticAberrationSource: LensCorrectionSource

    /// A Lensfun lens for all three aspects — the choice every JPEG profile
    /// was before sources were per aspect.
    public init(lensID: String, cameraCropFactor: Double, isAutomatic: Bool) {
        self.init(
            lensID: lensID,
            cameraCropFactor: cameraCropFactor,
            isAutomatic: isAutomatic,
            distortionSource: .lensfun,
            vignettingSource: .lensfun,
            chromaticAberrationSource: .lensfun
        )
    }

    public init(
        lensID: String?,
        cameraCropFactor: Double,
        isAutomatic: Bool,
        distortionSource: LensCorrectionSource,
        vignettingSource: LensCorrectionSource,
        chromaticAberrationSource: LensCorrectionSource
    ) {
        self.lensID = lensID
        self.cameraCropFactor = cameraCropFactor
        self.isAutomatic = isAutomatic
        self.distortionSource = distortionSource
        self.vignettingSource = vignettingSource
        self.chromaticAberrationSource = chromaticAberrationSource
    }

    /// Whether any aspect is corrected by ShotDex's own passes (sources 1 and
    /// 2) — then Apple's built-in correction must be off (§3, never twice).
    public var usesProfile: Bool {
        [distortionSource, vignettingSource, chromaticAberrationSource].contains { $0 == .embedded || $0 == .lensfun }
    }

    /// Apple's decoder correction is the choice: no aspect has a profile.
    public var usesAppleBuiltIn: Bool {
        [distortionSource, vignettingSource, chromaticAberrationSource].contains(.appleBuiltIn)
    }

    private enum CodingKeys: String, CodingKey {
        case lensID, cameraCropFactor, isAutomatic
        case distortionSource, vignettingSource, chromaticAberrationSource
    }

    /// Each field on its own: a source this build does not know (a newer
    /// build's, or a typo) falls to `.none` for that aspect only, and the
    /// rest of the choice survives (FS-03.16 AC-1). A choice saved before
    /// sources existed was a Lensfun lens for everything.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lensID = (try? container.decodeIfPresent(String.self, forKey: .lensID)) ?? nil
        self.lensID = lensID
        cameraCropFactor = (try? container.decodeIfPresent(Double.self, forKey: .cameraCropFactor)) ?? 1
        isAutomatic = (try? container.decodeIfPresent(Bool.self, forKey: .isAutomatic)) ?? true
        func source(_ key: CodingKeys) -> LensCorrectionSource {
            guard container.contains(key) else { return lensID == nil ? .none : .lensfun }
            let raw = try? container.decode(String.self, forKey: key)
            return raw.flatMap(LensCorrectionSource.init(rawValue:)) ?? .none
        }
        distortionSource = source(.distortionSource)
        vignettingSource = source(.vignettingSource)
        chromaticAberrationSource = source(.chromaticAberrationSource)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lensID, forKey: .lensID)
        try container.encode(cameraCropFactor, forKey: .cameraCropFactor)
        try container.encode(isAutomatic, forKey: .isAutomatic)
        try container.encode(distortionSource, forKey: .distortionSource)
        try container.encode(vignettingSource, forKey: .vignettingSource)
        try container.encode(chromaticAberrationSource, forKey: .chromaticAberrationSource)
    }
}
