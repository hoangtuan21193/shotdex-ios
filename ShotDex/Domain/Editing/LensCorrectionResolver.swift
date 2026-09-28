import ShotDexKit

/// One of the three things a lens profile corrects (FS-03.16 §3).
enum LensCorrectionAspect: String, CaseIterable, Sendable {
    case distortion
    case vignetting
    case chromaticAberration
}

/// What the resolver is told about a photo: the facts, gathered off the main
/// actor when the photo opens. A plain value so every row of FS-03.16a §6 can
/// be tested without a RAW file.
struct LensCorrectionInputs: Sendable {
    var isRAW: Bool
    /// Aspects the maker's data in the file covers (source 1) — RAW only.
    var embeddedAspects: Set<LensCorrectionAspect> = []
    /// The lens as the file names it, for the panel when source 1 is used.
    var embeddedLensName: String?
    /// The Lensfun row: matched from EXIF, or the one the user chose.
    var lensfunLens: LensfunLens?
    var lensfunChosenByUser = false
    var cameraCropFactor: Double = 1
    /// `CIRAWFilter.isLensCorrectionSupported` — the seam that lets a test
    /// stand in for a body the repo has no file from.
    var decoderSupportsLensCorrection = false
    /// A JPEG whose camera already corrected the lens (16a §4).
    var isJPEGCorrectedInCamera = false
}

/// What the Optics panel's status row says (FS-03.16b §2).
enum LensCorrectionPanelState: Equatable, Sendable {
    /// Source 1, or source 2 matched from EXIF.
    case found(lensName: String)
    /// Source 2 the user picked.
    case chosen(lensName: String)
    /// A JPEG the camera corrected.
    case correctedInCamera
    /// Source 3: Apple's own correction, on or off only.
    case builtIn
    /// Source 4.
    case noProfile
}

struct LensCorrectionResolution: Equatable, Sendable {
    var choice: PhotoLensProfileChoice
    var panel: LensCorrectionPanelState
    /// Aspects whose strength slider does something.
    var liveAspects: Set<LensCorrectionAspect>

    /// Apple's decoder correction runs only when nothing better exists —
    /// never on top of a profile (§3, never twice).
    var usesAppleBuiltIn: Bool { choice.usesAppleBuiltIn }
}

/// The source order of FS-03.16 §3, per aspect: the maker's data in the
/// file, else Lensfun, and Apple's built-in correction only when no aspect has
/// either; never two at once. Pure — the controller feeds it and stores what
/// it returns.
enum LensCorrectionResolver {

    static func resolve(_ inputs: LensCorrectionInputs) -> LensCorrectionResolution {
        // A camera that corrected its own JPEG is not corrected again unless
        // the user asks for a lens by hand.
        let lens = inputs.isJPEGCorrectedInCamera && !inputs.lensfunChosenByUser ? nil : inputs.lensfunLens
        let embedded = inputs.isRAW ? inputs.embeddedAspects : []
        let lensfunAspects = lens.map(aspects(of:)) ?? []

        func source(_ aspect: LensCorrectionAspect) -> LensCorrectionSource {
            // A lens picked by hand wins over the file for what it covers
            // (16b AC-b9: "Chosen by you" on a file with its own data).
            if inputs.lensfunChosenByUser, lensfunAspects.contains(aspect) { return .lensfun }
            if embedded.contains(aspect) { return .embedded }
            if lensfunAspects.contains(aspect) { return .lensfun }
            return .none
        }
        var sources = Dictionary(uniqueKeysWithValues: LensCorrectionAspect.allCases.map { ($0, source($0)) })
        let usesProfile = sources.values.contains { $0 == .embedded || $0 == .lensfun }
        if !usesProfile, inputs.isRAW, inputs.decoderSupportsLensCorrection {
            for aspect in LensCorrectionAspect.allCases { sources[aspect] = .appleBuiltIn }
        }

        let usesLensfun = sources.values.contains(.lensfun)
        let choice = PhotoLensProfileChoice(
            lensID: usesLensfun ? lens?.id : nil,
            cameraCropFactor: inputs.cameraCropFactor,
            isAutomatic: !inputs.lensfunChosenByUser,
            distortionSource: sources[.distortion] ?? .none,
            vignettingSource: sources[.vignetting] ?? .none,
            chromaticAberrationSource: sources[.chromaticAberration] ?? .none
        )

        let panel: LensCorrectionPanelState
        if usesLensfun, inputs.lensfunChosenByUser, let lens {
            panel = .chosen(lensName: lens.displayName)
        } else if sources.values.contains(.embedded) {
            panel = .found(lensName: inputs.embeddedLensName ?? lens?.displayName ?? "")
        } else if usesLensfun, let lens {
            panel = .found(lensName: lens.displayName)
        } else if inputs.isJPEGCorrectedInCamera {
            panel = .correctedInCamera
        } else if choice.usesAppleBuiltIn {
            panel = .builtIn
        } else {
            panel = .noProfile
        }
        let live = Set(LensCorrectionAspect.allCases.filter {
            sources[$0] == .embedded || sources[$0] == .lensfun
        })
        return LensCorrectionResolution(choice: choice, panel: panel, liveAspects: live)
    }

    /// The aspects a Lensfun row has data for.
    static func aspects(of lens: LensfunLens) -> Set<LensCorrectionAspect> {
        var result: Set<LensCorrectionAspect> = []
        if !lens.distortion.isEmpty { result.insert(.distortion) }
        if !lens.vignetting.isEmpty { result.insert(.vignetting) }
        if !lens.tca.isEmpty { result.insert(.chromaticAberration) }
        return result
    }
}
