import Foundation
import OSLog

/// Collects the app's own `os_log` output so a bug report can carry evidence
/// rather than a description of evidence.
///
/// Two limits are worth knowing before relying on this. It can only read the
/// **current process**: `OSLogStore(scope: .system)` needs an entitlement Apple
/// does not grant third-party apps, so the log from the launch that crashed is
/// gone by the time the user reopens the app to report it — ask them to
/// reproduce the problem, then send. And `os_log` redacts interpolated values
/// unless they were logged as `public`, so paths and identifiers mostly arrive
/// as `<private>`, which is the behaviour we want here.
enum SupportLogCollector {
    static let subsystem = "com.hoangtuan.shotdex"

    /// Newest entries first is how a reader wants them, but the text keeps
    /// chronological order because a log that jumps backwards is unreadable.
    /// Oldest lines are dropped when the budget is exceeded.
    static func collect(
        since interval: TimeInterval = 15 * 60,
        maxBytes: Int = 48_000
    ) async -> String {
        await Task.detached(priority: .utility) {
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
                return String(localized: "The log could not be read on this device.", comment: "Support log unavailable")
            }
            let position = store.position(date: Date().addingTimeInterval(-interval))
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            guard let entries = try? store.getEntries(at: position, matching: predicate) else {
                return String(localized: "The log could not be read on this device.", comment: "Support log unavailable")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current

            var lines: [String] = []
            for entry in entries {
                guard let log = entry as? OSLogEntryLog else { continue }
                lines.append("\(formatter.string(from: log.date)) [\(log.category)] \(log.composedMessage)")
            }

            return trimmed(lines, toBytes: maxBytes)
        }.value
    }

    /// Keeps the newest lines that fit, and says how many were dropped so the
    /// reader does not mistake a truncated log for a short one.
    private static func trimmed(_ lines: [String], toBytes maxBytes: Int) -> String {
        guard !lines.isEmpty else {
            return String(localized: "No log entries in the last few minutes.", comment: "Support log is empty")
        }
        var kept: [String] = []
        var bytes = 0
        for line in lines.reversed() {
            let size = line.utf8.count + 1
            if bytes + size > maxBytes { break }
            kept.append(line)
            bytes += size
        }
        kept.reverse()
        let dropped = lines.count - kept.count
        guard dropped > 0 else { return kept.joined(separator: "\n") }
        return "… \(dropped) earlier lines omitted\n" + kept.joined(separator: "\n")
    }
}
