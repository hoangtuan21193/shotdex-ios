import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-8 and AC-10 — a column of frames comes out the right way up, and
/// the curved edges are cropped away without inventing anything.
struct PanoramaCropTests {

    // MARK: Auto Crop

    /// A coverage mask with the wedges a real stitch leaves: full in the
    /// middle, eaten into at the corners.
    private func curvedCoverage(width: Int, height: Int) -> [Float] {
        var coverage = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            // The top and bottom edges bow inwards, the way a swept row does.
            let t = Double(y) / Double(height - 1)
            let bow = Int((Foundation.sin(t * .pi) * 0.12 * Double(width)).rounded())
            for x in bow..<(width - bow) {
                coverage[y * width + x] = 1
            }
        }
        return coverage
    }

    @Test func theCropIsTheBiggestRectangleWithNoHoleInIt() throws {
        let width = 160, height = 90
        let coverage = curvedCoverage(width: width, height: height)
        let crop = try #require(
            PanoramaAutoCrop.largestRectangle(coverage: coverage, width: width, height: height)
        )
        // Nothing empty inside it — that is the whole promise.
        for y in crop.y..<(crop.y + crop.height) {
            for x in crop.x..<(crop.x + crop.width) {
                #expect(coverage[y * width + x] > 0, "the crop must not contain a hole")
            }
        }
        // AC-10: at least 80% of what was actually photographed survives.
        let retained = PanoramaAutoCrop.retainedFraction(of: crop, coverage: coverage, width: width)
        #expect(retained >= 0.8, "kept \(retained)")
    }

    @Test func aFullyCoveredCanvasIsNotCropped() throws {
        let coverage = [Float](repeating: 1, count: 40 * 30)
        let crop = try #require(
            PanoramaAutoCrop.largestRectangle(coverage: coverage, width: 40, height: 30)
        )
        #expect(crop == PanoramaCropRect(x: 0, y: 0, width: 40, height: 30))
    }

    @Test func anEmptyCanvasHasNothingToCropTo() {
        let coverage = [Float](repeating: 0, count: 20 * 10)
        #expect(PanoramaAutoCrop.largestRectangle(coverage: coverage, width: 20, height: 10) == nil)
    }

    @Test func croppingReturnsExactlyThatRectangle() throws {
        var image = PanoramaRGBImage(width: 8, height: 6)
        for index in 0..<(8 * 6) {
            image.pixels[3 * index] = Float(index)
            image.coverage[index] = 1
        }
        let crop = PanoramaCropRect(x: 2, y: 1, width: 4, height: 3)
        let cropped = try #require(PanoramaAutoCrop.crop(image, to: crop))
        #expect(cropped.width == 4)
        #expect(cropped.height == 3)
        // Top-left of the crop is the pixel that was at (2, 1).
        #expect(cropped.pixels[0] == Float(1 * 8 + 2))
    }

    // MARK: AC-8 — a column of frames

    /// Projected about the usual axis a vertical panorama comes out as an
    /// hourglass; turned, it fills its canvas. The numbers here are the shape
    /// of that difference, measured rather than asserted.
    @Test func aColumnOfFramesFillsItsCanvasOnlyWhenTheAxisIsTurned() throws {
        let frameWidth = 60, frameHeight = 45
        let focal = 80.0
        let cameras = stride(from: -24.0, through: 24.0, by: 12).map {
            PanoramaCamera(rotation: PanoramaRotation.matrix(fromAxisAngle: ($0 * .pi / 180, 0, 0)))
        }
        var frames: [PanoramaRGBImage] = []
        for _ in cameras {
            var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
            for index in 0..<(frameWidth * frameHeight) {
                for channel in 0..<3 { image.pixels[3 * index + channel] = 0.5 }
                image.coverage[index] = 1
            }
            frames.append(image)
        }
        let placed = Dictionary(uniqueKeysWithValues: cameras.enumerated().map { ($0.offset, $0.element) })

        func coveredFraction(frame: [Double]) throws -> Double {
            var canvas = try #require(
                PanoramaProjection.canvas(
                    kind: .spherical, cameras: cameras, focal: focal,
                    imageWidth: frameWidth, imageHeight: frameHeight
                )
            )
            canvas = PanoramaCanvas(
                kind: canvas.kind, width: canvas.width, height: canvas.height,
                focal: canvas.focal, frame: frame, originU: canvas.originU, originV: canvas.originV
            )
            // Re-lay the canvas out for this axis so the bounds are honest.
            let directions = PanoramaProjection.boundaryDirections(
                cameras: cameras, focal: focal, imageWidth: frameWidth, imageHeight: frameHeight
            )
            var minU = Double.infinity, maxU = -Double.infinity
            var minV = Double.infinity, maxV = -Double.infinity
            for direction in directions {
                let turned = PanoramaRotation.apply(frame, to: direction)
                guard let uv = PanoramaProjection.project(turned, kind: .spherical, focal: canvas.focal)
                else { continue }
                minU = min(minU, uv.u); maxU = max(maxU, uv.u)
                minV = min(minV, uv.v); maxV = max(maxV, uv.v)
            }
            let laid = PanoramaCanvas(
                kind: .spherical,
                width: Int((maxU - minU).rounded(.up)),
                height: Int((maxV - minV).rounded(.up)),
                focal: canvas.focal,
                frame: frame,
                originU: minU,
                originV: minV
            )
            let rendered = try #require(
                PanoramaCompositor.render(
                    canvas: laid, frames: frames, cameras: placed, focal: focal, quality: .draft
                )
            )
            let covered = rendered.coverage.reduce(into: 0) { $0 += $1 > 0 ? 1 : 0 }
            return Double(covered) / Double(rendered.coverage.count)
        }

        let directions = PanoramaProjection.boundaryDirections(
            cameras: cameras, focal: focal, imageWidth: frameWidth, imageHeight: frameHeight
        )
        let chosen = PanoramaProjection.projectionFrame(for: directions, kind: .spherical)
        #expect(chosen != PanoramaRotation.identity, "a column should be projected on its side")

        let turned = try coveredFraction(frame: chosen)
        let straight = try coveredFraction(frame: PanoramaRotation.identity)
        #expect(turned > straight, "turned \(turned) should beat straight \(straight)")
        #expect(turned >= 0.9, "the turned projection should fill its canvas, got \(turned)")
    }

    @Test func standingUprightTurnsThePictureBackAndLosesNothing() {
        var image = PanoramaRGBImage(width: 5, height: 3)
        for index in 0..<(5 * 3) {
            image.pixels[3 * index] = Float(index)
            image.coverage[index] = 1
        }
        let upright = PanoramaCompositor.standUpright(image)
        #expect(upright.width == 3)
        #expect(upright.height == 5)
        #expect(upright.coverage.allSatisfy { $0 > 0 })
        // The pixel that was top-left ends up bottom-left.
        #expect(upright.pixels[3 * ((5 - 1) * 3)] == 0)
    }
}
