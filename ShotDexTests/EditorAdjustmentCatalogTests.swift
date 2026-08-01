import Testing
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
        #expect(groups.map(\.id) == [.light, .color, .detail, .effects])
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

    @Test func everyGroupedKindAppearsExactlyOnce() {
        let kinds = EditorAdjustmentCatalog
            .groups(isRAWSource: true, scope: .global)
            .flatMap(\.kinds)
        #expect(Set(kinds).count == kinds.count)
        #expect(Set(kinds) == Set(PhotoAdjustmentKind.allCases))
    }

    @Test func unipolarSlidersStartAtZero() {
        // Grain and the RAW strengths are the only one-way sliders.
        #expect(EditorAdjustmentCatalog.sliderRange(of: .grain) == 0...1)
        #expect(EditorAdjustmentCatalog.isBipolar(.grain) == false)
        #expect(EditorAdjustmentCatalog.sliderRange(of: .rawLuminanceNoise) == 0...1)
        #expect(EditorAdjustmentCatalog.sliderRange(of: .exposure) == -2...2)
        #expect(EditorAdjustmentCatalog.isBipolar(.whites))
    }

    @Test func detailAndEffectsSlidersGoBothWays() {
        // Left of centre has a real meaning for each of these: soften, denoise,
        // flatten local contrast, brighten the corners.
        for kind in [
            PhotoAdjustmentKind.sharpness, .noiseReduction, .definition, .vignette,
        ] {
            #expect(EditorAdjustmentCatalog.isBipolar(kind))
            #expect(EditorAdjustmentCatalog.sliderRange(of: kind) == -1...1)
        }
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
