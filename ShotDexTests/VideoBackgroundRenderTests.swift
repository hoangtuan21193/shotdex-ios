import CoreImage
import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-12.01 §7b, FS-12.10 AC-13/AC-14: what a fitted clip sits on.
@Suite(.serialized) @MainActor
struct VideoBackgroundRenderTests {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// RGBA bytes of `image` scaled to `size`.
    private func pixels(_ image: CIImage, size: CGSize) -> [UInt8] {
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: size.width / image.extent.width, y: size.height / image.extent.height
        ).concatenating(CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)))
        var bytes = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
        context.render(scaled, toBitmap: &bytes, rowBytes: Int(size.width) * 4,
                       bounds: CGRect(origin: .zero, size: size), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return bytes
    }

    /// A 16:9 frame with detail — a gradient and a bright bar — fitted into
    /// a 9:16 canvas of `long` points.
    private func fitted(long: CGFloat) -> (CIImage, CGRect) {
        let canvas = CGRect(x: 0, y: 0, width: long * 9 / 16, height: long)
        let width = canvas.width, height = width * 9 / 16
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: width, y: 0),
            "inputColor0": CIColor(red: 0.9, green: 0.2, blue: 0.1), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.9),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let bar = CIImage(color: .white).cropped(to: CGRect(x: width * 0.45, y: 0, width: width * 0.1, height: height))
        let frame = bar.composited(over: gradient)
            .transformed(by: CGAffineTransform(translationX: 0, y: (canvas.height - height) / 2))
        return (frame, canvas)
    }

    /// AC-13: Blur 50 at the preview's 1280 and the export's 3840 is one
    /// picture: brought down to 180×320, no channel differs by more than
    /// 3/255.
    @Test func blurPreviewMatchesExportScaledDown() {
        let size = CGSize(width: 180, height: 320)
        func render(_ long: CGFloat) -> [UInt8] {
            let (frame, canvas) = fitted(long: long)
            let backdrop = VideoBackgroundRenderer.backdrop(
                behind: frame, canvas: canvas, kind: .blur, colour: .black, blurAmount: 50, image: nil
            )
            return pixels(frame.composited(over: backdrop).cropped(to: canvas), size: size)
        }
        let preview = render(1280), export = render(3840)
        // The bands above and below the frame — the backdrop itself; the
        // sharp frame's own edges resample differently at each size.
        var worst = 0
        for row in Array(0..<100) + Array(220..<320) {
            for index in (row * 180 * 4)..<((row + 1) * 180 * 4) where index % 4 != 3 {
                worst = max(worst, abs(Int(preview[index]) - Int(export[index])))
            }
        }
        #expect(worst <= 3, "worst channel difference \(worst)/255")
        // The bars are the frame itself, blurred — not black, not the canvas colour.
        let top = (10 * 180 + 90) * 4
        #expect(Int(export[top]) + Int(export[top + 1]) + Int(export[top + 2]) > 120)
    }

    /// AC-14: an Image background whose photo cannot be read is black.
    @Test func missingImageIsBlack() {
        let (frame, canvas) = fitted(long: 640)
        let backdrop = VideoBackgroundRenderer.backdrop(
            behind: frame, canvas: canvas, kind: .image, colour: CIColor(red: 1, green: 1, blue: 1), blurAmount: 0, image: nil
        )
        let bytes = pixels(backdrop, size: CGSize(width: 36, height: 64))
        #expect(bytes.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element < 3 })
    }

    /// AC-13 (crossfade): a red clip crossfading into a blue one over Blur —
    /// half way, the bars carry both clips' blur (each side brought its own
    /// backdrop), not one colour for the whole frame.
    @Test func crossfadeBlendsEachSidesBackground() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let red = directory.appendingPathComponent("red.mp4"), blue = directory.appendingPathComponent("blue.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2, fill: .flat(red: 0.9, green: 0.1, blue: 0.1), to: red)
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2, fill: .flat(red: 0.1, green: 0.1, blue: 0.9), to: blue)
        var recipe = VideoProjectRecipe(clips: [
            VideoExportFixtures.videoClip("red", seconds: 2), VideoExportFixtures.videoClip("blue", seconds: 2),
        ])
        recipe.syncTransitionsWithClips()
        recipe.transitions[0] = VideoBoundaryTransition(kind: .crossfade, duration: 1)
        recipe.aspect = .r9x16
        recipe.resolution = .p720
        recipe.background = VideoBackground(kind: .blur, blurAmount: 50)
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(recipe: recipe, sources: [
            recipe.clips[0].id: try await VideoExportFixtures.videoSource(red),
            recipe.clips[1].id: try await VideoExportFixtures.videoSource(blue),
        ], progress: { _ in })
        func topBar(at seconds: Double) async throws -> (r: Int, b: Int) {
            let frame = try await VideoExportFixtures.frame(of: url, at: seconds)
            let index = (40 * frame.width + frame.width / 2) * 4
            return (Int(frame.bytes[index]), Int(frame.bytes[index + 2]))
        }
        let before = try await topBar(at: 0.5)
        let middle = try await topBar(at: 1.5)
        let after = try await topBar(at: 2.6)
        #expect(before.r > 150 && before.b < 80)
        #expect(after.b > 150 && after.r < 80)
        #expect(middle.r > 60 && middle.b > 60)
    }
}
