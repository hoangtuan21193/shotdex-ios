import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit

/// FS-01.10 AC-8, AC-9, AC-10: retouching a focus stack from one frame.
struct FocusStackRetouchTests {

    let side = 256

    private func sharpImage(seed: UInt64) -> CIImage {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        var generator = SplitMix64(seed: seed)
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

    /// Sharp inside rows `band` (Core Image y, bottom-up), blurred elsewhere.
    private func frame(_ sharp: CIImage, band: ClosedRange<CGFloat>) -> CIImage {
        let soft = sharp.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: sharp.extent)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: band.lowerBound, width: CGFloat(side), height: band.upperBound - band.lowerBound))
            .composited(over: CIImage(color: .black).cropped(to: sharp.extent))
        return sharp.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: soft, kCIInputMaskImageKey: mask])
    }

    /// Frame 0 sharp in the bottom 60% (Core Image y), frame 1 in the top 60%.
    private func bracket() -> [CIImage] {
        let truth = sharpImage(seed: 5)
        let s = CGFloat(side)
        return [frame(truth, band: 0...(s * 0.6)), frame(truth, band: (s * 0.4)...s)]
    }

    private func pixels(_ image: CIImage) async throws -> [UInt8] {
        let cg = try await PhotoStackRenderer().render(image)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return bytes
    }

    /// A hard round dab, `size` of the short edge wide, at a normalized point.
    private func dab(frame: Int, x: Double, y: Double, size: Double = 0.25) -> FocusStackRetouchStroke {
        FocusStackRetouchStroke(
            frame: frame,
            brush: BrushStroke(points: [NormalizedPoint(x: x, y: y)], size: size, feather: 0, flow: 1, isEraser: false)
        )
    }

    /// Largest channel difference over pixels within `radius` of (cx, cy) —
    /// bitmap coordinates, top-left origin — or outside it when `inside` is false.
    private func largestDifference(_ a: [UInt8], _ b: [UInt8], cx: Int, cy: Int, radius: Int, inside: Bool) -> Int {
        var worst = 0
        for y in 0..<side { for x in 0..<side {
            let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            guard inside ? d2 <= radius * radius : d2 > (radius + 6) * (radius + 6) else { continue }
            let i = (y * side + x) * 4
            for c in 0..<3 { worst = max(worst, abs(Int(a[i + c]) - Int(b[i + c]))) }
        } }
        return worst
    }

    @Test func aStrokePutsBackItsFramesPixelsAndNothingElse() async throws {
        // AC-8: paint frame 0 at the top, where the stack took frame 1.
        let frames = bracket()
        let renderer = PhotoStackRenderer()
        let prepared = try await renderer.prepareFocusStack(images: frames)
        let stacked = await renderer.focusStack(prepared, options: .standard)
        let stroke = dab(frame: 0, x: 0.5, y: 0.2)
        let retouched = await renderer.retouched(stacked, prepared: prepared, strokes: [stroke])

        let after = try await pixels(retouched)
        let before = try await pixels(stacked)
        let source = try await pixels(frames[0])
        // The dab is 64 px wide centred at (128, 51); check its core.
        #expect(largestDifference(after, source, cx: 128, cy: 51, radius: 26, inside: true) <= 1)
        #expect(largestDifference(after, before, cx: 128, cy: 51, radius: 32, inside: false) <= 1)
        // And it did change something: the stack there was frame 1's.
        #expect(largestDifference(before, source, cx: 128, cy: 51, radius: 26, inside: true) > 1)
    }

    @Test func undoingEveryStrokeGivesBackTheStackPixelForPixel() async throws {
        // AC-9: three strokes, then taken away one at a time.
        let frames = bracket()
        let renderer = PhotoStackRenderer()
        let prepared = try await renderer.prepareFocusStack(images: frames)
        let stacked = await renderer.focusStack(prepared, options: .standard)
        let strokes = [dab(frame: 0, x: 0.3, y: 0.2), dab(frame: 1, x: 0.6, y: 0.8), dab(frame: 0, x: 0.5, y: 0.5)]

        var renders: [[UInt8]] = []
        for count in 0...strokes.count {
            renders.append(try await pixels(renderer.retouched(stacked, prepared: prepared, strokes: Array(strokes.prefix(count)))))
        }
        #expect(renders[0] == (try await pixels(stacked)))
        #expect(renders[1] != renders[0] && renders[2] != renders[1] && renders[3] != renders[2])
        // Undo is dropping the last stroke; each step back matches the render
        // from before that stroke was painted.
        var undone = strokes
        for count in stride(from: strokes.count - 1, through: 0, by: -1) {
            undone.removeLast()
            #expect(try await pixels(renderer.retouched(stacked, prepared: prepared, strokes: undone)) == renders[count])
        }
    }

    @Test func theFrameOfferedIsTheSharpestWhereTheUserTouched() async throws {
        // AC-10: top of the picture is frame 1's, bottom is frame 0's.
        let prepared = try await PhotoStackRenderer().prepareFocusStack(images: bracket())
        let renderer = PhotoStackRenderer()
        #expect(await renderer.sharpestFrame(in: prepared, at: NormalizedPoint(x: 0.5, y: 0.1)) == 1)
        #expect(await renderer.sharpestFrame(in: prepared, at: NormalizedPoint(x: 0.5, y: 0.9)) == 0)
    }

    @Test func strokesOnOneFrameShareAMask() {
        let strokes = [dab(frame: 2, x: 0.1, y: 0.1), dab(frame: 2, x: 0.2, y: 0.2), dab(frame: 0, x: 0.3, y: 0.3), dab(frame: 2, x: 0.4, y: 0.4)]
        #expect(PhotoStackRenderer.runs(strokes).map(\.frame) == [2, 0, 2])
        #expect(PhotoStackRenderer.runs(strokes).map(\.brushes.count) == [2, 1, 1])
    }

    @Test func aStrokeOnAFrameThatDidNotLineUpIsSkipped() async throws {
        let frames = bracket()
        let renderer = PhotoStackRenderer()
        var prepared = try await renderer.prepareFocusStack(images: frames)
        prepared.inputIndices = [0, 3]   // as if frames 1 and 2 had been left out
        let stacked = await renderer.focusStack(prepared, options: .standard)
        let retouched = await renderer.retouched(stacked, prepared: prepared, strokes: [dab(frame: 1, x: 0.5, y: 0.5)])
        #expect(try await pixels(retouched) == (try await pixels(stacked)))
    }
}
