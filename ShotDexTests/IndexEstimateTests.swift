import Foundation
import Testing
@testable import ShotDex

/// FS-19 01 §4 — one way to say how long an index run has left.
@Suite struct IndexEstimateTests {
    /// AC-5: 3,812 files. At 150 read there is no number ("Estimating
    /// time…"); at 200, read at 20 files a second, 3,612 are left — about
    /// 3 minutes, to the nearest minute.
    @Test func waitsFor200ThenRoundsToMinutes() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let total = 3_812
        var estimate = IndexEstimate()
        for processed in stride(from: 0, through: 150, by: 10) {
            estimate.record(processed: processed, at: start.addingTimeInterval(Double(processed) / 20))
        }
        #expect(estimate.secondsLeft(remaining: total - 150) == nil)
        #expect(IndexThroughput(photosPerMinute: 1_200, remaining: nil).summaryLine.hasPrefix("Estimating time…"))

        for processed in stride(from: 160, through: 200, by: 10) {
            estimate.record(processed: processed, at: start.addingTimeInterval(Double(processed) / 20))
        }
        let seconds = estimate.secondsLeft(remaining: total - 200)
        #expect(seconds.map { abs($0 - 180.6) < 0.01 } == true)
        #expect(IndexThroughput(photosPerMinute: 1_200, remaining: seconds.map { .seconds($0) }).remainingText
            == "About 3 min left")
    }

    /// The speed is the last 200 items', so a run that slows down shows it.
    @Test func speedFollowsTheLast200() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var estimate = IndexEstimate()
        // 400 items at 40 a second, then 200 at 10 a second.
        for processed in stride(from: 0, through: 400, by: 20) {
            estimate.record(processed: processed, at: start.addingTimeInterval(Double(processed) / 40))
        }
        for processed in stride(from: 420, through: 600, by: 20) {
            estimate.record(processed: processed, at: start.addingTimeInterval(10 + Double(processed - 400) / 10))
        }
        #expect(estimate.itemsPerSecond.map { abs($0 - 10) < 0.001 } == true)
    }
}
