import Foundation

/// Keep gathering, one set, one pass (FS-19.08 §6c): the pass finds the new
/// common photos, and a Copy set puts them into its run of the day — the
/// caller runs that run as any other (§6), so it is logged, its CSV is the
/// day's, and it can be undone. A Move set only finds them: nothing is
/// moved before the user says so.
@MainActor
struct CommonPhotosAutoGather {
    let database: AppDatabase
    let pass: CommonPhotosGatherPass
    var timeZone: TimeZone = .current

    struct Result: Equatable {
        var outcome: CommonPhotosGatherPass.Outcome
        /// The day's run holding what this pass found, to run now.
        var runId: String?
    }

    func gather(_ watch: CommonPhotosWatch, now: Date = Date()) async -> Result {
        var runId: String?
        let outcome = await pass.run(watch, now: now) { scan in
            guard watch.action == .copy, let made = scan.makeRun(), !made.items.isEmpty else { return }
            do {
                runId = try CommonPhotosStore(database: database).gatherIntoDay(
                    made.run, items: made.items, watchId: watch.id, day: CommonPhotosStore.day(of: now, timeZone: timeZone),
                    now: Int(now.timeIntervalSince1970))
            } catch is CommonPhotosStore.DayRunBusy {
                // The day's run still goes: these photos wait for the next pass.
            } catch {
                CommonPhotosGatherPass.logger.error("gathered photos not recorded: \(error.localizedDescription, privacy: .public)")
            }
        }
        return Result(outcome: outcome, runId: runId)
    }
}
