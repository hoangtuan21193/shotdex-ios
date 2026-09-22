import CoreImage
import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// FS-03.11 AC-1 and AC-3 — the Heal tool.
struct PhotoHealingTests {
    private let size = 256

    /// A sky that brightens toward the top and a little to the right, with or
    /// without a dust speck — a soft dark blob — in the middle.
    private func sky(dust: Bool) -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let t = Float(y) / Float(size - 1), u = Float(x) / Float(size - 1)
                var r = 0.35 + 0.4 * t + 0.03 * u
                var g = 0.45 + 0.35 * t + 0.02 * u
                var b = 0.7 + 0.2 * t
                if dust {
                    let dx = Float(x - 128), dy = Float(y - 128)
                    let speck = 0.2 * exp(-(dx * dx + dy * dy) / 32)
                    r -= speck; g -= speck; b -= speck
                }
                let index = (y * size + x) * 4
                pixels[index] = r
                pixels[index + 1] = g
                pixels[index + 2] = b
            }
        }
        return CIImage(
            bitmapData: pixels.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: size * 16,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    private func pixels(_ image: CIImage) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixels = [Float](repeating: 0, count: size * size * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: size * 16,
            bounds: CGRect(x: 0, y: 0, width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
        return pixels
    }

    /// Mean error inside the spot and the worst error anywhere near it, in
    /// 8-bit steps, against the sky without the speck.
    private func error(of image: CIImage, radius: Float) -> (mean: Float, worst: Float) {
        let clean = pixels(sky(dust: false))
        let healed = pixels(image)
        var sum: Float = 0, count: Float = 0, worst: Float = 0
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x - 128), dy = Float(y - 128)
                let distance = (dx * dx + dy * dy).squareRoot()
                let index = (y * size + x) * 4
                let difference = (0..<3).map { abs(healed[index + $0] - clean[index + $0]) }
                    .reduce(0, +) / 3 * 255
                if distance <= radius { sum += difference; count += 1 }
                if distance <= radius * 1.8 { worst = max(worst, difference) }
            }
        }
        return (sum / count, worst)
    }

    /// A 12px spot in a 256px frame, at the centre. Top-left origin, like a tap.
    private func spot(mode: PhotoHealingMode, sourceX: Double, sourceY: Double) -> PhotoHealingSpot {
        PhotoHealingSpot(
            mode: mode,
            center: NormalizedPoint(x: 0.5, y: 0.5),
            source: NormalizedPoint(x: sourceX, y: sourceY),
            radius: 12.0 / 256,
            feather: 0.5
        )
    }

    /// AC-1. The speck is gone to within 2/255 on average, with no edge.
    @Test(arguments: [(0.62, 0.5), (0.5, 0.35), (0.39, 0.65)])
    func healMatchesTheSurroundingSky(sourceX: Double, sourceY: Double) {
        let dusty = sky(dust: true)
        #expect(error(of: dusty, radius: 12).mean > 5, "the speck is there to begin with")

        let healed = PhotoRenderService.applyHealing(
            [spot(mode: .heal, sourceX: sourceX, sourceY: sourceY)],
            to: dusty
        )
        let measured = error(of: healed, radius: 12)
        #expect(measured.mean <= 2, "mean \(measured.mean)/255")
        #expect(measured.worst <= 3, "no hard edge: worst \(measured.worst)/255")
    }

    /// Clone copies the source as it is, so from paler sky it shows — which is
    /// the reason Heal exists.
    @Test func cloneFromDifferentGroundShows() {
        let cloned = PhotoRenderService.applyHealing(
            [spot(mode: .clone, sourceX: 0.5, sourceY: 0.35)],
            to: sky(dust: true)
        )
        #expect(error(of: cloned, radius: 12).mean > 4)
    }

    @Test func suggestedSourceSitsBesideTheSpot() {
        let near = PhotoHealingSpot.suggestedSource(
            for: NormalizedPoint(x: 0.5, y: 0.4),
            radius: 0.03,
            aspectRatio: 1.5
        )
        #expect(near.y == 0.4)
        #expect(near.x > 0.5)
        // At the right edge it goes the other way instead of leaving the frame.
        let edge = PhotoHealingSpot.suggestedSource(
            for: NormalizedPoint(x: 0.97, y: 0.4),
            radius: 0.03,
            aspectRatio: 1.5
        )
        #expect(edge.x < 0.97)
    }

    @Test func healingRoundTripsAndDropsUnknownModes() throws {
        var recipe = PhotoEditRecipe()
        recipe.healing = [spot(mode: .heal, sourceX: 0.6, sourceY: 0.5)]
        #expect(!recipe.isIdentity)
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(PhotoEditRecipe.self, from: data).healing == recipe.healing)

        var json = try #require(String(data: data, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"heal\"", with: "\"future-mode\"")
        let degraded = try JSONDecoder().decode(PhotoEditRecipe.self, from: Data(json.utf8))
        #expect(degraded.healing.isEmpty, "the unreadable spot is dropped, not the recipe")
    }

    /// AC-3. Healing belongs to one frame: Copy Edits, Paste, Sync Look and a
    /// saved look never carry it, and pasting leaves the target's own spots.
    @MainActor @Test func healingIsNeverCopied() {
        var source = PhotoEditRecipe()
        source.adjustments.exposure = 0.5
        source.healing = [spot(mode: .heal, sourceX: 0.6, sourceY: 0.5)]
        var target = PhotoEditRecipe()
        let ownSpot = spot(mode: .clone, sourceX: 0.3, sourceY: 0.3)
        target.healing = [ownSpot]

        #expect(EditClipboard.look(of: source).healing.isEmpty)
        #expect(EditorSyncScope.look.apply(source, onto: target).healing == [ownSpot])

        let defaults = UserDefaults(suiteName: "PhotoHealingTests-\(UUID().uuidString)")!
        let clipboard = EditClipboard(defaults: defaults)
        clipboard.copy(from: source)
        let pasted = clipboard.paste(onto: target)
        #expect(pasted.healing == [ownSpot])
        #expect(pasted.adjustments.exposure == 0.5)
    }
}
