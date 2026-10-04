import Foundation
import UIKit
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

extension VideoExportFlowTests {
    /// AC-8: leaving the app mid-export stops it like Cancel, leaves no
    /// file, and Export Video says why on return.
    @Test func backgroundingCancelsAndExplains() async throws {
        let directory = try VideoExportFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("long.mp4")
        try await VideoExportFixtures.writeVideo(width: 640, height: 360, seconds: 12, to: file)
        let clip = VideoExportFixtures.videoClip("long", seconds: 12)
        let model = VideoStudioModelFixture.model(clips: [clip])
        defer { model.close() }
        model.sources[clip.id] = try await VideoExportFixtures.videoSource(file)
        model.availableBytes = { nil }
        // A center of its own: posting the real one would stop every other
        // export the suites run in parallel.
        let notifications = NotificationCenter()
        model.exportNotifications = notifications
        model.export()
        for _ in 0..<2000 {
            if case .exporting(let progress) = model.exportState, progress > 0.05 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for _ in 0..<300 where model.isExportBusy {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.exportState == .failed("Export stopped when you left ShotDex. Export again to finish."))
        #expect(model.savedAssetID == nil)
    }
}
