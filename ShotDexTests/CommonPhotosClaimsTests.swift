import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.08 §6c: the Mac app and its helper open one database file; a run
/// or a set's pass is claimed by one of them at a time.
@Suite struct CommonPhotosClaimsTests {
    /// Two openings of one file, as the app and the helper have.
    private static func twoProcesses() throws -> (app: AppDatabase, helper: AppDatabase, cleanup: () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Claims-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("db.sqlite").path
        let app = try AppDatabase(DatabasePool(path: path))
        let helper = try AppDatabase(DatabasePool(path: path))
        return (app, helper, { try? FileManager.default.removeItem(at: folder) })
    }

    private static func run(in database: AppDatabase) throws -> String {
        let run = CommonPhotosRun(connectionId: "C", folders: ["photos/A", "photos/B"], destination: "photos/Shared", action: .copy)
        try CommonPhotosStore(database: database).start(run, items: [])
        return run.id
    }

    @Test func claimAcrossProcesses() throws {
        let (app, helper, cleanup) = try Self.twoProcesses()
        defer { cleanup() }
        let runId = try Self.run(in: app)
        let mine = CommonPhotosClaims(database: app, owner: "app")
        let theirs = CommonPhotosClaims(database: helper, owner: "helper")
        let now = Date(timeIntervalSince1970: 1_793_700_000)

        #expect(mine.claim(.run, id: runId, now: now))
        #expect(!theirs.claim(.run, id: runId, now: now.addingTimeInterval(60)))
        #expect(theirs.isClaimedElsewhere(.run, id: runId, now: now.addingTimeInterval(60)))
        #expect(!mine.isClaimedElsewhere(.run, id: runId, now: now))
        // Renewed, it holds past the first expiry.
        #expect(mine.renew(.run, id: runId, now: now.addingTimeInterval(100)))
        #expect(!theirs.claim(.run, id: runId, now: now.addingTimeInterval(200)))
        // Not renewed for two minutes: free — a process that died locks nothing.
        #expect(theirs.claim(.run, id: runId, now: now.addingTimeInterval(100 + 121)))
        #expect(!mine.renew(.run, id: runId, now: now.addingTimeInterval(230)))
        // A release frees it at once; only the holder can release.
        mine.release(.run, id: runId)
        #expect(!mine.claim(.run, id: runId, now: now.addingTimeInterval(240)))
        theirs.release(.run, id: runId)
        #expect(mine.claim(.run, id: runId, now: now.addingTimeInterval(240)))
    }

    /// A set's pass: the same claim on `common_photo_watches`.
    @Test func onePassPerSet() throws {
        let (app, helper, cleanup) = try Self.twoProcesses()
        defer { cleanup() }
        let watch = try CommonPhotosWatchStore(database: app).keepGathering(
            connectionId: "C", folders: ["photos/A", "photos/B"], destination: "photos/Shared", action: .copy)
        let now = Date(timeIntervalSince1970: 1_793_700_000)
        #expect(CommonPhotosClaims(database: helper, owner: "helper").claim(.watch, id: watch.id, now: now))
        #expect(!CommonPhotosClaims(database: app, owner: "app").claim(.watch, id: watch.id, now: now))
    }

    /// The runner's own claim reaches the file: the other opening sees it
    /// as busy while it runs, and free once it ends.
    @Test func runnerClaimIsSeenByTheOtherOpening() throws {
        let (app, helper, cleanup) = try Self.twoProcesses()
        defer { cleanup() }
        let runId = try Self.run(in: app)
        #expect(CommonPhotosRunner.claim(runId: runId, in: app))
        let other = CommonPhotosClaims(database: helper, owner: "helper")
        #expect(other.isClaimedElsewhere(.run, id: runId))
        #expect(!other.claim(.run, id: runId))
        CommonPhotosRunner.release(runId: runId, in: app)
        #expect(!other.isClaimedElsewhere(.run, id: runId))
    }
}

/// FS-19.08 §6c: a set as Activity's Gathering section lists it.
@Suite struct CommonPhotosWatchRowTests {
    private func watch(_ action: CommonPhotosRun.Action = .copy, isOn: Bool = true, checkedAt: Date? = nil,
                       waiting: OnServerSchedule.Wait? = nil, stopped: CommonPhotosWatch.Stop? = nil) -> CommonPhotosWatch {
        CommonPhotosWatch(id: "W", connectionId: "C", folders: ["photos/Tuấn", "photos/Vợ"], destination: "photos/Shared",
                          action: action, isOn: isOn, checkedAt: checkedAt, waiting: waiting, stopped: stopped)
    }

    @Test func copySetSaysWhenItLookedAndHowMany() throws {
        let now = Date(timeIntervalSince1970: 1_793_700_000)
        let row = try #require(CommonPhotosWatchRow.make(watch(checkedAt: now.addingTimeInterval(-180)), connectionName: "NAS Home",
                                                         gathered: 128, readyToMove: 0, now: now))
        #expect(row.title == "Tuấn + Vợ → Shared")
        #expect(row.detail.hasPrefix("Copy · checked "))
        #expect(row.detail.hasSuffix(" · 128 gathered"))
        #expect(row.actions == [.runNow, .stopGathering] && !row.isStopped)
    }

    @Test func aWaitIsSaidInTheOnServerWords() throws {
        let row = try #require(CommonPhotosWatchRow.make(watch(.move, waiting: .charging), connectionName: "NAS Home",
                                                         gathered: 0, readyToMove: 4))
        #expect(row.detail == "Move · Waiting to Charge · 4 ready to move")
        let away = try #require(CommonPhotosWatchRow.make(watch(waiting: .unreachable("NAS Home")), connectionName: "NAS Home",
                                                          gathered: 0, readyToMove: 0))
        #expect(away.detail == "Copy · NAS Home isn't reachable")
    }

    /// AC-171: a folder gone stops the set, and the row says which.
    @Test func aSetThatStoppedByItselfSaysWhy() throws {
        let row = try #require(CommonPhotosWatchRow.make(watch(isOn: false, stopped: .folderGone("photos/Vợ")), connectionName: "NAS Home",
                                                         gathered: 0, readyToMove: 0))
        #expect(row.detail == "“Vợ” isn’t on NAS Home anymore · Stopped gathering")
        #expect(row.isStopped && row.actions == [.remove])
    }

    /// AC-172: a set the user turned off leaves the section; its runs stay.
    @Test func stoppedByTheUserIsNotListed() {
        #expect(CommonPhotosWatchRow.make(watch(isOn: false), connectionName: "NAS Home", gathered: 3, readyToMove: 0) == nil)
    }
}
