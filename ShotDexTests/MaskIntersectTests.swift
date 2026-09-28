import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15d AC-40, AC-41 — a mask's areas: Add, Subtract, Intersect, in
/// list order.
struct MaskIntersectTests {

    static let size = 256
    static let blue: SIMD3<Float> = [0.1, 0.2, 0.9]
    static let yellow: SIMD3<Float> = [0.9, 0.85, 0.1]

    /// Grey, with a blue and a yellow square in both the top half and the
    /// bottom half.
    static func squares() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                var colour: SIMD3<Float> = [0.5, 0.5, 0.5]
                let inRow = (32..<96).contains(y) || (160..<224).contains(y)
                if inRow, (32..<96).contains(x) { colour = blue }
                if inRow, (160..<224).contains(x) { colour = yellow }
                let index = (y * size + x) * 4
                pixels[index] = colour.x
                pixels[index + 1] = colour.y
                pixels[index + 2] = colour.z
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: size * 16, size: CGSize(width: size, height: size),
                       format: .RGBAf, colorSpace: nil)
    }

    /// Mean of the matte over a square's inside, rows top-down like the
    /// picture above.
    static func mean(_ matte: CIImage, x: Range<Int>, y: Range<Int>) -> Float {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: size * size * 4)
        context.render(matte, toBitmap: &values, rowBytes: size * 16,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: nil)
        var sum: Float = 0, count: Float = 0
        for row in y { for column in x { sum += values[(row * size + column) * 4]; count += 1 } }
        return sum / count
    }

    /// Linear covering the top half, full strength above the middle.
    static func topHalf() -> PhotoMaskComponent {
        var linear = PhotoMaskComponent(kind: .linearGradient)
        linear.startPoint = NormalizedPoint(x: 0.5, y: 0.47)
        linear.endPoint = NormalizedPoint(x: 0.5, y: 0.53)
        return linear
    }

    static func blueRange(_ operation: MaskBlendOperation) -> PhotoMaskComponent {
        var range = PhotoMaskComponent(kind: .colorRange, operation: operation)
        range.sampledRed = Double(blue.x)
        range.sampledGreen = Double(blue.y)
        range.sampledBlue = Double(blue.z)
        return range
    }

    /// AC-40. Linear over the top half, then a Color Range on blue by
    /// Intersect: only the top blue square is left.
    @Test func intersectKeepsOnlyTheOverlap() async throws {
        var mask = PhotoMask(name: "Blue sky", component: Self.topHalf())
        mask.components.append(Self.blueRange(.intersect))
        let matte = try #require(try await PhotoRenderService().maskMatte(mask, over: Self.squares()))

        let topBlue = Self.mean(matte, x: 40..<88, y: 40..<88)
        let bottomBlue = Self.mean(matte, x: 40..<88, y: 168..<216)
        let topYellow = Self.mean(matte, x: 168..<216, y: 40..<88)
        #expect(topBlue >= 0.95, "top blue \(topBlue)")
        #expect(bottomBlue <= 0.05, "bottom blue \(bottomBlue)")
        #expect(topYellow <= 0.05, "top yellow \(topYellow)")
    }

    /// The editor side: Intersect area adds a second area to the picked
    /// mask, one undo step.
    @MainActor @Test func intersectAreaJoinsTheSelectedMask() throws {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.addMask(kind: .linearGradient)
        controller.addMaskArea(kind: .colorRange, operation: .intersect)
        let mask = try #require(controller.recipe.masks.first)
        #expect(controller.recipe.masks.count == 1)
        #expect(mask.components.map(\.operation) == [.add, .intersect])
        controller.undo()
        #expect(controller.recipe.masks.first?.components.count == 1)
    }
}
