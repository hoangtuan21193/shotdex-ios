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
}
