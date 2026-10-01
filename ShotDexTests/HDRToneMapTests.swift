import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.11 §5 — AC-1 (tone map), AC-2 (nothing clipped), AC-13 (preview
/// against the save): the radiance made displayable.
@Suite struct HDRToneMapTests {
    static func radiance(_ fixture: HDRBracketFixture, _ series: HDRBracketFixture.Series,
                         frames: [CIImage]? = nil, pixelScale: Double = 1) throws -> CIImage {
        let input = HDRSeries(frames: frames ?? series.frames.map(fixture.image), stops: series.stops,
                              reference: series.reference, noise: fixture.noise, pixelScale: pixelScale)
        return try #require(HDRMerge.radiance(input, deghost: .medium))
    }

    /// AC-1: the merged series, tone mapped, against the clean scene put
    /// through the same tone map.
    @Test func theMergedSeriesToneMapsLikeTheCleanScene() throws {
        let fixture = HDRBracketFixture()
        let series = fixture.series(stops: [-4, -2, 0, 2, 4])
        let strength = HDROptions.standard.strength
        let merged = try #require(HDRMerge.toneMapped(try Self.radiance(fixture, series), stops: series.stops, strength: strength))
        let clean = try #require(HDRMerge.toneMapped(fixture.image(series.scene), stops: series.stops, strength: strength))
        let psnr = HDRBracketFixture.psnr(fixture.displayPixels(merged), fixture.displayPixels(clean))
        print(String(format: "HDR AC-1 tone mapped %.1f dB", psnr))
        #expect(psnr >= 48)
    }

    /// AC-2, the tone-map half: three frames ±2 of a 10-stop scene whose
    /// radiance holds every highlight (`HDRMergeTests`) — after the tone map
    /// nothing is at white, at any Strength.
    @Test func nothingIsLeftClippedAtAnyStrength() throws {
        let fixture = HDRBracketFixture(dynamicRange: 10, highlightStops: 1.5)
        let series = fixture.series(stops: [-2, 0, 2])
        let radiance = try Self.radiance(fixture, series)
        for strength in [0, HDROptions.standard.strength, 1] {
            let out = fixture.displayPixels(try #require(HDRMerge.toneMapped(radiance, stops: series.stops, strength: strength)))
            let clipped = (0..<(fixture.width * fixture.height)).filter { max(out[$0 * 3], out[$0 * 3 + 1], out[$0 * 3 + 2]) >= 0.999 }
            print(String(format: "HDR AC-2 strength %.1f: %d px at white", strength, clipped.count))
            #expect(clipped.isEmpty)
        }
    }

    /// Where the darkest frame clipped too, the picture is white — not the
    /// grey the extra-dark virtual exposure would make of it.
    @Test func whatEveryFrameClippedStaysWhite() throws {
        let fixture = HDRBracketFixture(dynamicRange: 10, highlightStops: 3)
        let series = fixture.series(stops: [-1, 0, 1])
        let radiance = try Self.radiance(fixture, series)
        let out = fixture.displayPixels(try #require(HDRMerge.toneMapped(radiance, stops: series.stops, strength: 0.6)))
        let darkest = series.frames[0]
        let blown = (0..<(fixture.width * fixture.height)).filter { i in
            min(darkest[i * 3], darkest[i * 3 + 1], darkest[i * 3 + 2]) >= 0.999
        }
        #expect(!blown.isEmpty)
        #expect(blown.allSatisfy { min(out[$0 * 3], out[$0 * 3 + 1], out[$0 * 3 + 2]) >= 0.99 })
    }

    /// Strength 0 is the reference with its highlights brought back: shadows
    /// and mid-tones stay within half a stop of where the reference put them
    /// (median; the extra-dark exposure darkens them ~⅓ stop), and higher
    /// Strength lifts the shadows.
    @Test func strengthZeroStaysNearTheReference() throws {
        let fixture = HDRBracketFixture(dynamicRange: 10, highlightStops: 1.5)
        let scene = fixture.scene()
        func medianShift(strength: Double, in range: ClosedRange<Double>) throws -> Double {
            let out = fixture.pixels(try #require(HDRMerge.toneMapped(fixture.image(scene), stops: [-2, 0, 2], strength: strength)))
            let shifts = (0..<(fixture.width * fixture.height))
                .filter { range.contains(HDRBracketFixture.luma(scene, $0)) && HDRBracketFixture.luma(out, $0) > 1e-4 }
                .map { log2(HDRBracketFixture.luma(out, $0) / HDRBracketFixture.luma(scene, $0)) }
                .sorted()
            return shifts[shifts.count / 2]
        }
        let shadows = try medianShift(strength: 0, in: 0.005...0.05), mids = try medianShift(strength: 0, in: 0.05...0.5)
        let lifted = try medianShift(strength: 1, in: 0.005...0.05)
        print(String(format: "HDR strength 0: shadows %+.2f, mid-tones %+.2f stop; strength 1 shadows %+.2f", shadows, mids, lifted))
        #expect(abs(shadows) <= 0.5)
        #expect(abs(mids) <= 0.5)
        #expect(lifted > shadows + 0.5)
    }

    /// AC-13: the preview — frames read small, merged, tone mapped — against
    /// the full-size save shrunk to the preview's size, for an AEB ±2 of a
    /// 10-stop scene. (The 14-stop fixture measures 30.0 dB, but clamping
    /// alone, no tone map, already measures 30.7 there: shrinking and
    /// clipping its hard 14-stop edges do not commute.)
    @Test func thePreviewMatchesTheSave() throws {
        let fixture = HDRBracketFixture(width: 960, height: 720, dynamicRange: 10, highlightStops: 1.5)
        let series = fixture.series(stops: [-2, 0, 2])
        let factor = 3.75   // 6000 px saved, 1600 previewed
        var small = fixture
        small.width = Int(Double(fixture.width) / factor)
        small.height = Int(Double(fixture.height) / factor)
        let previewRect = CGRect(x: 0, y: 0, width: small.width, height: small.height)
        func shrink(_ image: CIImage) -> CIImage {
            image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1 / factor, kCIInputAspectRatioKey: 1])
                .cropped(to: previewRect)
        }
        let strength = HDROptions.standard.strength
        let saved = try #require(HDRMerge.toneMapped(try Self.radiance(fixture, series), stops: series.stops, strength: strength))
        let preview = try #require(HDRMerge.toneMapped(
            try Self.radiance(small, series, frames: series.frames.map { shrink(fixture.image($0)) }, pixelScale: 1 / factor),
            stops: series.stops, strength: strength))
        let psnr = HDRBracketFixture.psnr(small.displayPixels(preview), small.displayPixels(shrink(saved)))
        print(String(format: "HDR AC-13 preview against save %.1f dB", psnr))
        #expect(psnr >= 32)
    }
}
