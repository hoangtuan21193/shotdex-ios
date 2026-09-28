import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15c AC-35…AC-38 — Red Eye. Synthetic eyes only: no test here uses a
/// photo of a real face.
struct RedEyeTests {

    private static let size = 1024
    private static let pupilRadius = 12.0
    private static let irisRadius = 30.0
    private static let red: SIMD3<Float> = [220 / 255, 40 / 255, 40 / 255]
    private static let iris: SIMD3<Float> = [0.35, 0.25, 0.18]

    /// Grey, with one eye at the centre: a brown iris around a red pupil.
    private static func eye() -> CIImage {
        var pixels = [Float](repeating: 1, count: size * size * 4)
        let centre = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let d = hypot(Double(x) + 0.5 - centre, Double(y) + 0.5 - centre)
                let colour: SIMD3<Float> = d <= pupilRadius ? red : d <= irisRadius ? iris : [0.5, 0.5, 0.5]
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

    private static func pixels(_ image: CIImage) -> [Float] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var values = [Float](repeating: 0, count: size * size * 4)
        context.render(image, toBitmap: &values, rowBytes: size * 16,
                       bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBAf, colorSpace: nil)
        return values
    }

    /// The pupil Vision would report for the drawn eye.
    private static let pupil = RedEyeLocator.Pupil(
        center: NormalizedPoint(x: 0.5, y: 0.5),
        eyeWidth: irisRadius * 2 / Double(size)
    )

    /// AC-35. A tap 20px off the pupil lands on it, within 2px; inside the
    /// pupil red drops to within 10/255 of green and blue; the iris is left
    /// within 2/255.
    @MainActor @Test func tapCentresOnThePupil() throws {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.isRedEyeMode = true
        let tap = NormalizedPoint(x: 0.5 + 20 / Double(Self.size), y: 0.5)
        controller.addRedEye(at: tap, pupils: [Self.pupil])
        let spot = try #require(controller.recipe.redEyes.first)
        let offBy = hypot(spot.center.x - 0.5, spot.center.y - 0.5) * Double(Self.size)
        #expect(offBy <= 2, "spot centre \(offBy)px from the pupil")

        let input = Self.eye()
        let before = Self.pixels(input)
        let after = Self.pixels(PhotoRenderService.applyRedEyes([spot], to: input))
        let centre = Double(Self.size) / 2
        var worstRed: Float = 0, worstIris: Float = 0
        for y in 0..<Self.size {
            for x in 0..<Self.size {
                let d = hypot(Double(x) + 0.5 - centre, Double(y) + 0.5 - centre)
                let index = (y * Self.size + x) * 4
                if d <= Self.pupilRadius - 1.5 {
                    worstRed = max(worstRed, after[index] - max(after[index + 1], after[index + 2]))
                } else if d >= Self.pupilRadius + 4, d <= Self.irisRadius - 1 {
                    for channel in 0..<3 { worstIris = max(worstIris, abs(after[index + channel] - before[index + channel])) }
                }
            }
        }
        #expect(worstRed <= 10 / 255, "pupil red over green/blue by \(worstRed * 255)/255")
        #expect(worstIris <= 2 / 255, "iris moved \(worstIris * 255)/255")

        controller.undo()
        #expect(controller.recipe.redEyes.isEmpty, "one tap, one undo step")
    }

    /// AC-36. No face — Vision finds nothing on a plain frame — or a pupil
    /// too far from the finger: the spot sits exactly where the tap was, at
    /// 1% of the short edge, and nothing is asked.
    @MainActor @Test func noFaceFallsBackToTheTap() throws {
        let plain = try #require(CIContext().createCGImage(
            CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256)),
            from: CGRect(x: 0, y: 0, width: 256, height: 256)
        ))
        #expect(RedEyeLocator.pupils(in: plain).isEmpty)

        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.isRedEyeMode = true
        let tap = NormalizedPoint(x: 0.3, y: 0.6)
        controller.addRedEye(at: tap, pupils: [])
        let spot = try #require(controller.recipe.redEyes.first)
        #expect(spot.center == tap)
        #expect(spot.radius == RedEyeLocator.defaultRadius)
        #expect(RedEyeLocator.defaultRadius == 0.01)

        // A pupil well past three default radii does not pull the spot.
        let far = RedEyeLocator.Pupil(center: NormalizedPoint(x: 0.5, y: 0.6), eyeWidth: 0.05)
        let unpulled = RedEyeLocator.spot(forTapAt: tap, pupils: [far], aspect: 1)
        #expect(unpulled.center == tap && unpulled.radius == RedEyeLocator.defaultRadius)
    }

    /// A picture with two drawn faces' pupils: a red pair and a dark brown
    /// pair, in the 0…1 layout the pupils below use.
    private static func twoFaces() -> (picture: HealingSourceFinder.Picture, red: [RedEyeLocator.Pupil], brown: [RedEyeLocator.Pupil]) {
        let side = 512
        var rgb = [Float](repeating: 0.6, count: side * side * 3)
        let red = [NormalizedPoint(x: 0.25, y: 0.3), NormalizedPoint(x: 0.4, y: 0.3)]
        let brown = [NormalizedPoint(x: 0.6, y: 0.7), NormalizedPoint(x: 0.75, y: 0.7)]
        func paint(_ centre: NormalizedPoint, _ colour: (Float, Float, Float)) {
            let cx = centre.x * Double(side), cy = centre.y * Double(side)
            for y in 0..<side {
                for x in 0..<side where hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) <= 8 {
                    let index = (y * side + x) * 3
                    rgb[index] = colour.0; rgb[index + 1] = colour.1; rgb[index + 2] = colour.2
                }
            }
        }
        red.forEach { paint($0, (220 / 255, 40 / 255, 40 / 255)) }
        brown.forEach { paint($0, (60 / 255, 40 / 255, 30 / 255)) }
        let eyeWidth = 40.0 / Double(side)
        return (
            HealingSourceFinder.Picture(width: side, height: side, rgb: rgb),
            red.map { RedEyeLocator.Pupil(center: $0, eyeWidth: eyeWidth) },
            brown.map { RedEyeLocator.Pupil(center: $0, eyeWidth: eyeWidth) }
        )
    }

    /// AC-37. Two faces, one red-eyed and one with dark brown pupils: Fix
    /// Red Eye makes exactly two spots, both on the red pupils; the brown
    /// pair is left alone; one Undo takes both off. (Vision finding the
    /// pupils on a real face needs a device and a real face; the pupils are
    /// handed in here as it would report them.)
    @MainActor @Test func fixRedEyeSkipsDarkPupils() {
        let (picture, red, brown) = Self.twoFaces()
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        #expect(controller.fixRedEyes(pupils: red + brown, in: picture) == 2)
        #expect(controller.recipe.redEyes.count == 2)
        for spot in controller.recipe.redEyes {
            #expect(red.contains { hypot($0.center.x - spot.center.x, $0.center.y - spot.center.y) < 1e-9 })
        }
        // A second press finds the same pupils already fixed.
        #expect(controller.fixRedEyes(pupils: red + brown, in: picture) == 0)
        controller.undo()
        #expect(controller.recipe.redEyes.isEmpty, "the whole pass is one undo step")
    }

    /// AC-38. Nothing red to fix — no pupils, or Vision unable to run: no
    /// spot, no undo step, and "No red eyes found".
    @MainActor @Test func fixRedEyeWithNothingToFix() {
        let (picture, _, brown) = Self.twoFaces()
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        #expect(controller.fixRedEyes(pupils: [], in: picture) == 0)
        #expect(controller.fixRedEyes(pupils: brown, in: picture) == 0)
        #expect(controller.fixRedEyes(pupils: [], in: nil) == 0)
        #expect(controller.recipe.redEyes.isEmpty)
        #expect(!controller.canUndo)
        #expect(controller.redEyeNotice == "No red eyes found")
    }
}
