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
        return Result(outcome: outcome, runId: runId)
    }
}
