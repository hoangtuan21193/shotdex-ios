import Foundation
import Testing
@testable import ShotDex

struct FilmSimulationTests {
    // MARK: Catalogue

    @Test func everyFilterOutsideTheOriginalPresetsHasALook() {
        for filter in PhotoFilter.allCases {
            let look = FilmLookLibrary.look(for: filter)
            if filter.category == .basic {
                #expect(look == nil, "\(filter.rawValue) is a Core Image preset")
            } else {
                #expect(look != nil, "\(filter.rawValue) has no film look")
            }
        }
    }

    @Test func theCatalogueIsThreeStripsThatPartitionEveryLook() {
        #expect(PhotoFilter.all(in: .basic).count == 10)
        #expect(PhotoFilter.all(in: .film).count == 24)
        #expect(PhotoFilter.all(in: .monochrome).count == 15)
        // Categories partition the enum: nothing missing, nothing counted twice.
        let grouped = FilmLookCategory.allCases.flatMap { PhotoFilter.all(in: $0) }
        #expect(grouped.count == PhotoFilter.allCases.count)
        #expect(Set(grouped) == Set(PhotoFilter.allCases))
    }

    @Test func theBlackAndWhiteStripHoldsExactlyTheMonochromeLooks() {
        // The strips are sorted by what a look *is*, so a toned silver print sits
        // with the black and white looks no matter which camera maker's it is.
        for filter in PhotoFilter.all(in: .monochrome) {
            #expect(
                FilmLookLibrary.look(for: filter)?.isMonochrome == true,
                "\(filter.rawValue) is in B&W but renders colour"
            )
        }
        for filter in PhotoFilter.all(in: .film) {
            #expect(
                FilmLookLibrary.look(for: filter)?.isMonochrome != true,
                "\(filter.rawValue) is in Film but renders monochrome"
            )
        }
    }

    @Test func namesAreUniqueAndFitTheirRow() {
        #expect(Set(PhotoFilter.allCases.map(\.displayName)).count == PhotoFilter.allCases.count)
        for filter in PhotoFilter.allCases {
            #expect(!filter.tileName.isEmpty)
            // Longer than this and a caption under a 60pt swatch has to shrink to
            // the point of being unreadable.
            #expect(filter.tileName.count <= 14, "\(filter.rawValue) caption is too long")
        }
    }

    // MARK: Curve

    @Test func curvesAreMonotoneAndKeepTheirEndpoints() {
        let curves: [FilmLook.Curve] = [
            .linear,
            FilmLook.Curve(contrast: 0.4, shoulder: 0.3),
            FilmLook.Curve(lift: 0.05, gain: 0.94, gamma: 0.9, contrast: -0.2, shoulder: 0.5),
            FilmLook.Curve(lift: 0.02, gamma: 1.2, contrast: 0.5, shoulder: 0.05),
        ]
        for curve in curves {
            #expect(abs(curve.apply(0) - curve.lift) < 1e-9)
            #expect(abs(curve.apply(1) - curve.gain) < 1e-9)
            var previous = -1.0
            for step in 0...200 {
                let value = curve.apply(Double(step) / 200)
                #expect(value >= previous, "curve dipped at \(step)")
                previous = value
            }
        }
    }

    @Test func curvesClampTheirInput() {
        let curve = FilmLook.Curve(lift: 0.1, gain: 0.9)
        #expect(curve.apply(-2) == 0.1)
        #expect(curve.apply(4) == 0.9)
    }

    // MARK: Look behaviour

    @Test func everyLookStaysInRangeAndKeepsBlackDarkAndWhiteBright() {
        for filter in PhotoFilter.allCases {
            guard let look = FilmLookLibrary.look(for: filter) else { continue }
            for step in 0...16 {
                let input = Double(step) / 16
                let output = look.apply(to: SIMD3(repeating: input))
                for channel in [output.x, output.y, output.z] {
                    #expect(channel >= 0 && channel <= 1, "\(filter.rawValue) left 0...1")
                }
            }
            let black = luma(look.apply(to: SIMD3(repeating: 0)))
            let white = luma(look.apply(to: SIMD3(repeating: 1)))
            #expect(black < 0.30, "\(filter.rawValue) black point is too high")
            #expect(white > 0.55, "\(filter.rawValue) white point is too low")
            #expect(white > black)

            // A look may bend tone anywhere it likes but must never fold it back:
            // a grey ramp in has to come out still climbing, or a gradient shows a
            // seam the photo never had.
            var previous = -1.0
            for step in 0...64 {
                let value = luma(look.apply(to: SIMD3(repeating: Double(step) / 64)))
                #expect(
                    value >= previous - 0.0005,
                    "\(filter.rawValue) ramp dipped at step \(step)"
                )
                previous = value
            }
        }
    }

    @Test func monochromeLooksAreNeutralUnlessTheyAreToned() {
        for filter in PhotoFilter.allCases {
            guard let look = FilmLookLibrary.look(for: filter), look.isMonochrome else { continue }
            let output = look.apply(to: SIMD3(0.6, 0.35, 0.2))
            let isToned = look.shadowToner != nil && look.highlightToner != nil
            let spread = max(output.x, max(output.y, output.z))
                - min(output.x, min(output.y, output.z))
            if isToned {
                #expect(spread > 0.01, "\(filter.rawValue) claims a toner but came out neutral")
            } else {
                #expect(spread < 0.001, "\(filter.rawValue) is not neutral")
            }
        }
    }

    @Test func contrastFiltersLightenTheirOwnHueAndDarkenTheComplement() {
        let red = SIMD3(0.70, 0.15, 0.12)
        let sky = SIMD3(0.35, 0.55, 0.85)
        let withRed = FilmLookLibrary.look(for: .acrosRed)!
        let withGreen = FilmLookLibrary.look(for: .acrosGreen)!
        let plain = FilmLookLibrary.look(for: .acros)!

        #expect(luma(withRed.apply(to: red)) > luma(plain.apply(to: red)))
        #expect(luma(withRed.apply(to: red)) > luma(withGreen.apply(to: red)))
        // The classic red-filter sky: much darker than the unfiltered rendering.
        #expect(luma(withRed.apply(to: sky)) < luma(plain.apply(to: sky)))
        #expect(luma(withGreen.apply(to: sky)) > luma(withRed.apply(to: sky)))
    }

    @Test func looksDifferInTheDirectionTheirFilmDid() {
        let patch = SIMD3(0.62, 0.36, 0.26)
        let velvia = FilmLookLibrary.look(for: .velvia)!
        let proNegStd = FilmLookLibrary.look(for: .proNegStd)!
        let classicChrome = FilmLookLibrary.look(for: .classicChrome)!
        let provia = FilmLookLibrary.look(for: .provia)!
        let eterna = FilmLookLibrary.look(for: .eterna)!

        // Velvia was the most saturated colour film sold; PRO Neg. Std is the
        // flattest thing Fujifilm ships.
        #expect(saturation(velvia.apply(to: patch)) > saturation(proNegStd.apply(to: patch)))

        // Classic Chrome sits reds back — that is its whole signature.
        let redPatch = SIMD3(0.78, 0.20, 0.18)
        #expect(
            saturation(classicChrome.apply(to: redPatch)) < saturation(provia.apply(to: redPatch))
        )

        // ETERNA is a cinema negative: less range between shadow and highlight
        // than a slide film has.
        let shadow = SIMD3(repeating: 0.25)
        let highlight = SIMD3(repeating: 0.75)
        let eternaRange = luma(eterna.apply(to: highlight)) - luma(eterna.apply(to: shadow))
        let velviaRange = luma(velvia.apply(to: highlight)) - luma(velvia.apply(to: shadow))
        #expect(eternaRange < velviaRange)
        #expect(eternaRange > 0)
    }

    /// Classic Neg.'s colour response changes with brightness — that is the look —
    /// and these are the two ends of it as **measured** off published PROVIA/Classic
    /// Neg. comparison frames: cyan-green shadows, warm red-led highlights.
    ///
    /// Note what is deliberately not asserted: magenta highlights. Fujifilm's own
    /// copy says magenta, and the pixels say otherwise — red rises about twice as
    /// much as green and four times as much as blue. The measurement wins.
    @Test func classicNegativePutsCyanGreenInTheShadowsAndWarmthInTheHighlights() {
        let look = FilmLookLibrary.look(for: .classicNeg)!

        let shadow = look.apply(to: SIMD3(repeating: 0.16))
        #expect(shadow.y > shadow.x, "shadow lost its green")
        #expect(shadow.z > shadow.x, "shadow lost its cyan")

        let highlight = look.apply(to: SIMD3(repeating: 0.86))
        #expect(highlight.x > highlight.y, "highlight lost its warmth")
        #expect(highlight.y > highlight.z, "highlight lost its warmth")
    }

    /// The structure behind that: red is the steepest curve of the three and green
    /// has the highest floor. Green above red at the bottom is what makes the
    /// shadows cyan-green; red outrunning both at the top is what makes the
    /// highlights warm. Break either ordering and the look inverts.
    @Test func classicNegativeIsBuiltOnASteepRedAndAHighGreenFloor() {
        let look = FilmLookLibrary.look(for: .classicNeg)!
        #expect(look.red.contrast > look.green.contrast)
        #expect(look.green.contrast > look.blue.contrast)
        #expect(look.green.lift > look.red.lift)
    }

    @Test func classicNegativeGivesUpCoolHuesBeforeWarmOnes() {
        let look = FilmLookLibrary.look(for: .classicNeg)!
        // Measured: cyans keep 0.64 of their saturation while reds keep 1.03 of
        // theirs. Sky and haze are what give the look its reputation.
        let red = SIMD3(0.72, 0.26, 0.22)
        let blue = SIMD3(0.24, 0.40, 0.72)
        let redKept = saturation(look.apply(to: red)) / saturation(red)
        let blueKept = saturation(look.apply(to: blue)) / saturation(blue)
        #expect(redKept > blueKept)
    }

    /// Fujifilm's point about Nostalgic Neg. is that shadows normally sink into blue
    /// or green and that this one refuses to let them. Here the measurement agreed:
    /// red is lifted 0.065 off the floor against blue's 0.008, so the amber runs
    /// from the deepest shadow to the brightest highlight.
    @Test func nostalgicNegativeKeepsAmberAllTheWayIntoTheShadows() {
        let look = FilmLookLibrary.look(for: .nostalgicNeg)!
        for level in [0.14, 0.40, 0.82] {
            let output = look.apply(to: SIMD3(repeating: level))
            #expect(output.x > output.z, "lost its amber at \(level)")
        }
        let shadow = look.apply(to: SIMD3(repeating: 0.14))
        #expect(shadow.x > shadow.y && shadow.y > shadow.z, "shadow is not warm")

        let classicNeg = FilmLookLibrary.look(for: .classicNeg)!
        // The two negatives pull opposite ways down there, which is the whole
        // reason both are worth having.
        let coolShadow = classicNeg.apply(to: SIMD3(repeating: 0.16))
        #expect(coolShadow.z > coolShadow.x)

        // Lifted shadows and softer contrast than Classic Neg. Compared in the
        // shadows proper rather than at zero: Classic Neg.'s green floor is high, so
        // pure black alone would say the opposite of what a shadow actually does.
        #expect(
            luma(look.apply(to: SIMD3(repeating: 0.12)))
                > luma(classicNeg.apply(to: SIMD3(repeating: 0.12)))
        )
        #expect(range(of: look) < range(of: classicNeg))
    }

    /// ASTIA, Classic Chrome and ETERNA were fitted the same way as the two
    /// negatives, from one published PROVIA comparison frame each. These lock the
    /// shape the pixels showed — which for two of the three is not the shape the
    /// look is popularly credited with.
    @Test func theMeasuredSimulationsKeepTheShapeTheirFramesShowed() {
        let astia = FilmLookLibrary.look(for: .astia)!
        // "/Soft" turned out to be literal: both curves *flatten* tone rather than
        // shaping it, and the colour comes from saturation instead.
        #expect(astia.red.contrast < 0)
        #expect(astia.green.contrast < 0)
        #expect(astia.saturation > 1)

        let chrome = FilmLookLibrary.look(for: .classicChrome)!
        // Global desaturation plus a reshaped blue channel — no red-specific
        // suppression appeared in the data, though the look is usually credited
        // with one.
        #expect(chrome.saturation < 0.9)
        #expect(chrome.blue.gamma > chrome.red.gamma)
        #expect(chrome.blue.contrast < 0)

        let eterna = FilmLookLibrary.look(for: .eterna)!
        // Lifted at the bottom and capped at the top in every channel: a profile
        // meant to be graded, not published.
        for curve in [eterna.red, eterna.green, eterna.blue] {
            #expect(curve.lift > 0.04)
            #expect(curve.gain < 0.95)
        }
        #expect(eterna.saturation < 0.8)
        #expect(range(of: eterna) < range(of: FilmLookLibrary.look(for: .classicNeg)!))
    }

    @Test func highlightDesaturationOnlyTouchesTheBrightEnd() {
        let look = FilmLook.color(saturation: 1, highlightDesaturation: 0.8)
        let midtone = SIMD3(0.45, 0.28, 0.20)
        let bright = SIMD3(0.97, 0.80, 0.72)
        #expect(abs(saturation(look.apply(to: midtone)) - saturation(midtone)) < 0.01)
        #expect(saturation(look.apply(to: bright)) < saturation(bright) - 0.05)
    }

    @Test func hueBandsOnlyMoveTheHuesTheyName() {
        let look = FilmLook.color(
            highlightDesaturation: 0,
            bands: [FilmLook.HueBand(center: 120, width: 40, hueShift: -20)]
        )
        let green = FilmLook.hsv(from: look.apply(to: FilmLook.rgb(fromHSV: SIMD3(120, 0.6, 0.6))))
        #expect(abs(green.x - 100) < 1.5)
        // A red patch is 120° away, well outside the band's half-width.
        let red = FilmLook.hsv(from: look.apply(to: FilmLook.rgb(fromHSV: SIMD3(0, 0.6, 0.6))))
        #expect(abs(red.x - 0) < 1.5 || abs(red.x - 360) < 1.5)
    }

    @Test func hsvRoundTripsThroughRGB() {
        for hue in stride(from: 0.0, to: 360, by: 17) {
            for saturation in [0.0, 0.35, 1.0] {
                for value in [0.15, 0.6, 1.0] {
                    let hsv = SIMD3(hue, saturation, value)
                    let round = FilmLook.hsv(from: FilmLook.rgb(fromHSV: hsv))
                    #expect(abs(round.z - value) < 1e-9)
                    #expect(abs(round.y - saturation) < 1e-9)
                    if saturation > 0 { #expect(abs(round.x - hue) < 1e-6) }
                }
            }
        }
    }

    // MARK: Lookup table

    @Test func theLookupTableIsLaidOutAsCoreImageExpects() {
        let look = FilmLookLibrary.look(for: .classicChrome)!
        let dimension = 5
        let data = FilmLookLUT.data(for: look, dimension: dimension)
        let expected = dimension * dimension * dimension * 4
        #expect(data.count == expected * MemoryLayout<Float>.size)

        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(values.count == expected)
        // Alpha is 1 everywhere: the cube is opaque by construction.
        for index in stride(from: 3, to: values.count, by: 4) {
            #expect(values[index] == 1)
        }
        // First sample is black, last is white, and red varies fastest — so entry
        // one is the look's response to a single red step and nothing else.
        let black = look.apply(to: SIMD3(repeating: 0))
        #expect(abs(Double(values[0]) - black.x) < 1e-6)
        let white = look.apply(to: SIMD3(repeating: 1))
        #expect(abs(Double(values[expected - 4]) - white.x) < 1e-6)
        let firstRedStep = look.apply(to: SIMD3(0.25, 0, 0))
        #expect(abs(Double(values[4]) - firstRedStep.x) < 1e-6)
        #expect(abs(Double(values[5]) - firstRedStep.y) < 1e-6)
    }

    @Test func theShippedTableSizeIsTheStandardOddCube() {
        // Odd, so neutral grey is sampled exactly rather than interpolated.
        #expect(FilmLookLUT.dimension % 2 == 1)
        #expect(FilmLookLUT.dimension == 33)
    }

    // MARK: Helpers

    private func luma(_ color: SIMD3<Double>) -> Double {
        0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
    }

    private func saturation(_ color: SIMD3<Double>) -> Double {
        FilmLook.hsv(from: color).y
    }

    private func range(of look: FilmLook) -> Double {
        luma(look.apply(to: SIMD3(repeating: 0.75)))
            - luma(look.apply(to: SIMD3(repeating: 0.25)))
    }
}
