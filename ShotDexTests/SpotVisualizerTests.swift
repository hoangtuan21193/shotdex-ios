import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15c AC-33 — Visualize Spots is a way of looking, not an edit.
struct SpotVisualizerTests {

    private static let size = 128

    /// Mid grey with five faint dust specks.
    private static func dusty() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        let specks = [(20, 30), (60, 64), (100, 20), (40, 100), (96, 96)]
        for y in 0..<size {
            for x in 0..<size {
                var value: Float = 0.55
                for (sx, sy) in specks {
                    let d = Float((x - sx) * (x - sx) + (y - sy) * (y - sy))
                    value -= 0.04 * exp(-d / 4)
                }
                let index = (y * size + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: size * 16, size: CGSize(width: size, height: size),
                       format: .RGBAf, colorSpace: nil)
    }

    private static func whiteCount(_ image: CIImage) -> Int {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: size * size * 4)
        context.render(image, toBitmap: &values, rowBytes: size * 16,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: nil)
        return stride(from: 0, to: values.count, by: 4).filter { values[$0] > 0.5 }.count
    }

    /// AC-33, the map: higher Threshold is more sensitive — more white — and
    /// the specks show at a middling setting.
    @Test func thresholdControlsSensitivity() {
        let high = Self.whiteCount(SpotVisualizer.map(of: Self.dusty(), threshold: 0.8))
        let low = Self.whiteCount(SpotVisualizer.map(of: Self.dusty(), threshold: 0.2))
        #expect(high > low, "Threshold 80: \(high) white, 20: \(low)")
        #expect(high > 0)
    }

    /// AC-33, the save: turning Visualize on changes nothing that is saved —
    /// the recipe, which is all a save renders, stays exactly as it was — and
    /// leaving Heal turns it off.
    @MainActor @Test func visualizeIsDisplayOnly() {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.selectedTool = .heal
        controller.addHealingSpot(at: NormalizedPoint(x: 0.4, y: 0.4))
        let before = controller.recipe
        controller.isVisualizingSpots = true
        controller.spotVisualizeThreshold = 0.8
        #expect(controller.recipe == before)
        controller.selectedTool = .adjust
        #expect(!controller.isVisualizingSpots)
    }
}
