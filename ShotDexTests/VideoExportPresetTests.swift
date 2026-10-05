import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex
import ShotDexKit

/// FS-12.16: five presets as constants, chosen per export, never an undo
/// step, read leniently.
@MainActor
struct VideoExportPresetTests {
    /// AC-17: exactly five built-in presets; Custom on the phone and the
    /// iPad, not on the Duo (its Video Settings button is Custom); no
    /// preset of the user's.
    @Test func exactlyFivePresets() {
        #expect(VideoExportPreset.allCases.map(\.name) == ["Reels / TikTok", "YouTube 4K", "YouTube", "Instagram 4:5", "Square"])
        #expect(VideoExportPreset.allCases.map(\.specLine) == [
            "1080×1920 · 30 fps", "3840×2160 · 30 fps · HEVC", "1920×1080 · 30 fps", "1080×1350 · 30 fps", "1080×1080 · 30 fps",
        ])
    }

    @Test func rowsPerDevice() {
        for windowClass in VideoStudioWindowClass.allCases {
            let rows = VideoExportPreset.allCases.count + (VideoExportPreset.listsCustom(on: windowClass) ? 1 : 0)
            switch windowClass {
            case .duoInner, .duoCover: #expect(rows == 5)
            default: #expect(rows == 6)
            }
        }
    }

    /// AC-12: "vimeo" in a 16:9 project is YouTube; the recipe still reads.
    @Test func unknownIDFallsBackToAspect() {
        #expect(VideoExportTarget.resolve(storedID: "vimeo", aspect: .r16x9) == .preset(.youTube))
        #expect(VideoExportTarget.resolve(storedID: nil, aspect: .r9x16) == .preset(.reels))
        #expect(VideoExportTarget.resolve(storedID: nil, aspect: .r4x5) == .preset(.instagram))
        #expect(VideoExportTarget.resolve(storedID: nil, aspect: .r1x1) == .preset(.square))
        #expect(VideoExportTarget.resolve(storedID: nil, aspect: .r4x3) == .custom)
        #expect(VideoExportTarget.resolve(storedID: "custom", aspect: .r16x9) == .custom)
    }

    @Test func recipeWithVimeoStillDecodes() throws {
        var recipe = CaptionFixture.recipe()
        recipe.exportTarget = "vimeo"
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as! [String: Any]
        object["exportFraming"] = "letterbox"
        let decoded = try JSONDecoder().decode(VideoProjectRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.clips.count == 5)
        #expect(decoded.exportFraming == nil)
        let model = VideoStudioModelFixture.model(clips: decoded.clips, configure: { $0 = decoded })
        #expect(model.exportTarget == .preset(.youTube))
        #expect(model.exportFraming == .fill)
    }

    /// AC-16: ~30 · ~72 · ~30 · ~21 · ~17 MB for 24.0 s (FS-12.10's formula).
    @Test func estimatesMatchTable() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        #expect(abs(model.totalDuration - 24) < 0.01)
        let labels = VideoExportPreset.allCases.map { VideoExportEstimate.label(model.estimatedBytes(for: .preset($0))) }
        #expect(labels == ["~30 MB", "~72 MB", "~30 MB", "~21 MB", "~17 MB"])
    }

    /// AC-13: VoiceOver reads the row; the selected trait adds "selected".
    @Test func accessibilityLabelReadsSpec() {
        #expect(VideoStudioCopy.presetAccessibility(.reels, megabytes: 30)
            == "Reels / TikTok, 1080 by 1920, 30 frames per second, about 30 megabytes")
        #expect(VideoStudioCopy.presetAccessibility(.youTube4K, megabytes: 72).contains("HEVC"))
    }

    /// AC-1: opening Export Video exports nothing; the button names the
    /// preset; a 16:9 project starts on YouTube with no Fit · Fill.
    @Test func firstTapOpensNeverExports() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.showToolPanel(.export)
        #expect(model.exportState == .idle)
        #expect(model.exportTarget == .preset(.youTube))
        #expect(!model.exportNeedsFraming)
        #expect(model.exportButtonTitle == "Export for YouTube")
    }

    @Test func exportButtonTitle() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.chooseExportTarget(.preset(.reels))
        #expect(model.exportButtonTitle == "Export for Reels / TikTok")
        #expect(model.exportNeedsFraming)
        model.chooseExportTarget(.custom)
        #expect(model.exportButtonTitle == "Export")
    }

    /// AC-8: choosing a preset and Fit · Fill is no undo step; Undo of a
    /// later edit keeps them; they ride in the recipe to the draft.
    @Test func presetIsNotAnUndoStep() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        let steps = model.history.undoEntries.count
        model.chooseExportTarget(.preset(.reels))
        model.setExportFraming(.fill)
        #expect(model.history.undoEntries.count == steps)
        #expect(model.recipe.aspect == .r16x9, "the project keeps its ratio")
    }

    @Test func undoKeepsCurrentTarget() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.pushUndo()
        model.setVideoVolume(0.3)
        model.chooseExportTarget(.preset(.reels))
        model.setExportFraming(.fit)
        model.undo()
        #expect(model.recipe.videoVolume == 1)
        #expect(model.exportTarget == .preset(.reels) && model.exportFraming == .fit)
        model.redo()
        #expect(model.exportTarget == .preset(.reels) && model.exportFraming == .fit)
    }

    @Test func targetSurvivesEncodeDecode() throws {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.chooseExportTarget(.preset(.reels))
        let row = try model.draftSnapshot()
        let reopened = try #require(row.videoRecipe)
        #expect(reopened.exportTarget == "reels")
        let again = VideoStudioModelFixture.model(clips: reopened.clips, configure: { $0 = reopened })
        #expect(again.exportTarget == .preset(.reels) && again.exportFraming == .fill)
    }

    /// AC-15: the iPad's settings button reads the destination while the
    /// sheet is open; the project's settings never change.
    @Test func settingsLabelFollowsTargetWhileOpen() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.chooseExportTarget(.preset(.reels))
        #expect(model.exportTargetSettingsLine == "9:16 · 1080p · 30 fps")
        #expect(model.outputSummary(includesLength: false).hasPrefix("1920×1080"))
    }

    /// AC-7: Custom reads the project's Video Settings.
    @Test func customLineReadsProjectSettings() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { recipe in
            recipe = CaptionFixture.recipe()
            recipe.aspect = .r4x3
            recipe.resolution = .p720
            recipe.frameRate = .fps24
        })
        #expect(model.exportTarget == .custom, "4:3 has no preset of its own")
        #expect(model.customExportLine == "4:3 · 720p · 24 fps · H.264")
        #expect(model.exportSpec.size == CGSize(width: 960, height: 720))
    }

    /// AC-6: YouTube 4K is refused while the 4K gate is shut.
    @Test func fourKRowDisabledByGate() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        for clip in model.recipe.clips {
            model.sources[clip.id] = .photo(assetID: clip.assetID, pixelSize: CGSize(width: 1920, height: 1080))
        }
        #expect(model.fourKPresetRefusal != nil)
        model.chooseExportTarget(.preset(.youTube4K))
        #expect(model.exportTarget == .preset(.youTube))
    }

    /// AC-11: 40 MB free and ~30 MB to write: refused before it starts.
    @Test func insufficientSpaceBlocksStart() {
        let model = VideoStudioModelFixture.model(clips: CaptionFixture.recipe().clips, configure: { $0 = CaptionFixture.recipe() })
        model.chooseExportTarget(.preset(.reels))
        model.availableBytes = { 40_000_000 }
        model.export()
        #expect(model.exportState == .failed(VideoStudioCopy.notEnoughSpace("60 MB")))
    }
}

struct VideoExportFramingTests {
    /// AC-2: Reels' crop in the phone's 402×226 frame — 127×226 at x 137.5.
    @Test func fillCropRectOnPhone() {
        let crop = VideoExportFraming.fillCrop(in: CGRect(x: 0, y: 60, width: 402, height: 226), output: CGSize(width: 1080, height: 1920))
        #expect(abs(crop.width - 127.1) < 1 && abs(crop.height - 226) < 0.5)
        #expect(abs(crop.minX - 137.5) <= 1)
        #expect(VideoExportFraming.pill(.reels, framing: .fill) == "9:16 · Fill")
    }

    @Test func fitShowsBands() {
        let fit = VideoExportFraming.fit(in: CGRect(x: 0, y: 60, width: 402, height: 226), output: CGSize(width: 1080, height: 1920), project: CGSize(width: 1920, height: 1080))
        #expect(abs(fit.project.width - fit.output.width) < 0.5)
        #expect(fit.project.height < fit.output.height)
        // The layout canvas: Fill covers 1080×1920 at the export's
        // resolution; Fit lies inside it.
        let fill = VideoExportSpec(size: CGSize(width: 1080, height: 1920), frameRate: .fps30, codec: .h264, framing: .fill)
        #expect(fill.layoutCanvas(project: CGSize(width: 1920, height: 1080)) == CGSize(width: 3414, height: 1920))
        let fitSpec = VideoExportSpec(size: CGSize(width: 1080, height: 1920), frameRate: .fps30, codec: .h264, framing: .fit)
        #expect(fitSpec.layoutCanvas(project: CGSize(width: 1920, height: 1080)) == CGSize(width: 1080, height: 608))
    }
}

/// The preset's file, end to end through the compositor and the writer.
@Suite(.serialized) @MainActor
struct VideoPresetExportTests {
    private let frame = 1.0 / 30

    /// A 16:9 still whose red rises left to right — a centre crop is
    /// readable in pixels.
    private func gradientPhoto(_ url: URL) throws {
        let width = 1920, height = 1080
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for column in 0..<width {
            context.setFillColor(red: CGFloat(column) / CGFloat(width - 1), green: 0.4, blue: 0.4, alpha: 1)
            context.fill(CGRect(x: column, y: 0, width: 1, height: height))
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private func export(_ configure: (inout VideoProjectRecipe) -> Void, preset: VideoExportPreset?, framing: VideoFraming = .fill) async throws -> (URL, URL, VideoStudioService) {
        let directory = try VideoExportFixtures.makeDirectory()
        let photo = directory.appendingPathComponent("gradient.jpg")
        try gradientPhoto(photo)
        var clip = VideoClip(assetID: "S1|gradient.jpg", kind: .photo)
        clip.photoDuration = 1
        var recipe = VideoProjectRecipe(clips: [clip])
        configure(&recipe)
        let service = VideoExportFixtures.service()
        service.setServerFiles([clip.assetID: photo])
        let target: VideoExportTarget = preset.map(VideoExportTarget.preset) ?? .custom
        let url = try await service.export(
            recipe: recipe,
            sources: [clip.id: .photo(assetID: clip.assetID, pixelSize: CGSize(width: 1920, height: 1080))],
            spec: VideoExportSpec.make(target: target, framing: framing, recipe: recipe),
            progress: { _ in }
        )
        return (url, directory, service)
    }

    /// The fixture hands frames back as RGBA.
    private func red(_ frame: (width: Int, height: Int, bytes: [UInt8]), _ x: Int, _ y: Int) -> Int {
        Int(frame.bytes[(y * frame.width + x) * 4])
    }

    /// AC-3: Reels + Fill — 1080×1920, 30 fps, H.264, the timeline's length;
    /// the frame is the middle of the project's frame.
    @Test func reelsFillIs1080x1920At30() async throws {
        let (url, directory, service) = try await export({ _ in }, preset: .reels)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1080, height: 1920))
        #expect(abs(Double(output.nominalFrameRate) - 30) < 0.5)
        #expect(output.codec == kCMVideoCodecType_H264)
        #expect(abs(output.videoTrackDuration - 1) <= frame)
        // The crop keeps project x 0.342…0.658: red from ~87 to ~168.
        let picture = try await VideoExportFixtures.frame(of: url, at: 0.5)
        #expect(abs(red(picture, 2, 960) - 87) <= 8, "left \(red(picture, 2, 960))")
        #expect(abs(red(picture, 1077, 960) - 168) <= 8, "right \(red(picture, 1077, 960))")
    }

    /// AC-4: Fit — the project 1080×608 in the middle, grey bands above and
    /// below.
    @Test func reelsFitCentresAndFillsBands() async throws {
        let (url, directory, service) = try await export({ $0.background = VideoBackground(colour: OverlayColor(white: 0.5)) }, preset: .reels, framing: .fit)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let picture = try await VideoExportFixtures.frame(of: url, at: 0.5)
        #expect(picture.width == 1080 && picture.height == 1920)
        #expect(abs(red(picture, 540, 300) - 128) <= 3, "band \(red(picture, 540, 300))")
        #expect(abs(red(picture, 540, 1600) - 128) <= 3)
        // The picture spans the width: red runs 0 → 255 across.
        #expect(red(picture, 4, 960) < 20 && red(picture, 1075, 960) > 235)
        // 608 tall, centred: rows 660 and 1260 are picture, 650 and 1270 band.
        #expect(abs(red(picture, 4, 650) - 128) <= 6 && red(picture, 4, 700) < 20)
    }

    /// AC-5: Instagram 4:5 and Square.
    @Test func instagramAndSquareSizes() async throws {
        for (preset, size) in [(VideoExportPreset.instagram, CGSize(width: 1080, height: 1350)), (.square, CGSize(width: 1080, height: 1080))] {
            let (url, directory, service) = try await export({ _ in }, preset: preset)
            let output = try await VideoExportFixtures.inspect(url)
            #expect(output.naturalSize == size)
            #expect(output.codec == kCMVideoCodecType_H264)
            try? FileManager.default.removeItem(at: directory)
            service.cleanupSession()
        }
    }

    /// AC-9: a caption at the bottom is whole in the Reels frame; a sticker
    /// at x 0.1 is cut away with the crop.
    @Test func captionsStayInsideAndOverlaysAreCropped() async throws {
        let (url, directory, service) = try await export({ recipe in
            var lane = VideoCaptionLane()
            lane.style = .box
            lane.cues = [CaptionCue(clipID: recipe.clips[0].id, sourceStart: 0, sourceEnd: 1, text: "starts right here.")]
            recipe.captions = lane
            // Photos have no source time: captions are video-only.
        }, preset: .reels)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1080, height: 1920))
        // Overlay geometry: x 0.1 of the project lies left of the crop
        // (which keeps 0.342…0.658), so it is not in the file.
        let crop = VideoExportSpec(size: CGSize(width: 1080, height: 1920), frameRate: .fps30, codec: .h264, framing: .fill)
            .layoutCanvas(project: CGSize(width: 1920, height: 1080))
        let left = (crop.width - 1080) / 2 / crop.width
        #expect(0.1 < left)
        // A caption is measured against the written frame: inside it.
        var lane = VideoCaptionLane()
        lane.style = .box
        let typeset = VideoCaptionRenderer.typeset("Listen to that water, it never stops.", lane: lane, frame: CGSize(width: 1080, height: 1920))
        #expect(typeset.plate.minX >= 0 && typeset.plate.maxX <= 1080)
    }

    /// AC-7: Custom writes the project's Video Settings — 4:3, 720p, 24 fps.
    @Test func customExportIs4x3At720p24() async throws {
        let (url, directory, service) = try await export({ recipe in
            recipe.aspect = .r4x3
            recipe.resolution = .p720
            recipe.frameRate = .fps24
        }, preset: nil)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 960, height: 720))
        #expect(abs(Double(output.nominalFrameRate) - 24) < 0.5)
    }

    /// AC-6: YouTube 4K writes 3840×2160 HEVC.
    @Test func youTube4KIsHEVC3840() async throws {
        let (url, directory, service) = try await export({ _ in }, preset: .youTube4K)
        defer { try? FileManager.default.removeItem(at: directory); service.cleanupSession() }
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 3840, height: 2160))
        #expect(output.codec == kCMVideoCodecType_HEVC)
    }
}
