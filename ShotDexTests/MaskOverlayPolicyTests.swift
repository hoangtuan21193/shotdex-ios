import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.13c §3 — the red mask overlay, one rule at every layout.
@MainActor
struct MaskOverlayPolicyTests {

    private func brushController() -> PhotoEditorController {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.maskOverlayFadeDelay = .milliseconds(40)
        controller.addMask(option: .brush)
        controller.editSelectedMaskAdjustments()
        return controller
    }

    /// FS-03.13 AC-31. Chip off: on while painting, still on at the lift,
    /// gone once the fade has run, off at once when a slider moves. Chip on:
    /// it stays through the slider.
    @Test func autoOverlayFollowsPaintAndYieldsToSliders() async throws {
        let controller = brushController()
        #expect(!controller.isMaskOverlayPinned)
        try await Task.sleep(for: .milliseconds(120))
        controller.beginBrushStroke(at: NormalizedPoint(x: 0.3, y: 0.5))
        #expect(controller.showsMaskOverlay, "on while the finger paints")
        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.showsMaskOverlay, "no fade while the finger is down")
        controller.continueBrushStroke(at: NormalizedPoint(x: 0.5, y: 0.5))
        controller.endBrushStroke()
        #expect(controller.showsMaskOverlay, "still on at the lift")
        try await Task.sleep(for: .milliseconds(160))
        #expect(!controller.showsMaskOverlay, "faded after the lift")

        controller.beginBrushStroke(at: NormalizedPoint(x: 0.3, y: 0.6))
        controller.endBrushStroke()
        controller.setAdjustment(.exposure, value: 0.3)
        #expect(!controller.showsMaskOverlay, "a slider takes it away at once")

        controller.setMaskOverlay(true)
        controller.setAdjustment(.exposure, value: 0.5)
        #expect(controller.showsMaskOverlay, "pinned stays through the slider")
        try await Task.sleep(for: .milliseconds(160))
        #expect(controller.showsMaskOverlay, "and through the fade")
        controller.setMaskOverlay(false)
        #expect(!controller.showsMaskOverlay)
    }
}
