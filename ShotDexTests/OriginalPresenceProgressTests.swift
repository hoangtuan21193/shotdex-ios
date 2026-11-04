import Foundation
import Testing
@testable import ShotDex

/// FS-06.10 §3 — the line under an album on the Original rule.
struct OriginalPresenceProgressTests {
    @Test func runningShowsCounts() {
        let line = OriginalPresenceProgressLine.text(checked: 12_400, total: 55_000, finishedAt: nil)
        #expect(line == "Checking originals · \(12_400.formatted()) of \(55_000.formatted())")
    }

    /// AC-9: under `.limited` the total is the shared items — the line just
    /// says what it is given.
    @Test func limitedTotal() {
        #expect(OriginalPresenceProgressLine.text(checked: 12, total: 40, finishedAt: nil).hasSuffix("of 40"))
    }

    @Test func doneShowsWhen() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let line = OriginalPresenceProgressLine.text(checked: 40, total: 40, finishedAt: now.addingTimeInterval(-180), now: now)
        #expect(line.hasPrefix("Originals checked "))
    }

    /// A pass that found new items after it finished is running again.
    @Test func newItemsAfterAFinishedPassShowCounts() {
        let line = OriginalPresenceProgressLine.text(checked: 39, total: 40, finishedAt: Date())
        #expect(line.hasPrefix("Checking originals"))
    }
}
