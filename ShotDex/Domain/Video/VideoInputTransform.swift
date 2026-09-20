import Foundation

/// How the footage was encoded, so the studio can undo it before grading.
///
/// A camera shooting log records a flat, washed-out picture on purpose: it
/// spends its code values on dynamic range instead of contrast, and expects
/// the edit to put the contrast back. Until that happens every look applied on
/// top is being dialled against the wrong picture — which is why an input
/// transform belongs at the *front* of the chain, before adjustments, the
/// film sims or the tone curve.
///
/// **What this does and does not do.** Each profile below is a published
/// *transfer function*: it maps the recorded code value back to scene-linear
/// light, then re-encodes to Rec.709. That is the part that makes the picture
/// look right. It does **not** convert gamut — a wide-gamut capture
/// (S-Gamut3, V-Gamut, BT.2020) keeps its primaries, so deep saturated colour
/// will read slightly differently than a full colour-managed conversion would.
/// Saying so here rather than implying a completeness this does not have.
///
/// **Why these five and not more.** Every constant below comes from the
/// camera maker's own published formula. Profiles whose constants would have
/// to be guessed at are deliberately absent: a de-log curve that is nearly
/// right is worse than none, because it looks plausible and is wrong in the
/// shadows. `genericLog` exists for those cameras — it is an honest
/// approximation the user can dial, not a claim about a specific format.
enum VideoInputTransform: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Footage is already display-referred. No transform.
    case none
    /// ITU-R BT.2100 Hybrid Log-Gamma.
    case hlg
    /// Sony S-Log3.
    case sLog3
    /// Panasonic V-Log.
    case vLog
    /// A middle-of-the-road log curve for cameras whose exact constants are
    /// not published here.
    case genericLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None (Rec. 709)", comment: "Video Studio colour: the footage needs no de-log")
        case .hlg: String(localized: "HLG", comment: "Video Studio colour: Hybrid Log-Gamma input transform")
        case .sLog3: String(localized: "S-Log3", comment: "Video Studio colour: Sony S-Log3 input transform")
        case .vLog: String(localized: "V-Log", comment: "Video Studio colour: Panasonic V-Log input transform")
        case .genericLog: String(localized: "Generic Log", comment: "Video Studio colour: an approximate de-log for cameras whose curve is not listed")
        }
    }

    var subtitle: String {
        switch self {
        case .none: String(localized: "Leave the picture as recorded.", comment: "Video Studio colour: what None does")
        case .hlg: String(localized: "BT.2100, as shot on iPhone and many broadcast cameras.", comment: "Video Studio colour: where HLG comes from")
        case .sLog3: String(localized: "Sony cinema and Alpha bodies.", comment: "Video Studio colour: where S-Log3 comes from")
        case .vLog: String(localized: "Panasonic Lumix and Varicam.", comment: "Video Studio colour: where V-Log comes from")
        case .genericLog: String(localized: "An approximation, for a curve this list does not name.", comment: "Video Studio colour: what Generic Log is")
        }
    }

    /// Scene-linear light for one recorded value, 0…1 in and (roughly) 0…1+
    /// out. The inverse of each maker's published encoding function.
    func sceneLinear(_ value: Double) -> Double {
        let v = min(max(value, 0), 1)
        switch self {
        case .none:
            return v
        case .hlg:
            // ITU-R BT.2100 inverse OETF. Below the half-way point the curve
            // is a plain square root; above it, logarithmic.
            let a = 0.17883277
            let b = 1 - 4 * a
            let c = 0.5 - a * log(4 * a)
            return v <= 0.5 ? (v * v) / 3 : (exp((v - c) / a) + b) / 12
        case .sLog3:
            // Sony's published S-Log3 → linear reflection formula, in code
            // values over 1023.
            let code = v * 1023
            if code >= 171.2102946929 {
                return pow(10, (code - 420) / 261.5) * (0.18 + 0.01) - 0.01
            }
            return (code - 95) * 0.01125000 / (171.2102946929 - 95)
        case .vLog:
            // Panasonic's published V-Log → linear, with the maker's cut,
            // b, c and d constants.
            let cut = 0.181
            let b = 0.00873
            let c = 0.241514
            let d = 0.598206
            return v < cut ? (v - 0.125) / 5.6 : pow(10, (v - d) / c) - b
        case .genericLog:
            // A plain Cineon-shaped curve: no maker's name on it, and none
            // claimed. Black at 95/1023, mid grey at 0.18, roughly 6 stops
            // above mid to clip — the shape most log formats sit near.
            let code = max(0, v * 1023 - 95) / (1023 - 95)
            return pow(2, code * 11 - 6) * 0.18
        }
    }

    /// Rec.709's OETF, which is what puts the contrast back for display.
    private func rec709(_ linear: Double) -> Double {
        let l = min(max(linear, 0), 1)
        return l < 0.018 ? 4.5 * l : 1.099 * pow(l, 0.45) - 0.099
    }

    /// The whole transform as `count` evenly spaced samples, ready for a
    /// `CIColorCurves` pass — one table, applied identically to R, G and B,
    /// because a transfer function is per-channel by definition.
    func curveSamples(count: Int = 256) -> [Float] {
        guard self != .none, count > 1 else {
            return (0..<max(count, 2)).map { Float(Double($0) / Double(max(count, 2) - 1)) }
        }
        return (0..<count).map { index in
            let input = Double(index) / Double(count - 1)
            return Float(min(max(rec709(sceneLinear(input)), 0), 1))
        }
    }

    /// Whether this transform changes anything at all.
    var isIdentity: Bool { self == .none }
}
