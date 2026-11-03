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

    @Test func overRowsHaveNoBarAndCanBeCleared() {
        let done = CommonPhotosJob.job(input(.finished, done: 268))
        #expect(done.state == .done)
        #expect(done.fraction == nil)
        #expect(done.status == "Done — 268 copied · 12 skipped · 0 failed")
        #expect(done.actions == [.showLog, .clear])
        #expect(done.isOver)
        let failures = CommonPhotosJob.job(input(.finished, action: .move, done: 267, failed: 1))
        #expect(failures.state == .doneWithFailures)
        #expect(failures.status == "Done — 267 moved · 12 skipped · 1 failed")
        let stopped = CommonPhotosJob.job(input(.stopped))
        #expect(stopped.state == .stopped)
        #expect(stopped.status.hasPrefix("Stopped — "))
        #expect(stopped.actions == [.showLog, .clear])
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

    @Test func doneWithFailuresCanBeShownAndCleared() {
        let job = CommonPhotosJob.job(input(.finished, done: 270, failed: 2))
        #expect(job.state == .doneWithFailures)
        #expect(job.actions == [.showLog, .clear])
        #expect(job.fraction == nil)
    }

    @Test func moveWordsForDoneAndStopped() {
        #expect(CommonPhotosJob.job(input(.finished, action: .move, done: 268)).status == "Done — 268 moved · 12 skipped · 0 failed")
        #expect(CommonPhotosJob.job(input(.stopped, action: .move, done: 40)).status == "Stopped — 40 moved · 12 skipped · 0 failed")
    }
}
