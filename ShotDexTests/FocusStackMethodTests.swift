import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.10 AC-5: both methods rebuild an all-in-focus picture from a bracket
/// whose frames are each sharp in one part, and Radius and Smoothing reach
/// the result.
struct FocusStackMethodTests {

    let side = 256

    /// Seeded grey noise: detail everywhere, one answer for registration.
    private func sharpImage() -> CIImage {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var generator = SplitMix64(seed: 5)
        for i in 0..<(side * side) {
            let v = UInt8(truncatingIfNeeded: generator.next() >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v
        }
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return CIImage(cgImage: image)
    }

    /// `sharp` inside rows `band` (Core Image y, bottom-up), blurred elsewhere.
    private func frame(_ sharp: CIImage, band: ClosedRange<CGFloat>) -> CIImage {
        let soft = sharp.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: sharp.extent)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: band.lowerBound, width: CGFloat(side), height: band.upperBound - band.lowerBound))
            .composited(over: CIImage(color: .black).cropped(to: sharp.extent))
        return sharp.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: mask])
    }

    private func pixels(_ image: CIImage) async throws -> [UInt8] {
        let cg = try await PhotoStackRenderer().render(image)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return bytes
    }

    /// PSNR of the red channel, ignoring a 16 px border.
    private func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0.0, n = 0.0
        for y in 16..<(side - 16) { for x in 16..<(side - 16) {
            let i = (y * side + x) * 4
            let d = (Double(a[i]) - Double(b[i])) / 255
            total += d * d; n += 1
        } }
        return 10 * log10(1 / max(1e-12, total / n))
    }

    private func bracket() -> (truth: CIImage, frames: [CIImage]) {
        let truth = sharpImage()
        let s = CGFloat(side)
        // Each sharp in about 60% of the frame, the middle fifth shared.
        return (truth, [frame(truth, band: 0...(s * 0.6)), frame(truth, band: (s * 0.4)...s)])
    }

    @Test(arguments: FocusStackOptions.Method.allCases)
    func eachMethodBeatsEveryFrameItWasMadeFrom(method: FocusStackOptions.Method) async throws {
        let (truth, frames) = bracket()
        let reference = try await pixels(truth)
        let stacked = try await PhotoStackRenderer().combine(images: frames, mode: .focusStack, focus: .defaults(for: method))
        let score = psnr(try await pixels(stacked), reference)
        var bestFrame = -Double.infinity
        for frame in frames { bestFrame = max(bestFrame, psnr(try await pixels(frame), reference)) }
        #expect(score >= bestFrame + 3, "\(method): stack \(score) dB vs best frame \(bestFrame) dB")
    }

    @Test func radiusReachesTheResult() async throws {
        let frames = bracket().frames
        let small = try await pixels(PhotoStackRenderer().combine(images: frames, mode: .focusStack,
                                                                  focus: FocusStackOptions(method: .weighted, radius: 1, smoothing: 0)))
        let large = try await pixels(PhotoStackRenderer().combine(images: frames, mode: .focusStack,
                                                                  focus: FocusStackOptions(method: .weighted, radius: 10, smoothing: 0)))
        #expect(small != large)
    }

    @Test func smoothingReachesTheResult() async throws {
        let frames = bracket().frames
        let hard = try await pixels(PhotoStackRenderer().combine(images: frames, mode: .focusStack,
                                                                 focus: FocusStackOptions(method: .depthMap, radius: 4, smoothing: 0)))
        let soft = try await pixels(PhotoStackRenderer().combine(images: frames, mode: .focusStack,
                                                                 focus: FocusStackOptions(method: .depthMap, radius: 4, smoothing: 10)))
        #expect(hard != soft)
    }

    @Test func defaultsFollowTheSpike() {
        #expect(FocusStackOptions.standard == FocusStackOptions(method: .weighted, radius: 2, smoothing: 0))
        #expect(FocusStackOptions.defaults(for: .depthMap) == FocusStackOptions(method: .depthMap, radius: 4, smoothing: 4))
    }

    @Test func valuesOutsideTheSlidersAreClamped() {
        let options = FocusStackOptions(method: .weighted, radius: 40, smoothing: -3)
        #expect(options.radius == 10 && options.smoothing == 0)
    }

    @Test func preparingOnceThenStackingMatchesCombine() async throws {
        // AC-6 at the renderer: the model lines the bracket up once and
        // re-stacks it on every slider change; that must equal a fresh combine.
        let frames = bracket().frames
        let renderer = PhotoStackRenderer()
        let prepared = try await renderer.prepareFocusStack(images: frames)
        for method in FocusStackOptions.Method.allCases {
            let options = FocusStackOptions.defaults(for: method)
            let direct = try await pixels(renderer.combine(images: frames, mode: .focusStack, focus: options))
            let restacked = try await pixels(renderer.focusStack(prepared, options: options))
            #expect(direct == restacked, "\(method)")
        }
    }
}
