import Foundation

/// How a slider's raw −1…1 (or −2…2) storage value is written for the user. The
/// editor shows photographic units — stops with two decimals, ±100 percentages,
/// a Kelvin offset — rather than the normalized number the render graph takes.
enum EditorValueFormat: Sendable {
    case stops
    case percent
    case kelvinOffset
    case tintOffset
    case toggle
}

struct EditorAdjustmentGroup: Identifiable, Equatable, Sendable {
    enum Identity: String, Sendable {
        case light
        case color
        case detail
        case effects
        case optics
        case geo
        case raw
    }

    let id: Identity
    let title: String
    let kinds: [PhotoAdjustmentKind]
    let hasAuto: Bool
}

/// Single source of truth for how Adjust is grouped and how values read. The
/// panel, the mask editor and the history labels all go through here so a slider
/// never shows one number in the panel and another in a summary.
enum EditorAdjustmentCatalog {
    enum Scope: Sendable {
        case global
        case mask
    }

    /// Sliders that only make sense in one direction: their track fills from the
    /// left instead of from the centre and the negative half is not offered.
    ///
    /// Detail and Effects are deliberately *not* in here — dragging left has a
    /// real meaning for each of them (soften, blur, denoise, brighten the
    /// corners). Grain and the RAW decode controls are the genuine one-way ones:
    /// there is no negative amount of film grain, and the RAW parameters are 0…1
    /// strengths inside `CIRAWFilter`.
    static let unipolarKinds: Set<PhotoAdjustmentKind> = [
        .grain,
        .grainSize,
        .grainRoughness,
        .vignetteMidpoint,
        .vignetteFeather,
        .sharpenRadius,
        .sharpenDetail,
        .sharpenMasking,
        .colorNoiseReduction,
        .vignetteHighlights,
        .defringe,
        .rawSharpness,
        .rawLuminanceNoise,
        .rawColorNoise,
        .lensCorrection,
    ]

    static func groups(isRAWSource: Bool, scope: Scope) -> [EditorAdjustmentGroup] {
        var groups: [EditorAdjustmentGroup] = [
            EditorAdjustmentGroup(
                id: .light,
                title: "Light",
                kinds: [
                    .exposure,
                    .contrast,
                    .highlights,
                    .shadows,
                    .whites,
                    .blackPoint,
                    .brilliance,
                    .brightness,
                ],
                hasAuto: true
            ),
            EditorAdjustmentGroup(
                id: .color,
                title: "Color",
                kinds: [.warmth, .tint, .vibrance, .saturation, .blackAndWhite],
                hasAuto: false
            ),
            EditorAdjustmentGroup(
                id: .detail,
                title: "Detail",
                kinds: [
                    .sharpness, .sharpenRadius, .sharpenDetail, .sharpenMasking,
                    .definition,
                    .noiseReduction, .colorNoiseReduction,
                ],
                hasAuto: false
            ),
            EditorAdjustmentGroup(
                id: .effects,
                title: "Effects",
                kinds: [
                    .texture, .clarity, .dehaze,
                    .vignette, .vignetteMidpoint, .vignetteFeather,
                    .vignetteRoundness, .vignetteHighlights,
                    .grain, .grainSize, .grainRoughness,
                ],
                hasAuto: false
            ),
        ]
        // Optics and Geo act on the whole frame's geometry / lens, so they are
        // global-only — never inside a mask.
        if scope == .global {
            groups.append(
                EditorAdjustmentGroup(
                    id: .optics,
                    title: "Optics",
                    kinds: [.chromaticAberration, .defringe],
                    hasAuto: false
                )
            )
            groups.append(
                EditorAdjustmentGroup(
                    id: .geo,
                    title: "Geo",
                    kinds: [
                        .geoVertical, .geoHorizontal, .geoRotate,
                        .geoScale, .geoOffsetX, .geoOffsetY,
                    ],
                    hasAuto: false
                )
            )
        }
        // RAW demosaic and lens controls act on the decode of the source file, so
        // they exist once per photo and never inside a mask.
        if isRAWSource, scope == .global {
            groups.append(
                EditorAdjustmentGroup(
                    id: .raw,
                    title: "RAW",
                    kinds: [
                        .rawTemperature,
                        .rawTint,
                        .rawSharpness,
                        .rawLuminanceNoise,
                        .rawColorNoise,
                        .lensCorrection,
                    ],
                    hasAuto: false
                )
            )
        }
        return groups
    }

    static func format(of kind: PhotoAdjustmentKind) -> EditorValueFormat {
        switch kind {
        case .lensCorrection, .blackAndWhite, .chromaticAberration: .toggle
        case .exposure, .contrast: .stops
        case .warmth: .kelvinOffset
        case .tint: .tintOffset
        default: .percent
        }
    }

    static func isBipolar(_ kind: PhotoAdjustmentKind) -> Bool {
        !unipolarKinds.contains(kind)
    }

    static func sliderRange(of kind: PhotoAdjustmentKind) -> ClosedRange<Double> {
        let range = kind.range
        guard unipolarKinds.contains(kind) else { return range }
        return 0...range.upperBound
    }

    /// Short label used in slider rows. `Black Point` and `Warmth` read as
    /// `Blacks` and `Temp` in a 78pt column, matching how photographers name them.
    static func shortTitle(of kind: PhotoAdjustmentKind) -> String {
        switch kind {
        case .blackPoint: "Blacks"
        case .warmth: "Temp"
        case .noiseReduction: "Noise"
        case .sharpness: "Sharpen"
        case .sharpenRadius: "Radius"
        case .sharpenDetail: "Detail"
        case .sharpenMasking: "Masking"
        case .colorNoiseReduction: "Color NR"
        case .blackAndWhite: "B&W"
        case .grainSize: "Size"
        case .grainRoughness: "Roughness"
        case .vignetteMidpoint: "Midpoint"
        case .vignetteFeather: "Feather"
        case .vignetteRoundness: "Round"
        case .vignetteHighlights: "Highlights"
        case .chromaticAberration: "Remove CA"
        case .rawTemperature: "WB Temp"
        case .rawTint: "WB Tint"
        case .rawLuminanceNoise: "Lum Noise"
        case .rawColorNoise: "Color Noise"
        case .rawSharpness: "RAW Sharpen"
        case .lensCorrection: "Lens"
        default: kind.displayName
        }
    }

    static func displayText(_ value: Double, of kind: PhotoAdjustmentKind) -> String {
        switch format(of: kind) {
        case .toggle:
            return value >= 0.5 ? "On" : "Off"
        case .stops:
            guard abs(value) > 0.0001 else { return "0" }
            return typographic(String(format: "%+.2f", value))
        case .percent:
            return signedInteger(value * 100)
        case .kelvinOffset:
            return signedInteger((value * 3_000 / 10).rounded() * 10)
        case .tintOffset:
            return signedInteger(value * 150)
        }
    }

    /// Text seeded into the numeric keypad when the user taps a value. The keypad
    /// needs an ASCII minus, not the typographic one used for display.
    static func editableText(_ value: Double, of kind: PhotoAdjustmentKind) -> String {
        guard format(of: kind) != .toggle else { return "" }
        let text = displayText(value, of: kind)
            .replacingOccurrences(of: "\u{2212}", with: "-")
        return text.hasPrefix("+") ? String(text.dropFirst()) : text
    }

    /// Inverse of `displayText`, used by the numeric keypad. Returns nil for text
    /// that isn't a number so the field can reject it instead of writing 0.
    static func value(fromDisplayText text: String, of kind: PhotoAdjustmentKind) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "+", with: "")
        guard let entered = Double(trimmed) else { return nil }
        let raw: Double = switch format(of: kind) {
        case .toggle: entered >= 0.5 ? 1 : 0
        case .stops: entered
        case .percent: entered / 100
        case .kelvinOffset: entered / 3_000
        case .tintOffset: entered / 150
        }
        let range = sliderRange(of: kind)
        return min(range.upperBound, max(range.lowerBound, raw))
    }

    private static func signedInteger(_ value: Double) -> String {
        let rounded = value.rounded()
        guard abs(rounded) >= 1 else { return "0" }
        return typographic(String(format: "%+.0f", rounded))
    }

    private static func typographic(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: "\u{2212}")
    }
}
