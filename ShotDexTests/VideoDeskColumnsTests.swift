import CoreGraphics
import Testing
@testable import ShotDex

/// The wide layouts' side columns (FS-12.03 §5).
struct VideoDeskColumnsTests {
    /// FS-12.03 AC-8: the inspector shut, a selection opens it — ✕ · ✓
    /// live at its foot.
    @Test func selectingOpensAClosedInspector() {
        var columns = VideoDeskColumns()
        columns.isInspectorOpen = false
        columns.presentsSheetChanged(from: false, to: true)
        #expect(columns.isInspectorOpen)
    }

    /// Deselecting does not shut it again.
    @Test func deselectingLeavesItOpen() {
        var columns = VideoDeskColumns()
        columns.isInspectorOpen = false
        columns.presentsSheetChanged(from: false, to: true)
        columns.presentsSheetChanged(from: true, to: false)
        #expect(columns.isInspectorOpen)
    }

    /// Nothing else moves: the pool and Quick Adjust keep what the user set.
    @Test func aSelectionTouchesOnlyTheInspector() {
        var columns = VideoDeskColumns(isPoolOpen: false, isInspectorOpen: false, isQuickAdjustOpen: true)
        columns.presentsSheetChanged(from: false, to: true)
        #expect(columns.isPoolOpen == false)
        #expect(columns.isQuickAdjustOpen)
    }

    /// The columns are the screen's, not a layout's: computing another
    /// class's frames from them leaves them as they were (FS-12.03 §1).
    @Test func classChangeKeepsColumns() {
        let columns = VideoDeskColumns(isPoolOpen: false, isInspectorOpen: false, isQuickAdjustOpen: true)
        let before = columns
        for window in [CGSize(width: 1376, height: 1032), CGSize(width: 1032, height: 1376), CGSize(width: 951, height: 669)] {
            let input = VideoStudioDeskGeometry.Input(
                window: window, canvas: CGSize(width: 16, height: 9),
                isPoolOpen: columns.isPoolOpen ?? false, isInspectorOpen: columns.isInspectorOpen
            )
            _ = VideoStudioDeskGeometry.iPadLandscape(input)
            _ = VideoStudioDeskGeometry.iPadPortrait(input)
            _ = VideoStudioDeskGeometry.duoInner(input)
        }
        #expect(columns == before)
    }
}
