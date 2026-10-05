import AVFoundation
import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// FS-12.15: Before and After is screen state — never the recipe, never an
/// undo step, never an export — and Before is the project without its look,
/// grade, de-log, overlays and captions.
@MainActor
struct VideoBeforeAfterTests {
    private func gradedRecipe() -> VideoProjectRecipe {
        var recipe = CaptionFixture.recipe()
        recipe.look = { var look = VideoLook(.preset(.velvia)); look.amount = 0.8; return look }()
        recipe.inputTransform = .sLog3
        recipe.nodes[0].adjustments.exposure = 0.3
        recipe.clips[1].effect = .zoomIn
        recipe.clips[1].look = VideoLook(.preset(.velvia))
        var text = PhotoOverlay.text()
        text.text = "GOLDEN HOUR"
        recipe.overlays.append(TimedOverlay(overlay: text, start: 3, duration: 6))
        return recipe
    }

    /// AC-11: the project an export reads is the same with compare on —
    /// Split at 30 % — and toggling makes no undo step.
    @Test func exportIgnoresCompareState() {
        let model = VideoStudioModelFixture.model(clips: gradedRecipe().clips, configure: { $0 = self.gradedRecipe() })
        let before = model.recipe
        let steps = model.history.undoEntries.count
        model.toggleBeforeAfter(sideBySide: false)
        model.setCompareFraction(0.3)
        #expect(model.compare?.mode == .split)
        #expect(model.recipe == before, "export reads the recipe; compare is not in it")
        #expect(model.history.undoEntries.count == steps)
        #expect(model.previewStage == .pair)
        let encoded = try! JSONEncoder().encode(model.recipe)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("compare"))
    }

    @Test func compareStateIsNotUndoable() {
        let model = VideoStudioModelFixture.model(clips: gradedRecipe().clips, configure: { $0 = self.gradedRecipe() })
        model.pushUndo()
        model.setVideoVolume(0.4)
        model.toggleBeforeAfter(sideBySide: true)
        model.setCompareMode(.split)
        model.undo()
        #expect(model.compare?.mode == .split, "Undo leaves compare on (§8)")
        #expect(model.recipe.videoVolume == 1)
    }

    /// AC-13: Before drops de-log with the look, grade, overlays, captions.
    @Test func beforeDropsDeLog() {
        let before = VideoBeforeAfter.beforeRecipe(gradedRecipe())
        #expect(before.inputTransform == .none)
        #expect(before.look == nil && before.clips.allSatisfy { $0.look == nil })
        #expect(!before.hasGrade)
        #expect(before.overlays.isEmpty && before.captions == nil)
    }

    /// §3: cuts, motion, transitions and sound stay.
    @Test func beforeKeepsEffectsTransitionsAudio() {
        var recipe = gradedRecipe()
        recipe.transitions[0] = .defaultCrossfade
        recipe.videoVolume = 0.5
        let before = VideoBeforeAfter.beforeRecipe(recipe)
        #expect(before.clips.map(\.effect) == recipe.clips.map(\.effect))
        #expect(before.clips.map(\.trimStart) == recipe.clips.map(\.trimStart))
        #expect(before.transitions == recipe.transitions)
        #expect(before.videoVolume == 0.5 && before.musicTracks == recipe.musicTracks)
        #expect(before.aspect == recipe.aspect && before.background == recipe.background)
    }

    /// AC-10: nothing to compare when there is no look, grade or overlay.
    @Test func nothingToCompareWhenNoLookAdjustColorOverlay() {
        var plain = CaptionFixture.recipe()
        plain.overlays = []
        #expect(VideoBeforeAfter.hasNothingToCompare(plain))
        #expect(!VideoBeforeAfter.hasNothingToCompare(gradedRecipe()))
        var delog = plain
        delog.inputTransform = .hlg
        #expect(!VideoBeforeAfter.hasNothingToCompare(delog))
        #expect(VideoStudioCopy.noEditsToCompare == "No edits to compare yet.")
    }

    /// AC-1: the Split line opens at half the phone's 402pt frame.
    @Test func phoneSplitGeometry() {
        let compare = VideoBeforeAfter.opening(sideBySide: false)
        #expect(compare.mode == .split)
        #expect(abs(compare.lineX(in: CGRect(x: 0, y: 60, width: 402, height: 226)) - 201) <= 1)
        #expect(VideoBeforeAfter.modes(sideBySide: false) == [.split, .hold])
        #expect(VideoBeforeAfter.modes(sideBySide: true) == [.sideBySide, .split])
    }

    /// AC-3: dragged to x 100 the line is at 25 %, and VoiceOver says so;
    /// a swipe moves it a tenth.
    @Test func fractionFromDrag() {
        let frame = CGRect(x: 0, y: 60, width: 402, height: 226)
        let fraction = VideoBeforeAfter.fraction(forX: 100, in: frame)
        var compare = VideoBeforeAfter.opening(sideBySide: false)
        compare.fraction = fraction
        #expect(abs(compare.lineX(in: frame) - 100) <= 1)
        #expect(compare.percent == 25)
        #expect(VideoBeforeAfter.fraction(forX: -40, in: frame) == 0)
        #expect(VideoBeforeAfter.fraction(forX: 900, in: frame) == 1)
    }

    @Test func accessibilityValueReadsPercent() {
        var compare = VideoBeforeAfter.opening(sideBySide: false)
        compare.fraction = 0.25
        #expect(VideoStudioCopy.before + ", " + VideoStudioCopy.percentValue(compare.percent) == "Before, 25 percent")
        #expect(compare.adjusted(by: 1).percent == 35)
        #expect(compare.adjusted(by: -3).percent == 0)
    }

    /// AC-4: holding the frame shows Before; the recipe and undo do not move.
    @Test func holdNeverTouchesRecipeOrUndo() {
        let model = VideoStudioModelFixture.model(clips: gradedRecipe().clips, configure: { $0 = self.gradedRecipe() })
        model.toggleBeforeAfter(sideBySide: false)
        model.setCompareMode(.hold)
        #expect(model.previewStage == .single)
        let recipe = model.recipe
        let steps = model.history.undoEntries.count
        model.holdCompare(true)
        #expect(model.showsOriginal)
        model.holdCompare(false)
        #expect(!model.showsOriginal)
        #expect(model.recipe == recipe && model.history.undoEntries.count == steps)
    }

    /// AC-5: ✓ on the Look panel turns compare off; reopened it is off.
    @Test func closingLookPanelTurnsCompareOff() {
        let model = VideoStudioModelFixture.model(clips: gradedRecipe().clips, configure: { $0 = self.gradedRecipe() })
        model.showToolPanel(.look)
        model.toggleBeforeAfter(sideBySide: false, fromLookPanel: true)
        #expect(model.compare != nil)
        model.commitSession()
        #expect(model.compare == nil)
        model.showToolPanel(.look)
        #expect(model.compare == nil)
        // ✕ too.
        model.toggleBeforeAfter(sideBySide: false, fromLookPanel: true)
        model.cancelSession()
        #expect(model.compare == nil)
    }

    /// AC-6: iPad landscape, the pool folded — two frames of 448×252, 16
    /// apart, x 33 and 497 in the stage the board draws (x 17…961).
    @Test func iPadLandscapeFrames() {
        let frames = VideoBeforeAfter.sideBySideFrames(in: CGRect(x: 17, y: 80, width: 944, height: 440), aspect: 16.0 / 9, inset: 16, gap: 16)
        #expect(abs(frames.left.minX - 33) <= 1 && abs(frames.right.minX - 497) <= 1)
        #expect(abs(frames.left.width - 448) <= 1 && abs(frames.left.height - 252) <= 1)
        // And the pool folds and comes back as it was.
        var columns = VideoDeskColumns()
        columns.isPoolOpen = true
        columns.compareModeChanged(from: nil, to: .sideBySide)
        #expect(columns.isPoolOpen == false)
        columns.compareModeChanged(from: .sideBySide, to: nil)
        #expect(columns.isPoolOpen == true)
        var fresh = VideoDeskColumns()
        fresh.compareModeChanged(from: nil, to: .sideBySide)
        fresh.compareModeChanged(from: .sideBySide, to: .split)
        #expect(fresh.isPoolOpen == nil, "back to the window's default")
    }

    /// AC-9: iPad portrait, Swap sides — After at x 28, Before at x 502.
    @Test func swapPutsAfterLeft() {
        let model = VideoStudioModelFixture.model(clips: gradedRecipe().clips, configure: { $0 = self.gradedRecipe() })
        model.toggleBeforeAfter(sideBySide: true)
        model.swapCompareSides()
        #expect(model.compare?.isSwapped == true)
        let frames = VideoBeforeAfter.sideBySideFrames(in: CGRect(x: 12, y: 120, width: 964, height: 400), aspect: 16.0 / 9, inset: 16, gap: 16)
        let after = model.compare!.isSwapped ? frames.left : frames.right
        let before = model.compare!.isSwapped ? frames.right : frames.left
        #expect(abs(after.minX - 28) <= 1 && abs(before.minX - 502) <= 1)
        #expect(abs(after.width - 458) <= 1)
    }
}

/// The pair frame through the real compositor (FS-12.15 AC-2, AC-8, AC-13):
/// one request, Before on the left, After on the right.
@Suite(.serialized) @MainActor
struct VideoBeforeAfterRenderTests {
    private func firstFrame(_ recipe: VideoProjectRecipe, source: VideoClipSource, canvas: CGSize, at seconds: Double = 0.5) async throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let (composition, layout) = try VideoCompositionBuilder.build(
            recipe: recipe, sources: [recipe.clips[0].id: source], musicSources: [:], blankVideo: nil, renderSize: canvas
        )
        let videoComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe, layout: layout, stillStore: StillFrameStore(targetLongEdge: 640),
            bakesOverlays: false, renderSize: canvas, stage: .pair
        )
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: seconds, preferredTimescale: 600), duration: CMTime(seconds: 0.2, preferredTimescale: 600))
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: composition.tracks(withMediaType: .video), videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.videoComposition = videoComposition
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw CancellationError()
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                for channel in 0..<4 { bytes[(row * width + column) * 4 + channel] = base[row * rowBytes + column * 4 + channel] }
            }
        }
        reader.cancelReading()
        return (width, height, bytes)
    }

    private func pixel(_ frame: (width: Int, height: Int, bytes: [UInt8]), _ x: Int, _ y: Int) -> [Int] {
        let index = (y * frame.width + x) * 4
        return [Int(frame.bytes[index + 2]), Int(frame.bytes[index + 1]), Int(frame.bytes[index])]
    }

    private func project(directory: URL) async throws -> (VideoProjectRecipe, VideoClipSource) {
        let file = directory.appendingPathComponent("grey.mp4")
        try await VideoExportFixtures.writeVideo(width: 320, height: 180, seconds: 1, fill: .flat(red: 0.4, green: 0.4, blue: 0.4), to: file)
        var recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("grey", seconds: 1)])
        recipe.nodes[0].adjustments.exposure = 0.8
        return (recipe, try await VideoExportFixtures.videoSource(file))
    }

    /// AC-2: the left half is the frame with nothing applied, the right
    /// half the graded one — from the same request.
    @Test func leftIsBeforeRightIsAfter() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (recipe, source) = try await project(directory: directory)
        var plain = recipe
        plain.nodes = [ColorNode()]
        let pair = try await firstFrame(recipe, source: source, canvas: CGSize(width: 320, height: 180))
        let reference = try await firstFrame(plain, source: source, canvas: CGSize(width: 320, height: 180))
        #expect(pair.width == 640 && pair.height == 180)
        let left = pixel(pair, 160, 90)
        let ungraded = pixel(reference, 160, 90)
        #expect(zip(left, ungraded).allSatisfy { abs($0 - $1) <= 1 }, "left \(left) vs plain \(ungraded)")
        let right = pixel(pair, 480, 90)
        #expect(right[1] > left[1] + 20, "after \(right) is brighter than before \(left)")
    }

    /// AC-13: de-log on — Before is still the source's flat picture.
    @Test func beforeDropsDeLogInPixels() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, source) = try await project(directory: directory)
        recipe.nodes = [ColorNode()]
        let plain = try await firstFrame(recipe, source: source, canvas: CGSize(width: 320, height: 180))
        recipe.inputTransform = .sLog3
        let delogged = try await firstFrame(recipe, source: source, canvas: CGSize(width: 320, height: 180))
        #expect(zip(pixel(delogged, 160, 90), pixel(plain, 160, 90)).allSatisfy { abs($0 - $1) <= 1 })
        #expect(pixel(delogged, 480, 90) != pixel(plain, 480, 90), "After de-logs")
    }

    /// AC-8: a different Amount changes After only; Before holds to the pixel.
    @Test func amountDragChangesOnlyAfter() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, source) = try await project(directory: directory)
        recipe.nodes = [ColorNode()]
        recipe.look = { var look = VideoLook(.preset(.velvia)); look.amount = 0.8; return look }()
        let at80 = try await firstFrame(recipe, source: source, canvas: CGSize(width: 320, height: 180))
        recipe.look?.amount = 0.4
        let at40 = try await firstFrame(recipe, source: source, canvas: CGSize(width: 320, height: 180))
        #expect(pixel(at80, 160, 90) == pixel(at40, 160, 90))
        #expect(pixel(at80, 480, 90) != pixel(at40, 480, 90))
    }
}
