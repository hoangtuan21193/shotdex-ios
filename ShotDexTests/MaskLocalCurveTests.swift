import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15d AC-44 — a mask's own curve.
struct MaskLocalCurveTests {

    static let softS = ToneCurveAdjustments.presets.first { $0.id == "softS" }!.points

    /// The left half, full strength left of the middle.
    static func leftHalf() -> PhotoMask {
        var linear = PhotoMaskComponent(kind: .linearGradient)
        linear.startPoint = NormalizedPoint(x: 0.45, y: 0.5)
        linear.endPoint = NormalizedPoint(x: 0.55, y: 0.5)
        return PhotoMask(name: "Left", component: linear)
    }

    /// AC-44. Mid grey, a global Soft S, and a mask on the left half whose
    /// curve pins 0.5 to 0.4: the left half comes out at 0.4 (± 2/255 plus
    /// the 8-bit step), the right half exactly as with Soft S alone.
    @Test func maskCurveOnlyInside() async throws {
        let file = try MaskLocalColorTests.flatFile(red: 128, green: 128, blue: 128)
        defer { try? FileManager.default.removeItem(at: file) }
        var base = PhotoEditRecipe()
        base.curve.rgb = Self.softS
        base.masks = [Self.leftHalf()]
        var edited = base
        var maskCurve = ToneCurveAdjustments.identity
        maskCurve.rgb = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.4), CurvePoint(x: 1, y: 1)]
        edited.masks[0].curve = maskCurve

        let without = try await MaskLocalColorTests.render(base, file: file)
        let with = try await MaskLocalColorTests.render(edited, file: file)
        let size = MaskLocalColorTests.size

        let left = (128 * size + 32) * 4
        let expected = 0.4 * 255 * (128.0 / 255 / 0.5)
        #expect(abs(Double(with[left]) - 0.4 * 255) <= 3, "left half \(with[left]), wanted ~\(Int(expected))")

        var worst = 0
        for y in 100..<156 {
            for x in 200..<250 {
                let index = (y * size + x) * 4
                worst = max(worst, abs(Int(with[index]) - Int(without[index])))
            }
        }
        #expect(worst <= 1, "right half moved \(worst)/255")
    }

    /// The editor side: Edit Curve points the curve editor at the mask, the
    /// photo's curve stays as it was, and an identity mask curve writes no key.
    @MainActor @Test func editCurveWritesTheMaskCurve() throws {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.addMask(kind: .radialGradient)
        controller.curveTargetMaskID = controller.selectedMaskID
        controller.setCurve([CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.4), CurvePoint(x: 1, y: 1)], for: .rgb)
        #expect(controller.recipe.curve.isIdentity)
        #expect(controller.recipe.masks.first?.curve?.rgb.count == 3)
        controller.resetAllCurves()
        #expect(controller.recipe.masks.first?.curve == nil)
    }
}
