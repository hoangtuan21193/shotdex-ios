import Foundation
import Testing
@testable import ShotDex

/// FS-19.07 §6: the check runs by the connection's Backup jobs — the
/// strictest of them, Wi‑Fi only with none — and not one server call or
/// iCloud download goes out while it waits.
@MainActor
struct OnServerScheduleTests {
    /// AC-86: the job is Only on Wi‑Fi, the device is on cellular.
    @Test func followsBackupJob() async {
        let calls = Calls()
        let check = OnServerCheck(environment: calls.environment(jobs: [.init(onlyOnWiFi: true, onlyWhileCharging: false)],
                                                                 expensive: true))
        await check.run()
        #expect(calls.counts == Calls.Counts())
        #expect(check.waits == ["S1": .wifi])
        #expect(check.photosWait == .wifi)
        #expect(check.finishedAt == nil)
    }

    /// AC-94: no Backup job on the connection means Wi‑Fi only, whatever
    /// Use Cellular Data for Indexing says.
    @Test func noJobMeansWiFiOnly() async {
        UserDefaults.standard.set(true, forKey: SettingsKeys.allowCellularIndexing)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKeys.allowCellularIndexing) }
        let calls = Calls()
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: true))
        await check.run()
        #expect(calls.counts == Calls.Counts())
        #expect(check.waits == ["S1": .wifi])
    }

    /// AC-97: two jobs on one connection, one Only on Wi‑Fi — the strictest
    /// wins; and Only While Charging holds it while unplugged.
    @Test func strictestJobWins() async {
        let jobs: [OnServerSchedule.JobRules] = [.init(onlyOnWiFi: true, onlyWhileCharging: false),
                                                 .init(onlyOnWiFi: false, onlyWhileCharging: false)]
        let calls = Calls()
        let check = OnServerCheck(environment: calls.environment(jobs: jobs, expensive: true))
        await check.run()
        #expect(calls.counts == Calls.Counts())
        #expect(check.waits == ["S1": .wifi])

        #expect(OnServerSchedule.wait(for: [.init(onlyOnWiFi: false, onlyWhileCharging: true), .init(onlyOnWiFi: false, onlyWhileCharging: false)],
                                      isExpensivePath: true, isCharging: false) == .charging)
        #expect(OnServerSchedule.wait(for: jobs.reversed(), isExpensivePath: false, isCharging: false) == nil)
    }

    /// On Wi‑Fi: the source is listed, then batches run on both sides until
    /// a round does nothing; the pass is done.
    @Test func runsUntilNothingLeft() async {
        let calls = Calls()
        calls.workRounds = 2
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        await check.run(now: { Date(timeIntervalSince1970: 1_000) })
        // The Photos side runs while the source is listed and stops when
        // the listing is done (1–3 calls, by timing), then once a round
        // with the server's 3.
        #expect(calls.counts.list == 1)
        #expect(calls.counts.server == 3)
        #expect((4...6).contains(calls.counts.photos))
        #expect(check.waits.isEmpty)
        #expect(check.photosWait == nil)
        #expect(check.finishedAt == Date(timeIntervalSince1970: 1_000))
        // Every round of one pass passes the same start time.
        #expect(Set(calls.starts) == [Date(timeIntervalSince1970: 1_000)])
    }

    /// A library with days of iCloud downloads left does not hold the
    /// server back: once the source is listed, server batches take turns
    /// with Photos batches (user 2026-11-11: 20,000 Photos files hashed on
    /// an iPad, not one server file).
    @Test func photosBacklogDoesNotHoldUpServer() async {
        let calls = Calls()
        calls.workRounds = 2
        calls.photosWorkRounds = 1_000
        var photosAtFirstServer: Int? = nil
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        calls.onServer = { if photosAtFirstServer == nil { photosAtFirstServer = calls.counts.photos } }
        calls.onPhotos = { if calls.counts.photos == 20 { check.appDidEnterBackground() } }
        check.appBecameActive()
        while check.isRunning { await Task.yield() }
        #expect((photosAtFirstServer ?? .max) < 5)
    }

    /// Back in front while the cancelled pass is still finishing its batch:
    /// the next pass starts when it ends instead of the foreground being lost.
    @Test func foregroundDuringWindDownStartsAgain() async {
        let calls = Calls()
        calls.workRounds = 100
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        calls.onPhotos = {
            if calls.counts.photos == 2 {
                check.appDidEnterBackground()
                check.appBecameActive()
            }
            if calls.counts.photos == 6 { check.appDidEnterBackground() }
        }
        check.appBecameActive()
        // Bounded: before the fix the second pass never came.
        for _ in 0..<20_000 where check.isRunning || calls.counts.list < 2 { await Task.yield() }
        #expect(calls.counts.list == 2)
        check.appDidEnterBackground()
        while check.isRunning { await Task.yield() }
    }

    /// iCloud refuses every original of a batch: the Photos side stops for
    /// this pass and says so, instead of asking for the next 24 at once —
    /// and the server side still runs (iPad, 2026-11-11: 456 refusals in
    /// a few minutes, each after 0.0 s).
    @Test func iCloudRefusalRests() async {
        let calls = Calls()
        calls.workRounds = 1
        calls.photosRefuse = true
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        await check.run()
        #expect(check.photosWait == .iCloudRefusing)
        #expect(check.finishedAt == nil)
        #expect(calls.counts.server >= 1)
        // One refused batch while listing, none after.
        #expect(calls.counts.photos == 1)
    }

    /// The server did not answer the listing: nothing is read from it, and
    /// the line names it. iCloud downloads still go on for what is known.
    @Test func unreachableSourceWaits() async {
        let calls = Calls()
        calls.reachable = false
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        await check.run()
        // Once while it is listed, once after — no server call.
        #expect(calls.counts == Calls.Counts(list: 1, server: 0, photos: 2))
        #expect(check.waits == ["S1": .unreachable("NAS Home")])
    }

    /// The app goes to the background mid-pass: it stops between batches
    /// and the line says to open ShotDex.
    @Test func backgroundStopsAndSaysOpenApp() async {
        let calls = Calls()
        calls.workRounds = 100
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        calls.onPhotos = { if calls.counts.photos == 2 { check.appDidEnterBackground() } }
        check.appBecameActive()
        while check.isRunning { await Task.yield() }
        #expect(calls.counts.photos == 2)
        #expect(check.waits == ["S1": .openApp])
        #expect(check.photosWait == .openApp)
    }

    /// AC-105: with the app closed, the system's background slot runs the
    /// check — progress grows — and when iOS ends the slot the pass stops
    /// between batches, with work left for the next one.
    @Test func backgroundSlotStopsCleanly() async {
        let calls = Calls()
        calls.workRounds = 100
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        var slot: Task<Void, Never>?
        calls.onPhotos = { if calls.counts.photos == 3 { slot?.cancel() } }
        slot = check.startBackground()
        await slot?.value
        #expect(calls.counts.photos == 3)
        #expect(check.lastPassHashed.photos == 3)
        #expect(!check.isRunning)
        #expect(check.hasWorkLeft)
        // A slot already running is the one handed back.
        calls.onPhotos = {}
        let next = check.startBackground()
        #expect(check.startBackground() == next)
        next.cancel()
        await next.value
    }
}

/// Counts every call the check makes into the world.
@MainActor
private final class Calls {
    struct Counts: Equatable {
        var list = 0
        var server = 0
        var photos = 0
    }

    var counts = Counts()
    var reachable = true
    /// Rounds that report work before one reports none.
    var workRounds = 0
    var starts: [Date] = []
    var onPhotos: () -> Void = {}
    var onServer: () -> Void = {}
    /// Photos rounds with work, when not `workRounds`.
    var photosWorkRounds: Int?
    /// Every Photos batch fails whole, as when iCloud refuses originals.
    var photosRefuse = false

    func environment(jobs: [OnServerSchedule.JobRules], expensive: Bool) -> OnServerCheck.Environment {
        OnServerCheck.Environment(
            serverSources: { [(id: "S1", name: "NAS Home", connectionId: "C1")] },
            jobRules: { _ in jobs },
            conditions: { (expensive, false) },
            list: { _ in await MainActor.run { self.counts.list += 1; return self.reachable } },
            hashServer: { _, _, start in
                await MainActor.run {
                    self.counts.server += 1
                    self.starts.append(start)
                    self.onServer()
                    return ServerFileHashPass.Summary(hashed: self.counts.server <= self.workRounds ? 1 : 0)
                }
            },
            hashPhotos: { start in
                await MainActor.run {
                    self.counts.photos += 1
                    self.starts.append(start)
                    self.onPhotos()
                    if self.photosRefuse { return PhotosFileHashPass.Summary(failed: 24) }
                    return PhotosFileHashPass.Summary(hashed: self.counts.photos <= (self.photosWorkRounds ?? self.workRounds) ? 1 : 0)
                }
            }
        )
    }
}
