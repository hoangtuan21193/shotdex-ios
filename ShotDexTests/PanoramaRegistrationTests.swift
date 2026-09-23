import Foundation
import Testing
@testable import ShotDexKit

/// FS-14 — the registration stage: can two overlapping frames be lined up, and
/// is "these do not overlap" a possible answer.
///
/// The frames are synthesised here rather than shipped as fixtures. That buys
/// three things a bundled photo cannot: the exact transform between them is
/// known, so error is a number and not an impression; the test has no licence
/// attached to it; and the overlap can be dialled to find where the method
/// stops working. What it does not buy is realism — there is no parallax, no
/// moving subject and no exposure drift here, exactly the gap the spike warned
/// about, so `/verify` still owes a run on a real handheld sequence.
struct PanoramaRegistrationTests {

    // MARK: A scene to photograph

    /// Deterministic value noise at several frequencies: something with corners
    /// everywhere and no repeat, which is what a detector needs and what a flat
    /// gradient would not give.
    private func scene(width: Int, height: Int) -> PanoramaImage {
        var pixels = [Float](repeating: 0, count: width * height)
        var generator = SplitMix64(seed: 0x5343_454E_4531)
        // A few octaves of random blobs. Cheap, and it gives structure at both
        // the scale the detector looks at and the scale the descriptor does.
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

    /// Renders what a camera would see after the given transform, by pulling
    /// each output pixel from where it came from in the source.
    private func warp(_ image: PanoramaImage, by homography: PanoramaHomography) -> PanoramaImage {
        guard let inverse = inverted(homography) else { return image }
        var pixels = [Float](repeating: 0, count: image.width * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard let source = inverse.map(x: Double(x), y: Double(y)) else { continue }
                pixels[y * image.width + x] = sample(image, x: source.x, y: source.y)
            }
        }
        return PanoramaImage(width: image.width, height: image.height, pixels: pixels)
    }

    private func sample(_ image: PanoramaImage, x: Double, y: Double) -> Float {
        guard x >= 0, y >= 0, x < Double(image.width - 1), y < Double(image.height - 1) else { return 0 }
        let x0 = Int(x), y0 = Int(y)
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        let top = image[x0, y0] * (1 - tx) + image[x0 + 1, y0] * tx
        let bottom = image[x0, y0 + 1] * (1 - tx) + image[x0 + 1, y0 + 1] * tx
        return top * (1 - ty) + bottom * ty
    }

    private func inverted(_ homography: PanoramaHomography) -> PanoramaHomography? {
        let m = homography.m
        let a = m[4] * m[8] - m[5] * m[7]
        let b = m[5] * m[6] - m[3] * m[8]
        let c = m[3] * m[7] - m[4] * m[6]
        let determinant = m[0] * a + m[1] * b + m[2] * c
        guard abs(determinant) > 1e-12 else { return nil }
        let adjugate = [
            a, m[2] * m[7] - m[1] * m[8], m[1] * m[5] - m[2] * m[4],
            b, m[0] * m[8] - m[2] * m[6], m[2] * m[3] - m[0] * m[5],
            c, m[1] * m[6] - m[0] * m[7], m[0] * m[4] - m[1] * m[3],
        ]
        return PanoramaHomography(adjugate.map { $0 / determinant })
    }

    /// Worst distance, over a grid covering the overlap, between where the
    /// truth puts a point and where the estimate does. One number for "how
    /// wrong is this transform", in pixels.
    private func worstDisagreement(
        _ estimate: PanoramaHomography,
        _ truth: PanoramaHomography,
        width: Int,
        height: Int
    ) -> Double {
        var worst = 0.0
        for row in 0...8 {
            for column in 0...8 {
                let x = Double(column) / 8 * Double(width - 1)
                let y = Double(row) / 8 * Double(height - 1)
                guard let expected = truth.map(x: x, y: y), let actual = estimate.map(x: x, y: y) else {
                    continue
                }
                let dx = expected.x - actual.x, dy = expected.y - actual.y
                worst = max(worst, (dx * dx + dy * dy).squareRoot())
            }
        }
        return worst
    }

    /// A camera turned sideways by `degrees`, seen as a homography on the image
    /// plane: the usual K·R·K⁻¹ for a pinhole of the given focal length.
    private func rotation(degrees: Double, focal: Double, width: Int, height: Int) -> PanoramaHomography {
        let radians = degrees * .pi / 180
        let cx = Double(width) / 2, cy = Double(height) / 2
        let c = Foundation.cos(radians), s = Foundation.sin(radians)
        // K · Ry · K⁻¹, multiplied out.
        let r = [c, 0, s, 0, 1, 0, -s, 0, c]
        let k = [focal, 0, cx, 0, focal, cy, 0, 0, 1]
        let kInverse = [1 / focal, 0, -cx / focal, 0, 1 / focal, -cy / focal, 0, 0, 1]
        func multiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: 9)
            for row in 0..<3 {
                for column in 0..<3 {
                    var sum = 0.0
                    for index in 0..<3 { sum += lhs[row * 3 + index] * rhs[index * 3 + column] }
                    out[row * 3 + column] = sum
                }
            }
            return out
        }
        return PanoramaHomography(multiply(multiply(k, r), kInverse))!
    }

    // MARK: The tests

    /// Renders what a camera pointed `degrees` away would have seen of a wider
    /// scene, so a run of frames really does overlap the way a sweep does.
    private func frame(of scene: PanoramaImage, degrees: Double, width: Int, height: Int) -> PanoramaImage {
        let focal = 700.0
        let offset = focal * Foundation.tan(degrees * .pi / 180)
        var pixels = [Float](repeating: 0, count: width * height)
        let originX = Double(scene.width - width) / 2 + offset
        let originY = Double(scene.height - height) / 2
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = sample(scene, x: originX + Double(x), y: originY + Double(y))
            }
        }
        return PanoramaImage(width: width, height: height, pixels: pixels)
    }

    // MARK: Whole sets

    /// AC-4: a run of frames from one sweep all land in the panorama, and the
    /// one from somewhere else is named rather than dropped.
    @Test func aStrayFrameComesBackAsNotPlaced() throws {
        let width = 520, height = 400
        let wide = scene(width: 1_400, height: 520)
        var frames = [-12.0, -4.0, 4.0, 12.0].map {
            frame(of: wide, degrees: $0, width: width, height: height)
        }
        // A picture of something else entirely.
        var noise = SplitMix64(seed: 0x0DD_0FF)
        var pixels = [Float](repeating: 0, count: width * height)
        for index in pixels.indices { pixels[index] = Float(Double(noise.next() % 1_000) / 1_000) }
        frames.append(PanoramaImage(width: width, height: height, pixels: pixels).blurred())

        let registration = try PanoramaRegistrar.register(images: frames)
        #expect(registration.solution.cameras.count == 4)
        #expect(registration.solution.unplaced == [4])
        // Five frames is under the exhaustive limit, so every pair was tried:
        // nothing was skipped on a guess.
        #expect(registration.comparedPairs == 10)
    }

    /// AC-5: two frames that do not overlap are not a panorama, and saying so
    /// is the answer — not a picture made of one of them.
    @Test func framesThatDoNotOverlapAreRefused() {
        let width = 520, height = 400
        let wide = scene(width: 2_600, height: 520)
        let frames = [-60.0, 60.0].map { frame(of: wide, degrees: $0, width: width, height: height) }
        #expect(throws: PanoramaRegistrationError.noOverlappingFrames) {
            _ = try PanoramaRegistrar.register(images: frames)
        }
    }

    @Test func oneFrameIsNotAPanorama() {
        let single = [scene(width: 200, height: 160)]
        #expect(throws: PanoramaRegistrationError.needsTwoImages) {
            _ = try PanoramaRegistrar.register(images: single)
        }
    }

    /// Above a dozen frames every-pair comparison stops being free, so pairs
    /// are filtered first. The filter must cut work without cutting the run.
    @Test func aBigSetSkipsThePairsItHasNoReasonToTry() {
        let related = [Float](repeating: 0.5, count: 64)
        // Far enough away that the filter has a reason: the limit is an average
        // of 0.35 per cell, and this is 0.45 in every one of them.
        let different = [Float](repeating: 0.95, count: 64)
        let thumbnails = Array(repeating: related, count: 13) + [different]
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let dates: [Date?] = (0..<14).map { start.addingTimeInterval(Double($0)) }

        let everything = PanoramaRegistrar.candidatePairs(
            count: 14, thumbnails: thumbnails, captureDates: nil
        )
        #expect(everything.count < 14 * 13 / 2, "the odd frame out should not be compared to all")

        // Shot seconds apart, so the time signal keeps the pair even though the
        // thumbnails disagree: a sweep across a sky is still one sweep.
        let withDates = PanoramaRegistrar.candidatePairs(
            count: 14, thumbnails: thumbnails, captureDates: dates
        )
        #expect(withDates.count == 14 * 13 / 2)
    }

    @Test func theLinearSolverAnswersASystemItKnows() throws {
        // x + 2y = 5, 3x - y = 1  →  x = 1, y = 2.
        let solution = try #require(PanoramaMatcher.solve([[1, 2, 5], [3, -1, 1]]))
        #expect(abs(solution[0] - 1) < 1e-9)
        #expect(abs(solution[1] - 2) < 1e-9)
        // Collinear equations have no single answer, and saying so is the job.
        #expect(PanoramaMatcher.solve([[1, 2, 3], [2, 4, 6]]) == nil)
    }

    @Test func fourPointPairsGiveBackTheTransformThatMadeThem() throws {
        let truth = rotation(degrees: 25, focal: 900, width: 800, height: 600)
        let corners = [(100.0, 100.0), (700.0, 120.0), (680.0, 500.0), (120.0, 480.0)]
        let pairs = corners.map { point -> (Double, Double, Double, Double) in
            let mapped = truth.map(x: point.0, y: point.1)!
            return (point.0, point.1, mapped.x, mapped.y)
        }
        let estimate = try #require(PanoramaMatcher.homography(fromFour: pairs))
        #expect(worstDisagreement(estimate, truth, width: 800, height: 600) < 1e-6)
    }

    @Test func aDescriptorIsClosestToItself() {
        let image = scene(width: 400, height: 300)
        let features = PanoramaFeatureDetector.features(in: image, maximumCount: 200)
        #expect(features.count > 50)
        for feature in features.prefix(10) {
            #expect(feature.descriptor.distance(to: feature.descriptor) == 0)
        }
        // Two different corners of a textured scene should not describe alike.
        if features.count > 1 {
            let spread = features.prefix(20).map { features[0].descriptor.distance(to: $0.descriptor) }
            #expect(spread.max()! > 40)
        }
    }

    /// The heart of AC-3: a pair of frames a camera made by turning, lined back
    /// up from nothing but their pixels.
    @Test(arguments: [20.0, 30.0, 40.0])
    func aTurnedFrameIsLinedBackUp(degrees: Double) throws {
        let width = 700, height = 520
        let truth = rotation(degrees: degrees, focal: 820, width: width, height: height)
        let first = scene(width: width, height: height)
        let second = warp(first, by: truth)

        let a = PanoramaFeatureDetector.features(in: first)
        let b = PanoramaFeatureDetector.features(in: second)
        let matches = PanoramaMatcher.matches(a, b)
        let fit = try #require(
            PanoramaMatcher.fit(matches: matches, a: a, b: b),
            "frames overlapping by this much must line up"
        )

        #expect(fit.inliers.count >= PanoramaMatcher.minimumInliers)
        #expect(fit.medianError < 1.5)
        // Compared over the part of the frame both cameras actually saw; the
        // far edge of the source is off the side of the turned frame, where an
        // estimate has nothing to be right about.
        let overlap = Int(Double(width) * (1 - degrees / 60))
        #expect(worstDisagreement(fit.homography, truth, width: overlap, height: height) < 4)
    }

    /// AC-5's other side: two frames of different scenes must come back as no
    /// answer, not as a confident wrong one. This is the failure that would put
    /// a stranger's photo into somebody's panorama.
    @Test func framesOfDifferentScenesDoNotLineUp() {
        let first = scene(width: 700, height: 520)
        var other = SplitMix64(seed: 0xDEAD_BEEF)
        var pixels = [Float](repeating: 0, count: 700 * 520)
        for index in pixels.indices {
            pixels[index] = Float(Double(other.next() % 1_000) / 1_000)
        }
        let unrelated = PanoramaImage(width: 700, height: 520, pixels: pixels).blurred()

        let a = PanoramaFeatureDetector.features(in: first)
        let b = PanoramaFeatureDetector.features(in: unrelated)
        let fit = PanoramaMatcher.fit(matches: PanoramaMatcher.matches(a, b), a: a, b: b)
        #expect(fit == nil)
    }

    /// Two runs of the same input must give the same stitch. The descriptor
    /// pattern and the RANSAC sampling both draw from a seeded generator for
    /// this reason.
    @Test func registrationIsRepeatable() throws {
        let width = 600, height = 450
        let truth = rotation(degrees: 28, focal: 700, width: width, height: height)
        let first = scene(width: width, height: height)
        let second = warp(first, by: truth)

        func run() -> PanoramaHomography? {
            let a = PanoramaFeatureDetector.features(in: first)
            let b = PanoramaFeatureDetector.features(in: second)
            return PanoramaMatcher.fit(matches: PanoramaMatcher.matches(a, b), a: a, b: b)?.homography
        }
        let once = try #require(run())
        let twice = try #require(run())
        #expect(once == twice)
    }
}
