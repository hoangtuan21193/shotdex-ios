import Testing
@testable import ShotDex

struct LensNormalizerTests {

    @Test func spellingVariantsGroupTogether() {
        let variants = [
            "RF100-500mm F4.5-7.1 L IS USM",
            "Canon RF100-500mm F4.5-7.1 L IS USM",
            "RF 100-500mm F4.5-7.1L IS USM",
        ]
        let normalized = variants.compactMap { LensNormalizer.normalize($0) }
        #expect(normalized.count == 3)
        let keys = Set(normalized.map { LensNormalizer.groupingKey($0) })
        #expect(keys.count == 1)
    }

    @Test func stripsMakerPrefix() {
        #expect(LensNormalizer.normalize("Canon RF 24-70mm F2.8 L IS USM")?.hasPrefix("RF") == true)
        #expect(LensNormalizer.normalize("SIGMA 35mm F1.4 DG HSM") == "35mm F1.4 DG HSM")
    }

    @Test func insertsSpaceBetweenMountCodeAndFocal() {
        #expect(LensNormalizer.normalize("RF100-500mm F4.5-7.1 L IS USM") == "RF 100-500mm F4.5-7.1 L IS USM")
        #expect(LensNormalizer.normalize("XF23mmF1.4 R") == "XF 23mm F1.4 R")
    }

    @Test func nilAndEmptyHandled() {
        #expect(LensNormalizer.normalize(nil) == nil)
        #expect(LensNormalizer.normalize("   ") == nil)
    }

    @Test func detectsZoomVsPrime() {
        #expect(LensNormalizer.isZoom("RF 100-500mm F4.5-7.1 L IS USM"))
        #expect(LensNormalizer.isZoom("FE 24-70mm F2.8 GM"))
        #expect(!LensNormalizer.isZoom("RF 85mm F1.2 L USM"))
        #expect(!LensNormalizer.isZoom(nil))
    }
}
