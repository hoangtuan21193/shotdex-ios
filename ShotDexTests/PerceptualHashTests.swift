import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct PerceptualHashTests {

    /// Row-major 9×8 grid where every pixel is brighter than the one to its
    /// left — every comparison is "darker than the right neighbour".
    private var ascendingRows: [UInt8] {
        (0..<DifferenceHash.sampleHeight).flatMap { _ in
            (0..<DifferenceHash.sampleWidth).map { UInt8($0 * 20) }
        }
    }

    @Test func ascendingGradientSetsEveryBit() {
        let hash = DifferenceHash.hash(grayscale: ascendingRows)
        #expect(hash?.bits == UInt64.max)
    }

    @Test func flatImageSetsNoBit() {
        let flat = [UInt8](repeating: 128, count: 72)
        #expect(DifferenceHash.hash(grayscale: flat)?.bits == 0)
    }

    @Test func wrongSampleCountIsRejected() {
        #expect(DifferenceHash.hash(grayscale: [UInt8](repeating: 0, count: 71)) == nil)
    }

    @Test func bitOrderIsRowMajorLeftToRight() {
        // Only the first comparison of the first row (pixel 0 < pixel 1) is true.
        var samples = [UInt8](repeating: 100, count: 72)
        samples[1] = 200
        // Row 0: 100<200 (bit 0 set), 200<100 false, then flat.
        #expect(DifferenceHash.hash(grayscale: samples)?.bits == 1)

        // Only the last comparison of the last row (pixel 70 < pixel 71).
        samples = [UInt8](repeating: 100, count: 72)
        samples[71] = 200
        #expect(DifferenceHash.hash(grayscale: samples)?.bits == 1 << 63)
    }

    @Test func hammingDistanceCountsDifferingBits() {
        let a = PerceptualHash(bits: 0b1011)
        let b = PerceptualHash(bits: 0b0001)
        #expect(a.hammingDistance(to: b) == 2)
        #expect(a.hammingDistance(to: a) == 0)
    }

    @Test func imageHashIsStableAcrossResize() throws {
        let large = try #require(Self.gradientImage(width: 300, height: 200))
        let small = try #require(Self.gradientImage(width: 60, height: 40))
        let largeHash = try #require(DifferenceHash.hash(of: large))
        let smallHash = try #require(DifferenceHash.hash(of: small))
        #expect(largeHash.hammingDistance(to: smallHash) <= 2)
        // A left-to-right gradient sets every horizontal comparison.
        #expect(largeHash.bits == UInt64.max)
    }

    @Test func differentImagesHashFarApart() throws {
        let horizontal = try #require(Self.gradientImage(width: 90, height: 80))
        let vertical = try #require(Self.gradientImage(width: 90, height: 80, vertical: true))
        let a = try #require(DifferenceHash.hash(of: horizontal))
        let b = try #require(DifferenceHash.hash(of: vertical))
        #expect(a.hammingDistance(to: b) > DuplicateStrictness.similarMaxDistance)
    }

    /// Gray gradient, dark on the left (or top) to light on the right (or bottom).
    private static func gradientImage(width: Int, height: Int, vertical: Bool = false) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let t = vertical ? Double(y) / Double(height - 1) : Double(x) / Double(width - 1)
                pixels[y * width + x] = UInt8(t * 255)
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
