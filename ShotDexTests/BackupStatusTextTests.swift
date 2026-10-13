import Foundation
import Testing
@testable import ShotDex

/// The card's status lines (FS-22.02 §5).
@Suite struct BackupStatusTextTests {
    private func text(_ status: BackupJobState.Status, done: Int? = nil, total: Int? = nil, progress: BackupProgress? = nil, items: Int = 4_118) -> BackupStatusText {
        var state = BackupJobState(jobId: "J")
        state.status = status
        state.statusDone = done
        state.statusTotal = total
        state.lastCheckedAt = nil
        return BackupStatusText.make(.init(state: state, progress: progress, backedUpItems: items, connectionName: "NAS Home", sourceName: "T7 RAW Archive"))
    }

    @Test func everyStateHasItsLine() {
        let watching = text(.watching)
        #expect(watching.title == "Watching · Up to Date")
        #expect(watching.detail == "4,118 items")
        #expect(watching.action == nil)

        let firstRun = text(.uploading, progress: BackupProgress(done: 1_204, total: 3_580, bytesDone: 0, bytesTotal: 0, isFirstRun: true))
        #expect(firstRun.title == "Backing Up · 34%")
        #expect(firstRun.action == .pause)

        let new = text(.uploading, progress: BackupProgress(done: 0, total: 3, bytesDone: 0, bytesTotal: 0, isFirstRun: false))
        #expect(new.title == "3 New · Uploading")
        #expect(new.detail.hasPrefix("1 of 3"))

        let wifi = text(.waitingForWiFi, done: 0, total: 12)
        #expect(wifi.title == "Waiting for Wi‑Fi")
        #expect(wifi.detail == "12 new · Only on Wi‑Fi is on")

        let system = text(.pausedBySystem, done: 812, total: 2_940)
        #expect(system.title == "Paused")
        #expect(system.detail == "iOS stopped ShotDex at 812 of 2,940. Resumes from there.")
        #expect(system.action == .resume)

        #expect(text(.unreachable, done: 4, total: 10).title == "Can't Reach NAS Home")
        #expect(text(.unreachable, done: 4, total: 10).action == .retry)
        #expect(text(.sourceOffline).detail == "T7 RAW Archive isn't connected")
        #expect(text(.noPhotosAccess).action == .openSettings)
        #expect(text(.signInFailed).action == .editServer)
        #expect(text(.destinationFull).title == "NAS Home Is Full")
    }

    /// FS-22.05 §5: while the destination tree is listed, the card counts the
    /// files found, named after the connection.
    @Test func checkingDestination() {
        var progress = BackupProgress(done: 0, total: 3, isFirstRun: true)
        progress.phase = .checkingDestination
        progress.listedCount = 8_000
        let first = text(.uploading, progress: progress)
        #expect(first.title == "Checking NAS Home · 8,000 files")
        #expect(first.detail == "before the first copy")
        #expect(first.action == .pause)

        var state = BackupJobState(jobId: "J")
        state.status = .uploading
        state.hasFinishedFirstRun = true
        let daily = BackupStatusText.make(.init(state: state, progress: progress, backedUpItems: 1, connectionName: "NAS Home", sourceName: ""))
        #expect(daily.detail == "daily check")
    }
}
