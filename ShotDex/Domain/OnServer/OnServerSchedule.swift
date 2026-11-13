import Foundation

/// When the on-server check may talk to a server or download from iCloud
/// (FS-19.07 §6): by the Backup jobs of the connection — Only on Wi‑Fi and
/// Only While Charging, the strictest of them when there are several. A
/// connection with no job is Wi‑Fi only. Use Cellular Data for Indexing is
/// for the Photos index alone and plays no part.
enum OnServerSchedule {
    /// What the check is waiting for, as the progress line says it.
    enum Wait: Equatable, Sendable {
        case wifi
        case charging
        case space
        /// The source's server did not answer, by the source's name.
        case unreachable(String)
        /// Phase 1 runs only while ShotDex is open.
        case openApp
        /// iCloud refused every original of a batch (CloudPhotoLibrary
        /// error 1006 on an iPad, 2026-11-11): the Photos side rests and
        /// tries again later, rather than asking for hundreds a minute.
        case iCloudRefusing
    }

    /// The rules of one Backup job that matter here.
    struct JobRules: Equatable, Sendable {
        var onlyOnWiFi: Bool
        var onlyWhileCharging: Bool
    }

    /// The strictest rules of a connection's jobs; Wi‑Fi only with none.
    static func rules(of jobs: [JobRules]) -> JobRules {
        guard !jobs.isEmpty else { return JobRules(onlyOnWiFi: true, onlyWhileCharging: false) }
        return JobRules(onlyOnWiFi: jobs.contains(where: \.onlyOnWiFi),
                        onlyWhileCharging: jobs.contains(where: \.onlyWhileCharging))
    }

    /// Nil when the check may run now.
    static func wait(for jobs: [JobRules], isExpensivePath: Bool, isCharging: Bool) -> Wait? {
        let rules = rules(of: jobs)
        if rules.onlyOnWiFi, isExpensivePath { return .wifi }
        if rules.onlyWhileCharging, !isCharging { return .charging }
        return nil
    }
}
