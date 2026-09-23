import Foundation
import ImageIO
import Testing
@testable import ShotDexKit

/// FS-14 AC-13 — what the stitched picture says it was shot with.
struct PanoramaMetadataTests {

    private func frame(
        camera: String = "EOS R6",
        lens: String = "RF 24-105mm F4 L IS USM",
        iso: Int,
        shutter: Double,
        aperture: Double
    ) -> [CFString: Any] {
        [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: camera,
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: lens,
                kCGImagePropertyExifFocalLength: 24,
                kCGImagePropertyExifISOSpeedRatings: [iso],
                kCGImagePropertyExifExposureTime: shutter,
                kCGImagePropertyExifFNumber: aperture,
            ] as [CFString: Any],
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyPixelWidth: 6_000,
            kCGImagePropertyPixelHeight: 4_000,
        ]
    }

    /// Identity always comes from the first frame: the photographer filters and
    /// charts on camera and lens, and a panorama that lost them would drop out
    /// of their library's statistics.
    @Test func cameraAndLensComeFromTheFirstFrame() throws {
        let frames = [
            frame(iso: 100, shutter: 1.0 / 250, aperture: 8),
            frame(iso: 100, shutter: 1.0 / 250, aperture: 8),
        ]
        let merged = PanoramaMetadataRule.merge(frames: frames, pixelWidth: 24_000, pixelHeight: 5_000)
        let tiff = try #require(merged[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "EOS R6")
        let exif = try #require(merged[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifLensModel] as? String == "RF 24-105mm F4 L IS USM")
    }

    /// Exposure survives only when every frame agrees. One shutter speed for a
    /// sweep that crossed a bright sky and a dark street would be a claim the
    /// library then filters and charts on.
    @Test func exposureIsKeptOnlyWhenEveryFrameAgrees() throws {
        let same = [
            frame(iso: 200, shutter: 1.0 / 500, aperture: 5.6),
            frame(iso: 200, shutter: 1.0 / 500, aperture: 5.6),
            frame(iso: 200, shutter: 1.0 / 500, aperture: 5.6),
        ]
        let agreed = try #require(
            PanoramaMetadataRule.merge(frames: same, pixelWidth: 100, pixelHeight: 50)[
                kCGImagePropertyExifDictionary
            ] as? [CFString: Any]
        )
        #expect(agreed[kCGImagePropertyExifExposureTime] != nil)
        #expect(agreed[kCGImagePropertyExifISOSpeedRatings] != nil)

        let drifting = [
            frame(iso: 200, shutter: 1.0 / 500, aperture: 5.6),
            frame(iso: 400, shutter: 1.0 / 250, aperture: 5.6),
        ]
        let dropped = try #require(
            PanoramaMetadataRule.merge(frames: drifting, pixelWidth: 100, pixelHeight: 50)[
                kCGImagePropertyExifDictionary
            ] as? [CFString: Any]
        )
        #expect(dropped[kCGImagePropertyExifExposureTime] == nil, "shutter differed, so it must go")
        #expect(dropped[kCGImagePropertyExifISOSpeedRatings] == nil, "ISO differed, so it must go")
        // The aperture was the same in every frame, so it stays.
        #expect(dropped[kCGImagePropertyExifFNumber] != nil)
        // And the lens is not an exposure — it survives regardless.
        #expect(dropped[kCGImagePropertyExifLensModel] as? String == "RF 24-105mm F4 L IS USM")
    }

    /// The size is the panorama's, and it is already the right way up — the
    /// first frame's rotation would turn a picture that needs no turning.
    @Test func theSizeAndOrientationAreThePanoramasOwn() {
        let merged = PanoramaMetadataRule.merge(
            frames: [frame(iso: 100, shutter: 1.0 / 60, aperture: 4)],
            pixelWidth: 24_847,
            pixelHeight: 6_120
        )
        #expect(merged[kCGImagePropertyPixelWidth] as? Int == 24_847)
        #expect(merged[kCGImagePropertyPixelHeight] as? Int == 6_120)
        #expect(merged[kCGImagePropertyOrientation] as? Int == 1)
    }

    @Test func noFramesMeansNoProperties() {
        #expect(PanoramaMetadataRule.merge(frames: [], pixelWidth: 10, pixelHeight: 10).isEmpty)
    }
}
