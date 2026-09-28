import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

@MainActor
struct EditClipboardTests {

    private func makeClipboard() -> EditClipboard {
        let defaults = UserDefaults(suiteName: "EditClipboardTests-\(UUID().uuidString)")!
        return EditClipboard(defaults: defaults)
    }

    private func lookRecipe() -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.4
        recipe.adjustments.contrast = -0.2
        recipe.filter = .original
        recipe.filterIntensity = 0.6
        return recipe
    }

    @Test func copyingCarriesTheLook() {
        let clipboard = makeClipboard()
        clipboard.copy(from: lookRecipe())

        let pasted = clipboard.paste(onto: .identity)
        #expect(pasted.adjustments.exposure == 0.4)
        #expect(pasted.adjustments.contrast == -0.2)
        #expect(pasted.filterIntensity == 0.6)
    }

    /// Crop, masks, the drawing and the overlays belong to one frame. Pasting a
    /// crop would reframe a photo the user never framed; pasting a mask would
    /// brighten a region that on this photo is somebody's face.
    @Test func pastingLeavesFramingAndLayersAlone() {
        let clipboard = makeClipboard()
        var copied = lookRecipe()
        copied.crop.rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        copied.overlays = [PhotoOverlay.shape(.oval)]
        clipboard.copy(from: copied)

        var target = PhotoEditRecipe.identity
        target.crop.rect = NormalizedRect(x: 0, y: 0, width: 0.8, height: 0.8)
        let pasted = clipboard.paste(onto: target)

        #expect(pasted.crop.rect == target.crop.rect)
        #expect(pasted.overlays.isEmpty)
        #expect(pasted.adjustments.exposure == 0.4)
    }

    /// A copied identity is not worth offering: the paste would do nothing.
    /// FS-03.15 AC-2. Calibration and the region curve travel with the look;
    /// retouch spots, Red Eye and the Upright guides stay on photo A. Sync Look
    /// and a saved look cut the same way, because they are the same function.
    @Test func parityLookSlice() {
        var a = PhotoEditRecipe.identity
        a.color.calibration.redHue = 0.3
        a.curve.region.shadows = 0.4
        a.color.grayMixer.blue = -0.5
        a.vignetteStyle = .colorPriority
        a.healing = [
            PhotoHealingSpot(center: NormalizedPoint(x: 0.3, y: 0.3), source: NormalizedPoint(x: 0.5, y: 0.3)),
            PhotoHealingSpot(center: NormalizedPoint(x: 0.6, y: 0.6), source: NormalizedPoint(x: 0.4, y: 0.6)),
        ]
        a.redEyes = [PhotoRedEyeSpot(center: NormalizedPoint(x: 0.45, y: 0.4), radius: 0.01)]
        a.upright.mode = .guided
        a.upright.guides = [
            PhotoUprightGuide(start: NormalizedPoint(x: 0.2, y: 0.1), end: NormalizedPoint(x: 0.21, y: 0.9)),
        ]
        a.upright.solved.vertical = 0.2
        a.lensBlur.amount = 0.5

        let clipboard = makeClipboard()
        clipboard.copy(from: a)
        let b = clipboard.paste(onto: .identity)

        #expect(b.color.calibration.redHue == 0.3)
        #expect(b.curve.region.shadows == 0.4)
        #expect(b.color.grayMixer.blue == -0.5)
        #expect(b.vignetteStyle == .colorPriority)
        #expect(b.healing.isEmpty)
        #expect(b.redEyes.isEmpty)
        #expect(b.upright.guides.isEmpty)
        #expect(b.upright.solved.isIdentity, "the solved transform is re-solved on B, not copied")
        #expect(b.upright.mode == .guided)
        #expect(b.lensBlur.isIdentity)

        #expect(EditorSyncScope.look.apply(a, onto: .identity) == b)
        #expect(EditClipboard.look(of: a) == b)
    }

    /// A 256² grey frame ruled with five parallel lines at `tilt`°, plus a
    /// pair of side edges leaning in by `lean`° each — a building.
    private func building(tilt: Double, lean: Double) -> CIImage {
        let size = 256
        var pixels = [Float](repeating: 0.12, count: size * size)
        func draw(degrees: Double, through centre: (x: Double, y: Double)) {
            let radians = degrees * .pi / 180
            for step in 0...(size * 3) {
                let t = (Double(step) / Double(size * 3) - 0.5) * Double(size)
                let x = centre.x + cos(radians) * t
                let y = centre.y - sin(radians) * t
                for dx in -1...1 {
                    for dy in -1...1 {
                        let px = Int(x.rounded()) + dx, py = Int(y.rounded()) + dy
                        guard px >= 0, px < size, py >= 0, py < size else { continue }
                        pixels[py * size + px] = 0.95
                    }
                }
            }
        }
        for line in 0..<5 {
            draw(degrees: tilt, through: (128, 128 + Double(line - 2) * 36))
        }
        draw(degrees: 90 - lean + tilt, through: (30, 128))
        draw(degrees: 90 + lean + tilt, through: (226, 128))
        var rgba = [Float](repeating: 1, count: size * size * 4)
        for (index, value) in pixels.enumerated() {
            rgba[index * 4] = value
            rgba[index * 4 + 1] = value
            rgba[index * 4 + 2] = value
        }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: size, height: size),
            format: .RGBAf,
            colorSpace: nil
        )
    }

    /// FS-03.15b AC-28. Photo A carries Upright Auto solved on A. Pasted onto
    /// B, a different building, B gets the mode and a transform solved on B's
    /// own lines — not A's. Level reads the horizon with Vision, which runs
    /// on the simulator too (measured 2026-09-28: 2.87° read for a drawn 3°).
    @Test func uprightModeIsResolvedOnTheTarget() throws {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var a = PhotoEditRecipe.identity
        a.upright.mode = .auto
        a = UprightResolver.resolve(a, on: building(tilt: -5, lean: 5), context: context)
        #expect(!a.upright.solved.isIdentity, "A solved on A")

        let clipboard = makeClipboard()
        clipboard.copy(from: a)
        let pasted = clipboard.paste(onto: .identity)
        #expect(pasted.upright.mode == .auto)
        #expect(pasted.upright.needsSolving)

        let b = UprightResolver.resolve(pasted, on: building(tilt: 3, lean: 3), context: context)
        #expect(b.upright.mode == .auto)
        #expect(!b.upright.solved.isIdentity)
        #expect(b.upright.solved != a.upright.solved, "B's transform is B's own")
        #expect(b.upright.solved.rotate * 3 < 0, "B's 3° tilt is corrected the other way")
        let applied = b.upright.solved.rotate * 0.35 * 180 / .pi
        #expect(abs(applied + 3) <= 0.5, "B's 3° met with \(applied)°")
        #expect(b.upright.solved.vertical != 0, "B's own convergence is straightened too")

        // Already solved: nothing is solved again.
        #expect(UprightResolver.resolve(b, on: building(tilt: -5, lean: 5), context: context) == b)
    }

    /// FS-03.16 AC-3. A (embedded data, 50/100/150) pasted onto B (its own
    /// Lensfun lens): B gets the strengths and keeps its own source.
    @Test func pasteCarriesStrengthsKeepsTargetLensSource() {
        var a = PhotoEditRecipe.identity
        a.adjustments.lensDistortionScale = 0.5
        a.adjustments.lensVignettingScale = 1
        a.adjustments.lensChromaticAberrationScale = 1.5
        a.lensProfile = PhotoLensProfileChoice(
            lensID: nil, cameraCropFactor: 1, isAutomatic: true,
            distortionSource: .embedded, vignettingSource: .embedded, chromaticAberrationSource: .embedded
        )
        var b = PhotoEditRecipe.identity
        let bLens = PhotoLensProfileChoice(lensID: "Canon|Canon EF 24-70mm f/2.8L II USM|1.0", cameraCropFactor: 1, isAutomatic: true)
        b.lensProfile = bLens
        let clipboard = makeClipboard()
        clipboard.copy(from: a)
        let pasted = clipboard.paste(onto: b)
        #expect(pasted.adjustments.lensDistortionScale == 0.5)
        #expect(pasted.adjustments.lensChromaticAberrationScale == 1.5)
        #expect(pasted.lensProfile == bLens)
    }

    /// FS-03.16 §4 (E18). Sync "Everything" keeps each target's own lens
    /// profile and still carries the strengths and the switch.
    @Test func syncEverythingKeepsTargetLensProfile() {
        var a = PhotoEditRecipe.identity
        a.adjustments.lensDistortionScale = 1.8
        a.adjustments.lensCorrection = 0
        a.lensProfile = PhotoLensProfileChoice(lensID: "Sony|FE 24-70mm F2.8 GM II|1.0", cameraCropFactor: 1, isAutomatic: true)
        var b = PhotoEditRecipe.identity
        b.lensProfile = PhotoLensProfileChoice(lensID: "Canon|Canon EF 24-70mm f/2.8L II USM|1.0", cameraCropFactor: 1, isAutomatic: false)
        let synced = EditorSyncScope.everything.apply(a, onto: b)
        #expect(synced.lensProfile == b.lensProfile)
        #expect(synced.adjustments.lensDistortionScale == 1.8 && synced.adjustments.lensCorrection == 0)
    }

    @Test func copyingNothingOffersNothing() {
        let clipboard = makeClipboard()
        clipboard.copy(from: .identity)
        #expect(!clipboard.hasContent)

        clipboard.copy(from: lookRecipe())
        #expect(clipboard.hasContent)
    }

    @Test func theClipboardSurvivesALaunch() {
        let suite = "EditClipboardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        EditClipboard(defaults: defaults).copy(from: lookRecipe())

        let reopened = EditClipboard(defaults: defaults)
        #expect(reopened.hasContent)
        #expect(reopened.paste(onto: .identity).adjustments.exposure == 0.4)
    }

    @Test func pastingWithAnEmptyClipboardChangesNothing() {
        let clipboard = makeClipboard()
        var target = PhotoEditRecipe.identity
        target.adjustments.exposure = 1
        #expect(clipboard.paste(onto: target) == target)
    }
}
