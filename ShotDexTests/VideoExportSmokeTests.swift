import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex
import ShotDexKit

/// The export path end to end, without PhotoKit: recipe → composition →
/// custom compositor → reader → writer → a file AVFoundation can open
/// (FS-12 README AC-6 to AC-8, FS-12.10, FS-12.10b, FS-12.01 §9).
@Suite(.serialized) @MainActor
struct VideoExportSmokeTests {
    /// One frame at 30 fps.
    private let frame = 1.0 / 30

    /// README AC-6: two clips, a crossfade and a music bed at 9:16 → a
    /// readable 1080×1920 file as long as the timeline, to within a frame.
    @Test func nineBySixteenWithTransitionAndMusic() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.mp4")
        let second = directory.appendingPathComponent("b.mp4")
        let tone = directory.appendingPathComponent("tone.m4a")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2, to: first)
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 2,
                                                 fill: .flat(red: 0.9, green: 0.9, blue: 0.1), to: second)
        try await VideoExportFixtures.writeTone(seconds: 3.5, to: tone)

        var recipe = VideoProjectRecipe(clips: [
            VideoExportFixtures.videoClip("a", seconds: 2),
            VideoExportFixtures.videoClip("b", seconds: 2),
        ])
        recipe.syncTransitionsWithClips()
        recipe.transitions[0] = .defaultCrossfade
        recipe.aspect = .r9x16
        var music = MusicTrack(source: .imported(url: tone, displayName: "Tone"))
        music.sourceDuration = 3.5
        music.trimEnd = 3.5
        recipe.musicTracks = [music]

        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(
            recipe: recipe,
            sources: [
                recipe.clips[0].id: try await VideoExportFixtures.videoSource(first),
                recipe.clips[1].id: try await VideoExportFixtures.videoSource(second),
            ],
            progress: { _ in }
        )
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1080, height: 1920))
        #expect(abs(output.videoTrackDuration - 3.5) < frame)
        #expect(output.audioTrackCount == 1)
    }

    /// README AC-7: a project of stills has a real video track — one frame
    /// per tick, no empty segment — and no empty audio track.
    @Test func photoOnlyProjectHasRealVideoAndNoEmptyAudio() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoA = directory.appendingPathComponent("a.jpg")
        let photoB = directory.appendingPathComponent("b.jpg")
        try VideoExportFixtures.writePhoto(width: 1200, height: 800, to: photoA)
        try VideoExportFixtures.writePhoto(width: 800, height: 1200, red: 0.1, green: 0.6, blue: 0.3, to: photoB)

        var clipA = VideoClip(assetID: "S1|a.jpg", kind: .photo)
        clipA.photoDuration = 1
        var clipB = VideoClip(assetID: "S1|b.jpg", kind: .photo)
        clipB.photoDuration = 1
        var recipe = VideoProjectRecipe(clips: [clipA, clipB])
        recipe.syncTransitionsWithClips()

        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        service.setServerFiles([clipA.assetID: photoA, clipB.assetID: photoB])
        let url = try await service.export(
            recipe: recipe,
            sources: [
                clipA.id: .photo(assetID: clipA.assetID, pixelSize: CGSize(width: 1200, height: 800)),
                clipB.id: .photo(assetID: clipB.assetID, pixelSize: CGSize(width: 800, height: 1200)),
            ],
            progress: { _ in }
        )
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1920, height: 1080))
        #expect(abs(output.videoTrackDuration - 2) < frame)
        #expect(abs(output.videoSampleCount - 60) <= 1)
        #expect(output.audioTrackCount == 0)
    }

    /// FS-12.10 AC-3: a landscape clip fitted into 9:16 over grey — the top
    /// row of the exported frame is #808080 ± 2, not a colour-managed shade
    /// near it.
    @Test func fitGreyBackgroundFillsTheBars() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 1, to: file)

        var recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("a", seconds: 1)])
        recipe.aspect = .r9x16
        recipe.background = VideoBackground(colour: OverlayColor(white: 0.5))

        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(
            recipe: recipe,
            sources: [recipe.clips[0].id: try await VideoExportFixtures.videoSource(file)],
            progress: { _ in }
        )
        let frame = try await VideoExportFixtures.frame(of: url, at: 0.5)
        #expect(frame.width == 1080 && frame.height == 1920)
        // Row 0, every 60th pixel, all three channels.
        var worst = 0
        for column in stride(from: 0, to: frame.width, by: 60) {
            for channel in 0..<3 {
                worst = max(worst, abs(Int(frame.bytes[column * 4 + channel]) - 128))
            }
        }
        #expect(worst <= 2, "top row is off #808080 by \(worst): \(Array(frame.bytes[0..<4]))")
    }

    /// FS-12.10 AC-12: 16:9 · 1080p · 30 fps · H.264 is ~10 Mbps — width ×
    /// height × fps × 0.16 bit — and the file is that rate times its length,
    /// both within 15 %. The source is fresh grain every frame, so the
    /// encoder's rate control has to hold the target rather than undershoot
    /// it on easy content.
    @Test func bitrateIsTenMbpsAt1080p30() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("grain.mp4")
        let seconds = 4.0
        try await VideoExportFixtures.writeVideo(width: 1920, height: 1080, seconds: seconds, fill: .grain(amplitude: 12), to: file)

        let recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("grain", seconds: seconds)])
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(
            recipe: recipe,
            sources: [recipe.clips[0].id: try await VideoExportFixtures.videoSource(file)],
            progress: { _ in }
        )
        let output = try await VideoExportFixtures.inspect(url)
        let target = 1920.0 * 1080 * 30 * 0.16
        #expect(output.naturalSize == CGSize(width: 1920, height: 1080))
        #expect(abs(Double(output.estimatedDataRate) / target - 1) <= 0.15,
                "video rate \(output.estimatedDataRate) vs \(target)")
        let expectedBytes = target * seconds / 8
        #expect(abs(Double(output.fileBytes) / expectedBytes - 1) <= 0.15,
                "file \(output.fileBytes) B vs \(expectedBytes)")
    }
}

extension VideoExportSmokeTests {
    /// Two one-second clips of 1280×720 for the frame-rate tests.
    private func twoClips(in directory: URL) async throws -> (VideoProjectRecipe, [UUID: VideoClipSource]) {
        let a = directory.appendingPathComponent("a.mp4")
        let b = directory.appendingPathComponent("b.mp4")
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 1.5, to: a)
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 1.5,
                                                 fill: .flat(red: 0.9, green: 0.4, blue: 0.1), to: b)
        let recipe = VideoProjectRecipe(clips: [
            VideoExportFixtures.videoClip("a", seconds: 1.5), VideoExportFixtures.videoClip("b", seconds: 1.5),
        ])
        return (recipe, [
            recipe.clips[0].id: try await VideoExportFixtures.videoSource(a),
            recipe.clips[1].id: try await VideoExportFixtures.videoSource(b),
        ])
    }

    /// FS-12.10b AC-3: 9:16 at 24 fps writes a 1080×1920 H.264 file at 24
    /// frames a second, as long as the timeline to within one frame.
    @Test func nineBySixteenAt24fps() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, sources) = try await twoClips(in: directory)
        recipe.aspect = .r9x16
        recipe.frameRate = .fps24
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(recipe: recipe, sources: sources, progress: { _ in })
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1080, height: 1920))
        #expect(abs(output.nominalFrameRate - 24) < 0.5)
        #expect(output.codec == kCMVideoCodecType_H264)
        #expect(abs(output.videoTrackDuration - 3) < 1.0 / 24)
        #expect(abs(output.videoSampleCount - 72) <= 1)
    }

    /// FS-12.01 §8: the preview's composition runs at 30 whatever the
    /// export's rate; the export's at the project's.
    @Test func previewStaysAt30() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, sources) = try await twoClips(in: directory)
        recipe.frameRate = .fps60
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let preview = try await service.makePreviewItem(recipe: recipe, sources: sources)
        #expect(preview.playerItem.videoComposition?.frameDuration == CMTime(value: 1, timescale: 30))
        let exportComposition = VideoCompositionBuilder.videoComposition(
            recipe: recipe, layout: preview.layout, stillStore: StillFrameStore(targetLongEdge: 1920),
            bakesOverlays: true, frameRate: recipe.frameRate
        )
        #expect(exportComposition.frameDuration == CMTime(value: 1, timescale: 60))
    }
}

extension VideoExportSmokeTests {
    /// FS-12.10b AC-4: 60 fps · HEVC writes a 1920×1080 HEVC track at 60
    /// frames a second, as long as the timeline to within one frame.
    @Test func hevcAt60fps() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, sources) = try await twoClips(in: directory)
        recipe.frameRate = .fps60
        recipe.codec = .hevc
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(recipe: recipe, sources: sources, progress: { _ in })
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.naturalSize == CGSize(width: 1920, height: 1080))
        #expect(abs(output.nominalFrameRate - 60) < 0.5)
        #expect(output.codec == kCMVideoCodecType_HEVC)
        #expect(abs(output.videoTrackDuration - 3) < 1.0 / 60)
    }
}

extension VideoExportSmokeTests {
    /// FS-12.10 AC-2: a 16:9 clip in a 9:16 project, Fill — the exported
    /// frame's top and bottom rows are the clip's colour, not the
    /// background's.
    @Test func fillLeavesNoBackgroundPixel() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.mp4")
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 1,
                                                 fill: .flat(red: 0.9, green: 0.4, blue: 0.1), to: file)
        var recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("a", seconds: 1)])
        recipe.aspect = .r9x16
        recipe.framing = .fill
        recipe.background = VideoBackground(colour: OverlayColor(white: 0.5))
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(
            recipe: recipe, sources: [recipe.clips[0].id: try await VideoExportFixtures.videoSource(file)], progress: { _ in }
        )
        let frame = try await VideoExportFixtures.frame(of: url, at: 0.5)
        for row in [0, frame.height / 2, frame.height - 1] {
            for column in stride(from: 0, to: frame.width, by: 90) {
                let index = (row * frame.width + column) * 4
                #expect(frame.bytes[index] > 200 && frame.bytes[index + 2] < 60, "row \(row) column \(column)")
            }
        }
    }

    /// FS-12.01 §8, plan T-2: ratio and Fit/Fill are video-composition
    /// edits — the player item keeps its composition and only its video
    /// composition (and canvas) changes.
    @Test func aspectAndFramingKeepTheComposition() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var (recipe, sources) = try await twoClips(in: directory)
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let preview = try await service.makePreviewItem(recipe: recipe, sources: sources)
        let asset = preview.playerItem.asset
        #expect(preview.playerItem.videoComposition?.renderSize == CGSize(width: 1280, height: 720))
        recipe.aspect = .r9x16
        recipe.framing = .fill
        service.applyVideoComposition(recipe: recipe, layout: preview.layout, to: preview.playerItem)
        #expect(preview.playerItem.asset === asset)
        #expect(preview.playerItem.videoComposition?.renderSize == CGSize(width: 720, height: 1280))
    }
}

extension VideoExportSmokeTests {
    /// FS-12.10b AC-6, README AC-8: Cancel at half way stops the export
    /// within a second and leaves no .mp4 in the session folder.
    @Test func cancelStopsWithinASecondAndLeavesNoFile() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("long.mp4")
        try await VideoExportFixtures.writeVideo(width: 1280, height: 720, seconds: 20, fill: .grain(amplitude: 12), to: file)
        let recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("long", seconds: 20)])
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let source = try await VideoExportFixtures.videoSource(file)
        let reached = Reached()
        let export = Task { @MainActor in
            try await service.export(recipe: recipe, sources: [recipe.clips[0].id: source]) { reached.value = $0 }
        }
        for _ in 0..<12_000 where reached.value < 0.5 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reached.value >= 0.5)
        let cancelledAt = ContinuousClock.now
        export.cancel()
        var threwCancellation = false
        do { _ = try await export.value } catch is CancellationError { threwCancellation = true }
        let elapsed = ContinuousClock.now - cancelledAt
        #expect(threwCancellation)
        #expect(elapsed < .seconds(1), "stopped after \(elapsed)")
        let folder = try #require(service.sessionFolder)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("ShotDex-Video-") }
        #expect(left.isEmpty, "left behind: \(left)")
    }

    @MainActor final class Reached { var value = 0.0 }
}

extension VideoExportSmokeTests {
    /// FS-12.10b AC-14: a frame the H.264 encoder refuses (16384² — past
    /// any H.264 level, standing in for a device that refuses 2160×3840)
    /// ends in the sentence that names the way out, leaves no file, and
    /// keeps the codec H.264.
    @Test func refusedH264SizeSaysSwitchToHEVC() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.mp4")
        try await VideoExportFixtures.writeVideo(width: 320, height: 180, seconds: 0.5, to: file)
        let recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("a", seconds: 0.5)])
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let source = try await VideoExportFixtures.videoSource(file)
        let built = try await service.makePreviewItem(recipe: recipe, sources: [recipe.clips[0].id: source])
        let output = directory.appendingPathComponent("out.mp4")
        let encoding = VideoEncodingSettings(size: CGSize(width: 16384, height: 16384), frameRate: .fps30, codec: .h264, bitrate: 10_000_000)
        do {
            try await VideoExportWriter.write(
                composition: built.playerItem.asset as! AVComposition,
                videoComposition: built.playerItem.videoComposition!,
                audioMix: AVMutableAudioMix(), encoding: encoding, totalDuration: 0.5, to: output, progress: { _ in }
            )
            Issue.record("a 16384² H.264 frame should be refused")
        } catch {
            let ns = error as NSError
            #expect(error.localizedDescription == "This size can't be encoded as H.264 on this device. Switch Codec to HEVC.",
                    "\(ns.domain) \(ns.code) \(ns.userInfo)")
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(recipe.codec == .h264)
    }
}

extension VideoExportSmokeTests {
    /// FS-12.01 §9, FS-12.10 AC-16: the export says it is SDR Rec. 709 —
    /// primaries, transfer function and matrix are in the track's format
    /// description — so players show #808080 as #808080; the grey bars
    /// still hold 128 in the file.
    @Test func exportIsTaggedRec709() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 1, to: file)
        var recipe = VideoProjectRecipe(clips: [VideoExportFixtures.videoClip("a", seconds: 1)])
        recipe.aspect = .r9x16
        recipe.background = VideoBackground(colour: OverlayColor(white: 0.5))
        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        let url = try await service.export(
            recipe: recipe, sources: [recipe.clips[0].id: try await VideoExportFixtures.videoSource(file)], progress: { _ in }
        )
        let output = try await VideoExportFixtures.inspect(url)
        #expect(output.colorPrimaries == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(output.transferFunction == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(output.yCbCrMatrix == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
        let frame = try await VideoExportFixtures.frame(of: url, at: 0.5)
        #expect(abs(Int(frame.bytes[0]) - 128) <= 2)
    }
}

/// FS-12.17b AC-17: the In–Out range is where the user watches, not a cut
/// — the export writes the whole project. Six seconds, not AC-17's 24:
/// the length is the same rule and a quarter of the export time
/// (`VideoInOutExportTests.placementsIgnoreInOut` holds the 24.0).
@Suite(.serialized) @MainActor
struct VideoExportInOutSmokeTests {
    @Test func inOutDoesNotShortenTheExport() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoA = directory.appendingPathComponent("a.jpg")
        let photoB = directory.appendingPathComponent("b.jpg")
        try VideoExportFixtures.writePhoto(width: 1200, height: 800, to: photoA)
        try VideoExportFixtures.writePhoto(width: 1200, height: 800, red: 0.1, green: 0.6, blue: 0.3, to: photoB)

        var clipA = VideoClip(assetID: "S1|a.jpg", kind: .photo)
        clipA.photoDuration = 3
        var clipB = VideoClip(assetID: "S1|b.jpg", kind: .photo)
        clipB.photoDuration = 3
        var recipe = VideoProjectRecipe(clips: [clipA, clipB])
        recipe.syncTransitionsWithClips()
        recipe.inPoint = 1
        recipe.outPoint = 4
        let before = recipe.clips

        let service = VideoExportFixtures.service()
        defer { service.cleanupSession() }
        service.setServerFiles([clipA.assetID: photoA, clipB.assetID: photoB])
        let url = try await service.export(
            recipe: recipe,
            sources: [
                clipA.id: .photo(assetID: clipA.assetID, pixelSize: CGSize(width: 1200, height: 800)),
                clipB.id: .photo(assetID: clipB.assetID, pixelSize: CGSize(width: 1200, height: 800)),
            ],
            progress: { _ in }
        )
        let output = try await VideoExportFixtures.inspect(url)
        #expect(abs(output.videoTrackDuration - 6) < 1.0 / 30)
        #expect(recipe.clips == before)
    }
}
