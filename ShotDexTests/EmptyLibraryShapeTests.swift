import CoreGraphics
import Testing
@testable import ShotDex

/// Which layout the empty library takes (FS-21 §3): cards side by side when
/// wide, stacked on a phone, one row per source on the Duo's short cover.
struct EmptyLibraryShapeTests {
    @Test func iPadAndDuoInnerAreWide() {
        #expect(EmptyLibraryView.shape(for: CGSize(width: 1032, height: 1376)) == .wide)
        #expect(EmptyLibraryView.shape(for: CGSize(width: 867, height: 669)) == .wide)
    }

    @Test func phoneStacks() {
        #expect(EmptyLibraryView.shape(for: CGSize(width: 402, height: 874)) == .stacked)
    }

    @Test func duoCoverUsesRows() {
        // 466pt cover minus its 84pt rail, 678pt tall.
        #expect(EmptyLibraryView.shape(for: CGSize(width: 382, height: 678)) == .rows)
    }
}
