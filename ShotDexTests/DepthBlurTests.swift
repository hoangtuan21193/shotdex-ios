import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDex

/// Portrait depth blur, against real pixels: the point of it is that the same
/// photo comes out sharp in one place and soft in another, which only a render
/// can show.
struct DepthBlurTests {

    private let side: CGFloat = 240

    /// Vertical black-and-white stripes, four pixels wide. Fine detail, so a
    /// blur is unmistakable in the numbers.
    private func stripedImage() -> CIImage {
        let context = CGContext(
            data: nil,
            width: Int(side),
            height: Int(side),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: Int(side), by: 8) {
            context.fill(CGRect(x: x, y: 0, width: 4, height: Int(side)))
        }
        return CIImage(cgImage: context.makeImage()!)
    }

    /// Near on the left half, far on the right, at a quarter of the photo's
    /// resolution — the size a real capture stores its map at.
    private func splitDisparity() -> CIImage {
        let mapSide = Int(side / 4)
        let context = CGContext(
            data: nil,
            width: mapSide,
            height: mapSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: mapSide / 2, height: mapSide))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: mapSide / 2, y: 0, width: mapSide / 2, height: mapSide))
        return CIImage(cgImage: context.makeImage()!)
    }

    /// How much light and dark differ across one row — high on crisp stripes,
    /// low once they smear together.
    private func stripeContrast(of image: CIImage, inLeftHalf: Bool) -> Double {
        let x = inLeftHalf ? 40 : Int(side) - 40
        var samples: [Double] = []
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        for offset in 0..<8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                image,
                toBitmap: &pixel,
                rowBytes: 4,
                bounds: CGRect(x: x + offset, y: Int(side) / 2, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
            samples.append(Double(pixel[0]) / 255)
        }
        return (samples.max() ?? 0) - (samples.min() ?? 0)
    }

    @Test func zeroLeavesThePhotoExactlyAsShot() {
        let input = stripedImage()
        let output = PhotoRenderService.applyDepthBlur(
            0,
            to: input,
            disparity: splitDisparity(),
            matte: nil
        )
        #expect(output === input)
    }

    /// A recipe carrying depth blur can be pasted onto a photo that has no
    /// depth. The right answer there is the photo as shot, not a refusal and
    /// not a guess.
    @Test func noDepthMapMeansNoBlur() {
        let input = stripedImage()
        let output = PhotoRenderService.applyDepthBlur(1, to: input, disparity: nil, matte: nil)
        #expect(output === input)
    }

    @Test func farSideBlursAndNearSideStaysSharp() {
        let input = stripedImage()
        let sharpBefore = stripeContrast(of: input, inLeftHalf: false)
        #expect(sharpBefore > 0.5)

        let output = PhotoRenderService.applyDepthBlur(
            1,
            to: input,
            disparity: splitDisparity(),
            matte: nil
        )
        let far = stripeContrast(of: output, inLeftHalf: false)
        let near = stripeContrast(of: output, inLeftHalf: true)
        #expect(far < sharpBefore, "the far half should have lost stripe contrast")
        #expect(near > far, "the near half should stay sharper than the far half")
    }

    @Test func outputKeepsThePhotosFrame() {
        let input = stripedImage()
        let output = PhotoRenderService.applyDepthBlur(
            0.5,
            to: input,
            disparity: splitDisparity(),
            matte: nil
        )
        #expect(output.extent == input.extent)
    }

    /// The Depth Blur row exists only for photos that carry depth, and only
    /// outside a mask — a mask already limits where an adjustment lands, and
    /// depth blur has its own idea about that.
    @Test func catalogOffersDepthBlurOnlyForDepthPhotos() {
        let withDepth = EditorAdjustmentCatalog.groups(
            isRAWSource: false, scope: .global, hasDepth: true
        )
        let without = EditorAdjustmentCatalog.groups(
            isRAWSource: false, scope: .global, hasDepth: false
        )
        let masked = EditorAdjustmentCatalog.groups(
            isRAWSource: false, scope: .mask, hasDepth: true
        )
        #expect(withDepth.first { $0.id == .effects }?.kinds.first == .depthBlur)
        #expect(without.first { $0.id == .effects }?.kinds.contains(.depthBlur) == false)
        #expect(masked.first { $0.id == .effects }?.kinds.contains(.depthBlur) == false)
    }
}
