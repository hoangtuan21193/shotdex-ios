import Foundation

/// A 256-bit binary description of the neighbourhood around one corner.
///
/// Binary rather than a float vector because the only thing ever done with it
/// is compare it to a few thousand others: a Hamming distance is four XORs and
/// four population counts, and a panorama of ten frames asks that question
/// millions of times.
public struct PanoramaDescriptor: Sendable, Equatable {
    public var bits: SIMD4<UInt64>

    public init(bits: SIMD4<UInt64> = .zero) { self.bits = bits }

    /// Number of differing bits. 0 is identical, 256 is opposite.
    @inlinable
    public func distance(to other: PanoramaDescriptor) -> Int {
        let difference = bits ^ other.bits
        return difference[0].nonzeroBitCount
            + difference[1].nonzeroBitCount
            + difference[2].nonzeroBitCount
            + difference[3].nonzeroBitCount
    }
}

/// One corner and what it looks like.
public struct PanoramaFeature: Sendable {
    /// Position in the working image, in pixels.
    public var x: Float
    public var y: Float
    /// Corner strength, for ranking.
    public var response: Float
    public var descriptor: PanoramaDescriptor

    public init(x: Float, y: Float, response: Float, descriptor: PanoramaDescriptor) {
        self.x = x
        self.y = y
        self.response = response
        self.descriptor = descriptor
    }
}

/// Finds the points two overlapping frames can be lined up on.
///
/// Harris corners and a BRIEF-style binary descriptor, both written here
/// because the system has nothing that does this job: `Vision`'s registration
/// requests are image-stabilisation tools, accurate to 0.1 px when two frames
/// differ by one degree and wrong by 620 px at forty — and every panorama pair
/// differs by twenty to forty-five ([spike §2.1](../../../docs/_intents/2026-09-23-panorama-stitch-spike.md)).
///
/// Deliberately **not** rotation-invariant. A panorama is shot by turning a
/// camera about its own axis, so frames arrive within a few degrees of upright
/// relative to each other; paying for an orientation estimate per corner would
/// buy robustness against a case that does not occur, and orientation estimates
/// are themselves a source of mismatches.
public enum PanoramaFeatureDetector {
    /// Half-width of the window the descriptor samples from. A corner closer
    /// than this to an edge is dropped rather than clamped: a descriptor built
    /// from clamped reads describes the edge of the frame, and every frame has
    /// one of those in the same place.
    public static let patchRadius = 15

    /// Corners kept per frame. Enough that a 30% overlap still holds a few
    /// hundred in common, few enough that comparing every pair stays cheap.
    public static let defaultMaximumFeatures = 1_200

    /// Detects corners and describes them.
    ///
    /// - Parameter image: the working-resolution luminance image.
    /// - Returns: features, strongest first, spread across the frame.
    public static func features(
        in image: PanoramaImage,
        maximumCount: Int = defaultMaximumFeatures
    ) -> [PanoramaFeature] {
        guard image.width > 2 * patchRadius + 2, image.height > 2 * patchRadius + 2 else { return [] }
        let responses = harrisResponse(of: image)
        let corners = pickCorners(responses: responses, image: image, maximumCount: maximumCount)
        let smoothed = image.blurred()
        return corners.map { corner in
            PanoramaFeature(
                x: Float(corner.x),
                y: Float(corner.y),
                response: corner.response,
                descriptor: describe(smoothed, atX: corner.x, y: corner.y)
            )
        }
    }

    // MARK: Corners

    private struct Corner {
        var x: Int
        var y: Int
        var response: Float
    }

    /// Harris response per pixel: the corner measure `det(M) - k·trace(M)²` over
    /// a 3×3 window of the structure tensor.
    ///
    /// Harris rather than a difference-of-Gaussians keypoint: this runs once per
    /// frame at 1024 px, where a dense per-pixel measure is a few milliseconds,
    /// and Harris answers the question that matters here — "is this point
    /// pinned in both directions" — without a scale search. Panorama frames are
    /// all at one scale by construction.
    private static func harrisResponse(of image: PanoramaImage) -> [Float] {
        let width = image.width, height = image.height
        var ixx = [Float](repeating: 0, count: width * height)
        var iyy = [Float](repeating: 0, count: width * height)
        var ixy = [Float](repeating: 0, count: width * height)

        image.pixels.withUnsafeBufferPointer { pixels in
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let index = y * width + x
                    // Sobel, so a single noisy pixel cannot invent a gradient.
                    let dx =
                        (pixels[index - width + 1] + 2 * pixels[index + 1] + pixels[index + width + 1])
                        - (pixels[index - width - 1] + 2 * pixels[index - 1] + pixels[index + width - 1])
                    let dy =
                        (pixels[index + width - 1] + 2 * pixels[index + width] + pixels[index + width + 1])
                        - (pixels[index - width - 1] + 2 * pixels[index - width] + pixels[index - width + 1])
                    ixx[index] = dx * dx
                    iyy[index] = dy * dy
                    ixy[index] = dx * dy
                }
            }
        }

        let k: Float = 0.04
        var responses = [Float](repeating: 0, count: width * height)
        for y in 2..<(height - 2) {
            for x in 2..<(width - 2) {
                var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
                for dy in -1...1 {
                    let row = (y + dy) * width + x
                    for dx in -1...1 {
                        sxx += ixx[row + dx]
                        syy += iyy[row + dx]
                        sxy += ixy[row + dx]
                    }
                }
                let determinant = sxx * syy - sxy * sxy
                let trace = sxx + syy
                responses[y * width + x] = determinant - k * trace * trace
            }
        }
        return responses
    }

    /// Non-maximum suppression, then the strongest corners **per cell of a
    /// grid** rather than the strongest overall.
    ///
    /// Taking the global top N puts every feature on the one high-contrast
    /// building in the corner of the frame, and a homography fitted to points
    /// from one corner of the image is a homography that is only right there.
    /// The grid forces coverage, which is what the fit actually needs.
    private static func pickCorners(
        responses: [Float],
        image: PanoramaImage,
        maximumCount: Int
    ) -> [Corner] {
        let width = image.width, height = image.height
        let margin = patchRadius + 1
        guard width > 2 * margin, height > 2 * margin else { return [] }

        let columns = 8, rows = 8
        let perCell = max(1, maximumCount / (columns * rows))
        let cellWidth = max(1, width / columns), cellHeight = max(1, height / rows)
        var byCell = [[Corner]](repeating: [], count: columns * rows)

        for y in margin..<(height - margin) {
            for x in margin..<(width - margin) {
                let index = y * width + x
                let response = responses[index]
                guard response > 0 else { continue }
                // 3×3 non-maximum suppression: one corner, not a smear of them.
                var isPeak = true
                for dy in -1...1 where isPeak {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        if responses[index + dy * width + dx] >= response {
                            isPeak = false
                            break
                        }
                    }
                }
                guard isPeak else { continue }
                let cell = min(rows - 1, y / cellHeight) * columns + min(columns - 1, x / cellWidth)
                byCell[cell].append(Corner(x: x, y: y, response: response))
            }
        }

        var corners: [Corner] = []
        corners.reserveCapacity(maximumCount)
        for var cell in byCell {
            cell.sort { $0.response > $1.response }
            corners.append(contentsOf: cell.prefix(perCell))
        }
        corners.sort { $0.response > $1.response }
        return Array(corners.prefix(maximumCount))
    }

    // MARK: Descriptor

    /// The 256 pixel pairs the descriptor compares, as offsets from the corner.
    ///
    /// Drawn once from a seeded generator, not from `random()`: two runs of the
    /// app must describe the same corner the same way, or a panorama would
    /// stitch differently each time it was opened. The distribution is the
    /// usual one — normally distributed around the centre, so most comparisons
    /// are near the corner where the detail is.
    private static let testPairs: [(Int, Int, Int, Int)] = {
        var generator = SplitMix64(seed: 0x5150_5F50_414E_4F52)
        var pairs: [(Int, Int, Int, Int)] = []
        pairs.reserveCapacity(256)
        let sigma = Double(patchRadius) / 2.4
        while pairs.count < 256 {
            let ax = Int((generator.nextGaussian() * sigma).rounded())
            let ay = Int((generator.nextGaussian() * sigma).rounded())
            let bx = Int((generator.nextGaussian() * sigma).rounded())
            let by = Int((generator.nextGaussian() * sigma).rounded())
            let inside = [ax, ay, bx, by].allSatisfy { abs($0) <= patchRadius }
            guard inside, (ax, ay) != (bx, by) else { continue }
            pairs.append((ax, ay, bx, by))
        }
        return pairs
    }()

    private static func describe(_ image: PanoramaImage, atX x: Int, y: Int) -> PanoramaDescriptor {
        var bits = SIMD4<UInt64>.zero
        image.pixels.withUnsafeBufferPointer { pixels in
            let width = image.width
            for (index, pair) in testPairs.enumerated() {
                let a = pixels[(y + pair.1) * width + (x + pair.0)]
                let b = pixels[(y + pair.3) * width + (x + pair.2)]
                if a > b {
                    bits[index >> 6] |= (1 as UInt64) << UInt64(index & 63)
                }
            }
        }
        return PanoramaDescriptor(bits: bits)
    }
}

/// A small deterministic generator, so the descriptor pattern and the RANSAC
/// sampling are the same on every run and every device.
///
/// `SystemRandomNumberGenerator` would make a stitch unreproducible, and a
/// panorama that comes out subtly different each time it is built is one nobody
/// can file a bug against.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Box–Muller, one value at a time. Called a few hundred times at startup
    /// and never again, so the wasted second sample does not matter.
    mutating func nextGaussian() -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude...1, using: &self)
        let u2 = Double.random(in: 0...1, using: &self)
        return (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * .pi * u2)
    }
}
