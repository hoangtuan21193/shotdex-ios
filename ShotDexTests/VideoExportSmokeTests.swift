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
