import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// A clip whose original is still in iCloud (FS-12.04 §7, AC-11).
@MainActor
struct VideoUnavailableClipTests {
    /// FS-12.04 AC-11: clip 1, a video not downloaded, stays on the track
    /// and is selectable; Freeze and Split are dimmed with "Waiting for
    /// iCloud" under the row; the rest of the row works.
    @Test func anUnavailableClipStaysAndBlocksFreeze() {
        let model = VideoStudioModelFixture.model()
        let clip1 = model.recipe.clips[0]
        model.sources[clip1.id] = .unavailable(assetID: clip1.assetID)

        model.selectClip(clip1.id)
        #expect(model.selectedClipID == clip1.id)
        #expect(model.isClipUnavailable(clip1.id))
        #expect(!model.isItemCommandEnabled(.freeze))
        #expect(!model.isItemCommandEnabled(.split))
        #expect(model.isItemCommandEnabled(.speed))
        #expect(model.isItemCommandEnabled(.delete))
        #expect(model.itemCommandNote == "Waiting for iCloud")

        model.selectClip(model.recipe.clips[1].id)
        #expect(model.isItemCommandEnabled(.freeze))
        #expect(model.itemCommandNote == nil)
    }

    /// The builder keeps an unavailable clip's window: placements, total and
    /// instructions tile [0, total) exactly as if the clip were there.
    @Test func unavailableClipIsAWellFormedGap() throws {
        var recipe = VideoProjectRecipe(clips: VideoStudioModelFixture.photoClips(3))
        recipe.syncTransitionsWithClips()
        var sources: [UUID: VideoClipSource] = [:]
        for clip in recipe.clips {
            sources[clip.id] = .photo(assetID: clip.assetID, pixelSize: CGSize(width: 100, height: 100))
        }
        sources[recipe.clips[1].id] = .unavailable(assetID: recipe.clips[1].assetID)

        let built = try VideoCompositionBuilder.build(
            recipe: recipe, sources: sources, musicSources: [:], blankVideo: nil,
            renderSize: CGSize(width: 1920, height: 1080)
        )
        #expect(abs(built.layout.totalDuration - 9) < 0.001)
        let segments = built.layout.segments
        #expect(!segments.isEmpty)
        #expect(segments.first?.timeRange.start == .zero)
        for (previous, next) in zip(segments, segments.dropFirst()) {
            #expect(previous.timeRange.end == next.timeRange.start)
        }
        #expect(abs((segments.last?.timeRange.end.seconds ?? 0) - 9) < 0.01)
        // The middle segment belongs to clip 2, and draws nothing over the
        // background.
        #expect(segments.contains { $0.frontClip.clipID == recipe.clips[1].id })
    }
}
