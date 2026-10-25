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
        #expect(calls.counts == Calls.Counts(list: 1, server: 3, photos: 3))
        #expect(check.waits.isEmpty)
        #expect(check.photosWait == nil)
        #expect(check.finishedAt == Date(timeIntervalSince1970: 1_000))
        // Every round of one pass passes the same start time.
        #expect(Set(calls.starts) == [Date(timeIntervalSince1970: 1_000)])
    }

    /// The server did not answer the listing: nothing is read from it, and
    /// the line names it. iCloud downloads still go on for what is known.
    @Test func unreachableSourceWaits() async {
        let calls = Calls()
        calls.reachable = false
        let check = OnServerCheck(environment: calls.environment(jobs: [], expensive: false))
        await check.run()
        #expect(calls.counts == Calls.Counts(list: 1, server: 0, photos: 1))
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
                    return ServerFileHashPass.Summary(hashed: self.counts.server <= self.workRounds ? 1 : 0)
                }
            },
            hashPhotos: { start in
                await MainActor.run {
                    self.counts.photos += 1
                    self.starts.append(start)
                    self.onPhotos()
                    return PhotosFileHashPass.Summary(hashed: self.counts.photos <= self.workRounds ? 1 : 0)
                }
            }
        )
    }
}
