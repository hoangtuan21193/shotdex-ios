import CoreImage
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15b AC-20, AC-21 — the manual lens corrections under Optics › MANUAL.
struct LensManualTests {

    private static let width = 240
    private static let height = 160
    private static var halfDiagonal: Double {
        (Double(width * width + height * height)).squareRoot() / 2
    }

    /// Black with two 3×3 white dots: one at the centre, one on the
    /// up-right diagonal at 0.8 of the half-diagonal.
    private static func dots() -> CIImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let centre = (x: Double(width) / 2, y: Double(height) / 2)
        let reach = 0.8 * halfDiagonal
        let angle = atan2(Double(height), Double(width))
        let far = (x: centre.x + reach * cos(angle), y: centre.y + reach * sin(angle))
        for point in [centre, far] {
            let cx = Int(point.x.rounded(.down)), cy = Int(point.y.rounded(.down))
            for y in (cy - 1)...(cy + 1) {
                for x in (cx - 1)...(cx + 1) {
                    let index = (y * width + x) * 4
                    pixels[index] = 1
                    pixels[index + 1] = 1
                    pixels[index + 2] = 1
                }
            }
        }
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 1 }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private static func pixels(of image: CIImage) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: width * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf,
            colorSpace: nil
        )
        return pixels
    }

    /// Brightness-weighted centre of the dot nearest `near`, in pixels from
    /// the frame's centre.
    private static func dotOffset(in image: CIImage, near: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let values = pixels(of: image)
        var total = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) + 0.5 - Double(width) / 2
                let dy = Double(y) + 0.5 - Double(height) / 2
                guard abs(dx - near.x) < 12, abs(dy - near.y) < 12 else { continue }
                let weight = Double(values[(y * width + x) * 4])
                total += weight
                sx += weight * dx
                sy += weight * dy
            }
        }
        return total > 0 ? (sx / total, sy / total) : (.nan, .nan)
    }

    private static func manual(_ distortion: Double) -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe()
        recipe.adjustments.lensManualDistortion = distortion
        return recipe
    }

    private static func source(isRAW: Bool) -> PhotoRenderSourceInfo {
        PhotoRenderSourceInfo(
            url: URL(fileURLWithPath: "/dev/null"),
            type: isRAW ? .rawImage : .jpeg,
            pixelWidth: width,
            pixelHeight: height,
            orientation: .up,
            isRAW: isRAW,
            properties: [:]
        )
    }

    private static let jpeg = source(isRAW: false)

    /// AC-20. Distortion +50 straightens barrel: a point at 0.8 of the
    /// half-diagonal moves 0.3%…1.5% of it, outward; the centre stays; no
    /// corner samples outside the photo.
    @Test func distortionPullsTheEdgesIn() {
        let input = Self.dots()
        let output = PhotoRenderService.applyLensProfile(of: Self.manual(0.5), source: Self.jpeg, to: input)

        let angle = atan2(Double(Self.height), Double(Self.width))
        let guess = (x: 0.8 * Self.halfDiagonal * cos(angle), y: 0.8 * Self.halfDiagonal * sin(angle))
        let before = Self.dotOffset(in: input, near: guess)
        let after = Self.dotOffset(in: output, near: guess)
        let move = ((after.x * after.x + after.y * after.y).squareRoot()
            - (before.x * before.x + before.y * before.y).squareRoot()) / Self.halfDiagonal
        #expect(move >= 0.003 && move <= 0.015, "point at 0.8 moved \(move) of the half-diagonal")

        let centre = Self.dotOffset(in: output, near: (0, 0))
        let original = Self.dotOffset(in: input, near: (0, 0))
        #expect(abs(centre.x - original.x) < 0.05 && abs(centre.y - original.y) < 0.05)
    }

    /// Either direction, the corners sample inside the photo: straightening
    /// barrel needs no zoom, straightening pincushion zooms just enough.
    @Test func neitherDirectionShowsEmptyCorners() {
        let extent = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let identity = LensDistortionTerm(model: .poly3, focal: 0, k1: 0)
        for distortion in [1.0, 0.5, -0.5, -1.0] {
            let manual = PhotoRenderService.manualDistortionCoefficient(distortion)
            let zoom = PhotoRenderService.fillZoom(identity, manual: manual, extent: extent, norm: 100)
            // The corner, ρ = 1 before the zoom, samples at 1 · (1 − m/zoom²) / zoom.
            let rho = 1 / zoom
            let sampled = (1 - manual * rho * rho) / zoom
            // The zoom is a six-step fixed-point iteration: 1e-6 of the
            // half-diagonal is a thousandth of a pixel on a 24MP frame.
            #expect(sampled <= 1 + 1e-6, "Distortion \(distortion): corner samples at \(sampled)")
        }
        #expect(PhotoRenderService.fillZoom(identity, manual: PhotoRenderService.manualDistortionCoefficient(1), extent: extent, norm: 100) == 1)
        #expect(PhotoRenderService.fillZoom(identity, manual: PhotoRenderService.manualDistortionCoefficient(-1), extent: extent, norm: 100) > 1)
    }

    /// RAW gets the manual correction too: the decoder corrects its own lens
    /// profile, not a Distortion the photographer dialled in.
    @Test func rawSourcesGetTheManualCorrection() {
        let input = Self.dots()
        let raw = Self.source(isRAW: true)
        let output = PhotoRenderService.applyLensProfile(of: Self.manual(0.5), source: raw, to: input)
        #expect(output !== input)
        #expect(PhotoRenderService.applyLensProfile(of: PhotoEditRecipe(), source: raw, to: input) === input)
    }

    /// E14. The row sits under MANUAL and says so to VoiceOver.
    @Test func distortionRowNamesItsGroup() {
        let groups = EditorAdjustmentCatalog.groups(isRAWSource: false, scope: .global)
        let manual = groups.first { $0.id == .lensManual }
        #expect(manual?.title == "Manual")
        #expect(manual?.kinds.contains(.lensManualDistortion) == true)
        #expect(EditorAdjustmentCatalog.shortTitle(of: .lensManualDistortion) == "Distortion")
        #expect(EditorAdjustmentCatalog.accessibilityName(of: .lensManualDistortion) == "Distortion, Manual")
        #expect(EditorAdjustmentCatalog.isBipolar(.lensManualDistortion))
    }
}
