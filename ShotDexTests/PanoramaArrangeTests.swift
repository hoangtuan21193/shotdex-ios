import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 AC-6 — the photographer moves a frame and the app takes the hint.
///
/// The drop is deliberately *not* what places the frame: it says where to look
/// and is then checked against what the matcher found. These tests hold both
/// halves of that — a drop near the truth ends up at the truth to well under a
/// pixel, and a drop on a frame that matches nothing is refused rather than
/// pasted down where the finger stopped.
struct PanoramaArrangeTests {

    // MARK: A sweep to arrange

    private let focal = 700.0
    private let frameWidth = 520
    private let frameHeight = 400

    /// The same value-noise scene the registration tests photograph, so a
    /// detector has corners to find at every scale.
    private func scene(width: Int, height: Int) -> PanoramaImage {
        var pixels = [Float](repeating: 0, count: width * height)
        var generator = SplitMix64(seed: 0x4152_5241_4E47_45)
        for octave in 0..<5 {
            let cells = 4 << octave
            let amplitude = Float(1.0 / Double(1 << octave))
            var grid = [Float](repeating: 0, count: (cells + 1) * (cells + 1))
            for index in grid.indices {
                grid[index] = Float(Double(generator.next() % 1_000) / 1_000)
            }
            for y in 0..<height {
                for x in 0..<width {
                    let fx = Float(x) / Float(width) * Float(cells)
                    let fy = Float(y) / Float(height) * Float(cells)
                    let x0 = Int(fx), y0 = Int(fy)
                    let tx = fx - Float(x0), ty = fy - Float(y0)
                    let row = y0 * (cells + 1) + x0
                    let top = grid[row] * (1 - tx) + grid[row + 1] * tx
                    let bottom = grid[row + cells + 1] * (1 - tx) + grid[row + cells + 2] * tx
                    pixels[y * width + x] += amplitude * (top * (1 - ty) + bottom * ty)
                }
            }
        }
        let peak = pixels.max() ?? 1
        if peak > 0 {
            for index in pixels.indices { pixels[index] /= peak }
        }
        return PanoramaImage(width: width, height: height, pixels: pixels)
    }

    private func sample(_ image: PanoramaImage, x: Double, y: Double) -> Float {
        let cx = max(0, min(Double(image.width - 1), x))
        let cy = max(0, min(Double(image.height - 1), y))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(image.width - 1, x0 + 1), y1 = min(image.height - 1, y0 + 1)
        let tx = Float(cx - Double(x0)), ty = Float(cy - Double(y0))
        let top = image.pixels[y0 * image.width + x0] * (1 - tx)
            + image.pixels[y0 * image.width + x1] * tx
        let bottom = image.pixels[y1 * image.width + x0] * (1 - tx)
            + image.pixels[y1 * image.width + x1] * tx
        return top * (1 - ty) + bottom * ty
    }

    /// One frame of a horizontal sweep, `degrees` from the middle.
    private func frame(of scene: PanoramaImage, degrees: Double) -> PanoramaImage {
        let offset = focal * Foundation.tan(degrees * .pi / 180)
        var pixels = [Float](repeating: 0, count: frameWidth * frameHeight)
        let originX = Double(scene.width - frameWidth) / 2 + offset
        let originY = Double(scene.height - frameHeight) / 2
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                pixels[y * frameWidth + x] = sample(
                    scene, x: originX + Double(x), y: originY + Double(y)
                )
            }
        }
        return PanoramaImage(width: frameWidth, height: frameHeight, pixels: pixels)
    }

    /// A four-frame sweep, and the registration of the first three — the
    /// fourth is the one Arrange will place.
    private func sweep(
        angles: [Double]
    ) throws -> (images: [PanoramaImage], registration: PanoramaRegistration) {
        let wide = scene(width: 1_400, height: 520)
        let images = angles.map { frame(of: wide, degrees: $0) }
        return (images, try PanoramaRegistrar.register(images: images))
    }

    private func angleBetween(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> Double {
        PanoramaArranger.angle(between: a, and: b)
    }

    // MARK: AC-6 — a drop near the right place lands on the right place

    /// The frame is dropped 20% of a frame width from where it belongs, which
    /// is the tolerance the spec asks for, and comes back matched to its
    /// neighbours rather than left where the finger stopped.
    @Test func aFrameDroppedNearItsPlaceIsAlignedToItsNeighbours() throws {
        let angles = [-12.0, -4.0, 4.0, 12.0]
        let (images, registration) = try sweep(angles: angles)
        let solution = registration.solution
        try #require(solution.cameras.count == 4)

        // The truth for the last frame, then take it out the way Not Placed
        // does and put it back from a drop that is deliberately off.
        let truth = PanoramaArranger.centreDirection(of: try #require(solution.cameras[3]))
        let without = try PanoramaArranger.remove(
            frame: 3, images: images, pairs: registration.pairs, solution: solution
        )
        #expect(without.solution.cameras[3] == nil)
        #expect(without.solution.unplaced.contains(3))

        // 20% of a frame width, along the sweep.
        let frameAngle = PanoramaArranger.angularWidth(
            focal: solution.focal, imageWidth: frameWidth, imageHeight: frameHeight
        )
        let off = rotatedAboutY(truth, by: 0.2 * frameAngle)
        #expect(angleBetween(off, truth) > 0.1 * frameAngle, "the drop has to actually be off")

        let placed = try PanoramaArranger.place(
            frame: 3,
            towards: off,
            images: images,
            pairs: without.pairs,
            solution: without.solution
        )
        let landed = PanoramaArranger.centreDirection(of: try #require(placed.solution.cameras[3]))

        // AC-6 asks for a pixel at 1024: at this focal length one pixel is
        // 1/700 radian, and the drop was thirty times further out than that.
        let pixels = angleBetween(landed, truth) * solution.focal
        #expect(pixels <= 1.0, "landed \(pixels) px from where it belongs")
        #expect(placed.solution.unplaced.isEmpty)
    }

    /// The other half of the same behaviour: a drop is a hint, so a frame that
    /// matches nothing where it was dropped is refused, not pasted down.
    @Test func aFrameThatMatchesNothingIsRefused() throws {
        let angles = [-12.0, -4.0, 4.0]
        let wide = scene(width: 1_400, height: 520)
        var images = angles.map { frame(of: wide, degrees: $0) }

        var noise = SplitMix64(seed: 0x4E4F_4953_45)
        var pixels = [Float](repeating: 0, count: frameWidth * frameHeight)
        for index in pixels.indices {
            pixels[index] = Float(Double(noise.next() % 1_000) / 1_000)
        }
        images.append(PanoramaImage(width: frameWidth, height: frameHeight, pixels: pixels).blurred())

        let registration = try PanoramaRegistrar.register(images: images)
        try #require(registration.solution.unplaced == [3])
        let anywhere = PanoramaArranger.centreDirection(
            of: try #require(registration.solution.cameras[1])
        )
        #expect(throws: PanoramaArrangeError.cannotAlign) {
            _ = try PanoramaArranger.place(
                frame: 3,
                towards: anywhere,
                images: images,
                pairs: registration.pairs,
                solution: registration.solution
            )
        }
    }

    /// A frame dropped far from where it matches is refused too — the matcher
    /// may still find the overlap, but agreeing with it would move the frame
    /// somewhere the photographer did not point.
    @Test func anAlignmentThatContradictsTheDropIsRefused() throws {
        let (images, registration) = try sweep(angles: [-12.0, -4.0, 4.0, 12.0])
        let solution = registration.solution
        let without = try PanoramaArranger.remove(
            frame: 3, images: images, pairs: registration.pairs, solution: solution
        )
        let truth = PanoramaArranger.centreDirection(of: try #require(solution.cameras[3]))
        let frameAngle = PanoramaArranger.angularWidth(
            focal: solution.focal, imageWidth: frameWidth, imageHeight: frameHeight
        )
        // Well past the half-frame tolerance, but still inside the
        // neighbourhood the matcher is allowed to search.
        let wrong = rotatedAboutY(truth, by: 1.5 * frameAngle)
        #expect(throws: PanoramaArrangeError.cannotAlign) {
            _ = try PanoramaArranger.place(
                frame: 3,
                towards: wrong,
                images: images,
                pairs: without.pairs,
                solution: without.solution
            )
        }
    }

    // MARK: Removing

    /// Dragging a frame to Not Placed leaves a panorama of the rest.
    @Test func removingAFrameLeavesTheOthersStanding() throws {
        let (images, registration) = try sweep(angles: [-12.0, -4.0, 4.0, 12.0])
        let after = try PanoramaArranger.remove(
            frame: 0, images: images, pairs: registration.pairs, solution: registration.solution
        )
        #expect(after.solution.cameras.count == 3)
        #expect(after.solution.unplaced == [0])
        #expect(after.pairs.allSatisfy { $0.a != 0 && $0.b != 0 })
    }

    /// Emptying the panorama is not a thing Arrange can do to you: two frames
    /// minus one is not a panorama, and the removal is refused.
    @Test func removingDownToOneFrameIsRefused() throws {
        let wide = scene(width: 1_400, height: 520)
        let images = [-4.0, 4.0].map { frame(of: wide, degrees: $0) }
        let registration = try PanoramaRegistrar.register(images: images)
        #expect(throws: PanoramaArrangeError.wouldEmptyThePanorama) {
            _ = try PanoramaArranger.remove(
                frame: 1,
                images: images,
                pairs: registration.pairs,
                solution: registration.solution
            )
        }
    }

    // MARK: The geometry the stage draws with

    /// The outline that follows a finger points where the finger is.
    @Test func theSeedRotationLooksWhereItWasAimed() {
        for direction in [(0.0, 0.0, 1.0), (0.4, 0.1, 0.9), (-0.7, 0.2, 0.68)] {
            let rotation = PanoramaArranger.seedRotation(towards: direction)
            let looking = PanoramaArranger.centreDirection(of: PanoramaCamera(rotation: rotation))
            #expect(angleBetween(looking, PanoramaArranger.normalised(direction)) < 1e-9)
        }
    }

    /// A rotation is a rotation: the seed has to be orthonormal or every
    /// downstream projection is quietly skewed.
    @Test func theSeedRotationIsARotation() {
        let r = PanoramaArranger.seedRotation(towards: (0.3, -0.2, 0.9))
        for row in 0..<3 {
            let length = (0..<3).reduce(0.0) { $0 + r[row * 3 + $1] * r[row * 3 + $1] }
            #expect(abs(length - 1) < 1e-9)
            for other in (row + 1)..<3 {
                let dot = (0..<3).reduce(0.0) { $0 + r[row * 3 + $1] * r[other * 3 + $1] }
                #expect(abs(dot) < 1e-9)
            }
        }
    }

    /// Frames on the far side of the sweep are not worth matching against, and
    /// the ones next to the drop are tried first.
    @Test func theNearestFramesAreTheOnesTried() throws {
        let (_, registration) = try sweep(angles: [-12.0, -4.0, 4.0, 12.0])
        let solution = registration.solution
        let atFrameZero = PanoramaArranger.centreDirection(of: try #require(solution.cameras[0]))
        let order = PanoramaArranger.neighbours(
            of: 3,
            towards: atFrameZero,
            solution: solution,
            imageWidth: frameWidth,
            imageHeight: frameHeight
        )
        #expect(order.first == 0)
        #expect(!order.contains(3))
    }

    // MARK: Helpers

    private func rotatedAboutY(
        _ v: (Double, Double, Double), by radians: Double
    ) -> (Double, Double, Double) {
        let c = Foundation.cos(radians), s = Foundation.sin(radians)
        return (c * v.0 + s * v.2, v.1, -s * v.0 + c * v.2)
    }
}
