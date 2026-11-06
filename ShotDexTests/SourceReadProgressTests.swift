import Foundation
import Testing
@testable import ShotDex

/// FS-19.01 §4: the banner's words while a folder is read.
struct SourceReadProgressTests {
    @Test func timeLeftIsWholeMinutesNeverSeconds() {
        #expect(SourceReadProgress.timeLeft(20) == "about 1 min left")
        #expect(SourceReadProgress.timeLeft(130) == "about 2 min left")
        #expect(SourceReadProgress.timeLeft(3600) == "about 1 h left")
        #expect(SourceReadProgress.timeLeft(4800) == "about 1 h 20 min left")
    }

    @Test func estimatingUntilTheFirst200Files() {
        var progress = SourceReadProgress(sourceId: "s", sourceName: "Client Shoots 2026", isAdding: true, done: 40, total: 3812)
        progress.estimate.record(processed: 40)
        #expect(progress.detail() == "40 of 3,812 photos read · Estimating time…")
        #expect(progress.title == "Adding “Client Shoots 2026”")
        #expect(progress.footLine == "Indexing 40 of 3,812")
    }

    @Test func pausedSaysNoTime() {
        let progress = SourceReadProgress(sourceId: "s", sourceName: "T7", isAdding: false, done: 1240, total: 3812, isPaused: true)
        #expect(progress.detail() == "1,240 of 3,812 photos read")
        #expect(progress.percent == 32)
    }

    @Test func reportsAreThrottledButKeepFirstAndLast() {
        let control = SourceReadControl()
        let now = Date()
        #expect(control.shouldReport(done: 0, total: 100, now: now))
        #expect(!control.shouldReport(done: 5, total: 100, now: now.addingTimeInterval(0.05)))
        #expect(control.shouldReport(done: 6, total: 100, now: now.addingTimeInterval(0.2)))
        #expect(control.shouldReport(done: 100, total: 100, now: now.addingTimeInterval(0.21)))
    }
}
