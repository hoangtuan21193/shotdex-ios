import CoreImage
import ImageIO
import Foundation
import Photos
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

    /// The full preview path, not just the pass: a spot changes its own
    /// neighbourhood and nothing else. (A first build smeared the whole frame
    /// into streaks around the spot on device while the pass-level test above
    /// stayed green, because it only looked near the spot and read pixels one at
    /// a time: Core Image evaluated the blend kernel over the whole frame unless
    /// its output was cropped before the composite.)
    @Test func spotsLeaveTheRestOfTheFrameAlone() async throws {
        let width = 600, height = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for y in 0..<height {
            for x in stride(from: 0, to: width, by: 20) {
                context.setFillColor(red: CGFloat(x) / CGFloat(width), green: CGFloat(y) / CGFloat(height), blue: 0.5, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 20, height: 1))
            }
        }
        let cgImage = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("heal-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        defer { try? FileManager.default.removeItem(at: url) }

        let renderer = PhotoRenderService()
        let info = try await renderer.inspectSource(at: url)
        let plain = try await renderer.renderPreview(source: info, recipe: PhotoEditRecipe(), maximumDimension: 600)
        var recipe = PhotoEditRecipe()
        recipe.healing = [
            PhotoHealingSpot(center: NormalizedPoint(x: 0.3, y: 0.5), source: NormalizedPoint(x: 0.4, y: 0.5)),
            PhotoHealingSpot(center: NormalizedPoint(x: 0.7, y: 0.3), source: NormalizedPoint(x: 0.8, y: 0.3)),
        ]
        let healed = try await renderer.renderPreview(source: info, recipe: recipe, maximumDimension: 600)
        #expect(healed.width == plain.width && healed.height == plain.height)

        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(
                data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return data
        }
        let a = bytes(plain), b = bytes(healed)
        // Corners and a band far from both spots, plus the rows just outside
        // each spot's working region, where a fractional edge drew a hairline.
        for (x, y) in [(5, 5), (590, 5), (5, 390), (590, 390), (300, 380), (100, 100),
                       (180, 166), (180, 167), (180, 233), (180, 234), (420, 87), (420, 153)] {
            let index = (y * plain.width + x) * 4
            for channel in 0..<3 {
                #expect(abs(Int(a[index + channel]) - Int(b[index + channel])) <= 2, "(\(x),\(y)) changed")
            }
        }
    }

    /// Clone puts the source's own pixels in the spot — asserted by value, on
    /// the pass and through a preview render that downsizes the frame (the
    /// case where a first build cloned black on device).
    @Test func cloneCopiesTheSourcePixels() async throws {
        let width = 600, height = 400
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for y in 0..<height {
            for x in stride(from: 0, to: width, by: 20) {
                context.setFillColor(red: CGFloat(x) / CGFloat(width), green: CGFloat(y) / CGFloat(height), blue: 0.5, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 20, height: 1))
            }
        }
        let cgImage = try #require(context.makeImage())
        let spot = PhotoHealingSpot(mode: .clone, center: NormalizedPoint(x: 0.3, y: 0.5), source: NormalizedPoint(x: 0.4, y: 0.5))

        func pixel(_ image: CGImage, _ nx: Double, _ ny: Double) -> [Int] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let c = CGContext(
                data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let x = Int(nx * Double(image.width)), y = Int(ny * Double(image.height))
            let index = (y * image.width + x) * 4
            return (0..<3).map { Int(data[index + $0]) }
        }

        let ciContext = CIContext()
        let direct = PhotoRenderService.applyHealing([spot], to: CIImage(cgImage: cgImage))
        let directImage = try #require(ciContext.createCGImage(direct, from: direct.extent))
        let expected = pixel(cgImage, 0.4, 0.5)
        #expect(zip(pixel(directImage, 0.3, 0.5), expected).allSatisfy { abs($0 - $1) <= 3 },
                "direct clone \(pixel(directImage, 0.3, 0.5)) vs source \(expected)")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clone-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = PhotoRenderService()
        let info = try await renderer.inspectSource(at: url)
        var recipe = PhotoEditRecipe()
        recipe.healing = [spot]
        for dimension in [600.0, 300.0] {
            let plain = try await renderer.renderPreview(source: info, recipe: PhotoEditRecipe(), maximumDimension: dimension)
            let cloned = try await renderer.renderPreview(source: info, recipe: recipe, maximumDimension: dimension)
            let want = pixel(plain, 0.4, 0.5), got = pixel(cloned, 0.3, 0.5)
            #expect(zip(got, want).allSatisfy { abs($0 - $1) <= 4 }, "preview \(dimension): clone \(got) vs source \(want)")
        }

        // Two spots, heal then clone — the second spot is where a nested
        // kernel graph cloned black on device.
        var pair = PhotoEditRecipe()
        pair.healing = [
            PhotoHealingSpot(mode: .heal, center: NormalizedPoint(x: 0.2, y: 0.7), source: NormalizedPoint(x: 0.25, y: 0.7)),
            spot,
        ]
        for dimension in [600.0, 300.0] {
            let plain = try await renderer.renderPreview(source: info, recipe: PhotoEditRecipe(), maximumDimension: dimension)
            let cloned = try await renderer.renderPreview(source: info, recipe: pair, maximumDimension: dimension)
            let want = pixel(plain, 0.4, 0.5), got = pixel(cloned, 0.3, 0.5)
            #expect(zip(got, want).allSatisfy { abs($0 - $1) <= 4 }, "two spots \(dimension): clone \(got) vs source \(want)")
        }

        // The slider/drag path: a cached base, re-rendered interactively.
        let identity = try await renderer.renderPreview(source: info, recipe: PhotoEditRecipe(), maximumDimension: 600)
        await renderer.installInteractiveBase(identity, source: info, recipe: PhotoEditRecipe())
        for dimension in [600.0, 427.0] {
            let plain = try await renderer.renderInteractivePreviewImages(
                source: info, recipe: PhotoEditRecipe(), maximumDimension: dimension, cachesBase: false
            ).cleanImage
            let cloned = try await renderer.renderInteractivePreviewImages(
                source: info, recipe: recipe, maximumDimension: dimension, cachesBase: false
            ).cleanImage
            let want = pixel(plain, 0.4, 0.5), got = pixel(cloned, 0.3, 0.5)
            #expect(zip(got, want).allSatisfy { abs($0 - $1) <= 4 }, "interactive \(dimension): clone \(got) vs source \(want)")
        }
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

    /// AC-2. Dragging a spot's source moves the fill, and the whole drag is
    /// one undo step, not one per frame.
    @MainActor @Test func draggingTheSourceIsOneUndoStep() throws {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.addHealingSpot(at: NormalizedPoint(x: 0.4, y: 0.4))
        let spot = try #require(controller.recipe.healing.first)
        #expect(controller.selectedHealingSpotID == spot.id)
        #expect(spot.source != spot.center, "a source is proposed beside the spot")

        controller.beginContinuousChange()
        for step in 1...5 {
            controller.updateHealingSpot(spot.id) {
                $0.source = NormalizedPoint(x: 0.4, y: 0.4 + Double(step) * 0.05)
            }
        }
        controller.endContinuousChange()
        #expect(controller.recipe.healing.first?.source == NormalizedPoint(x: 0.4, y: 0.4 + 5 * 0.05))

        controller.undo()
        #expect(controller.recipe.healing.first?.source == spot.source, "one undo puts the source back")
        controller.undo()
        #expect(controller.recipe.healing.isEmpty, "and the next removes the spot")
    }

    @MainActor @Test func panelSlidersEditTheSelectedSpot() throws {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.addHealingSpot(at: NormalizedPoint(x: 0.5, y: 0.5))
        controller.setHealingMode(.clone)
        controller.setHealingRadius(0.08)
        let spot = try #require(controller.recipe.healing.first)
        #expect(spot.mode == .clone)
        #expect(spot.radius == 0.08)
        controller.deleteSelectedHealingSpot()
        #expect(controller.recipe.healing.isEmpty)
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
