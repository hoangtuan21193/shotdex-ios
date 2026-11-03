import Foundation
import Testing
@testable import ShotDex

/// FS-18.01 §4, FS-19.08 §7: a common-photos run as an Activity row.
@Suite struct CommonPhotosJobTests {
    private func input(_ state: CommonPhotosRun.State, action: CommonPhotosRun.Action = .copy, running: Bool = false,
                       paused: Bool = false, problem: String? = nil, done: Int = 120, failed: Int = 0) -> CommonPhotosJob.Input {
        var run = CommonPhotosRun(id: "R", connectionId: "c", folders: ["photos/Tuấn", "photos/Vợ"], destination: "photos/Shared",
                                  action: action, state: state)
        run.isReadable = true
        var progress = CommonPhotosRunner.Progress(doneCount: done, totalCount: 280, doneBytes: 1_800_000_000, totalBytes: 4_200_000_000)
        progress.currentName = "IMG_4188.HEIC"
        progress.currentStep = .readingBack
        return CommonPhotosJob.Input(run: run, progress: progress, isRunning: running, isPausedByUser: paused, problem: problem,
                                     copiedOrMoved: done, skipped: 12, failed: failed, secondsLeft: 240)
    }

    @Test func aRunGoingCanBePausedStoppedAndShown() {
        let job = CommonPhotosJob.job(input(.running, running: true))
        #expect(job.state == .running)
        #expect(job.title == "Common photos · Tuấn + Vợ → Shared")
        #expect(job.actions == [.pause, .stop, .showLog])
        #expect(job.status.hasPrefix("Copying 121 of 280 · "))
        #expect(job.status.hasSuffix("about 4 min left"))
        #expect(job.detail == "IMG_4188.HEIC · reading back SHA-256 in Shared")
        #expect(job.aside == "43%")
        #expect(job.rank == 0)
    }

    /// AC-169: a Move set's ready run waits for Move N…, ranked with the
    /// paused ones, with no bar and nothing to resume or stop.
    @Test func readyToMoveWaitsForTheUser() {
        var ready = input(.ready, action: .move, done: 0)
        ready.progress = CommonPhotosRunner.Progress(doneCount: 0, totalCount: 4, doneBytes: 0, totalBytes: 40_000_000)
        ready.run.watchId = "W"
        ready.run.day = "2026-11-03"
        let job = CommonPhotosJob.job(ready)
        #expect(job.state == .readyToMove && job.rank == 1 && !job.isOver)
        #expect(job.status == "Ready to move 4 — nothing moved yet")
        #expect(job.actions == [.moveReady(4), .showLog, .remove])
        #expect(job.fraction == nil)
    }

    @Test func finishingOffersOnlyTheLog() {
        let job = CommonPhotosJob.job(input(.finishing, running: true, done: 280))
        #expect(job.state == .finishing)
        #expect(job.actions == [.showLog])
    }

    @Test func pausedResumes() {
        let job = CommonPhotosJob.job(input(.paused, paused: true))
        #expect(job.state == .paused)
        #expect(job.status == "Paused at 120 of 280")
        #expect(job.actions == [.resume, .stop, .showLog])
    }

    @Test func aLostConnectionTriesAgainAndAQuitResumes() {
        let lost = CommonPhotosJob.job(input(.paused, problem: "The connection to the server was lost."))
        #expect(lost.state == .interrupted)
        #expect(lost.actions == [.tryAgain, .stop, .showLog])
        #expect(lost.status.contains("The connection to the server was lost."))
        // Left over from a quit: no problem known, not paused by the user.
        let quit = CommonPhotosJob.job(input(.running))
        #expect(quit.state == .interrupted)
        #expect(quit.status == "Interrupted at 120 of 280")
        #expect(quit.actions == [.resume, .stop, .showLog])
        #expect(quit.rank == 1)
    }

    @Test func aRunThatCannotResumeOnlyShowsItsLog() {
        var unreadable = input(.paused)
        unreadable.run.isReadable = false
        #expect(CommonPhotosJob.job(unreadable).actions == [.showLog])
    }

    @Test func overRowsHaveNoBarAndCanBeRemoved() {
        let done = CommonPhotosJob.job(input(.finished, done: 268))
        #expect(done.state == .done)
        #expect(done.fraction == nil)
        #expect(done.status == "Done — 268 copied · 12 skipped · 0 failed")
        // A gathering run that is over can run again on its set (FS-19.08 §6c).
        #expect(done.actions == [.runAgain, .showLog, .remove])
        #expect(done.isOver)
        let failures = CommonPhotosJob.job(input(.finished, action: .move, done: 267, failed: 1))
        #expect(failures.state == .doneWithFailures)
        #expect(failures.status == "Done — 267 moved · 12 skipped · 1 failed")
        let stopped = CommonPhotosJob.job(input(.stopped))
        #expect(stopped.state == .stopped)
        #expect(stopped.status.hasPrefix("Stopped — "))
        #expect(stopped.actions == [.runAgain, .showLog, .remove])
        // An undo has no set of its own to run again.
        var undo = input(.finished)
        undo.run.undoOf = "R0"
        #expect(CommonPhotosJob.job(undo).actions == [.showLog, .remove])
    }
}

/// The cases the T11b review asked for.
@Suite struct CommonPhotosJobEdgeTests {
    private func input(_ state: CommonPhotosRun.State, action: CommonPhotosRun.Action = .copy, running: Bool = false,
                       done: Int = 120, failed: Int = 0) -> CommonPhotosJob.Input {
        let run = CommonPhotosRun(id: "R", connectionId: "c", folders: ["photos/Tuấn", "photos/Vợ"], destination: "photos/Shared",
                                  action: action, state: state)
        let progress = CommonPhotosRunner.Progress(doneCount: done, totalCount: 280, doneBytes: 1, totalBytes: 2)
        return CommonPhotosJob.Input(run: run, progress: progress, isRunning: running, isPausedByUser: false, problem: nil,
                                     copiedOrMoved: done, skipped: 12, failed: failed)
    }

    /// Left at `finishing` by a quit: Resume writes the log; Stop would be refused.
    @Test func finishingLeftOverResumesWithoutStop() {
        let job = CommonPhotosJob.job(input(.finishing, done: 280))
        #expect(job.state == .owesFinish)
        #expect(job.status == "Writing the log — Resume finishes it")
        #expect(job.actions == [.resume, .showLog])
        #expect(!job.actions.contains(.stop))
    }

    @Test func anInterruptedRunThatCannotBeReadOnlyShowsItsLog() {
        var unreadable = input(.running)
        unreadable.run.isReadable = false
        let job = CommonPhotosJob.job(unreadable)
        #expect(job.state == .interrupted)
        #expect(job.actions == [.showLog])
    }

    @Test func doneWithFailuresCanBeShownAndRemoved() {
        let job = CommonPhotosJob.job(input(.finished, done: 270, failed: 2))
        #expect(job.state == .doneWithFailures)
        #expect(job.actions == [.showLog, .remove])
        #expect(job.fraction == nil)
    }

    @Test func moveWordsForDoneAndStopped() {
        #expect(CommonPhotosJob.job(input(.finished, action: .move, done: 268)).status == "Done — 268 moved · 12 skipped · 0 failed")
        #expect(CommonPhotosJob.job(input(.stopped, action: .move, done: 40)).status == "Stopped — 40 moved · 12 skipped · 0 failed")
    }

    /// §6b: an undo run reads as one — its own title, Undoing / undone /
    /// not undone, and the steps of putting back.
    @Test func undoRunWords() {
        var going = input(.running, running: true)
        going.run.undoOf = "R0"
        going.progress.currentStep = .checking
        let job = CommonPhotosJob.job(going)
        #expect(job.title == "Undo · Shared → Tuấn + Vợ")
        #expect(job.status.hasPrefix("Undoing 121 of 280 · "))
        #expect(job.detail == "IMG_4188.HEIC · checking the copies")
        #expect(job.actions == [.pause, .stop, .showLog])

        var done = input(.finished, done: 277, failed: 1)
        done.run.undoOf = "R0"
        let over = CommonPhotosJob.job(done)
        #expect(over.status == "Done — 277 undone · 1 not undone")
        #expect(over.state == .doneWithFailures)
        #expect(over.actions == [.showLog, .remove])
    }

    /// A run an undo took back says so in its row.
    @Test func undoneRunSaysSo() {
        var taken = input(.finished, done: 8)
        taken.skipped = 0
        taken.undone = 8
        #expect(CommonPhotosJob.job(taken).status == "Done — 8 copied · 0 skipped · 0 failed · 8 undone")
    }
}
