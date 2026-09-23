import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 — warping the frames onto the canvas and joining them without a
/// visible seam.
struct PanoramaCompositorTests {

    // Small on purpose. The blend is six bands of full-canvas blur per
    // channel per frame, in plain Swift; at a few hundred pixels a side that
    // is seconds in a debug build and the suite stops being run. The maths
    // does not care about the size, so the test does not pay for one.
    private let frameWidth = 80
    private let frameHeight = 60
    private let focal = 100.0

    private func camera(yaw: Double) -> PanoramaCamera {
        PanoramaCamera(rotation: PanoramaRotation.matrix(fromAxisAngle: (0, yaw * .pi / 180, 0)))
    }

    /// A frame of flat colour with a little texture, so a blend has something
    /// to preserve as well as something to smooth.
    private func frame(brightness: Float) -> PanoramaRGBImage {
        var image = PanoramaRGBImage(width: frameWidth, height: frameHeight)
        for y in 0..<frameHeight {
            for x in 0..<frameWidth {
                let index = y * frameWidth + x
                let texture = Float((x / 4 + y / 4) % 2) * 0.03
                for channel in 0..<3 {
                    image.pixels[3 * index + channel] = brightness + texture
                }
                image.coverage[index] = 1
            }
        }
        return image
    }

    private func canvas(for cameras: [PanoramaCamera]) -> PanoramaCanvas? {
        PanoramaProjection.canvas(
            kind: .spherical,
            cameras: cameras,
            focal: focal,
            imageWidth: frameWidth,
            imageHeight: frameHeight
        )
    }

    /// The biggest jump between two side-by-side pixels along the middle row —
    /// a seam is exactly a place where that number is large.
    private func worstHorizontalStep(_ image: PanoramaRGBImage) -> Float {
        let y = image.height / 2
        var worst: Float = 0
        for x in 1..<image.width {
            let index = y * image.width + x
            guard image.coverage[index] > 0, image.coverage[index - 1] > 0 else { continue }
            worst = max(worst, abs(image.pixels[3 * index] - image.pixels[3 * (index - 1)]))
        }
        return worst
    }

    @Test func everyPlaceAFrameReachedComesOutCovered() throws {
        let cameras = [camera(yaw: -10), camera(yaw: 10)]
        let canvas = try #require(canvas(for: cameras))
        let result = try #require(
            PanoramaCompositor.render(
                canvas: canvas,
                frames: [frame(brightness: 0.5), frame(brightness: 0.5)],
                cameras: [0: cameras[0], 1: cameras[1]],
                focal: focal
            )
        )
        let covered = result.coverage.filter { $0 > 0 }.count
        // Two frames ten degrees apart fill most of the canvas they define.
        #expect(Double(covered) / Double(result.coverage.count) > 0.8)
    }

    /// The point of multi-band blending: two frames that disagree about
    /// brightness must not leave a step where they meet.
    @Test func aBrightnessDifferenceDoesNotLeaveAStep() throws {
        let cameras = [camera(yaw: -9), camera(yaw: 9)]
        let canvas = try #require(canvas(for: cameras))
        let frames = [frame(brightness: 0.40), frame(brightness: 0.60)]
        let placed = [0: cameras[0], 1: cameras[1]]

        let blended = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: frames, cameras: placed, focal: focal, quality: .sharp
            )
        )

        // What it would look like joined with a hard edge: each pixel taken
        // from whichever frame saw it most squarely, no blending at all.
        var warped: [PanoramaRGBImage] = []
        var weights: [[Float]] = []
        for index in 0..<2 {
            let (image, weight) = PanoramaCompositor.warp(
                frame: frames[index], camera: cameras[index], focal: focal, canvas: canvas, gain: 1
            )
            warped.append(image)
            weights.append(weight)
        }
        var hard = PanoramaRGBImage(width: canvas.width, height: canvas.height)
        for index in 0..<(canvas.width * canvas.height) {
            var best = -1
            var bestWeight: Float = 0
            for frameIndex in 0..<2 where warped[frameIndex].coverage[index] > 0 {
                if weights[frameIndex][index] > bestWeight {
                    bestWeight = weights[frameIndex][index]
                    best = frameIndex
                }
            }
            guard best >= 0 else { continue }
            for channel in 0..<3 {
                hard.pixels[3 * index + channel] = warped[best].pixels[3 * index + channel]
            }
            hard.coverage[index] = 1
        }

        let hardStep = worstHorizontalStep(hard)
        let blendedStep = worstHorizontalStep(blended)
        #expect(hardStep > 0.1, "the hard join should show the 0.2 difference it was given")
        #expect(blendedStep < hardStep / 4, "blending should take most of the step out")
    }

    /// The draft blend has to agree with the sharp one about *where* things
    /// are, or a control adjusted against the draft would move the picture
    /// when the sharp version arrived (FS-14.01 §4).
    @Test func theDraftAndTheSharpBlendShareTheirGeometry() throws {
        let cameras = [camera(yaw: -8), camera(yaw: 8)]
        let canvas = try #require(canvas(for: cameras))
        let frames = [frame(brightness: 0.45), frame(brightness: 0.55)]
        let placed = [0: cameras[0], 1: cameras[1]]

        let draft = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: frames, cameras: placed, focal: focal, quality: .draft
            )
        )
        let sharp = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: frames, cameras: placed, focal: focal, quality: .sharp
            )
        )
        #expect(draft.width == sharp.width)
        #expect(draft.height == sharp.height)
        for index in 0..<draft.coverage.count {
            #expect(draft.coverage[index] == sharp.coverage[index])
        }
    }

    /// Gains from the exposure solve are applied while warping, so the blend
    /// never sees the mismatch in the first place.
    @Test func gainsAreAppliedToTheFramesTheyBelongTo() throws {
        let cameras = [camera(yaw: 0)]
        let canvas = try #require(canvas(for: cameras))
        let base = frame(brightness: 0.4)
        let plain = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: [base], cameras: [0: cameras[0]], focal: focal, quality: .draft
            )
        )
        let doubled = try #require(
            PanoramaCompositor.render(
                canvas: canvas, frames: [base], cameras: [0: cameras[0]], focal: focal,
                gains: [2], quality: .draft
            )
        )
        let index = (canvas.height / 2) * canvas.width + canvas.width / 2
        #expect(plain.coverage[index] > 0)
        #expect(abs(doubled.pixels[3 * index] - 2 * plain.pixels[3 * index]) < 1e-4)
    }

    /// Filling outside a frame's edge before the pyramid is built is what stops
    /// the blur reaching into black and ringing the panorama with a dark halo.
    @Test func theOutsideOfAFrameIsFilledBeforeItIsBlurred() {
        var image = PanoramaRGBImage(width: 16, height: 16)
        for y in 4..<12 {
            for x in 4..<12 {
                let index = y * 16 + x
                image.pixels[3 * index] = 0.8
                image.coverage[index] = 1
            }
        }
        let filled = PanoramaCompositor.filledChannel(image, channel: 0, width: 16, height: 16)
        // A corner far outside the covered square must have taken a value from
        // it rather than staying black.
        #expect(filled[0] > 0.3)
        // And the covered area is untouched.
        #expect(abs(filled[8 * 16 + 8] - 0.8) < 1e-6)
    }
}
