import Foundation
import Testing
@testable import ShotDex

/// FS-06.10 AC-5, AC-6, AC-8, AC-9 — the background check.
@MainActor
struct OriginalPresenceCheckTests {
    /// Records every batch the check asked about.
    final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        // Both guarded by `lock`: the check calls in from the pool.
        private var batches: [[String]] = []
        private var answer: OriginalPresence? = .onDevice
        var delay: Duration = .zero

        var verdict: OriginalPresence? {
            get { lock.withLock { answer } }
            set { lock.withLock { answer = newValue } }
        }

        func check(_ ids: [String]) async -> [String: OriginalPresence?] {
            lock.withLock { batches.append(ids) }
            if delay > .zero { try? await Task.sleep(for: delay) }
            let value = verdict
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, value) })
        }

        var asked: [[String]] { lock.withLock { batches } }
    }

    /// Main actor only: `now` is read from `run()`.
    final class Clock: @unchecked Sendable {
        var seconds: TimeInterval = 1_000
    }

    private static func library(_ count: Int) throws -> (AppDatabase, [String]) {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<count).map { String(format: "p%04d", $0) }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        return (database, ids)
    }

    private static func check(_ database: AppDatabase, _ probe: Probe, clock: Clock = Clock(),
                              hot: @escaping @Sendable () -> Bool = { false }) -> OriginalPresenceCheck {
        var environment = OriginalPresenceCheck.Environment(
            store: OriginalPresenceStore(database: database),
            check: { await probe.check($0) },
            isTooHot: hot
        )
        environment.now = { Date(timeIntervalSince1970: clock.seconds) }
        return OriginalPresenceCheck(environment: environment)
    }

    /// AC-5: 1,000 unchecked items, one pass: 1,000 rows written, in
    /// batches of at most 200, through the network-off probe only — the
    /// live probe's every read has network access off.
    @Test func passChecksEverythingInBatches() async throws {
        let (database, _) = try Self.library(1_000)
        let probe = Probe()
        let check = Self.check(database, probe)
        await check.run()
        #expect(probe.asked.count == 5)
        #expect(probe.asked.allSatisfy { $0.count <= 200 })
        #expect(Set(probe.asked.joined()).count == 1_000)
        #expect(check.progress == .init(checked: 1_000, total: 1_000))
        #expect(check.pass?.finishedAt != nil)
        #expect(OriginalPresenceProbe.requestOptions().isNetworkAccessAllowed == false)
    }

    /// AC-6: a pass cut off after 3 batches; a new check over the same
    /// database (the app reopened) asks only for the rest.
    @Test func carriesOnAfterTheAppIsKilled() async throws {
        let (database, _) = try Self.library(1_000)
        let first = Probe()
        first.delay = .milliseconds(50)
        let stopping = Self.check(database, first)
        let pass = Task { await stopping.run() }
        while first.asked.count < 3 { try await Task.sleep(for: .milliseconds(5)) }
        pass.cancel()
        await pass.value
        #expect(stopping.pass?.finishedAt == nil)
        let written = try OriginalPresenceStore(database: database).progress(since: 0).checked
        #expect(written > 0 && written < 1_000)

        let second = Probe()
        let reopened = Self.check(database, second)
        await reopened.run()
        #expect(Set(second.asked.joined()).count == 1_000 - written)
        #expect(reopened.progress == .init(checked: 1_000, total: 1_000))
    }

    /// A hot device waits and carries on once it cools, rather than giving
    /// up until the next foreground.
    @Test func hotDeviceWaitsThenCarriesOn() async throws {
        let (database, _) = try Self.library(10)
        let probe = Probe()
        final class Heat: @unchecked Sendable {
            // Guarded by the lock: read from the pass, written by the test.
            private let lock = NSLock()
            private var hot = true
            var isHot: Bool { get { lock.withLock { hot } } set { lock.withLock { hot = newValue } } }
        }
        let heat = Heat()
        var environment = OriginalPresenceCheck.Environment(
            store: OriginalPresenceStore(database: database), check: { await probe.check($0) }, isTooHot: { heat.isHot })
        environment.thermalRetry = .milliseconds(20)
        let check = OriginalPresenceCheck(environment: environment)
        let pass = Task { await check.run() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.asked.isEmpty)
        heat.isHot = false
        await pass.value
        #expect(check.progress.checked == 10)
    }

    /// AC-8: A changed item goes back to unchecked and is checked again
    /// first; the progress line counts it.
    @Test func changedAssetRechecked() async throws {
        let (database, _) = try Self.library(10)
        let probe = Probe()
        let check = Self.check(database, probe)
        await check.run()
        await check.assetsChanged(["p0003"])
        #expect(try OriginalPresenceStore(database: database).state(of: "p0003") == nil)
        #expect(check.progress.checked == 9)
        probe.verdict = .iCloudOnly
        await check.run()
        #expect(probe.asked.last == ["p0003"])
        #expect(try OriginalPresenceStore(database: database).state(of: "p0003") == .iCloudOnly)
        #expect(check.progress.checked == 10)
    }

    /// §4: a full pass again only once the last one is more than a day old,
    /// and only when a screen using the rule opens.
    @Test func fullPassOnlyAfterADayWhenAScreenOpens() async throws {
        let (database, _) = try Self.library(5)
        let probe = Probe()
        let clock = Clock()
        let check = Self.check(database, probe, clock: clock)
        await check.run()
        #expect(probe.asked.joined().count == 5)

        clock.seconds += 23 * 3_600
        await check.run()
        #expect(probe.asked.joined().count == 5)

        clock.seconds += 2 * 3_600
        check.appDidEnterBackground()
        check.screenOpened()
        #expect(check.pass?.finishedAt == nil)
        #expect(check.progress.checked == 0)
        await check.run()
        #expect(probe.asked.joined().count == 10)
        check.screenClosed()
    }

    /// AC-9: under `.limited` the index holds only the shared items; the
    /// line's total is theirs, and nothing else is asked about.
    @Test func limitedAccessCountsOnlySharedItems() async throws {
        let (database, _) = try Self.library(40)
        let probe = Probe()
        let check = Self.check(database, probe)
        await check.run()
        #expect(check.progress == .init(checked: 40, total: 40))
        #expect(probe.asked.joined().count == 40)
    }

    /// An item PhotoKit no longer has is looked at, stays unchecked, and
    /// does not stall the pass.
    @Test func missingAssetDoesNotStallThePass() async throws {
        let (database, _) = try Self.library(3)
        /// Written in the probe, read after the pass — ordered by the await.
        final class Partial: @unchecked Sendable { var calls = 0 }
        let partial = Partial()
        var environment = OriginalPresenceCheck.Environment(
            store: OriginalPresenceStore(database: database),
            check: { ids in
                partial.calls += 1
                return Dictionary(uniqueKeysWithValues: ids.filter { $0 != "p0001" }.map { ($0, .onDevice) })
            }
        )
        environment.now = { Date(timeIntervalSince1970: 1_000) }
        let check = OriginalPresenceCheck(environment: environment)
        await check.run()
        #expect(partial.calls == 1)
        #expect(try OriginalPresenceStore(database: database).state(of: "p0001") == nil)
        #expect(check.pass?.finishedAt != nil)
    }

    /// Going to the background cancels the batch in flight — nothing is
    /// written for it — and coming back starts again at once.
    @Test func backgroundCancelsAndForegroundRestarts() async throws {
        let (database, _) = try Self.library(400)
        let probe = Probe()
        probe.delay = .milliseconds(300)
        let check = Self.check(database, probe)
        check.appBecameActive()
        try await Task.sleep(for: .milliseconds(100))
        check.appDidEnterBackground()
        #expect(!check.isRunning)
        try await Task.sleep(for: .milliseconds(400))
        #expect(try OriginalPresenceStore(database: database).progress(since: 0).checked == 0)

        probe.delay = .zero
        check.appBecameActive()
        #expect(check.isRunning)
        await check.waitUntilIdle()
        #expect(check.progress == .init(checked: 400, total: 400))
    }

    /// A full pass that begins while another runs is not closed by it: the
    /// running loop picks up the new start and rechecks everything.
    @Test func passBegunMidRunIsNotClosedEarly() async throws {
        let (database, _) = try Self.library(5)
        let probe = Probe()
        let clock = Clock()
        let check = Self.check(database, probe, clock: clock)
        await check.run()
        clock.seconds += 25 * 3_600
        probe.delay = .milliseconds(200)
        await check.assetsChanged(["p0000"])
        check.appBecameActive()
        try await Task.sleep(for: .milliseconds(50))
        check.screenOpened()
        await check.waitUntilIdle()
        // The first pass's 5, the changed p0000, then the other 4 again —
        // p0000 was written as the new pass began, so it counts for it.
        #expect(probe.asked.joined().count == 5 + 1 + 4)
        #expect(check.progress == .init(checked: 5, total: 5))
        #expect(check.pass?.finishedAt != nil)
        check.screenClosed()
    }
}
