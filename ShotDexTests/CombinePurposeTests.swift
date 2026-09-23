import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// The Combine Photos submenu as data (FS-01.09 AC-2, AC-4, AC-6): which rows,
/// in what order, and which stack mode each screen runs.
struct CombinePurposeTests {

    @Test func theSubmenuIsThreeRowsInOrder() {
        #expect(CombinePurpose.allCases == [.focusStack, .panorama, .stackExposures])
        #expect(CombinePurpose.allCases.map(\.title) == ["Focus Stack", "Panorama", "Stack Exposures"])
    }

    @Test func everyPurposeHasAScreenBehindIt() {
        // FS-14 landed the panorama screen, so the submenu is complete: a row
        // is listed only when the thing it opens exists.
        for purpose in CombinePurpose.allCases {
            #expect(purpose.isAvailable, "\(purpose.title)")
        }
        #expect(CombinePurpose.menuRows == [.focusStack, .panorama, .stackExposures])
    }

    @Test func noRowIsNamedAfterABlend() {
        let operators = ["Average", "Lighten", "Darken"]
        for purpose in CombinePurpose.allCases {
            #expect(!operators.contains { purpose.title.contains($0) }, "\(purpose.title)")
        }
    }

    @Test func focusStackIsOneModeWithNoPicker() {
        #expect(CombinePurpose.focusStack.stackModes == [.focusStack])
        #expect(!CombinePurpose.focusStack.showsModePicker)
    }

    @Test func stackExposuresOffersThreeModesAndOpensOnAverage() {
        #expect(CombinePurpose.stackExposures.stackModes == [.average, .lighten, .darken])
        #expect(CombinePurpose.stackExposures.defaultMode == .average)
        #expect(CombinePurpose.stackExposures.showsModePicker)
    }

    @Test func everyStackModeIsReachableFromExactlyOneRow() {
        // AC-4: the menu reaches the same four modes the old picker did — none
        // dropped, none offered twice.
        let reached = CombinePurpose.allCases.flatMap(\.stackModes)
        #expect(Set(reached) == Set(PhotoStackMode.allCases))
        #expect(reached.count == PhotoStackMode.allCases.count)
    }

    @Test func eachModeSaysWhatItIsFor() {
        #expect(PhotoStackMode.average.purposeDescription == "Reduces noise, or smooths water and clouds like a long exposure.")
        #expect(PhotoStackMode.lighten.purposeDescription == "Keeps the brightest light from every frame — star trails, traffic, fireworks.")
        #expect(PhotoStackMode.darken.purposeDescription == "Clears people and cars that moved between frames. Shoot from a tripod.")
        #expect(PhotoStackMode.focusStack.purposeDescription == "Keeps the sharpest part of every frame, for depth of field no single shot can reach.")
    }

    @Test func thePickerShowsTheBlendNames() {
        #expect(CombinePurpose.stackExposures.stackModes.map(\.displayName) == ["Average", "Lighten", "Darken"])
    }

    @Test func rowsDimBelowTwoPhotos() {
        for purpose in CombinePurpose.allCases {
            #expect(!purpose.isEnabled(imageCount: 0))
            #expect(!purpose.isEnabled(imageCount: 1))
            #expect(purpose.isEnabled(imageCount: 2))
        }
    }
}
