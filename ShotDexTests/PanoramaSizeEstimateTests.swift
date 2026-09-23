import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-25 and AC-26 — the line under the Size slider says what will be
/// saved, and says it before Save is pressed rather than after.
struct PanoramaSizeEstimateTests {

    private func estimate(
        full: (width: Int, height: Int),
        canvas: (width: Int, height: Int)? = nil,
        scale: Double,
        bytesPerPixel: Double = 0.25,
        secondsPerMegapixel: Double = 0.5
    ) -> PanoramaSizeEstimate? {
        PanoramaSizeEstimator.estimate(
            fullWidth: full.width,
            fullHeight: full.height,
            canvasWidth: (canvas ?? full).width,
            canvasHeight: (canvas ?? full).height,
            sizeScale: scale,
            bytesPerPixel: bytesPerPixel,
            secondsPerMegapixel: secondsPerMegapixel
        )
    }

    // MARK: AC-25 — half the size is half of each side

    @Test func halvingSizeHalvesEachSide() throws {
        let full = try #require(estimate(full: (24_000, 6_000), scale: 1))
        #expect(full.width == 24_000)
        #expect(full.height == 6_000)
        #expect(!full.isClamped)

        let half = try #require(estimate(full: (24_000, 6_000), scale: 0.5))
        #expect(abs(half.width - 12_000) <= 1)
        #expect(abs(half.height - 3_000) <= 1)
    }

    /// AC-25's second half: a quarter of the pixels is a quarter of the
    /// megapixels, and the file estimate follows the pixels rather than the
    /// slider.
    @Test func halvingSizeQuartersMegapixelsAndFile() throws {
        let full = try #require(estimate(full: (24_000, 6_000), scale: 1))
        let half = try #require(estimate(full: (24_000, 6_000), scale: 0.5))
        #expect(abs(half.megapixels - full.megapixels / 4) < 0.05)
        #expect(abs(Double(half.bytes) - Double(full.bytes) / 4) < Double(full.bytes) * 0.001)
        #expect(abs(half.seconds - full.seconds / 4) < full.seconds * 0.001)
    }

    /// Odd numbers round rather than truncate — a 5-point step of the slider
    /// must not quietly lose a pixel column each time.
    @Test func roundsRatherThanTruncates() throws {
        let estimate = try #require(estimate(full: (2_001, 999), scale: 0.5))
        #expect(estimate.width == 1_001)
        #expect(estimate.height == 500)
    }

    // MARK: The JPEG edge limit

    @Test func widePanoramaComesDownToWhatAJPEGCanHold() throws {
        // 90,000 px across at full size: past the format's own field width.
        let estimate = try #require(estimate(full: (90_000, 9_000), scale: 1))
        #expect(estimate.isClamped)
        #expect(estimate.width == PanoramaExporter.maximumEdge)
        #expect(estimate.requestedWidth == 90_000)
        // The aspect ratio is kept: 90,000 × 9,000 is 10:1 either way.
        #expect(abs(Double(estimate.width) / Double(estimate.height) - 10) < 0.01)
    }

    /// Shrinking Size below the limit takes the clamp away — the line goes back
    /// to plain pixels, so "Will save at…" only appears when it is true.
    @Test func clampLiftsWhenSizeComesDown() throws {
        let clamped = try #require(estimate(full: (90_000, 9_000), scale: 1))
        #expect(clamped.isClamped)
        let free = try #require(estimate(full: (90_000, 9_000), scale: 0.5))
        #expect(!free.isClamped)
        #expect(free.width == 45_000)
    }

    /// The limit applies to what the renderer draws, not to what is left after
    /// Auto Crop — the exporter refuses on the canvas.
    @Test func limitAppliesToTheUncroppedCanvas() throws {
        let estimate = try #require(
            estimate(full: (64_000, 8_000), canvas: (80_000, 10_000), scale: 1)
        )
        #expect(estimate.isClamped)
        // The canvas comes down by 65,535 / 80,000; the cropped picture rides
        // down with it rather than staying at its own 64,000.
        let factor = Double(PanoramaExporter.maximumEdge) / 80_000
        #expect(abs(estimate.width - Int((64_000 * factor).rounded())) <= 1)
    }

    @Test func writableScaleLeavesASmallPanoramaAlone() {
        let scale = PanoramaSizeEstimator.writableScale(
            fullWidth: 12_000, fullHeight: 4_000, sizeScale: 0.75
        )
        #expect(abs(scale - 0.75) < 1e-12)
    }

    // MARK: AC-26 — free space

    @Test func requiredSpaceCoversTheScratchFileAsWellAsThePhoto() throws {
        let estimate = try #require(estimate(full: (20_000, 5_000), scale: 1))
        #expect(
            PanoramaSizeEstimator.requiredFreeBytes(for: estimate) == Int64(estimate.bytes) * 2
        )
    }

    // MARK: Refusals

    @Test func refusesAGeometryItCannotMeasure() {
        #expect(estimate(full: (0, 0), scale: 1) == nil)
        #expect(estimate(full: (1_000, 500), scale: 0) == nil)
    }
}
