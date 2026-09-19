import Testing
@testable import ShotDexKit
@testable import ShotDex

struct EditorAdjustmentCatalogTests {
    @Test func lightGroupLeadsWithTheSpecOrderAndOffersAuto() {
        let groups = EditorAdjustmentCatalog.groups(isRAWSource: false, scope: .global)
        let light = groups.first
        #expect(light?.id == .light)
        #expect(light?.hasAuto == true)
        #expect(
            Array(light?.kinds.prefix(6) ?? []) == [
                .exposure, .contrast, .highlights, .shadows, .whites, .blackPoint,
            ]
        )
        // Order, not a frozen list: Optics and Geo were added after this test
        // was written and the catalog will grow again. What has to hold is that
        // Light comes first and the tone groups keep their relative order.
        let ids = groups.map(\.id)
        #expect(ids.prefix(4) == [.light, .color, .detail, .effects])
        #expect(ids.contains(.optics))
        #expect(ids.contains(.geo))
        #expect(groups.contains { $0.kinds.contains(.grain) })
    }

    @Test func rawGroupOnlyExistsForRAWGlobalScope() {
        let rawGlobal = EditorAdjustmentCatalog.groups(isRAWSource: true, scope: .global)
        #expect(rawGlobal.map(\.id).contains(.raw))

        let rawMask = EditorAdjustmentCatalog.groups(isRAWSource: true, scope: .mask)
        #expect(!rawMask.map(\.id).contains(.raw))

        let renderedGlobal = EditorAdjustmentCatalog.groups(isRAWSource: false, scope: .global)
        #expect(!renderedGlobal.map(\.id).contains(.raw))
    }

    /// Asked for the richest catalog there is — RAW, global, with depth — so
    /// "every kind is grouped somewhere" stays the claim. Depth Blur is only
    /// offered on photos that carry a depth map, so without `hasDepth` this
    /// would fail for a row that is deliberately conditional.
    @Test func everyGroupedKindAppearsExactlyOnce() {
        let kinds = EditorAdjustmentCatalog
            .groups(isRAWSource: true, scope: .global, hasDepth: true)
            .flatMap(\.kinds)
        #expect(Set(kinds).count == kinds.count)
        #expect(Set(kinds) == Set(PhotoAdjustmentKind.allCases))
    }

    @Test func unipolarSlidersStartAtZero() {
        // Grain (and its Size / Roughness) plus the RAW strengths are the one-way
        // sliders.
        for kind in [
            PhotoAdjustmentKind.grain, .grainSize, .grainRoughness,
            .vignetteMidpoint, .vignetteFeather, .sharpenRadius,
            .sharpenDetail, .sharpenMasking,
            .colorNoiseReduction, .vignetteHighlights, .defringe, .rawLuminanceNoise,
        ] {
            #expect(EditorAdjustmentCatalog.sliderRange(of: kind) == 0...1)
            #expect(EditorAdjustmentCatalog.isBipolar(kind) == false)
        }
        #expect(EditorAdjustmentCatalog.sliderRange(of: .exposure) == -2...2)
        #expect(EditorAdjustmentCatalog.isBipolar(.whites))
    }

    @Test func detailAndEffectsSlidersGoBothWays() {
        // Left of centre has a real meaning for each of these: soften, denoise,
        // flatten local contrast, brighten the corners, smooth texture/clarity.
        for kind in [
            PhotoAdjustmentKind.sharpness, .noiseReduction, .definition, .vignette,
            .texture, .clarity, .dehaze,
        ] {
            #expect(EditorAdjustmentCatalog.isBipolar(kind))
            #expect(EditorAdjustmentCatalog.sliderRange(of: kind) == -1...1)
        }
    }

    /// Effects opens with the three local-contrast sliders, then the vignette
    /// family, then grain. Asserted as order-and-membership rather than an
    /// exact list: the vignette family has grown twice (roundness, highlights)
    /// and freezing the list only records what it looked like on one day.
    @Test func effectsGroupCarriesTheExpandedSet() {
        let effects = try? #require(
            EditorAdjustmentCatalog
                .groups(isRAWSource: false, scope: .global)
                .first { $0.id == .effects }
        )
        let kinds = effects?.kinds ?? []
        #expect(kinds.prefix(3) == [.texture, .clarity, .dehaze])
        for kind in [
            PhotoAdjustmentKind.vignette, .vignetteMidpoint, .vignetteFeather,
            .vignetteRoundness, .vignetteHighlights,
            .grain, .grainSize, .grainRoughness,
        ] {
            #expect(kinds.contains(kind), "Effects lost \(kind)")
        }
        // Grain closes the group: it is the last thing applied to the picture.
        #expect(kinds.suffix(3) == [.grain, .grainSize, .grainRoughness])
    }

    @Test func detailGroupCarriesTheFourSharpenControls() {
        let detail = EditorAdjustmentCatalog
            .groups(isRAWSource: false, scope: .global)
            .first { $0.id == .detail }
        #expect(detail?.kinds == [
            .sharpness, .sharpenRadius, .sharpenDetail, .sharpenMasking,
            .definition, .noiseReduction, .colorNoiseReduction,
        ])
        // Detail and Masking are one-way strengths, like Radius.
        #expect(EditorAdjustmentCatalog.shortTitle(of: .sharpenDetail) == "Detail")
        #expect(EditorAdjustmentCatalog.shortTitle(of: .sharpenMasking) == "Masking")
    }

    @Test func opticsAndGeoAreGlobalOnlyGroups() {
        let global = EditorAdjustmentCatalog.groups(isRAWSource: false, scope: .global)
        #expect(global.map(\.id).contains(.optics))
        #expect(global.map(\.id).contains(.geo))
        let optics = global.first { $0.id == .optics }
        #expect(optics?.kinds == [.chromaticAberration, .defringe])
        let geo = global.first { $0.id == .geo }
        #expect(geo?.kinds == [
            .geoVertical, .geoHorizontal, .geoRotate, .geoScale, .geoOffsetX, .geoOffsetY,
        ])
        // Never inside a mask.
        let mask = EditorAdjustmentCatalog.groups(isRAWSource: true, scope: .mask)
        #expect(!mask.map(\.id).contains(.optics))
        #expect(!mask.map(\.id).contains(.geo))
        // Chromatic aberration reads as a toggle; the geo transforms are bipolar.
        #expect(EditorAdjustmentCatalog.format(of: .chromaticAberration) == .toggle)
        #expect(EditorAdjustmentCatalog.isBipolar(.geoRotate))
        #expect(EditorAdjustmentCatalog.isBipolar(.vignetteRoundness))
    }

    @Test func blackAndWhiteIsAToggleInTheColorGroup() {
        #expect(EditorAdjustmentCatalog.format(of: .blackAndWhite) == .toggle)
        #expect(EditorAdjustmentCatalog.displayText(1, of: .blackAndWhite) == "On")
        #expect(EditorAdjustmentCatalog.displayText(0, of: .blackAndWhite) == "Off")
        let color = EditorAdjustmentCatalog
            .groups(isRAWSource: false, scope: .global)
            .first { $0.id == .color }
        #expect(color?.kinds.contains(.blackAndWhite) == true)
    }

    @Test func vignetteMidpointAndFeatherDefaultToNeutralWithoutBreakingIdentity() {
        // Their 0.5 defaults are part of `.zero`, so an untouched recipe is still
        // identity and encodes no key for them.
        #expect(PhotoAdjustments().vignetteMidpoint == 0.5)
        #expect(PhotoAdjustments().vignetteFeather == 0.5)
        #expect(PhotoAdjustments.zero.isIdentity)
    }

    @Test func valuesReadInPhotographicUnits() {
        #expect(EditorAdjustmentCatalog.displayText(0, of: .exposure) == "0")
        #expect(EditorAdjustmentCatalog.displayText(0.28, of: .exposure) == "+0.28")
        #expect(EditorAdjustmentCatalog.displayText(-0.35, of: .contrast) == "\u{2212}0.35")
        #expect(EditorAdjustmentCatalog.displayText(-0.32, of: .highlights) == "\u{2212}32")
        #expect(EditorAdjustmentCatalog.displayText(0.12, of: .shadows) == "+12")
        #expect(EditorAdjustmentCatalog.displayText(0.06, of: .warmth) == "+180")
        #expect(EditorAdjustmentCatalog.displayText(1, of: .lensCorrection) == "On")
    }

    @Test func numericEntryRoundTripsAndClamps() {
        #expect(
            EditorAdjustmentCatalog.value(fromDisplayText: "+12", of: .shadows)
                == 0.12
        )
        #expect(
            EditorAdjustmentCatalog.value(fromDisplayText: "\u{2212}32", of: .highlights)
                == -0.32
        )
        #expect(
            EditorAdjustmentCatalog.value(fromDisplayText: "180", of: .warmth) == 0.06
        )
        // Out of range entries are clamped, not rejected.
        #expect(EditorAdjustmentCatalog.value(fromDisplayText: "900", of: .shadows) == 1)
        #expect(EditorAdjustmentCatalog.value(fromDisplayText: "-4", of: .exposure) == -2)
        #expect(EditorAdjustmentCatalog.value(fromDisplayText: "abc", of: .exposure) == nil)
    }

    @Test func editableTextDropsTheTypographicSigns() {
        #expect(EditorAdjustmentCatalog.editableText(0.28, of: .exposure) == "0.28")
        #expect(EditorAdjustmentCatalog.editableText(-0.32, of: .highlights) == "-32")
    }
}
