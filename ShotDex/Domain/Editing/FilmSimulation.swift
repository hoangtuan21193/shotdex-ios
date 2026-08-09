import Foundation

/// Strip the Filters tab groups a look under. Three generic strips rather than one
/// per camera maker: a heading is a label on ShotDex's own UI, and naming brands
/// there invites a trademark complaint the looks themselves do not.
enum FilmLookCategory: String, CaseIterable, Identifiable, Sendable {
    case basic
    case film
    case monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basic: "Basic"
        case .film: "Film"
        case .monochrome: "B&W"
        }
    }
}

/// A film or camera look expressed as parameters rather than as a baked table, so
/// every value here can be read, reasoned about and tested.
///
/// What actually makes an image read as film — in the order this type applies it:
///
/// 1. **Per-channel transfer curves.** Film's three dye layers do not share one
///    curve. A single luminance contrast curve can never produce a film look,
///    which is why `red`, `green` and `blue` are separate.
/// 2. **Dye crosstalk** (`matrix`). Each layer is contaminated by the others.
///    This — not a saturation cut — is what sits Classic Chrome's reds back and
///    turns its yellows olive.
/// 3. **Highlight desaturation.** Film dyes run out approaching the shoulder, so
///    bright colour washes toward white. Digital clips to a flat but still fully
///    saturated colour, and that is the single loudest "digital" tell.
/// 4. **Split toning.** Almost no stock is neutral at both ends: shadows and
///    highlights pull in different directions.
/// 5. **Hue-selective shifts** (`bands`). Classic Neg. sends greens toward teal
///    while pulling skin redder; Portra leaves skin alone and warms foliage.
///
/// These are emulations tuned by eye against reference frames, not measured
/// densitometric profiles — the same thing a camera maker's own "film simulation"
/// is.
struct FilmLook: Sendable, Equatable {
    /// Transfer curve for one channel. Monotone by construction for any
    /// `gain > lift`, `gamma > 0`, `shoulder >= 0` and `contrast` in -1...1, so a
    /// look can never invert tones.
    struct Curve: Sendable, Equatable {
        /// Output floor. Negative film never reaches pure black; a small lift here
        /// is most of why a scan looks like a scan.
        var lift = 0.0
        /// Output ceiling.
        var gain = 1.0
        /// Midtone power. Below 1 opens the midtones, above 1 closes them.
        var gamma = 1.0
        /// S-curve strength about the 0.5 pivot. Negative flattens.
        var contrast = 0.0
        /// Highlight compression — the film shoulder. Rolls values off toward the
        /// ceiling instead of clipping into it.
        var shoulder = 0.0

        static let linear = Curve()

        func apply(_ input: Double) -> Double {
            var value = min(1, max(0, input))
            if gamma != 1 { value = pow(value, gamma) }
            if contrast != 0 {
                // Smoothstep is the cheapest curve that is flat at both ends, so
                // the pivot moves midtones without touching clipping points.
                let smooth = value * value * (3 - 2 * value)
                value = value + (smooth - value) * contrast
            }
            if shoulder > 0 {
                // Hyperbolic roll-off, normalised so 1 still maps to 1: the knee
                // is smooth and the white point does not move.
                value = value * (1 + shoulder) / (1 + shoulder * value)
            }
            return lift + (gain - lift) * value
        }
    }

    /// Dye crosstalk, row-major. Each row says how much of the R/G/B input a
    /// channel picks up.
    struct Matrix: Sendable, Equatable {
        var red: SIMD3<Double>
        var green: SIMD3<Double>
        var blue: SIMD3<Double>

        static let identity = Matrix(
            red: SIMD3(1, 0, 0),
            green: SIMD3(0, 1, 0),
            blue: SIMD3(0, 0, 1)
        )

        /// Bleeds every channel toward the other two by `amount`, keeping row sums
        /// at 1 so overall brightness is untouched. A gentle, plausible stand-in
        /// for real layer contamination.
        static func bleed(_ amount: Double) -> Matrix {
            let side = amount / 2
            let center = 1 - amount
            return Matrix(
                red: SIMD3(center, side, side),
                green: SIMD3(side, center, side),
                blue: SIMD3(side, side, center)
            )
        }

        func apply(_ input: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(
                (red * input).sum(),
                (green * input).sum(),
                (blue * input).sum()
            )
        }
    }

    /// Hue-selective tweak. Bands are evaluated against the *incoming* hue and
    /// their effects summed, so listing them in any order gives the same result.
    struct HueBand: Sendable, Equatable {
        /// Hue this band is centred on, in degrees. 0 red, 60 yellow, 120 green,
        /// 180 cyan, 240 blue, 300 magenta.
        var center: Double
        /// Half-width in degrees. The band fades to nothing at the edge.
        var width: Double
        /// Degrees of rotation applied at full weight.
        var hueShift = 0.0
        /// Saturation multiplier at full weight.
        var saturation = 1.0
        /// Luminance multiplier at full weight.
        var luminance = 1.0
    }

    /// Channel gains standing in for a white-balance shift. Cheaper and more
    /// predictable here than a temperature model, because the LUT is built in
    /// display gamma.
    var whiteBalance = SIMD3<Double>(1, 1, 1)
    var matrix = Matrix.identity
    var red = Curve.linear
    var green = Curve.linear
    var blue = Curve.linear
    var saturation = 1.0
    /// How much saturation is surrendered as a pixel approaches white.
    var highlightDesaturation = 0.0
    /// Tint added into the shadows, weighted by 1 - luma.
    var shadowTint = SIMD3<Double>()
    /// Tint added into the highlights, weighted by luma.
    var highlightTint = SIMD3<Double>()
    var bands: [HueBand] = []
    /// Set for a monochrome look: how sensitive the "emulsion" is to each channel.
    /// A coloured lens filter over panchromatic stock is exactly this — Ye/R/G
    /// filters lighten their own hue and darken the complement.
    var monochromeMix: SIMD3<Double>?
    /// Two-point toning for a monochrome look. Black maps to `shadowToner`, white
    /// to `highlightToner`; sepia, selenium and cyanotype are all this one move.
    var shadowToner: SIMD3<Double>?
    var highlightToner: SIMD3<Double>?

    var isMonochrome: Bool { monochromeMix != nil }

    private static let lumaWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// Maps one sRGB triple through the look. Pure, so the LUT can be built on any
    /// thread and the whole look is testable without Core Image.
    func apply(to input: SIMD3<Double>) -> SIMD3<Double> {
        var color = Self.clamped(input * whiteBalance)

        if let monochromeMix {
            // Deliberately not normalised: the whole point of a Ye/R/G filter is
            // that it changes exposure per hue. The mixes in the library sum to
            // about 1 so overall brightness stays put.
            let gray = green.apply((monochromeMix * color).sum())
            if let shadowToner, let highlightToner {
                color = shadowToner + (highlightToner - shadowToner) * gray
            } else {
                color = SIMD3(repeating: gray)
            }
            return Self.clamped(Self.toned(color, shadow: shadowTint, highlight: highlightTint))
        }

        color = Self.clamped(matrix.apply(color))
        color = SIMD3(red.apply(color.x), green.apply(color.y), blue.apply(color.z))

        if !bands.isEmpty { color = applyBands(to: color) }

        if saturation != 1 || highlightDesaturation != 0 {
            let luma = (color * Self.lumaWeights).sum()
            // Falls off from the upper midtones so mid-bright colour keeps its
            // punch and only the near-clipped end washes out.
            let highlightWeight = Self.smoothstep(0.55, 1, luma)
            let amount = saturation * (1 - highlightDesaturation * highlightWeight)
            color = SIMD3(repeating: luma) + (color - SIMD3(repeating: luma)) * amount
        }

        return Self.clamped(Self.toned(color, shadow: shadowTint, highlight: highlightTint))
    }

    private func applyBands(to color: SIMD3<Double>) -> SIMD3<Double> {
        var hsv = Self.hsv(from: color)
        guard hsv.y > 0.001 else { return color }
        var hueShift = 0.0
        var saturationScale = 1.0
        var luminanceScale = 1.0
        for band in bands {
            let weight = Self.bandWeight(hue: hsv.x, band: band)
            guard weight > 0 else { continue }
            hueShift += band.hueShift * weight
            saturationScale *= 1 + (band.saturation - 1) * weight
            luminanceScale *= 1 + (band.luminance - 1) * weight
        }
        hsv.x = (hsv.x + hueShift).truncatingRemainder(dividingBy: 360)
        if hsv.x < 0 { hsv.x += 360 }
        hsv.y = min(1, max(0, hsv.y * saturationScale))
        hsv.z = min(1, max(0, hsv.z * luminanceScale))
        return Self.rgb(fromHSV: hsv)
    }

    /// Cosine falloff over the band's half-width: full effect at the centre,
    /// nothing at the edge, and no seam where two neighbouring bands meet.
    private static func bandWeight(hue: Double, band: HueBand) -> Double {
        var distance = abs(hue - band.center).truncatingRemainder(dividingBy: 360)
        if distance > 180 { distance = 360 - distance }
        guard distance < band.width else { return 0 }
        return 0.5 * (1 + cos(.pi * distance / band.width))
    }

    private static func toned(
        _ color: SIMD3<Double>,
        shadow: SIMD3<Double>,
        highlight: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard shadow != SIMD3<Double>() || highlight != SIMD3<Double>() else { return color }
        let luma = (color * lumaWeights).sum()
        return color + shadow * (1 - luma) + highlight * luma
    }

    static func clamped(_ color: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            min(1, max(0, color.x)),
            min(1, max(0, color.y)),
            min(1, max(0, color.z))
        )
    }

    private static func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }

    /// Hue in degrees, saturation and value in 0...1.
    static func hsv(from rgb: SIMD3<Double>) -> SIMD3<Double> {
        let maximum = max(rgb.x, max(rgb.y, rgb.z))
        let minimum = min(rgb.x, min(rgb.y, rgb.z))
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0 {
            if maximum == rgb.x {
                hue = 60 * ((rgb.y - rgb.z) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == rgb.y {
                hue = 60 * ((rgb.z - rgb.x) / delta + 2)
            } else {
                hue = 60 * ((rgb.x - rgb.y) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return SIMD3(hue, maximum > 0 ? delta / maximum : 0, maximum)
    }

    static func rgb(fromHSV hsv: SIMD3<Double>) -> SIMD3<Double> {
        let chroma = hsv.z * hsv.y
        let sector = hsv.x / 60
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = hsv.z - chroma
        let rgb: SIMD3<Double> = switch Int(sector) % 6 {
        case 0: SIMD3(chroma, secondary, 0)
        case 1: SIMD3(secondary, chroma, 0)
        case 2: SIMD3(0, chroma, secondary)
        case 3: SIMD3(0, secondary, chroma)
        case 4: SIMD3(secondary, 0, chroma)
        default: SIMD3(chroma, 0, secondary)
        }
        return rgb + SIMD3(repeating: base)
    }
}

extension FilmLook {
    /// Colour look. `curve` seeds all three channels; pass `red`/`green`/`blue` to
    /// pull one of them off the shared shape, which is what gives a stock its cast
    /// at a specific end of the range.
    static func color(
        curve: Curve = .linear,
        red: Curve? = nil,
        green: Curve? = nil,
        blue: Curve? = nil,
        saturation: Double = 1,
        highlightDesaturation: Double = 0.18,
        shadowTint: SIMD3<Double> = SIMD3<Double>(),
        highlightTint: SIMD3<Double> = SIMD3<Double>(),
        bands: [HueBand] = [],
        whiteBalance: SIMD3<Double> = SIMD3<Double>(1, 1, 1),
        matrix: Matrix = .identity
    ) -> FilmLook {
        FilmLook(
            whiteBalance: whiteBalance,
            matrix: matrix,
            red: red ?? curve,
            green: green ?? curve,
            blue: blue ?? curve,
            saturation: saturation,
            highlightDesaturation: highlightDesaturation,
            shadowTint: shadowTint,
            highlightTint: highlightTint,
            bands: bands
        )
    }

    /// Monochrome look. `curve` is the master transfer curve — for a monochrome
    /// look it is stored in `green`, because there is only one channel left to
    /// shape.
    static func monochrome(
        mix: SIMD3<Double>,
        curve: Curve,
        shadowToner: SIMD3<Double>? = nil,
        highlightToner: SIMD3<Double>? = nil,
        shadowTint: SIMD3<Double> = SIMD3<Double>(),
        highlightTint: SIMD3<Double> = SIMD3<Double>()
    ) -> FilmLook {
        FilmLook(
            green: curve,
            shadowTint: shadowTint,
            highlightTint: highlightTint,
            monochromeMix: mix,
            shadowToner: shadowToner,
            highlightToner: highlightToner
        )
    }
}

/// Panchromatic emulsion behind every monochrome look here, and the three
/// classic contrast filters over it. A yellow filter darkens blue sky a little, a
/// red one dramatically, and a green one lifts foliage while dropping skin.
private enum MonochromeMix {
    static let none = SIMD3<Double>(0.30, 0.59, 0.11)
    static let yellow = SIMD3<Double>(0.42, 0.50, 0.08)
    static let red = SIMD3<Double>(0.62, 0.33, 0.05)
    static let green = SIMD3<Double>(0.22, 0.68, 0.10)
}

/// Every look ShotDex ships, and the mapping from `PhotoFilter` onto it.
///
/// The Fujifilm set is the nineteen simulations an X-T5 actually has — the same
/// list as an X100VI minus REALA ACE, which needs a body Fujifilm never shipped
/// that mode to. The Leica set is the twelve Leica Looks distributed through
/// FOTOS for M11/Q3/SL3.
enum FilmLookLibrary {
    // MARK: Fujifilm

    /// The default. Barely anything: a touch of contrast and a shoulder, because
    /// PROVIA's job is to be the neutral all the others are judged against.
    static let provia = FilmLook.color(
        curve: Curve(contrast: 0.10, shoulder: 0.10),
        saturation: 1.05,
        highlightDesaturation: 0.16
    )

    /// Velvia 50's reputation in one line: the most saturated colour film ever
    /// sold, with blacks that fall off a cliff. Reds and magentas lead, greens go
    /// deep and slightly blue.
    static let velvia = FilmLook.color(
        curve: Curve(gamma: 1.06, contrast: 0.30, shoulder: 0.14),
        blue: Curve(gamma: 1.10, contrast: 0.30, shoulder: 0.14),
        saturation: 1.42,
        highlightDesaturation: 0.10,
        shadowTint: SIMD3(-0.008, -0.004, 0.012),
        bands: [
            HueBand(center: 0, width: 46, saturation: 1.12),
            HueBand(center: 120, width: 60, hueShift: -6, saturation: 1.10, luminance: 0.95),
            HueBand(center: 300, width: 50, saturation: 1.10),
        ]
    )

    /// Measured, one scene (rmse 0.0087). ASTIA earns its "/Soft": both the red and
    /// green transfer curves come out with *negative* contrast — the look flattens
    /// tone rather than shaping it — while overall saturation goes up 12%. Greens
    /// and cyans lose a little saturation but gain brightness, which is what keeps
    /// a lit background from competing with a face.
    static let astia = FilmLook.color(
        red: Curve(lift: 0.0, gain: 0.955, gamma: 1.191, contrast: -0.162, shoulder: 0.292),
        green: Curve(lift: 0.012, gain: 0.974, gamma: 1.291, contrast: -0.154, shoulder: 0.439),
        blue: Curve(lift: 0.0, gain: 1.0, gamma: 1.054, contrast: 0.035, shoulder: 0.075),
        saturation: 1.124,
        highlightDesaturation: 0.171,
        bands: [
            HueBand(center: 0, width: 30, hueShift: -5.6, saturation: 0.963, luminance: 0.991),
            HueBand(center: 120, width: 30, hueShift: -1.3, saturation: 0.906, luminance: 1.060),
            HueBand(center: 150, width: 30, hueShift: -6.9, saturation: 0.847, luminance: 1.056),
            HueBand(center: 180, width: 30, hueShift: 8.2, saturation: 0.916, luminance: 1.043),
            HueBand(center: 240, width: 30, saturation: 1.006, luminance: 1.039),
            HueBand(center: 330, width: 30, hueShift: 13.7, saturation: 0.959, luminance: 1.019),
        ]
    )

    /// Measured, one scene (rmse 0.0066). The result was not what the reputation
    /// says. Classic Chrome's signature is **global desaturation to 0.82 plus a
    /// reshaped blue channel** — blue alone gets lifted off the floor, flattened
    /// (negative contrast) and given a long shoulder, which cools the shadows and
    /// warms the highlights without touching hue. There was no red-specific
    /// suppression in the data at all; the hand-written version had invented one.
    ///
    /// Caveat worth keeping: the reference frame is sky, desert and a red truck, so
    /// only cyans and magentas carried enough pixels to fit a band. Greens and
    /// yellows here are whatever the global curves do to them.
    static let classicChrome = FilmLook.color(
        red: Curve(lift: 0.0, gain: 1.0, gamma: 1.036, contrast: 0.062, shoulder: 0.075),
        green: Curve(lift: 0.0, gain: 1.0, gamma: 1.057, contrast: 0.014, shoulder: 0.152),
        blue: Curve(lift: 0.020, gain: 1.0, gamma: 1.387, contrast: -0.399, shoulder: 0.436),
        saturation: 0.823,
        highlightDesaturation: 0.0,
        bands: [
            HueBand(center: 180, width: 30, hueShift: -3.2, saturation: 1.078, luminance: 0.930),
            HueBand(center: 210, width: 30, hueShift: -2.6, saturation: 1.058),
            HueBand(center: 330, width: 30, hueShift: 4.4, saturation: 1.071, luminance: 0.912),
        ]
    )

    /// Studio negative stock with the contrast pushed: true colour, hard light
    /// handled without skin going red.
    static let proNegHi = FilmLook.color(
        curve: Curve(lift: 0.008, contrast: 0.20, shoulder: 0.14),
        saturation: 1.02,
        highlightDesaturation: 0.20,
        highlightTint: SIMD3(0.006, 0, 0.008)
    )

    /// The flattest colour simulation Fujifilm makes — built to be graded, or to
    /// keep every tone in a face.
    static let proNegStd = FilmLook.color(
        curve: Curve(lift: 0.020, gamma: 0.98, contrast: 0.02, shoulder: 0.24),
        saturation: 0.95,
        highlightDesaturation: 0.22
    )

    // The two negatives are the looks people choose a Fujifilm body for, so they
    // are not tuned by eye like the rest of this file. Both were **measured**:
    // ten published comparison sheets — the same frame rendered by PROVIA and by
    // the simulation — were sampled at matching scene coordinates, giving 165,000
    // paired PROVIA→simulation pixels across five scenes with a PROVIA reference
    // (sky, interior, high contrast, warm, cool) and nine scenes for the
    // Classic Neg. ↔ Nostalgic Neg. difference. The pairs were binned into a tone
    // × hue grid and `FilmLook` itself was fitted to that grid by coordinate
    // descent, under bounds that keep a thinly-sampled hue from being fitted to
    // noise. Weighted RMSE against the measurement: 0.013 for Classic Neg., 0.008
    // for Nostalgic Neg. — around 2–3 values out of 255 per channel.
    //
    // PROVIA is the right baseline because it is Fujifilm's neutral, which is what
    // the image reaching this code already approximates.
    //
    // Two things the measurement contradicted, both of which had been coded from
    // Fujifilm's prose and were wrong:
    //
    // - Classic Neg.'s highlights are **warm, led by red** — red rises about twice
    //   as much as green and four times as much as blue. Not the magenta the
    //   marketing copy implies. The cyan-green shadows are real and measurable.
    // - Classic Neg.'s greens rotate **+29° toward cyan**, not toward yellow-olive.
    //   Foliage goes cooler and darker, and cyans lose a third of their saturation
    //   (×0.64) — the sky and haze behaviour that gives the look its reputation.

    /// Superia-derived: cyan-green shadows, warm red-led highlights, hard contrast,
    /// and a colour response that changes with brightness — which is why exposure
    /// changes the look of a Classic Neg. frame and not merely its brightness.
    ///
    /// Red carries the steepest curve of the three and green the highest floor. That
    /// pairing is the whole look: at the bottom green sits above red so shadows land
    /// cyan-green, at the top red outruns green and blue so highlights land warm.
    /// The measured 0.9 contrast on red is the ceiling this curve allows before an
    /// S-curve stops being monotone — the real stock is harder still.
    static let classicNeg = FilmLook.color(
        red: Curve(lift: 0.044, gain: 0.963, gamma: 1.158, contrast: 0.900, shoulder: 0.513),
        green: Curve(lift: 0.074, gain: 0.965, gamma: 1.269, contrast: 0.755, shoulder: 0.525),
        blue: Curve(lift: 0.041, gain: 0.979, gamma: 1.297, contrast: 0.374, shoulder: 0.413),
        saturation: 0.807,
        highlightDesaturation: 0.283,
        bands: [
            HueBand(center: 0, width: 30, hueShift: 13.5, saturation: 1.028, luminance: 1.030),
            HueBand(center: 30, width: 30, hueShift: -3.2, saturation: 0.812, luminance: 0.977),
            HueBand(center: 90, width: 30, hueShift: -6.8, saturation: 1.006, luminance: 0.985),
            // Foliage swings a full 29° toward cyan and darkens.
            HueBand(center: 120, width: 30, hueShift: 29.4, saturation: 1.016, luminance: 0.978),
            HueBand(center: 180, width: 30, saturation: 1.072),
            // Sky and haze: a third of the saturation gone, and brighter for it.
            HueBand(center: 210, width: 30, hueShift: 5.6, saturation: 0.637, luminance: 1.030),
            HueBand(center: 330, width: 30, hueShift: 3.4, saturation: 0.947, luminance: 1.037),
        ]
    )

    /// New American Color, the nineteen-seventies: Eggleston, Shore, Sternfeld,
    /// Misrach. Fujifilm's summary of what those photographs shared was "an overall
    /// atmosphere based on amber", and the measurement agrees exactly — red is
    /// lifted 0.065 off the floor while blue is lifted 0.008 and capped at 0.98, so
    /// the amber runs from the deepest shadow to the brightest highlight.
    ///
    /// It is not Classic Neg. with the shift reversed. Blue is *flattened* here
    /// (negative contrast) rather than lifted, shadows are raised instead of
    /// crushed, contrast is soft, and warm hues gain saturation while greens give a
    /// little up.
    static let nostalgicNeg = FilmLook.color(
        // Gain measured at 1.014; shipped at 1.0 so the top end rolls off instead of
        // clipping the last percent of the highlights flat.
        red: Curve(lift: 0.065, gain: 1.0, gamma: 1.056, contrast: 0.124, shoulder: 0.020),
        green: Curve(lift: 0.050, gain: 0.999, gamma: 1.183, contrast: -0.030, shoulder: 0.183),
        blue: Curve(lift: 0.008, gain: 0.981, gamma: 1.141, contrast: -0.251, shoulder: 0.167),
        saturation: 0.880,
        highlightDesaturation: 0.274,
        bands: [
            HueBand(center: 0, width: 30, hueShift: 11.7, saturation: 1.152, luminance: 0.990),
            HueBand(center: 30, width: 30, hueShift: -1.9, saturation: 1.192, luminance: 1.002),
            HueBand(center: 90, width: 30, hueShift: 2.1, saturation: 1.144, luminance: 0.989),
            HueBand(center: 120, width: 30, hueShift: 1.5, saturation: 1.033, luminance: 0.977),
            HueBand(center: 180, width: 30, hueShift: 16.8, saturation: 1.092, luminance: 1.018),
            HueBand(center: 210, width: 30, hueShift: -5.0, saturation: 1.195, luminance: 1.016),
            HueBand(center: 330, width: 30, hueShift: 10.0, saturation: 0.937, luminance: 1.006),
        ]
    )

    /// Measured, one scene (rmse 0.0055 — the closest fit of the set). A cinema
    /// negative in numbers: every channel lifted well off black (red most, at
    /// 0.097), every ceiling pulled down (blue to 0.875), and saturation at 0.78.
    /// Flat at both ends, which is the whole point of a profile you grade later.
    ///
    /// The fit wanted `highlightDesaturation` at its 0.9 bound. Shipped at 0.45:
    /// 0.9 renders a bright saturated sky nearly grey, and the reference frame — a
    /// grey-blue interior — had nothing bright and saturated in it to say otherwise.
    static let eterna = FilmLook.color(
        red: Curve(lift: 0.097, gain: 0.884, gamma: 1.318, contrast: 0.051, shoulder: 0.610),
        green: Curve(lift: 0.053, gain: 0.935, gamma: 1.0, contrast: -0.013),
        blue: Curve(lift: 0.044, gain: 0.875, gamma: 0.873, contrast: 0.127),
        saturation: 0.783,
        highlightDesaturation: 0.45,
        bands: [
            HueBand(center: 0, width: 30, hueShift: 3.0, saturation: 1.038, luminance: 1.007),
            HueBand(center: 30, width: 30, hueShift: 2.2, luminance: 0.970),
            HueBand(center: 180, width: 30, hueShift: -4.1, saturation: 1.050, luminance: 1.026),
            HueBand(center: 210, width: 30, hueShift: -3.8, saturation: 1.006, luminance: 0.996),
            HueBand(center: 330, width: 30, hueShift: 0.8, saturation: 0.919, luminance: 1.026),
        ]
    )

    /// Skipping the bleach step leaves the silver in with the dyes: almost
    /// monochrome, very hard, faintly metallic.
    static let eternaBleachBypass = FilmLook.color(
        curve: Curve(lift: 0.018, gamma: 1.06, contrast: 0.42, shoulder: 0.10),
        saturation: 0.34,
        highlightDesaturation: 0.30,
        shadowTint: SIMD3(-0.006, 0.002, 0.010),
        highlightTint: SIMD3(0.004, 0.008, 0.012),
        matrix: .bleed(0.16)
    )

    // MARK: Fujifilm monochrome

    /// ACROS 100: fine grain, deep blacks, a long smooth shoulder in the
    /// highlights. Fujifilm's best monochrome rendering, and noticeably richer
    /// than the plain Monochrome mode.
    static func acros(_ mix: SIMD3<Double>) -> FilmLook {
        .monochrome(
            mix: mix,
            curve: Curve(lift: 0.014, gamma: 1.02, contrast: 0.20, shoulder: 0.18)
        )
    }

    /// The older, plainer black-and-white conversion: flatter, no shoulder worth
    /// the name.
    static func monochrome(_ mix: SIMD3<Double>) -> FilmLook {
        .monochrome(mix: mix, curve: Curve(lift: 0.022, contrast: 0.10, shoulder: 0.06))
    }

    static let sepia = FilmLook.monochrome(
        mix: MonochromeMix.none,
        curve: Curve(contrast: 0.12, shoulder: 0.14),
        shadowToner: SIMD3(0.085, 0.050, 0.024),
        highlightToner: SIMD3(1.0, 0.905, 0.735)
    )

    // MARK: Leica Looks

    // No published before/after frames exist for the Leica Looks the way they do
    // for the Fujifilm simulations, so these three follow Leica's own descriptions
    // rather than a measurement. They are corrected here because the first pass
    // contradicted those descriptions outright.

    /// Leica's word for it is a **muted** palette accentuating subtle contrasts.
    /// The first version of this made it a Kodachrome — rich, dense, saturated —
    /// which is close to the opposite. Saturation comes down, the contrast lives in
    /// the midtones, and nothing shouts.
    static let leicaChrome = FilmLook.color(
        curve: Curve(lift: 0.014, gamma: 1.02, contrast: 0.22, shoulder: 0.20),
        saturation: 0.84,
        highlightDesaturation: 0.20,
        bands: [
            HueBand(center: 0, width: 42, saturation: 0.92),
            HueBand(center: 200, width: 54, saturation: 0.90, luminance: 0.97),
        ]
    )

    /// "High contrast, soft saturation and warm, slightly washed-out colours." The
    /// washed-out part is the lifted floor: contrast is high *and* black stops
    /// short of black, which is what an analogue print does and a contrast slider
    /// does not.
    static let leicaClassic = FilmLook.color(
        curve: Curve(lift: 0.042, gamma: 1.02, contrast: 0.30, shoulder: 0.18),
        saturation: 0.88,
        highlightDesaturation: 0.24,
        highlightTint: SIMD3(0.026, 0.012, -0.014)
    )

    /// "Bright shadows, natural colours and a subtle reddish tint." The first
    /// version had cool blue shadows, which is the wrong direction on the one
    /// detail Leica bothers to name.
    static let leicaContemporary = FilmLook.color(
        curve: Curve(lift: 0.048, gamma: 0.96, contrast: 0.14, shoulder: 0.20),
        saturation: 0.97,
        highlightDesaturation: 0.20,
        shadowTint: SIMD3(0.016, 0.002, 0.004),
        highlightTint: SIMD3(0.012, 0, 0.002)
    )

    /// Leica's own description is striking contrast, bold saturation and a
    /// magenta cast — which is exactly what this is.
    static let leicaEternal = FilmLook.color(
        curve: Curve(gamma: 1.06, contrast: 0.34, shoulder: 0.12),
        saturation: 1.24,
        highlightDesaturation: 0.12,
        shadowTint: SIMD3(0.010, -0.004, 0.012),
        highlightTint: SIMD3(0.024, -0.008, 0.020)
    )

    /// Cyanotype. Monochrome first, then toned into Prussian blue.
    static let leicaBlue = FilmLook.monochrome(
        mix: MonochromeMix.none,
        curve: Curve(contrast: 0.16, shoulder: 0.14),
        shadowToner: SIMD3(0.016, 0.055, 0.150),
        highlightToner: SIMD3(0.800, 0.900, 1.0)
    )

    /// Selenium-toned silver print: cool, slightly purple, soft contrast.
    static let leicaSelenium = FilmLook.monochrome(
        mix: MonochromeMix.none,
        curve: Curve(lift: 0.020, contrast: 0.08, shoulder: 0.18),
        shadowToner: SIMD3(0.050, 0.046, 0.088),
        highlightToner: SIMD3(0.965, 0.955, 1.0)
    )

    /// Warmer and flatter than the Fujifilm sepia — a faded print rather than a
    /// deliberate tone.
    static let leicaSepia = FilmLook.monochrome(
        mix: MonochromeMix.none,
        curve: Curve(lift: 0.030, contrast: 0.06, shoulder: 0.20),
        shadowToner: SIMD3(0.120, 0.082, 0.052),
        highlightToner: SIMD3(0.985, 0.930, 0.815)
    )

    /// Bleach bypass, Leica's version: harder than Fujifilm's and a shade cooler.
    static let leicaBleach = FilmLook.color(
        curve: Curve(lift: 0.012, gamma: 1.08, contrast: 0.46, shoulder: 0.08),
        saturation: 0.30,
        highlightDesaturation: 0.32,
        shadowTint: SIMD3(-0.008, 0, 0.012),
        matrix: .bleed(0.18)
    )

    /// High-key silver: bright, open shadows, blacks that stop short of black.
    static let leicaSilver = FilmLook.monochrome(
        mix: MonochromeMix.none,
        curve: Curve(lift: 0.036, gain: 0.985, gamma: 0.94, contrast: 0.14, shoulder: 0.20),
        shadowToner: SIMD3(0.036, 0.038, 0.046),
        highlightToner: SIMD3(0.985, 0.990, 1.0)
    )

    /// Teal-and-orange, kept restrained: shadows cool, highlights warm, mids
    /// untouched.
    static let leicaTeal = FilmLook.color(
        curve: Curve(lift: 0.024, contrast: 0.22, shoulder: 0.16),
        saturation: 1.04,
        highlightDesaturation: 0.20,
        shadowTint: SIMD3(-0.020, 0.006, 0.024),
        highlightTint: SIMD3(0.028, 0.010, -0.020),
        bands: [
            HueBand(center: 190, width: 56, saturation: 1.14),
            HueBand(center: 30, width: 36, saturation: 1.08),
        ]
    )

    /// Brass: gold highlights over a slightly green-brown mid, like old lacquer.
    static let leicaBrass = FilmLook.color(
        curve: Curve(lift: 0.022, gamma: 1.02, contrast: 0.18, shoulder: 0.18),
        blue: Curve(lift: 0.022, gain: 0.955, gamma: 1.06, contrast: 0.18, shoulder: 0.18),
        saturation: 0.96,
        highlightDesaturation: 0.22,
        highlightTint: SIMD3(0.036, 0.022, -0.026),
        bands: [
            HueBand(center: 50, width: 46, saturation: 1.14),
            HueBand(center: 120, width: 54, hueShift: 10, saturation: 0.86),
        ]
    )

    /// The portrait look in the FOTOS set: soft toe, warm skin, greens pulled
    /// back so a face is the only saturated thing in frame.
    static let leicaGregWilliams = FilmLook.color(
        curve: Curve(lift: 0.034, gamma: 0.97, contrast: 0.12, shoulder: 0.24),
        saturation: 0.94,
        highlightDesaturation: 0.24,
        highlightTint: SIMD3(0.018, 0.008, -0.010),
        bands: [
            HueBand(center: 26, width: 34, saturation: 1.10),
            HueBand(center: 120, width: 60, saturation: 0.80),
        ]
    )

    // MARK: Film stock

    /// The portrait standard. Very low contrast, creamy skin, foliage nudged
    /// yellow, and a long shoulder that never lets a highlight go hard.
    static let portra400 = FilmLook.color(
        curve: Curve(lift: 0.032, gamma: 0.97, contrast: 0.08, shoulder: 0.26),
        blue: Curve(lift: 0.040, gamma: 1.00, contrast: 0.08, shoulder: 0.26),
        saturation: 0.98,
        highlightDesaturation: 0.28,
        highlightTint: SIMD3(0.022, 0.012, -0.014),
        bands: [
            HueBand(center: 28, width: 36, saturation: 1.06),
            HueBand(center: 120, width: 58, hueShift: 7, saturation: 0.90),
        ]
    )

    /// Consumer Kodak: everything golden, sky slightly cyan, contrast mild.
    static let gold200 = FilmLook.color(
        curve: Curve(lift: 0.028, gamma: 0.98, contrast: 0.14, shoulder: 0.22),
        blue: Curve(lift: 0.034, gain: 0.96, gamma: 1.06, contrast: 0.14, shoulder: 0.22),
        saturation: 1.10,
        highlightDesaturation: 0.24,
        highlightTint: SIMD3(0.040, 0.024, -0.024),
        bands: [
            HueBand(center: 45, width: 46, saturation: 1.16),
            HueBand(center: 200, width: 50, saturation: 1.06),
        ]
    )

    /// Kodachrome 64: dense, dark, red-forward, and the sharpest-looking colour
    /// film there was. Blues are held down hard.
    static let kodachrome64 = FilmLook.color(
        curve: Curve(gamma: 1.06, contrast: 0.30, shoulder: 0.12),
        blue: Curve(gain: 0.940, gamma: 1.12, contrast: 0.30, shoulder: 0.12),
        saturation: 1.16,
        highlightDesaturation: 0.14,
        shadowTint: SIMD3(0.006, -0.004, 0.008),
        bands: [
            HueBand(center: 0, width: 44, saturation: 1.20, luminance: 0.96),
            HueBand(center: 55, width: 44, saturation: 1.06),
            HueBand(center: 220, width: 52, saturation: 0.94, luminance: 0.92),
        ]
    )

    /// Ektar 100: the most saturated colour negative Kodak sells, cool-neutral
    /// rather than golden, and unforgiving of skin.
    static let ektar100 = FilmLook.color(
        curve: Curve(lift: 0.008, gamma: 1.02, contrast: 0.24, shoulder: 0.16),
        saturation: 1.30,
        highlightDesaturation: 0.14,
        shadowTint: SIMD3(-0.008, 0, 0.012),
        bands: [
            HueBand(center: 210, width: 56, saturation: 1.16),
            HueBand(center: 0, width: 42, saturation: 1.10),
        ]
    )

    /// Superia 400: the green-cyan cast that made every nineties snapshot look
    /// the way it does.
    static let superia400 = FilmLook.color(
        curve: Curve(lift: 0.024, contrast: 0.18, shoulder: 0.18),
        red: Curve(lift: 0.024, gain: 0.985, contrast: 0.18, shoulder: 0.18),
        saturation: 1.12,
        highlightDesaturation: 0.20,
        shadowTint: SIMD3(-0.010, 0.010, 0.012),
        bands: [
            HueBand(center: 120, width: 60, hueShift: -8, saturation: 1.18),
            HueBand(center: 190, width: 52, saturation: 1.10),
        ]
    )

    /// Tungsten-balanced cine stock shot in daylight, which is how everyone
    /// actually uses it: strong cyan-blue cast, warm-magenta highlight bloom.
    static let cineStill800T = FilmLook.color(
        curve: Curve(lift: 0.042, gamma: 0.97, contrast: 0.16, shoulder: 0.24),
        saturation: 1.06,
        highlightDesaturation: 0.22,
        shadowTint: SIMD3(-0.024, -0.004, 0.038),
        highlightTint: SIMD3(0.030, -0.006, 0.014),
        bands: [
            HueBand(center: 220, width: 58, saturation: 1.18),
            HueBand(center: 0, width: 40, saturation: 1.12),
        ],
        whiteBalance: SIMD3(0.965, 0.995, 1.045)
    )

    /// HP5 pushed a stop: open shadows, gritty mids, highlights that keep going.
    static let hp5 = FilmLook.monochrome(
        mix: SIMD3(0.32, 0.55, 0.13),
        curve: Curve(lift: 0.032, gamma: 0.98, contrast: 0.24, shoulder: 0.14)
    )

    /// Tri-X: blacker blacks than HP5 and a much stronger shoulder — the reason
    /// its highlights never look clipped.
    static let triX = FilmLook.monochrome(
        mix: SIMD3(0.36, 0.52, 0.12),
        curve: Curve(lift: 0.012, gamma: 1.04, contrast: 0.30, shoulder: 0.22)
    )

    private typealias Curve = FilmLook.Curve
    private typealias HueBand = FilmLook.HueBand

    /// The look behind a filter, or `nil` for the ten original presets, which stay
    /// on their Core Image chains so recipes saved before this existed render
    /// exactly as they did.
    static func look(for filter: PhotoFilter) -> FilmLook? {
        switch filter {
        case .original, .vivid, .vividWarm, .vividCool, .dramatic, .dramaticWarm,
             .dramaticCool, .mono, .silvertone, .noir:
            nil
        case .provia: provia
        case .velvia: velvia
        case .astia: astia
        case .classicChrome: classicChrome
        case .proNegHi: proNegHi
        case .proNegStd: proNegStd
        case .classicNeg: classicNeg
        case .nostalgicNeg: nostalgicNeg
        case .eterna: eterna
        case .eternaBleachBypass: eternaBleachBypass
        case .acros: acros(MonochromeMix.none)
        case .acrosYellow: acros(MonochromeMix.yellow)
        case .acrosRed: acros(MonochromeMix.red)
        case .acrosGreen: acros(MonochromeMix.green)
        case .fujiMonochrome: monochrome(MonochromeMix.none)
        case .fujiMonochromeYellow: monochrome(MonochromeMix.yellow)
        case .fujiMonochromeRed: monochrome(MonochromeMix.red)
        case .fujiMonochromeGreen: monochrome(MonochromeMix.green)
        case .fujiSepia: sepia
        case .leicaChrome: leicaChrome
        case .leicaClassic: leicaClassic
        case .leicaContemporary: leicaContemporary
        case .leicaEternal: leicaEternal
        case .leicaBlue: leicaBlue
        case .leicaSelenium: leicaSelenium
        case .leicaSepia: leicaSepia
        case .leicaBleach: leicaBleach
        case .leicaSilver: leicaSilver
        case .leicaTeal: leicaTeal
        case .leicaBrass: leicaBrass
        case .leicaGregWilliams: leicaGregWilliams
        case .portra400: portra400
        case .gold200: gold200
        case .kodachrome64: kodachrome64
        case .ektar100: ektar100
        case .superia400: superia400
        case .cineStill800T: cineStill800T
        case .hp5: hp5
        case .triX: triX
        }
    }
}

/// Builds the 3D lookup table a look becomes on the GPU. One `CIColorCube` pass
/// replaces what would otherwise be a dozen chained filters, and — because the
/// table is resolution-independent — the 150pt thumbnail, the on-screen preview
/// and the full-resolution save are guaranteed to be the same look.
enum FilmLookLUT {
    /// 33 is the size commercial LUTs standardise on: odd, so the neutral midpoint
    /// is sampled exactly, and fine enough that trilinear interpolation of a
    /// smooth curve shows no banding. 575 KB per table.
    static let dimension = 33

    /// Float RGBA, red varying fastest, as `CIColorCubeWithColorSpace` expects.
    static func data(for look: FilmLook, dimension: Int = dimension) -> Data {
        let steps = max(2, dimension)
        let last = Double(steps - 1)
        var values = [Float](repeating: 0, count: steps * steps * steps * 4)
        var index = 0
        for blue in 0..<steps {
            for green in 0..<steps {
                for red in 0..<steps {
                    let output = look.apply(
                        to: SIMD3(
                            Double(red) / last,
                            Double(green) / last,
                            Double(blue) / last
                        )
                    )
                    values[index] = Float(output.x)
                    values[index + 1] = Float(output.y)
                    values[index + 2] = Float(output.z)
                    values[index + 3] = 1
                    index += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
