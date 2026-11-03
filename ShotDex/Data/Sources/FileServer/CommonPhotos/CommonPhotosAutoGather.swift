import Foundation

/// Keep gathering, one set, one pass (FS-19.08 §6c): the pass finds the new
/// common photos, and a Copy set puts them into its run of the day — the
/// caller runs that run as any other (§6), so it is logged, its CSV is the
/// day's, and it can be undone. A Move set's photos go into a run that is
/// ready to move and waits: nothing is moved before the user says so, and
/// the user hears of it when the pass found photos not listed before.
@MainActor
struct CommonPhotosAutoGather {
    let database: AppDatabase
    let pass: CommonPhotosGatherPass
    var timeZone: TimeZone = .current
    /// A Move set has photos ready: how many, its destination, the run.
    var readyToMove: (_ count: Int, _ destination: String, _ runId: String) -> Void = { _, _, _ in }

    struct Result: Equatable {
        var outcome: CommonPhotosGatherPass.Outcome
        /// The day's run holding what this pass found: for a Copy set to run
        /// now, for a Move set waiting for the user.
        var runId: String?
    }

    func gather(_ watch: CommonPhotosWatch, now: Date = Date()) async -> Result {
        var runId: String?
        let outcome = await pass.run(watch, now: now) { scan in
            guard let made = scan.makeRun(), !made.items.isEmpty else { return }
            let ready = watch.action == .move
            do {
                let gathered = try CommonPhotosStore(database: database).gatherIntoDay(
                    made.run, items: made.items, watchId: watch.id, day: CommonPhotosStore.day(of: now, timeZone: timeZone),
                    ready: ready, now: Int(now.timeIntervalSince1970))
                runId = gathered.runId
                if ready, gathered.added > 0 { readyToMove(made.items.count, watch.destination, gathered.runId) }
            } catch is CommonPhotosStore.DayRunBusy {
                // The day's run still goes: these photos wait for the next pass.
            } catch {
                CommonPhotosGatherPass.logger.error("gathered photos not recorded: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Nothing new for a Move set: a list it had waiting is stale.
        if outcome == .nothingNew, watch.action == .move {
            do { try CommonPhotosStore(database: database).dropReady(watchId: watch.id) } catch {
                CommonPhotosGatherPass.logger.error("ready list not cleared: \(error.localizedDescription, privacy: .public)")
            }
        }
        if case .resumes(let id) = outcome { runId = id }
        return Result(outcome: outcome, runId: runId)
    }

    /// The caller ran `runId`; `error` is how it stopped, nil at its end
    /// (FS-19.08 §6c). The server going away partway: the set says "NAS
    /// Home isn't reachable", and its next pass carries the run on — what
    /// was done stays done. Paused or stopped by the user, a quit
    /// (`byUser`, whatever the client threw on the cancel), or a refusal
    /// the server is not behind (no room on the Mac) is left to the user:
    /// no pass carries it on.
    func ran(_ watch: CommonPhotosWatch, runId: String, connectionName: String, error: (any Error)?, byUser: Bool = false) {
        let watches = CommonPhotosWatchStore(database: database)
        do {
            guard let error else { return try watches.clearResume(id: watch.id, runId: runId) }
            guard !byUser, Self.serverWentAway(error) else { return try watches.forgetResume(id: watch.id, runId: runId) }
            try watches.interrupted(id: watch.id, runId: runId, connectionName: connectionName)
        } catch {
            CommonPhotosGatherPass.logger.error("run outcome not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The server went away, not the user, this Mac or a refusal the
    /// server will repeat (login, permissions, full): only then does
    /// carrying on later help.
    static func serverWentAway(_ error: any Error) -> Bool {
        if error is CancellationError || error is CommonPhotosRunner.Stop || error is CommonPhotosStore.RunMissing { return false }
        guard let error = error as? RemoteFileError else { return !Task.isCancelled }
        return switch error {
        case .connectionLost, .unreachable, .other: true
        default: false
        }
    }
}
