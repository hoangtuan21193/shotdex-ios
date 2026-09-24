import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-23, through the blend that ships — a person standing in the
/// overlap of one frame and gone from the other comes out whole or absent,
/// never halved.
///
/// `PanoramaSeamTests` checks the join's arithmetic on buffers. This checks
/// that the join reaches the picture: the same two frames blended with and
/// without the seam planner, and what that changes about the figure.
struct PanoramaSeamBlendTests {

    private let frameWidth = 120
    private let frameHeight = 90
    private let focal = 150.0

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

    /// A wall with enough texture to register against, and optionally a dark
    /// figure standing on it.
    private func wall(figure: Bool) -> PanoramaRGBImage {
        var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let shade = 0.55 + 0.1 * Float(sin(Double(x) / 9) * cos(Double(y) / 7))
                let at = 3 * (y * frameWidth + x)
                image.pixels[at] = shade
                image.pixels[at + 1] = shade * 0.95
                image.pixels[at + 2] = shade * 0.9
            }
        }
        guard figure else { return image }
        for y in figureRows {
            for x in figureColumns {
                let at = 3 * (y * frameWidth + x)
                image.pixels[at] = 0.06
                image.pixels[at + 1] = 0.05
                image.pixels[at + 2] = 0.05
            }
        }
        return image
    }

    /// Where the figure stands in the first frame: in the half that overlaps
    /// the other one. Which half that is, is a fact about the projection and
    /// not a guess — `theFigureStandsInTheOverlap` fails loudly if this moves.
    private var figureColumns: Range<Int> { 22..<40 }
    private var figureRows: Range<Int> { 25..<80 }

    private func ciImage(from image: PanoramaRGBImage) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        for y in 0..<image.height {
            let row = (image.height - 1 - y) * image.width
            for x in 0..<image.width {
                let pixel = image.colour(atX: x, y: y)
                let at = 4 * (row + x)
                bytes[at] = UInt8(max(0, min(255, pixel.0 * 255)))
                bytes[at + 1] = UInt8(max(0, min(255, pixel.1 * 255)))
                bytes[at + 2] = UInt8(max(0, min(255, pixel.2 * 255)))
                bytes[at + 3] = 255
            }
        }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: image.width * 4,
            size: CGSize(width: image.width, height: image.height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }

    /// Two frames of the same wall, the left one with a figure on it.
    private func scene() -> (canvas: PanoramaCanvas, sources: [PanoramaCISource])? {
        let cameras = [camera(yaw: -12), camera(yaw: 12)]
        guard let canvas = PanoramaProjection.canvas(
            kind: .spherical, cameras: cameras, focal: focal,
            imageWidth: frameWidth, imageHeight: frameHeight
        ) else { return nil }
        let sources = [
            PanoramaCISource(
                image: ciImage(from: wall(figure: true)),
                width: frameWidth, height: frameHeight, camera: cameras[0], gain: 1
            ),
            PanoramaCISource(
                image: ciImage(from: wall(figure: false)),
                width: frameWidth, height: frameHeight, camera: cameras[1], gain: 1
            ),
        ]
        return (canvas, sources)
    }

    private func read(_ image: CIImage, canvas: PanoramaCanvas) -> [Float] {
        let width = canvas.width, height = canvas.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        var luminance = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = (height - 1 - y) * width
            for x in 0..<width {
                let at = 4 * (row + x)
                luminance[y * width + x] = (
                    0.2126 * Float(bytes[at]) + 0.7152 * Float(bytes[at + 1])
                        + 0.0722 * Float(bytes[at + 2])
                ) / 255
            }
        }
        return luminance
    }

    /// Columns that are dark enough to be the figure, per row — the shape it
    /// left in the panorama.
    ///
    /// Only where the panorama has a picture: the canvas is black outside the
    /// frames' coverage, and black is not a figure.
    private func figureRuns(
        _ luminance: [Float],
        covered: [Bool],
        canvas: PanoramaCanvas
    ) -> [Int] {
        (0..<canvas.height).map { y in
            (0..<canvas.width).count { x in
                let index = y * canvas.width + x
                return covered[index] && luminance[index] < 0.25
            }
        }
    }

    // MARK: AC-23

    /// AC-23 on the canvas: the figure stands inside the overlap, where the
    /// join has to run, and every pixel of it belongs to one frame.
    ///
    /// Ownership rather than pixels, because the multi-band blend feathers
    /// every edge and a cut figure comes out as a smear — "how dark is this
    /// pixel" cannot tell a cut from an absence, and who owns it can.
    @Test func theJoinGoesRoundTheFigureRatherThanThroughIt() throws {
        let scene = try #require(scene())
        let masks = try #require(
            PanoramaSeamPlanner.masks(
                canvas: scene.canvas, sources: scene.sources, focal: focal, context: context
            )
        )
        // Each frame on its own: where it reaches, and what the figure looks
        // like when nothing is competing with it.
        let soloA = try #require(
            PanoramaCIBlender.sharp(canvas: scene.canvas, sources: [scene.sources[0]], focal: focal)
        )
        let soloB = try #require(
            PanoramaCIBlender.sharp(canvas: scene.canvas, sources: [scene.sources[1]], focal: focal)
        )
        let lumA = read(soloA, canvas: scene.canvas)
        let lumB = read(soloB, canvas: scene.canvas)

        let footprint = lumA.indices.filter { lumA[$0] > 0.005 && lumA[$0] < 0.25 }
        try #require(footprint.count > 200, "the fixture has no figure to lose")

        // The figure is in the overlap — the only place a join can cut it.
        let inOverlap = footprint.count { lumB[$0] > 0.02 }
        #expect(
            Double(inOverlap) / Double(footprint.count) > 0.5,
            "only \(inOverlap) of \(footprint.count) figure pixels are in the overlap, so this proves nothing"
        )

        let first = read(masks[0], canvas: scene.canvas)
        let owners = Set(footprint.map { first[$0] > 0.5 })
        #expect(owners.count == 1, "the join runs through the figure")
    }

    /// The planner gives one mask per frame, they cover the panorama, and no
    /// pixel is claimed by two frames — otherwise the blend would double it.
    @Test func everyPixelHasExactlyOneOwner() throws {
        let scene = try #require(scene())
        let masks = try #require(
            PanoramaSeamPlanner.masks(
                canvas: scene.canvas, sources: scene.sources, focal: focal, context: context
            )
        )
        #expect(masks.count == scene.sources.count)

        let first = read(masks[0], canvas: scene.canvas)
        let second = read(masks[1], canvas: scene.canvas)
        var both = 0
        for index in first.indices where first[index] > 0.5 && second[index] > 0.5 {
            both += 1
        }
        #expect(both == 0, "\(both) pixels claimed by both frames")
        let owned = first.indices.count { first[$0] > 0.5 || second[$0] > 0.5 }
        #expect(owned > first.count / 2, "the masks cover only \(owned) of \(first.count)")
    }

    /// The seam path is not free, and the blend must still work without it —
    /// the draft tier never runs it (FS-14.02 §5), so `sharp` has to give a
    /// picture with the masks left out.
    @Test func theBlendStillWorksWithoutTheJoins() throws {
        let scene = try #require(scene())
        let plain = try #require(
            PanoramaCIBlender.sharp(canvas: scene.canvas, sources: scene.sources, focal: focal)
        )
        let luminance = read(plain, canvas: scene.canvas)
        #expect(luminance.contains { $0 > 0.2 })
    }

    /// One frame is not two: there is no join to find, and the planner says so
    /// rather than returning a mask that hides half the picture.
    @Test func oneFrameHasNoJoin() throws {
        let scene = try #require(scene())
        #expect(
            PanoramaSeamPlanner.masks(
                canvas: scene.canvas,
                sources: [scene.sources[0]],
                focal: focal,
                context: context
            ) == nil
        )
    }
}
