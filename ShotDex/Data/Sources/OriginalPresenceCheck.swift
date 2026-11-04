import Foundation
import Observation
import os

/// Checks, with the network off, which Photos items have every original on
/// this device (FS-06.10 §4), in batches of 200, writing as it goes — the
/// next start carries on where this one stopped (AC-6). It pauses while the
/// user is interacting, stops when the device is hot, and runs only while
/// the app is in front.
///
/// What it checks: items never checked, and items marked for a recheck
/// after PhotoKit said they changed. Everything again only when a screen
/// using the **Original** rule is open and the last full pass is more than
/// 24 hours old (§4) — Photos evicts originals without telling anyone, so a
/// fresh pass is the only way to notice.
@MainActor
@Observable
final class OriginalPresenceCheck {
    nonisolated static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "OriginalPresenceCheck")
    /// A full pass is due once the last one is this old.
    static let fullPassAge: TimeInterval = 24 * 60 * 60

    /// The world the check runs in; closures, so tests need no library.
    struct Environment: Sendable {
        var store: OriginalPresenceStore
        /// The verdict for each id, network off.
        var check: @Sendable (_ ids: [String]) async -> [String: OriginalPresence?]
        /// True while the user is scrolling or swiping — the check waits.
        var shouldPause: @Sendable () -> Bool = { false }
        /// True when the device is too hot to keep going.
        var isTooHot: @Sendable () -> Bool = { false }
        var batchSize = 200
        var now: @Sendable () -> Date = { Date() }
        var pauseInterval: Duration = .milliseconds(500)
        /// How long a hot device waits before looking again.
        var thermalRetry: Duration = .seconds(30)

        static func live(database: AppDatabase, gate: IndexInteractionGate?) -> Environment {
            Environment(
                store: OriginalPresenceStore(database: database),
                check: { await OriginalPresenceProbe.check($0) },
                shouldPause: { gate?.shouldPauseIndexing ?? false },
                isTooHot: { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
            )
        }
    }

    private let environment: Environment
    private var task: Task<Void, Never>?
    /// Which `task` is current: a cancelled one ending late must not clear
    /// the one that replaced it.
    private var taskToken = 0
    /// Work arrived while a pass was running: loop again before finishing.
    private var hasMoreWork = false
    /// Ids PhotoKit said changed while a batch was being checked: its
    /// answer for them is older than the change, so they are marked again
    /// after it is written.
    private var changedDuringBatch: Set<String> = []
    private var isInFront = false
    /// Screens open right now that use the Original rule.
    private var openScreens = 0

    private(set) var isRunning = false
    /// The pass on record: when it started and, once done, when it finished.
    private(set) var pass: OriginalPresenceStore.Pass?
    /// Items this pass has looked at, of those the grid shows.
    private(set) var progress = OriginalPresenceStore.Progress()
    /// Bumped after each batch, so an album using the rule reads again.
    private(set) var generation = 0

    init(environment: Environment) {
        self.environment = environment
        // One row by key: cheap enough for the main actor, once.
        pass = try? environment.store.pass()
        // An index run added rows the check has not seen.
        NotificationCenter.default.addObserver(forName: .indexRunEnded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isInFront == true { self?.start() } }
        }
    }

    /// The scene came to the foreground: new and changed items are checked.
    func appBecameActive() {
        isInFront = true
        start()
    }

    func appDidEnterBackground() {
        isInFront = false
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// A smart album, Filter or Advanced Search using the Original rule
    /// opened: checks what is new, and everything again once the last full
    /// pass is more than a day old. Pair with `screenClosed()`.
    func screenOpened() {
        openScreens += 1
        if let pass, let finished = pass.finishedAt,
           environment.now().timeIntervalSince1970 - Double(finished) > Self.fullPassAge {
            beginPass()
        }
        if isInFront { start() }
    }

    func screenClosed() {
        openScreens = max(0, openScreens - 1)
    }

    /// PhotoKit said these items were edited (AC-8): back to unchecked,
    /// first in line for the next batch. `nil` — PhotoKit could not say what
    /// changed — starts a fresh pass over everything.
    func assetsChanged(_ photoKitIds: Set<String>?) async {
        guard let photoKitIds else {
            beginPass()
            if isInFront { start() }
            return
        }
        guard !photoKitIds.isEmpty else { return }
        if task != nil { changedDuringBatch.formUnion(photoKitIds) }
        let store = environment.store
        try? await Self.offMain { try store.markForRecheck(photoKitIds) }
        await refreshProgress()
        generation &+= 1
        if isInFront { start() }
    }

    private func beginPass() {
        let now = Int64(environment.now().timeIntervalSince1970)
        try? environment.store.beginPass(at: now)
        pass = .init(startedAt: now, finishedAt: nil)
        progress.checked = 0
        hasMoreWork = true
        generation &+= 1
    }

    private func start() {
        guard task == nil else { hasMoreWork = true; return }
        isRunning = true
        taskToken &+= 1
        let token = taskToken
        task = Task { [weak self] in
            await self?.run()
            guard let self, self.taskToken == token else { return }
            self.isRunning = false
            self.task = nil
        }
    }

    /// Waits for the pass in flight, if any — for tests and the background
    /// slot.
    func waitUntilIdle() async {
        while let task { await task.value; if self.task == task { break } }
    }

    private func refreshProgress() async {
        guard let since = pass?.startedAt else { return }
        let store = environment.store
        if let fresh = try? await Self.offMain({ try store.progress(since: since) }) { progress = fresh }
    }

    /// Store reads and the probe run off the main actor; cancelling the
    /// caller cancels them (a detached task alone would not hear it).
    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let child = Task.detached(priority: .utility) { try await work() }
        return try await withTaskCancellationHandler { try await child.value } onCancel: { child.cancel() }
    }

    /// One pass until nothing is due; also what tests call.
    func run() async {
        if pass == nil { beginPass() }
        let store = environment.store
        await refreshProgress()
        // Items checked by this run: a finished pass that took in new ones
        // is finished again now, so "checked … ago" stays true.
        var didCheck = false
        while !Task.isCancelled {
            hasMoreWork = false
            // Read every batch: a pass begun meanwhile moves the line.
            guard let since = pass?.startedAt else { return }
            while environment.isTooHot() || environment.shouldPause() {
                if environment.isTooHot() { Self.logger.info("waiting: thermal state") }
                try? await Task.sleep(for: environment.isTooHot() ? environment.thermalRetry : environment.pauseInterval)
                if Task.isCancelled { return }
            }
            let size = environment.batchSize
            let batch = (try? await Self.offMain { try store.nextBatch(since: since, limit: size) }) ?? []
            if Task.isCancelled { return }
            if batch.isEmpty {
                // Nothing left for this pass — unless a pass began or work
                // came while the query ran.
                if hasMoreWork || pass?.startedAt != since { continue }
                break
            }
            let check = environment.check
            guard let results = try? await Self.offMain({ await check(batch) }), !Task.isCancelled else { return }
            // An id PhotoKit no longer had is looked at too, so the pass
            // moves on; the index drops its row on its next run.
            var gathered = results
            for id in batch where gathered[id] == nil { gathered[id] = .some(nil) }
            let answers = gathered
            let now = Int64(environment.now().timeIntervalSince1970)
            try? await Self.offMain { try store.record(answers, at: now) }
            let stale = changedDuringBatch.intersection(answers.keys)
            changedDuringBatch.subtract(answers.keys)
            if !stale.isEmpty { try? await Self.offMain { try store.markForRecheck(stale) } }
            didCheck = true
            await refreshProgress()
            generation &+= 1
        }
        guard !Task.isCancelled, let current = pass, current.finishedAt == nil || didCheck else { return }
        let now = Int64(environment.now().timeIntervalSince1970)
        try? store.finishPass(at: now)
        pass?.finishedAt = now
        generation &+= 1
    }
}

extension Notification.Name {
    /// An index run ended: rows were added or refreshed.
    static let indexRunEnded = Notification.Name("ShotDexIndexRunEnded")
}
