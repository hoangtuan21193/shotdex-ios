import Foundation
import Testing
@testable import ShotDexKit

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
}
