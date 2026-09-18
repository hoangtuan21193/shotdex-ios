import CoreGraphics
import Foundation

/// 64-bit difference hash (dHash) of an image: each bit records whether a
/// pixel of a 9×8 grayscale downsample is darker than its right-hand
/// neighbour. Two hashes a small Hamming distance apart describe images that
/// look the same — a re-export, a resize, a burst neighbour — while an exact
/// pixel copy hashes identically.
struct PerceptualHash: Hashable, Sendable, Codable {
    static let bitCount = 64

    let bits: UInt64

    init(bits: UInt64) {
        self.bits = bits
    }

    /// Number of differing bits — the distance the duplicate finder groups on.
    func hammingDistance(to other: PerceptualHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }
}

/// The dHash algorithm on raw grayscale samples, kept free of PhotoKit so the
/// bit pattern can be unit-tested against hand-built pixel grids.
enum DifferenceHash {
    /// Downsample grid the hash is read from: `sampleWidth - 1` comparisons per
    /// row × `sampleHeight` rows = 64 bits.
    static let sampleWidth = 9
    static let sampleHeight = 8

    /// Hashes a row-major grid of `sampleWidth × sampleHeight` gray samples.
    /// Returns `nil` when the buffer has the wrong size.
    static func hash(grayscale samples: [UInt8]) -> PerceptualHash? {
        guard samples.count == sampleWidth * sampleHeight else { return nil }
        var bits: UInt64 = 0
        var bit = 0
        for row in 0..<sampleHeight {
            let base = row * sampleWidth
            for column in 0..<(sampleWidth - 1) {
                if samples[base + column] < samples[base + column + 1] {
                    bits |= 1 << UInt64(bit)
                }
                bit += 1
            }
        }
        return PerceptualHash(bits: bits)
    }

    /// Oversampling factor for the gray downsample: the image is drawn at
    /// `supersample × (9×8)` and box-averaged down. Drawing straight into a
    /// 9×8 context leaves CoreGraphics' resampler with an edge artefact on the
    /// last row (its final samples repeat), which flipped bits for identical
    /// images at different sizes; averaging 4×4 blocks of a 36×32 draw is
    /// stable across source sizes.
    static let supersample = 4

    /// Hashes any `CGImage` by drawing it, squashed (aspect ratio ignored, as
    /// dHash requires), into a gray context and averaging down to 9×8.
    static func hash(of image: CGImage) -> PerceptualHash? {
        guard let samples = graySamples(of: image) else { return nil }
        return hash(grayscale: samples)
    }

    /// The 9×8 gray downsample of `image`, row-major, one byte per sample.
    static func graySamples(of image: CGImage) -> [UInt8]? {
        let width = sampleWidth * supersample
        let height = sampleHeight * supersample
        var pixels = [UInt8](repeating: 0, count: width * height)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var samples = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
        let blockArea = supersample * supersample
        for row in 0..<sampleHeight {
            for column in 0..<sampleWidth {
                var sum = 0
                for dy in 0..<supersample {
                    let base = (row * supersample + dy) * width + column * supersample
                    for dx in 0..<supersample {
                        sum += Int(pixels[base + dx])
                    }
                }
                samples[row * sampleWidth + column] = UInt8(sum / blockArea)
            }
        }
        return samples
    }
}
