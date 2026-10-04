import Foundation
import Testing
@testable import ShotDex

/// Export Video's flow (FS-12.10b): opening it, leaving it for Video
/// Settings, and the ways an export ends.
@Suite(.serialized) @MainActor
struct VideoExportFlowTests {
    private func model() -> VideoStudioModel {
        VideoStudioModelFixture.model(clips: VideoStudioModelFixture.photoClips(2))
    }

    /// AC-1: the Export button opens Export Video and nothing is exported:
    /// no progress, no Quality, the project untouched.
    @Test func firstTapOpensNeverExports() {
        let model = model()
        defer { model.close() }
        let before = model.recipe
        model.showToolPanel(.export)
        #expect(model.activeToolPanel == .export)
        #expect(model.exportState == .idle)
        #expect(!model.isExportBusy)
        #expect(model.recipe == before)
        #expect(VideoToolPanel.export.title == "Export Video")
        #expect(model.exportSpecSummary == "1920×1080 · 30 fps · H.264")
    }

    /// AC-2: the Custom row closes Export Video and opens Video Settings.
    @Test func customOpensVideoSettings() {
        let model = model()
        defer { model.close() }
        model.showToolPanel(.export)
        model.openVideoSettingsFromExport()
        #expect(model.activeToolPanel == .videoSettings)
    }
}

extension VideoExportFlowTests {
    /// AC-7 (model): with 40 MB free and a ~30 MB export the button does
    /// not start an export; it says how much is needed.
    @Test func notEnoughSpaceDoesNotStart() {
        var clip = VideoClip(assetID: "a", kind: .photo)
        clip.photoDuration = 24
        let model = VideoStudioModelFixture.model(clips: [clip]) { $0.aspect = .r9x16 }
        defer { model.close() }
        model.availableBytes = { 40_000_000 }
        model.export()
        #expect(model.exportState == .failed("Not enough space to export — about 60 MB needed. Free up space, then try again."))
        #expect(!model.isExportBusy)
    }
}
