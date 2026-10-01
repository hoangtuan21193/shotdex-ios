import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 §4 — the share sheet's header line and the app's two rows.
struct ShareBatchPlanTests {

    /// AC-7: at No Location the header says so and the two rows are the two
    /// other levels; the level in force has no row.
    @Test func rowsAndSubtitle() {
        let plan = ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 0)
        #expect(plan.subtitle == .locationRemoved)
        #expect(plan.rows == [.all, .noMetadata])
        #expect(ShareLevelRow.title(for: .all) == "Share With Location")
        #expect(ShareLevelRow.title(for: .noMetadata) == "Share Without Metadata")

        let all = ShareBatchPlan(level: .all, photoCount: 3, videoCount: 0)
        #expect(all.subtitle == .allMetadata)
        #expect(all.rows == [.noLocation, .noMetadata])
        #expect(ShareLevelRow.title(for: .noLocation) == "Share Without Location")

        let none = ShareBatchPlan(level: .noMetadata, photoCount: 2, videoCount: 0)
        #expect(none.subtitle == .metadataRemoved)
        #expect(none.rows == [.all, .noLocation])
        for plan in [plan, all, none] { #expect(plan.rows.count == 2) }
    }

    /// Video goes as it is at every level, so a share of only videos has no
    /// level to change.
    @Test func videosOnlyHaveNoRows() {
        #expect(ShareBatchPlan(level: .noLocation, photoCount: 0, videoCount: 2).rows.isEmpty)
    }
}
