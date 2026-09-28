import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.15d AC-46, AC-50 — Subject and Object over Vision's foreground
/// instances. The instance choice is tested here; Vision separating real
/// objects needs a device (or a Mac) and a CC0 photo, so its IoU half is
/// not in the simulator suite.
struct ObjectMaskTests {

    /// AC-50. Subject takes every instance, wherever (or whether) the photo
    /// was touched — no "Tap…" step.
    @Test func subjectTakesEveryObjectWithoutATap() {
        let all = IndexSet([1, 2])
        for tapped in [0, 1, 2] {
            #expect(PhotoRenderService.foregroundInstances(for: .subject, instanceAtPoint: tapped, all: all) == all)
        }
        #expect(PhotoRenderService.foregroundInstances(for: .subject, instanceAtPoint: 0, all: []) == nil)
    }

    /// AC-46. Object takes only the instance under the tap; a tap on
    /// background (instance 0) is nothing to select.
    @MainActor @Test func tapPicksOneObject() {
        let all = IndexSet([1, 2])
        #expect(PhotoRenderService.foregroundInstances(for: .object, instanceAtPoint: 1, all: all) == IndexSet(integer: 1))
        #expect(PhotoRenderService.foregroundInstances(for: .object, instanceAtPoint: 2, all: all) == IndexSet(integer: 2))
        #expect(PhotoRenderService.foregroundInstances(for: .object, instanceAtPoint: 0, all: all) == nil)
        #expect(PhotoEditorController.detectionFailureText(for: .object) == "Nothing to select there")
    }

    /// The editor side: an Object area waits for its tap (no point, so the
    /// stage asks for one), and the tap is what it selects from.
    @MainActor @Test func objectWaitsForATap() throws {
        let controller = PhotoEditorController(asset: PHAsset(), sourceAlbum: nil, service: PhotoEditingService())
        controller.addMask(option: .object)
        #expect(controller.selectedComponent?.kind == .object)
        #expect(controller.selectedComponent?.objectPoint == nil)
        controller.setAutomaticMaskPoint(NormalizedPoint(x: 0.3, y: 0.6))
        #expect(controller.selectedComponent?.objectPoint == NormalizedPoint(x: 0.3, y: 0.6))
    }
}
