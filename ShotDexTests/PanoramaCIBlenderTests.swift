import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 — the blend that actually runs, checked against the one that proves
/// the arithmetic.
///
/// `PanoramaCompositor` is the reference: slow, plain Swift, and already tested
/// on its own terms. This suite's job is to show the Core Image path agrees
/// with it, because from here on the GPU one is what a photographer sees.
struct PanoramaCIBlenderTests {

    private let frameWidth = 96
    private let frameHeight = 72
    private let focal = 120.0

    /// Raw values in, raw values out: no colour management, no gamma, or the
    /// two paths would be compared through a transform only one of them had.
    private var context: CIContext {
        CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAf,
            .useSoftwareRenderer: false,
        ])
    }

    private func camera(yaw: Double) -> PanoramaCamera {
        PanoramaCamera(rotation: PanoramaRotation.matrix(fromAxisAngle: (0, yaw * .pi / 180, 0)))
    }

    /// A frame that varies smoothly. Two resamplers always disagree a little
    /// on a hard edge, so anything checking *where* a pixel came from — the
    /// warp, the weights — uses this, where a small positional error shows as
    /// a small colour error instead of a whole texture cell.
    private func smoothFrame(seed: Int) -> PanoramaRGBImage {
        var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let index = y * frameWidth + x
                let u = Float(x) / Float(frameWidth - 1)
                let v = Float(y) / Float(frameHeight - 1)
                image.pixels[3 * index] = 0.2 + 0.5 * u + 0.1 * Float(seed)
                image.pixels[3 * index + 1] = 0.2 + 0.5 * v
                image.pixels[3 * index + 2] = 0.3 + 0.3 * u * v
                image.coverage[index] = 1
            }
        }
        return image
    }

    /// A frame with structure at several scales, so a disagreement between the
    /// two paths has something to show up in.
    private func frame(seed: Int) -> PanoramaRGBImage {
        var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let index = y * frameWidth + x
                let coarse = Float((x / 16 + y / 16 + seed) % 3) * 0.12
                let fine = Float((x / 3 + y / 2) % 2) * 0.05
                image.pixels[3 * index] = 0.25 + coarse + fine
                image.pixels[3 * index + 1] = 0.30 + coarse
                image.pixels[3 * index + 2] = 0.35 + fine
                image.coverage[index] = 1
            }
        }
        return image
    }

    /// The same pixels as a `CIImage`, in Core Image's y-up space.
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

    /// Renders a Core Image result back into the reference's own layout.
    private func readBack(_ image: CIImage, width: Int, height: Int) -> PanoramaRGBImage {
        var rgba = [Float](repeating: 0, count: 4 * width * height)
        rgba.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 16,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBAf,
                colorSpace: nil
            )
        }
        var output = PanoramaRGBImage(width: width, height: height)
        for y in 0..<height {
            let flipped = height - 1 - y
            for x in 0..<width {
                let source = flipped * width + x
                let target = y * width + x
                output.pixels[3 * target] = rgba[4 * source]
                output.pixels[3 * target + 1] = rgba[4 * source + 1]
                output.pixels[3 * target + 2] = rgba[4 * source + 2]
                output.coverage[target] = rgba[4 * source + 3]
            }
        }
        return output
    }

    private func scene(
        yaws: [Double],
        gains: [Double]? = nil,
        smooth: Bool = true
    ) -> (PanoramaCanvas, [PanoramaRGBImage], [PanoramaCISource], [Int: PanoramaCamera])? {
        let cameras = yaws.map { camera(yaw: $0) }
        guard let canvas = PanoramaProjection.canvas(
            kind: .spherical, cameras: cameras, focal: focal,
            imageWidth: frameWidth, imageHeight: frameHeight
        ) else { return nil }
        let frames = yaws.indices.map { smooth ? smoothFrame(seed: $0) : frame(seed: $0) }
        let sources = yaws.indices.map { index in
            PanoramaCISource(
                image: ciImage(from: frames[index]),
                width: frameWidth,
                height: frameHeight,
                camera: cameras[index],
                gain: gains?[index] ?? 1
            )
        }
        let placed = Dictionary(uniqueKeysWithValues: cameras.enumerated().map { ($0.offset, $0.element) })
        return (canvas, frames, sources, placed)
    }

    /// Pixels both paths cover, with `margin` pixels of every edge removed, so
    /// a comparison is about the picture rather than about two samplers'
    /// opinions of a boundary.
    private func erodedCoverage(
        _ a: PanoramaRGBImage,
        _ b: PanoramaRGBImage,
        canvas: PanoramaCanvas,
        by margin: Int
    ) -> [Bool] {
        var covered = (0..<(canvas.width * canvas.height)).map {
            a.coverage[$0] > 0 && b.coverage[$0] > 0
        }
        for _ in 0..<margin {
            var next = covered
            for y in 0..<canvas.height {
                for x in 0..<canvas.width {
                    let index = y * canvas.width + x
                    guard covered[index] else { continue }
                    if x == 0 || y == 0 || x == canvas.width - 1 || y == canvas.height - 1 {
                        next[index] = false
                        continue
                    }
                    for dy in -1...1 {
                        for dx in -1...1 where !covered[(y + dy) * canvas.width + (x + dx)] {
                            next[index] = false
                        }
                    }
                }
            }
            covered = next
        }
        return covered
    }

    // MARK: The agreement

    /// Differences between the two paths, over the part of the picture that is
    /// not a boundary: mean, and the 99th percentile so a handful of pixels
    /// where a frame's own edge ramp is near zero cannot decide the verdict.
    private func differences(
        yaws: [Double],
        smooth: Bool
    ) throws -> (mean: Float, percentile99: Float, compared: Int) {
        let (canvas, frames, sources, placed) = try #require(scene(yaws: yaws, smooth: smooth))
        let reference = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: frames, cameras: placed, focal: focal, quality: .draft
            )
        )
        let gpu = readBack(
            try #require(PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)),
            width: canvas.width,
            height: canvas.height
        )
        let inside = erodedCoverage(reference, gpu, canvas: canvas, by: 2)
        var collected: [Float] = []
        for index in 0..<(canvas.width * canvas.height) {
            guard inside[index] else { continue }
            for channel in 0..<3 {
                collected.append(
                    abs(reference.pixels[3 * index + channel] - gpu.pixels[3 * index + channel])
                )
            }
        }
        collected.sort()
        let mean = collected.reduce(0, +) / Float(max(collected.count, 1))
        let percentile = collected.isEmpty ? 0 : collected[Int(Double(collected.count) * 0.99)]
        return (mean, percentile, collected.count)
    }

    /// The warp and the weighting: where does each pixel come from, and how
    /// much say does each frame get. Checked on smooth frames so the answer is
    /// about geometry rather than about two resamplers meeting a hard edge.
    @Test func theGPUBlendAgreesWithTheReference() throws {
        let result = try differences(yaws: [-9, 0, 9], smooth: true)
        #expect(result.compared > 1_000, "compared \(result.compared)")
        #expect(result.mean < 0.004, "mean difference \(result.mean)")
        #expect(result.percentile99 < 0.02, "99th percentile \(result.percentile99)")
    }

    /// The same scene with detail down to two pixels. The two paths resample
    /// differently, and on a checkerboard at the sampling limit that shows —
    /// a real photograph has no such thing, but the bound is worth recording
    /// so a future change that makes it much worse is visible.
    @Test func detailedFramesStillAgreeBroadly() throws {
        let result = try differences(yaws: [-9, 0, 9], smooth: false)
        #expect(result.mean < 0.03, "mean difference \(result.mean)")
    }

    @Test func bothPathsCoverTheSamePicture() throws {
        let (canvas, frames, sources, placed) = try #require(scene(yaws: [-8, 8]))
        let reference = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: frames, cameras: placed, focal: focal, quality: .draft
            )
        )
        let gpu = readBack(
            try #require(PanoramaCIBlender.draft(canvas: canvas, sources: sources, focal: focal)),
            width: canvas.width,
            height: canvas.height
        )
        var disagreements = 0
        for index in 0..<(canvas.width * canvas.height) {
            let a = reference.coverage[index] > 0.5
            let b = gpu.coverage[index] > 0.5
            if a != b { disagreements += 1 }
        }
        // A thin rim can differ, where one path's sampler reaches a border
        // pixel the other declines. It must be a rim, not a region.
        let fraction = Double(disagreements) / Double(canvas.width * canvas.height)
        // A rim, not a region: three frames on a canvas this size have a few
        // hundred border pixels between them, and that is what this allows.
        #expect(fraction < 0.04, "coverage disagreed on \(fraction * 100)% of the canvas")
    }

    @Test func gainsAreAppliedOnTheGPUToo() throws {
        let plainScene = try #require(scene(yaws: [0]))
        let doubledScene = try #require(scene(yaws: [0], gains: [2]))
        let plain = readBack(
            try #require(
                PanoramaCIBlender.draft(canvas: plainScene.0, sources: plainScene.2, focal: focal)
            ),
            width: plainScene.0.width, height: plainScene.0.height
        )
        let doubled = readBack(
            try #require(
                PanoramaCIBlender.draft(canvas: doubledScene.0, sources: doubledScene.2, focal: focal)
            ),
            width: doubledScene.0.width, height: doubledScene.0.height
        )
        let index = (plainScene.0.height / 2) * plainScene.0.width + plainScene.0.width / 2
        #expect(plain.coverage[index] > 0)
        #expect(abs(doubled.pixels[3 * index] - 2 * plain.pixels[3 * index]) < 0.01)
    }

    /// The region callback is what lets a strip of output be drawn without the
    /// whole frame resident. If it ever returns the whole frame the strip
    /// renderer quietly loses its memory guarantee, so it is checked directly.
    @Test func aSlabOfCanvasOnlyNeedsPartOfAFrame() throws {
        let (canvas, _, sources, _) = try #require(scene(yaws: [-9, 0, 9]))
        let slab = CGRect(x: 0, y: 0, width: 24, height: 16)
        let region = PanoramaCIBlender.sourceRegion(
            for: slab, canvas: canvas, source: sources[0], focal: focal
        )
        let whole = Double(frameWidth * frameHeight)
        #expect(Double(region.width * region.height) < whole * 0.6, "asked for \(region)")
        #expect(region.width > 0 && region.height > 0)
    }
}
