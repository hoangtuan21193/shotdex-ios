import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

/// Video Settings in the model (FS-12.10 §5): every change is one undo
/// step, and the 4K gate follows the clips.
@Suite(.serialized) @MainActor
struct VideoStudioSettingsTests {
    /// A library of photos whose sizes the test names.
    struct Library: VideoSourceLoading {
        let sizes: [String: CGSize]
        func items(for ids: [String]) async -> [String: VideoSourceItem] {
            var items: [String: VideoSourceItem] = [:]
            for id in ids {
                guard let size = sizes[id] else { continue }
                items[id] = VideoSourceItem(
                    original: OriginalItem(id: id, filename: "\(id).jpg", photo: PixelSize(width: Int(size.width), height: Int(size.height))),
                    isVideo: false, pixelSize: size, duration: 0
                )
            }
            return items
        }
        func localAVAsset(for id: String) async -> AVAsset? { nil }
    }

    /// AC-6: a project of 4K photos at 4K; adding a 1920×1080 photo drops
    /// it to 1080p, and one Undo takes the photo back and 4K with it.
    @Test func addingA1080ClipDropsTo1080pInOneUndo() async throws {
        let clips = VideoStudioModelFixture.photoClips(2)
        let model = VideoStudioModelFixture.model(clips: clips, configure: { $0.resolution = .uhd4K }) { service in
            service.sourceLoader = Library(sizes: ["Small": CGSize(width: 1920, height: 1080)])
        }
        defer { model.close() }
        for clip in model.recipe.clips {
            model.sources[clip.id] = .photo(assetID: clip.assetID, pixelSize: CGSize(width: 4032, height: 3024))
        }
        #expect(model.fourKVerdict == .allowed)
        model.insertMedia([VideoMediaPick(assetID: "Small", kind: .photo)])
        for _ in 0..<300 where model.recipe.resolution == .uhd4K {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.recipe.resolution == .p1080)
        #expect(model.recipe.clips.count == 3)
        #expect(VideoStudioCopy.fourKReason(model.fourKVerdict) == "4K needs 4K clips — 1 of your 3 clips is 1080p.")
        model.undo()
        #expect(model.recipe.clips.count == 2)
        #expect(model.recipe.resolution == .uhd4K)
    }
}

extension VideoStudioSettingsTests {
    /// FS-12.10 §5: every tap in Video Settings is one undo step, and
    /// resolution, rate and codec leave the preview alone; a Blur drag is
    /// one step however far it goes.
    @Test func eachTapIsOneUndo() {
        let model = VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(2))
        defer { model.close() }
        let start = model.recipe
        model.showToolPanel(.videoSettings)
        model.setAspect(.r9x16)
        model.setFraming(.fill)
        model.setFraming(.fit)
        model.setBackgroundKind(.blur)
        model.beginUndoGroup()
        for amount in stride(from: 50.0, through: 80, by: 5) { model.setBlurAmount(amount) }
        model.endUndoGroup()
        model.setBackground(.white)
        model.setResolution(.p720)
        model.setFrameRate(.fps60)
        model.setCodec(.hevc)
        #expect(model.recipe.aspect == .r9x16 && model.recipe.background.kind == .colour && model.recipe.codec == .hevc)
        #expect(model.outputSummary() == "720×1280 · 0:06 · ~4 MB")
        var steps = 0
        while model.canUndo {
            model.undo()
            steps += 1
        }
        #expect(steps == 9)
        #expect(model.recipe == start)
    }

    /// 4K is refused while the gate is shut — no step, nothing changes.
    @Test func lockedFourKIsNotAStep() {
        let clips = VideoStudioModelFixture.photoClips(1)
        let model = VideoStudioModelFixture.model(clips: clips)
        defer { model.close() }
        model.sources[clips[0].id] = .photo(assetID: clips[0].assetID, pixelSize: CGSize(width: 1920, height: 1080))
        model.setResolution(.uhd4K)
        #expect(model.recipe.resolution == .p1080)
        #expect(!model.canUndo)
    }
}

extension VideoStudioSettingsTests {
    /// AC-11 (words): the button reads "Video Settings, 16:9, 1080p,
    /// 30 fps" and a dimmed 4K "4K, unavailable"; nothing is called Export
    /// Settings.
    @Test func videoSettingsIsTheOneName() {
        let recipe = VideoProjectRecipe(clips: [])
        #expect(VideoStudioCopy.videoSettingsAccessibility(recipe) == "Video Settings, 16:9, 1080p, 30 fps")
        #expect(VideoStudioCopy.unavailable("4K") == "4K, unavailable")
        #expect(VideoToolPanel.videoSettings.title == "Video Settings")
    }

    /// FS-12.10 AC-9 (iPad form): the popover is 400×548 — 16 in, labels in
    /// 96, 8 to the controls in 264, 16 out; Ratio is a 150 pop-up that
    /// offers every ratio, in VideoAspect's order.
    @Test func theIPadVideoSettingsIsAForm400By548() {
        let form = VideoStudioMetrics.SettingsForm.self
        #expect(VideoStudioMetrics.videoSettingsPopoverSize == CGSize(width: 400, height: 548))
        #expect(form.inset * 2 + form.labelWidth + form.labelGap + form.controlWidth == 400)
        #expect(form.ratioWidth == 150 && form.doneSize == CGSize(width: 72, height: 44))
        #expect(VideoAspect.allCases.count == 6)
        #expect(Set(VideoAspect.allCases.map(\.displayName)).count == VideoAspect.allCases.count)
    }
}
