import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15b AC-19 — purple and green Defringe act at high-contrast edges
/// only, each on its own hue band.
struct DefringeTests {

    private static let size = 96
    /// The black/white step every fringe sits on.
    private static let stepX = 40

    private static func colour(hue: Double, saturation: Double, value: Double) -> SIMD3<Float> {
        let h = hue / 60
        let c = value * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return SIMD3(Float(r + m), Float(g + m), Float(b + m))
    }

    static let purple = colour(hue: 290, saturation: 0.6, value: 0.6)
    static let green = colour(hue: 120, saturation: 0.6, value: 0.6)

    /// A black/white step down the frame. The top half's step carries a 2px
    /// purple fringe, the bottom half's a 2px green one; a flat purple
    /// square sits on the white, far from the step.
    private static func frame() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                var rgb: SIMD3<Float> = x < stepX ? [0.05, 0.05, 0.05] : [0.95, 0.95, 0.95]
                if x == stepX || x == stepX + 1 {
                    rgb = y < size / 2 ? purple : green
                }
                if (68..<92).contains(x), (8..<32).contains(y) {
                    rgb = purple
                }
                let index = (y * size + x) * 4
                pixels[index] = rgb.x
                pixels[index + 1] = rgb.y
                pixels[index + 2] = rgb.z
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private static func rgb(of image: CIImage, in rect: CGRect) -> [SIMD3<Float>] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let width = Int(rect.width), height = Int(rect.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: rect,
            format: .RGBAf,
            colorSpace: nil
        )
        return stride(from: 0, to: pixels.count, by: 4).map {
            SIMD3(pixels[$0], pixels[$0 + 1], pixels[$0 + 2])
        }
    }

    /// Mean of max − min over the rect: how coloured it is.
    private static func chroma(of image: CIImage, in rect: CGRect) -> Float {
        let values = rgb(of: image, in: rect).map { $0.max() - $0.min() }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func largestChange(_ a: CIImage, _ b: CIImage, in rect: CGRect) -> Float {
        let pairs = zip(rgb(of: a, in: rect), rgb(of: b, in: rect))
        return pairs.map { (first: SIMD3<Float>, second: SIMD3<Float>) -> Float in
            let difference: SIMD3<Float> = first - second
            return max(abs(difference.x), abs(difference.y), abs(difference.z))
        }.max() ?? 1
    }

    // Core Image's origin is bottom-left: the top half of the pixel array
    // (purple fringe) is at high y.
    private static let purpleFringe = CGRect(x: stepX, y: 56, width: 2, height: 32)
    private static let greenFringe = CGRect(x: stepX, y: 8, width: 2, height: 32)
    private static let flatPurple = CGRect(x: 74, y: 70, width: 12, height: 12)

    /// AC-19. Purple Amount 10 clears the purple fringe on the step and
    /// leaves the green fringe and the flat purple square alone.
    @Test func purpleOnlyAtEdges() {
        let input = Self.frame()
        var adjustments = PhotoAdjustments()
        adjustments.defringePurpleAmount = 0.5
        let output = PhotoRenderService.applyDefringe(adjustments, to: input)

        let before = Self.chroma(of: input, in: Self.purpleFringe)
        let after = Self.chroma(of: output, in: Self.purpleFringe)
        #expect(after <= before * 0.3, "purple fringe chroma \(before) → \(after)")

        let green = Self.largestChange(input, output, in: Self.greenFringe)
        #expect(green <= 2.0 / 255, "green fringe moved \(green)")
        let flat = Self.largestChange(input, output, in: Self.flatPurple)
        #expect(flat <= 2.0 / 255, "flat purple moved \(flat)")
    }

    /// The green band clears the green fringe the same way, and leaves the
    /// purple one.
    @Test func greenOnlyOnItsBand() {
        let input = Self.frame()
        var adjustments = PhotoAdjustments()
        adjustments.defringeGreenAmount = 0.5
        let output = PhotoRenderService.applyDefringe(adjustments, to: input)

        let before = Self.chroma(of: input, in: Self.greenFringe)
        let after = Self.chroma(of: output, in: Self.greenFringe)
        #expect(after <= before * 0.3, "green fringe chroma \(before) → \(after)")
        #expect(Self.largestChange(input, output, in: Self.purpleFringe) <= 2.0 / 255)
    }

    /// Amount 0 is the untouched frame, whatever the hue rows say.
    @Test func noAmountIsNoChange() {
        let input = Self.frame()
        var adjustments = PhotoAdjustments()
        adjustments.defringePurpleHueMinimum = 0
        adjustments.defringePurpleHueMaximum = 1
        #expect(PhotoRenderService.applyDefringe(adjustments, to: input) === input)
    }

    /// The amount reads on Lightroom's 0…20 scale, the hue rows on 0…100.
    @Test func rowsReadOnLightroomScales() {
        #expect(EditorAdjustmentCatalog.displayText(0.5, of: .defringePurpleAmount) == "10")
        #expect(EditorAdjustmentCatalog.value(fromDisplayText: "10", of: .defringeGreenAmount) == 0.5)
        #expect(EditorAdjustmentCatalog.displayText(0.3, of: .defringePurpleHueMinimum) == "30")
        #expect(EditorAdjustmentCatalog.parentKind(of: .defringeGreenHueMaximum) == .defringeGreenAmount)
        #expect(PhotoAdjustments().isIdentity)
    }

    /// Min above Max, or closer than 10 apart, still gives a band at least
    /// 10 wide — the rows cannot cross into nothing.
    @Test func hueBandKeepsItsMinimumWidth() {
        let crossed = PhotoRenderService.defringeHueBand(minimum: 0.7, maximum: 0.3)
        #expect(crossed.lowerBound == 0.3 && crossed.upperBound == 0.7)
        let pinched = PhotoRenderService.defringeHueBand(minimum: 0.5, maximum: 0.52)
        let width: Double = pinched.upperBound - pinched.lowerBound
        let centre: Double = (pinched.upperBound + pinched.lowerBound) / 2
        #expect(abs(width - 0.1) < 1e-9)
        #expect(abs(centre - 0.51) < 1e-9)
    }
}
