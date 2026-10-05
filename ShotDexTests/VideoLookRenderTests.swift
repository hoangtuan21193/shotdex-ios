import CoreImage
import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-12.06c: what a look does to the frames the compositor writes —
/// rendered through `VideoFrameCompositor.composeFrame`, the path every
/// preview and export frame takes, on images drawn in code.
@Suite(.serialized)
struct VideoLookRenderTests {
    static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    // MARK: Helpers

    /// RGBA bytes of `image` over `rect`, in sRGB.
    static func bytes(_ image: CIImage, in rect: CGRect) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(rect.width * rect.height) * 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: Int(rect.width) * 4, bounds: rect,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }

    /// Mean absolute difference per colour channel, in 1/255 steps.
    static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0, count = 0
        for index in a.indices where index % 4 != 3 {
            total += abs(Int(a[index]) - Int(b[index]))
            count += 1
        }
        return Double(total) / Double(max(count, 1))
    }

    /// A frame with tone and colour in it: a diagonal two-colour gradient,
    /// so a film look's curve bends it differently at every pixel.
    static func gradient(_ rect: CGRect, from: CIColor, to: CIColor) -> CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: rect.minX, y: rect.minY),
            "inputPoint1": CIVector(x: rect.maxX, y: rect.maxY),
            "inputColor0": from, "inputColor1": to,
        ])!.outputImage!.cropped(to: rect)
    }

    /// What the compositor does with a transition's outgoing side: draws it
    /// on its own, here into a bitmap through `context`.
    static func materialize(_ context: CIContext = context) -> (CIImage) -> CIImage {
        { image in
            guard let picture = context.createCGImage(
                image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            ) else { return image }
            return CIImage(cgImage: picture)
                .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
        }
    }

    static func timing(_ index: Int, start: Double, duration: Double) -> VideoCompositionInstruction.ClipRenderTiming {
        .init(clipIndex: index, start: start, duration: duration, effect: .none)
    }

    static func renderRecipe(_ recipe: VideoProjectRecipe, canvas: CGRect) -> VideoRenderRecipe {
        VideoRenderRecipe(recipe: recipe, renderSize: canvas.size, totalDuration: 10, bakesOverlays: false)
    }

    // MARK: AC-2

    /// AC-2: three clips, Look → My Looks → Moody Coast with All Clips — one
    /// undo step, every clip wears it, and each clip's frame at 1.0 s
    /// matches the photo editor's Moody Coast on that frame (≤ 2/255), the
    /// grain read from the same place.
    @Test @MainActor func myLookMatchesEditorAtOneSecond() throws {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(3))
        let moody = VideoLook.Source.myLook(sourceID: UUID(), name: "Moody Coast", isImported: false, recipe: VideoLookSamples.moodyCoast)
        model.toggleToolPanel(.look)
        model.lookShelf = .myLooks
        #expect(model.lookTarget == .allClips)
        let steps = model.history.undoEntries.count
        model.chooseLook(moody)
        #expect(model.history.undoEntries.count == steps + 1)
        #expect(model.recipe.clips.allSatisfy { VideoLookEditing.effectiveLook(for: $0, in: model.recipe)?.source == moody })

        let canvas = CGRect(x: 0, y: 0, width: 64, height: 64)
        let render = Self.renderRecipe(model.recipe, canvas: canvas)
        let frame = VideoLookBakerTests.testFrame()
        for (index, clip) in model.recipe.clips.enumerated() {
            let seconds = Double(index) * 3 + 1
            let composed = VideoFrameCompositor.composeFrame(
                front: (frame, .init(clipIndex: index, clipID: clip.id, start: Double(index) * 3, duration: 3, effect: .none)),
                back: nil, transition: nil, recipe: render, canvas: canvas, at: seconds
            )
            // The editor's chain: the pre-mask stages, then its Effects —
            // vignette, then grain — with the video frame's grain offset.
            let look = VideoLookSamples.moodyCoast
            var editor = VideoLookBakerTests.editorChain(look, on: frame)
            editor = PhotoRenderService.applyVignette(look.adjustments, style: look.vignetteStyle, to: editor)
            editor = PhotoRenderService.applyGrain(
                look.adjustments.grain, size: look.adjustments.grainSize, roughness: look.adjustments.grainRoughness,
                offset: VideoLookFrame(canvas: canvas.size, seconds: seconds).grainOffset, to: editor
            )
            let difference = Self.meanDifference(Self.bytes(composed, in: canvas), Self.bytes(editor, in: canvas))
            #expect(difference <= 2, "clip \(index + 1): mean \(difference)/255")
        }
    }

    // MARK: AC-3

    /// AC-3: the whole video in Velvia, clip 2 in Night Teal — the middle
    /// frame of clips 1 and 3 is Velvia, clip 2's is Night Teal alone, with
    /// no Velvia under it (each within 1/255 of the editor's own chain).
    @Test func middleFramesUseOwnLook() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 64)
        var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(3))
        project.look = VideoLookSamples.velvia
        project.clips[1].look = VideoLookSamples.nightTeal
        let render = Self.renderRecipe(project, canvas: canvas)
        let frame = VideoLookBakerTests.testFrame()
        for (index, clip) in project.clips.enumerated() {
            let start = Double(index) * 3
            let composed = VideoFrameCompositor.composeFrame(
                front: (frame, VideoCompositionInstruction.ClipRenderTiming(
                    clipIndex: index, clipID: clip.id, start: start, duration: 3, effect: .none
                )),
                back: nil, transition: nil, recipe: render, canvas: canvas, at: start + 1.5
            )
            let look = index == 1 ? VideoLookSamples.nightTeal : VideoLookSamples.velvia
            let expected = VideoLookBakerTests.editorChain(look.recipe, on: frame)
            let difference = Self.meanDifference(Self.bytes(composed, in: canvas), Self.bytes(expected, in: canvas))
            #expect(difference <= 1, "clip \(index + 1): mean \(difference)/255")
        }
        // Night Teal over Velvia would be a different picture.
        let stacked = VideoLookBakerTests.editorChain(
            VideoLookSamples.nightTeal.recipe,
            on: VideoLookBakerTests.editorChain(VideoLookSamples.velvia.recipe, on: frame)
        )
        let alone = VideoLookBakerTests.editorChain(VideoLookSamples.nightTeal.recipe, on: frame)
        #expect(Self.meanDifference(Self.bytes(stacked, in: canvas), Self.bytes(alone, in: canvas)) > 2)
    }

    // MARK: AC-5

    /// AC-5: Amount 40 is 40 % of the whole look over 60 % of the frame as
    /// it was before the look (≤ 1/255); Amount 0 is no look at all.
    @Test func amountMixesWholeLook() throws {
        let frame = VideoLookBakerTests.testFrame()
        let canvas = frame.extent
        var look = VideoLookSamples.moodyCoast
        look.adjustments.grain = 0
        look.adjustments.vignette = 0
        let full = VideoLookBakerTests.editorChain(look, on: frame)
        let source = VideoLook.Source.myLook(sourceID: UUID(), name: "Moody Coast", isImported: false, recipe: look)
        let cache = VideoLookTableCache(capacity: 4)

        let forty = try #require(VideoLookPlan(VideoLook(source, amount: 0.4), lutExists: { _ in true }))
        let rendered = VideoLookRenderer.apply(forty, to: frame, cache: cache)
        let expected = PhotoRenderService.filtered(
            "CIMix", image: full, values: [kCIInputBackgroundImageKey: frame, "inputAmount": 0.4]
        )
        let difference = Self.meanDifference(Self.bytes(rendered, in: canvas), Self.bytes(expected, in: canvas))
        #expect(difference <= 1, "mean \(difference)/255")
        // Not the full look, and not the frame.
        #expect(Self.meanDifference(Self.bytes(rendered, in: canvas), Self.bytes(full, in: canvas)) > 2)

        let zero = try #require(VideoLookPlan(VideoLook(source, amount: 0), lutExists: { _ in true }))
        #expect(VideoLookRenderer.apply(zero, to: frame, cache: cache) === frame)
    }

    // MARK: AC-6

    /// AC-6: a My Look with Grain 25, Noise Reduction 50 and Upright Auto —
    /// the caption names what video skips, and nothing else.
    @Test func skippedLineNamesNoiseReductionAndUpright() {
        var look = PhotoEditRecipe.identity
        look.adjustments.grain = 0.25
        look.adjustments.noiseReduction = 0.5
        look.upright.mode = .auto
        #expect(VideoLookEditing.skippedOnVideo(look) == ["Noise Reduction", "Upright"])
        #expect(VideoStudioCopy.lookSkippedLine(VideoLookEditing.skippedOnVideo(look)) == "Skipped on video: Noise Reduction, Upright.")
        #expect(VideoStudioCopy.lookSkippedLine(VideoLookEditing.skippedOnVideo(VideoLookSamples.moodyCoast)) == "Everything in this look applies to video.")
        // A lens profile is the photo's lens, not the look; a hand-set
        // distortion is the look's.
        var lens = PhotoEditRecipe.identity
        lens.adjustments.lensCorrection = 1
        #expect(VideoLookEditing.skippedOnVideo(lens).isEmpty)
        lens.adjustments.lensManualDistortion = 0.2
        #expect(VideoLookEditing.skippedOnVideo(lens) == ["Lens Correction"])
        // The switch of §5: off, the four neighbourhood stages are named.
        var clarity = PhotoEditRecipe.identity
        clarity.adjustments.clarity = 0.3
        clarity.adjustments.dehaze = 0.15
        #expect(VideoLookEditing.skippedOnVideo(clarity).isEmpty)
        #expect(VideoLookEditing.skippedOnVideo(clarity, policy: .skip) == ["Clarity", "Dehaze"])
        #expect(VideoLookPlan(VideoLook(.myLook(sourceID: UUID(), name: "C", isImported: false, recipe: clarity)), lutExists: { _ in true }, policy: .skip)?.neighbours == nil)
    }

    /// AC-6: two frames in a row of a still clip carry different grain, at
    /// the same strength (standard deviation within ±10 %).
    @Test func grainChangesEveryFrame() throws {
        let canvas = CGRect(x: 0, y: 0, width: 128, height: 128)
        var look = PhotoEditRecipe.identity
        look.adjustments.grain = 0.25
        var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(1))
        project.look = VideoLook(.myLook(sourceID: UUID(), name: "Grain", isImported: false, recipe: look))
        let render = Self.renderRecipe(project, canvas: canvas)
        let still = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: canvas)
        func frame(_ seconds: Double) -> [UInt8] {
            Self.bytes(VideoFrameCompositor.composeFrame(
                front: (still, .init(clipIndex: 0, clipID: project.clips[0].id, start: 0, duration: 3, effect: .none)),
                back: nil, transition: nil, recipe: render, canvas: canvas, at: seconds
            ), in: canvas)
        }
        let first = frame(1.0), second = frame(1.0 + 1.0 / 30)
        func deviation(_ bytes: [UInt8]) -> Double {
            let greens = stride(from: 1, to: bytes.count, by: 4).map { Double(bytes[$0]) }
            let mean = greens.reduce(0, +) / Double(greens.count)
            return (greens.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(greens.count)).squareRoot()
        }
        let a = deviation(first), b = deviation(second)
        #expect(a > 1, "grain is visible: σ \(a)")
        #expect(abs(a - b) / a <= 0.1, "σ \(a) vs \(b)")
        #expect(Self.meanDifference(first, second) > a * 0.5, "the pattern moved")
        // The same frame twice is the same grain: preview and export agree.
        #expect(Self.meanDifference(first, frame(1.0)) == 0)
    }

    /// Clarity's radius follows the frame: a 1280 preview and a 3840 export
    /// of one picture, brought to one size, are one picture.
    @Test func neighbourRadiusScalesWithFrame() throws {
        var look = PhotoEditRecipe.identity
        look.adjustments.clarity = 0.6
        let plan = try #require(VideoLookPlan(
            VideoLook(.myLook(sourceID: UUID(), name: "Clarity", isImported: false, recipe: look)),
            lutExists: { _ in true }
        ))
        #expect(plan.neighbours?.clarity == 0.6)
        #expect(plan.parts == [.light, .colour])
        let small = CGSize(width: 320, height: 180)
        func picture(long: CGFloat, scaled: Bool) -> [UInt8] {
            let rect = CGRect(x: 0, y: 0, width: long, height: long * 9 / 16)
            let frame = Self.gradient(rect, from: CIColor(red: 0.2, green: 0.25, blue: 0.3), to: CIColor(red: 0.8, green: 0.7, blue: 0.6))
            let bar = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95)).cropped(to: CGRect(x: rect.width * 0.48, y: 0, width: rect.width * 0.04, height: rect.height))
            let input = bar.composited(over: frame)
            let output = VideoLookRenderer.apply(
                plan, to: input,
                frame: VideoLookFrame(radiusScale: scaled ? long / VideoLookFrame.referenceLongEdge : 1),
                cache: VideoLookTableCache(capacity: 4)
            )
            let down = output.transformed(by: CGAffineTransform(scaleX: small.width / rect.width, y: small.height / rect.height))
            return Self.bytes(down, in: CGRect(origin: .zero, size: small))
        }
        let scaled = Self.meanDifference(picture(long: 1280, scaled: true), picture(long: 3840, scaled: true))
        let fixed = Self.meanDifference(picture(long: 1280, scaled: false), picture(long: 3840, scaled: false))
        #expect(scaled < fixed, "scaled \(scaled) vs fixed \(fixed)")
        #expect(scaled <= 2, "scaled \(scaled)/255")
    }

    // MARK: AC-8

    /// AC-8: clip 2's LUT "Kodak 2383" was deleted — clip 2 renders as if it
    /// had no look, and the project says which look is missing.
    @Test @MainActor func missingLUTRendersAsNoLook() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 64)
        var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(3))
        project.clips[1].look = VideoLook(.lut(id: "kodak-2383-gone", name: "Kodak 2383"))
        let render = VideoRenderRecipe(
            recipe: project, renderSize: canvas.size, totalDuration: 9, bakesOverlays: false,
            lutExists: { _ in false }
        )
        let frame = VideoLookBakerTests.testFrame()
        let composed = VideoFrameCompositor.composeFrame(
            front: (frame, .init(clipIndex: 1, clipID: project.clips[1].id, start: 3, duration: 3, effect: .none)),
            back: nil, transition: nil, recipe: render, canvas: canvas, at: 4.5
        )
        #expect(Self.meanDifference(Self.bytes(composed, in: canvas), Self.bytes(frame, in: canvas)) <= 0.5)

        let model = VideoStudioModelFixture.model(clips: project.clips)
        model.lutExists = { _ in false }
        #expect(model.lookPillText(for: model.recipe.clips[1]) == "Kodak 2383 · Missing")
        #expect(model.missingLUTLookCount == 1)
    }

    /// A My Look whose LUT is gone keeps the rest of the look.
    @Test func missingLUTInsideMyLookKeepsTheRest() throws {
        var look = PhotoEditRecipe.identity
        look.adjustments.exposure = 0.3
        look.adjustments.contrast = 0.2
        look.lutID = "kodak-2383-gone"
        let plan = try #require(VideoLookPlan(
            VideoLook(.myLook(sourceID: UUID(), name: "Coast", isImported: false, recipe: look)),
            lutExists: { _ in false }
        ))
        #expect(plan.recipe.lutID == nil)
        let frame = VideoLookBakerTests.testFrame()
        var withoutLUT = look
        withoutLUT.lutID = nil
        let rendered = VideoLookRenderer.apply(plan, to: frame, cache: VideoLookTableCache(capacity: 2))
        let expected = VideoLookBakerTests.editorChain(withoutLUT, on: frame)
        #expect(Self.meanDifference(Self.bytes(rendered, in: frame.extent), Self.bytes(expected, in: frame.extent)) <= 1)
        #expect(VideoLookEditing.isMissingLUT(VideoLook(.myLook(sourceID: UUID(), name: "Coast", isImported: false, recipe: look)), lutExists: { _ in false }))
    }

    /// AC-8: the Export line counts looks, in the catalog's plural.
    @Test @MainActor func exportLineCountsLooks() {
        #expect(VideoStudioCopy.looksMissingLUT(1) == "1 look is missing its LUT and exports without it.")
        #expect(VideoStudioCopy.looksMissingLUT(2) == "2 looks are missing their LUT and export without it.")
        var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(3))
        project.look = VideoLook(.lut(id: "a", name: "A"))
        project.clips[0].look = VideoLook(.lut(id: "b", name: "B"))
        project.clips[2].look = VideoLookSamples.velvia
        #expect(VideoLookEditing.missingLUTLookCount(in: project, lutExists: { _ in false }) == 2)
        #expect(VideoLookEditing.missingLUTLookCount(in: project, lutExists: { $0 == "a" }) == 1)
        #expect(VideoStudioCopy.lookMissingLUT("Kodak 2383") == "Kodak 2383 is missing. Import it again, then pick it in LUTs.")
    }

    // MARK: AC-4

    /// AC-4: half way through a dissolve the frame is the two clips, each
    /// graded on its own, mixed 50/50 — not the mix graded once. A film
    /// look is a curve, so the two orders differ and the test can tell.
    @Test func dissolveMixesTwoGradedFrames() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 36)
        var project = VideoProjectRecipe(clips: [])
        project.look = VideoLookSamples.velvia
        let render = Self.renderRecipe(project, canvas: canvas)
        let outgoing = Self.gradient(canvas, from: CIColor(red: 0.9, green: 0.3, blue: 0.1), to: CIColor(red: 0.2, green: 0.2, blue: 0.3))
        let incoming = Self.gradient(canvas, from: CIColor(red: 0.1, green: 0.5, blue: 0.9), to: CIColor(red: 0.95, green: 0.9, blue: 0.4))

        let frame = VideoFrameCompositor.composeFrame(
            front: (incoming, Self.timing(1, start: 2, duration: 3)),
            back: (outgoing, Self.timing(0, start: 0, duration: 3)),
            transition: (kind: .crossfade, start: 2, duration: 1),
            recipe: render, canvas: canvas, at: 2.5, materialize: Self.materialize()
        )
        let gradedEach = PhotoRenderService.filtered(
            "CIDissolveTransition",
            image: render.graded(outgoing, at: 2.5),
            values: [kCIInputTargetImageKey: render.graded(incoming, at: 2.5), kCIInputTimeKey: 0.5]
        )
        let gradedOnce = render.graded(PhotoRenderService.filtered(
            "CIDissolveTransition", image: outgoing,
            values: [kCIInputTargetImageKey: incoming, kCIInputTimeKey: 0.5]
        ), at: 2.5)

        let actual = Self.bytes(frame, in: canvas)
        let expected = Self.bytes(gradedEach, in: canvas)
        #expect(Self.meanDifference(actual, expected) <= 1, "mean \(Self.meanDifference(actual, expected))/255")
        // The old order — mix, then grade — is a different picture.
        #expect(Self.meanDifference(Self.bytes(gradedOnce, in: canvas), expected) > 1)
    }

    /// AC-4 as the spec writes it: clip 1 Velvia, clip 2 Night Teal — half
    /// way through their dissolve the frame is the two, each in its own
    /// look, mixed 50/50.
    @Test func dissolveBetweenTwoLooks() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 36)
        var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(2))
        project.clips[0].look = VideoLookSamples.velvia
        project.clips[1].look = VideoLookSamples.nightTeal
        let render = Self.renderRecipe(project, canvas: canvas)
        let outgoing = Self.gradient(canvas, from: CIColor(red: 0.9, green: 0.3, blue: 0.1), to: CIColor(red: 0.2, green: 0.2, blue: 0.3))
        let incoming = Self.gradient(canvas, from: CIColor(red: 0.1, green: 0.5, blue: 0.9), to: CIColor(red: 0.95, green: 0.9, blue: 0.4))
        let frame = VideoFrameCompositor.composeFrame(
            front: (incoming, .init(clipIndex: 1, clipID: project.clips[1].id, start: 2, duration: 3, effect: .none)),
            back: (outgoing, .init(clipIndex: 0, clipID: project.clips[0].id, start: 0, duration: 3, effect: .none)),
            transition: (kind: .crossfade, start: 2, duration: 1),
            recipe: render, canvas: canvas, at: 2.5, materialize: Self.materialize()
        )
        let expected = PhotoRenderService.filtered(
            "CIDissolveTransition",
            image: VideoLookBakerTests.editorChain(VideoLookSamples.velvia.recipe, on: outgoing),
            values: [
                kCIInputTargetImageKey: VideoLookBakerTests.editorChain(VideoLookSamples.nightTeal.recipe, on: incoming),
                kCIInputTimeKey: 0.5,
            ]
        )
        let difference = Self.meanDifference(Self.bytes(frame, in: canvas), Self.bytes(expected, in: canvas))
        #expect(difference <= 1, "mean \(difference)/255")
    }

    /// The compositor keeps one `CIContext` for every frame. A dissolve
    /// between two clips with the **same** look, then one between two
    /// **different** looks, must not render the second with the first
    /// one's tables: Core Image reused the program it compiled for the
    /// first frame and bound one cube to both sides (found 2026-10-04).
    @Test func aContextThatSawOneLookStillRendersTwo() throws {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 36)
        let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        func bytes(_ image: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: Int(canvas.width * canvas.height) * 4)
            context.render(image, toBitmap: &bytes, rowBytes: Int(canvas.width) * 4, bounds: canvas,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return bytes
        }
        let outgoing = Self.gradient(canvas, from: CIColor(red: 0.9, green: 0.3, blue: 0.1), to: CIColor(red: 0.2, green: 0.2, blue: 0.3))
        let incoming = Self.gradient(canvas, from: CIColor(red: 0.1, green: 0.5, blue: 0.9), to: CIColor(red: 0.95, green: 0.9, blue: 0.4))
        func dissolve(_ first: VideoLook, _ second: VideoLook) -> CIImage {
            var project = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(2))
            project.clips[0].look = first
            project.clips[1].look = second
            let render = Self.renderRecipe(project, canvas: canvas)
            return VideoFrameCompositor.composeFrame(
                front: (incoming, .init(clipIndex: 1, clipID: project.clips[1].id, start: 2, duration: 3, effect: .none)),
                back: (outgoing, .init(clipIndex: 0, clipID: project.clips[0].id, start: 0, duration: 3, effect: .none)),
                transition: (kind: .crossfade, start: 2, duration: 1),
                recipe: render, canvas: canvas, at: 2.5, materialize: Self.materialize(context)
            )
        }
        _ = bytes(dissolve(VideoLookSamples.velvia, VideoLookSamples.velvia))
        let mixed = bytes(dissolve(VideoLookSamples.velvia, VideoLookSamples.nightTeal))
        let expected = bytes(PhotoRenderService.filtered(
            "CIDissolveTransition",
            image: VideoLookBakerTests.editorChain(VideoLookSamples.velvia.recipe, on: outgoing),
            values: [
                kCIInputTargetImageKey: VideoLookBakerTests.editorChain(VideoLookSamples.nightTeal.recipe, on: incoming),
                kCIInputTimeKey: 0.5,
            ]
        ))
        let difference = Self.meanDifference(mixed, expected)
        #expect(difference <= 1, "mean \(difference)/255")
    }

    /// AC-4: a 9:16 clip on a 16:9 canvas with a look and an exposure
    /// node — the bars are the background colour that was chosen, byte for
    /// byte, not that colour graded.
    @Test func letterboxKeepsTheChosenBackground() throws {
        let canvas = CGRect(x: 0, y: 0, width: 160, height: 90)
        var project = VideoProjectRecipe(clips: [])
        project.look = VideoLookSamples.velvia
        project.nodes[0].adjustments.exposure = 1
        project.background.colour = .init(red: 0.2, green: 0.4, blue: 0.6)
        let render = Self.renderRecipe(project, canvas: canvas)
        // 9:16 fitted to 90 tall: 50.625 wide, centred.
        let clipRect = CGRect(x: 54.6875, y: 0, width: 50.625, height: 90)
        let clip = Self.gradient(clipRect, from: CIColor(red: 0.8, green: 0.4, blue: 0.2), to: CIColor(red: 0.1, green: 0.2, blue: 0.5))

        let frame = VideoFrameCompositor.composeFrame(
            front: (clip, Self.timing(0, start: 0, duration: 3)), back: nil, transition: nil,
            recipe: render, canvas: canvas, at: 1
        )
        let bar = Self.bytes(frame, in: CGRect(x: 0, y: 0, width: 40, height: 90))
        let expected: [Int] = [51, 102, 153]
        for pixel in stride(from: 0, to: bar.count, by: 4) {
            for channel in 0..<3 {
                #expect(abs(Int(bar[pixel + channel]) - expected[channel]) <= 1)
            }
        }
        // And the clip itself is graded: brighter than it went in.
        let inside = Self.bytes(frame, in: CGRect(x: 78, y: 44, width: 2, height: 2))
        let source = Self.bytes(clip, in: CGRect(x: 78, y: 44, width: 2, height: 2))
        let lifted = Int(inside[0]) + Int(inside[1]) + Int(inside[2])
        let before = Int(source[0]) + Int(source[1]) + Int(source[2])
        #expect(lifted > before + 30, "graded \(inside[0..<3]) vs source \(source[0..<3])")
    }

    /// The window of a node is drawn on the viewer, so it stays at that
    /// place on the canvas when the clip under it is letterboxed and graded
    /// on its own.
    @Test func windowStaysWhereDrawnOnLetterboxedClip() throws {
        let canvas = CGRect(x: 0, y: 0, width: 160, height: 90)
        var project = VideoProjectRecipe(clips: [])
        var radial = PhotoMaskComponent(kind: .radialGradient)
        // Left bar, a quarter of the way across: outside the clip.
        radial.center = NormalizedPoint(x: 0.2, y: 0.5)
        radial.radiusX = 0.08
        radial.radiusY = 0.12
        radial.feather = 0.1
        var window = PhotoMask(name: "Window", component: radial)
        window.adjustments.exposure = 2
        project.nodes[0].masks = [window]
        let render = Self.renderRecipe(project, canvas: canvas)
        let clipRect = CGRect(x: 54.6875, y: 0, width: 50.625, height: 90)
        let clip = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: clipRect)

        let frame = VideoFrameCompositor.composeFrame(
            front: (clip, Self.timing(0, start: 0, duration: 3)), back: nil, transition: nil,
            recipe: render, canvas: canvas, at: 1
        )
        // Where the window would land if it were measured on the clip:
        // 0.2 of the clip's width in from its left edge.
        let clipRelative = CGRect(x: 54.6875 + 50.625 * 0.2 - 1, y: 44, width: 2, height: 2)
        let pixels = Self.bytes(frame, in: clipRelative.integral)
        let untouched = Self.bytes(clip, in: clipRelative.integral)
        #expect(Self.meanDifference(pixels, untouched) <= 1)
    }
}
