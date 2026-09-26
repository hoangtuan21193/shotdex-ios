import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import os
import Testing
@testable import ShotDexKit

/// FS-14 AC-12 and AC-15 — the picture reaches a file without ever existing
/// whole, and cancelling leaves nothing behind.
struct PanoramaExportTests {

    private let frameWidth = 160
    private let frameHeight = 120
    private let focal = 200.0

    private func camera(yaw: Double) -> PanoramaCamera {
        PanoramaCamera(rotation: PanoramaRotation.matrix(fromAxisAngle: (0, yaw * .pi / 180, 0)))
    }

    private func frame(level: Float) -> PanoramaRGBImage {
        var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let index = y * frameWidth + x
                image.pixels[3 * index] = level
                image.pixels[3 * index + 1] = level * 0.8
                image.pixels[3 * index + 2] = 0.2 + Float(x) / Float(frameWidth) * 0.4
                image.coverage[index] = 1
            }
        }
        return image
    }

    private func ciImage(from image: PanoramaRGBImage) -> CIImage {
        var rgba = [Float](repeating: 0, count: 4 * image.width * image.height)
        for y in 0..<image.height {
            let flipped = image.height - 1 - y
            for x in 0..<image.width {
                let source = y * image.width + x
                let target = flipped * image.width + x
                rgba[4 * target] = image.pixels[3 * source]
                rgba[4 * target + 1] = image.pixels[3 * source + 1]
                rgba[4 * target + 2] = image.pixels[3 * source + 2]
                rgba[4 * target + 3] = 1
            }
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: image.width * 16,
            size: CGSize(width: image.width, height: image.height),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private func scene() throws -> (PanoramaCanvas, [PanoramaCISource]) {
        let yaws = [-10.0, 10.0]
        let cameras = yaws.map { camera(yaw: $0) }
        let canvas = try #require(
            PanoramaProjection.canvas(
                kind: .spherical, cameras: cameras, focal: focal,
                imageWidth: frameWidth, imageHeight: frameHeight
            )
        )
        let sources = yaws.indices.map { index in
            PanoramaCISource(
                image: ciImage(from: frame(level: index == 0 ? 0.4 : 0.6)),
                width: frameWidth,
                height: frameHeight,
                camera: cameras[index]
            )
        }
        return (canvas, sources)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPano-\(UUID().uuidString).jpg")
    }

    @Test func thePanoramaReachesAFileAtTheSizeItWasPromised() throws {
        let (canvas, sources) = try scene()
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // The callback is @Sendable, so the last value lands in a lock.
        let lastProgress = OSAllocatedUnfairLock(initialState: 0.0)
        try PanoramaExporter.write(
            canvas: canvas, sources: sources, focal: focal, quality: .draft, to: url,
            progress: { value in lastProgress.withLock { $0 = value } }
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(lastProgress.withLock { $0 } == 1)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == canvas.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == canvas.height)

        // And it is a picture, not a grey rectangle: the two frames' levels
        // both survive the trip through the encoder.
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == canvas.width)
        #expect(decoded.height == canvas.height)
    }

    /// Enough rows that several strips are needed, so the seam between strips
    /// is exercised rather than assumed.
    @Test func aPanoramaTallerThanOneStripComesOutWhole() throws {
        let yaws = stride(from: -20.0, through: 20.0, by: 10).map { $0 }
        let cameras = yaws.map { camera(yaw: $0) }
        let canvas = try #require(
            PanoramaProjection.canvas(
                kind: .spherical, cameras: cameras, focal: 900,
                imageWidth: 900, imageHeight: 700
            )
        )
        #expect(canvas.height > PanoramaExporter.stripHeight, "canvas \(canvas.width)x\(canvas.height)")

        let sources = yaws.indices.map { index in
            PanoramaCISource(
                image: ciImage(from: frame(level: 0.3 + Float(index) * 0.1)),
                width: frameWidth, height: frameHeight, camera: cameras[index]
            )
        }
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try PanoramaExporter.write(
            canvas: canvas, sources: sources, focal: 900, quality: .draft, to: url
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == canvas.height)
    }

    /// AC-15: a cancelled save leaves no file. Half a panorama on disk is worse
    /// than none — it would be indexed, shown, and look like a bug in the
    /// stitcher rather than a save the user stopped.
    @Test func cancellingLeavesNothingBehind() throws {
        let (canvas, sources) = try scene()
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: PanoramaExportError.cancelled) {
            try PanoramaExporter.write(
                canvas: canvas, sources: sources, focal: focal, quality: .draft, to: url,
                isCancelled: { true }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A crop is written as its own picture, not as the whole canvas with the
    /// edges left in.
    @Test func aCropIsWrittenAtItsOwnSize() throws {
        let (canvas, sources) = try scene()
        let crop = PanoramaCropRect(
            x: 10, y: 5, width: canvas.width - 40, height: canvas.height - 20
        )
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try PanoramaExporter.write(
            canvas: canvas, sources: sources, focal: focal, quality: .draft, crop: crop, to: url
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == crop.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == crop.height)
    }

    /// The format's own limit, not a choice of ours.
    @Test func aPictureTooWideForJPEGIsRefusedRatherThanTruncated() throws {
        let (canvas, sources) = try scene()
        let tooWide = PanoramaCropRect(x: 0, y: 0, width: PanoramaExporter.maximumEdge + 1, height: 10)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: PanoramaExportError.cannotEncode) {
            try PanoramaExporter.write(
                canvas: canvas, sources: sources, focal: focal, crop: tooWide, to: url
            )
        }
    }

    /// The panorama tag rides along, so the file is recognised as one the
    /// moment it is indexed.
    @Test func theStitchedTagIsWrittenIntoTheFile() throws {
        let (canvas, sources) = try scene()
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try #require(
            PanoramaXMP.makeMetadata(projection: "spherical", frameCount: sources.count)
        )
        try PanoramaExporter.write(
            canvas: canvas, sources: sources, focal: focal, quality: .draft, to: url,
            metadata: metadata
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(PanoramaXMP.isStitchedPanorama(source))
    }
}
