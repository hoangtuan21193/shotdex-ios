#if DEBUG
import Foundation
import os

/// Logs every stretch the main thread could not answer for longer than
/// 100 ms — a click that made the window wait. The Mac loop reads these after
/// each click-test (`docs/design/mac/MAC_LOOP.md`), so a heavy query or decode
/// that slipped onto the main actor fails the pass instead of shipping as lag:
///
/// ```
/// /usr/bin/log show --last 10m --predicate 'subsystem == "com.hoangtuan.shotdex" AND category == "hang"'
/// ```
///
/// A background thread posts a ping to the main queue every 50 ms and
/// measures how late it runs. Debug builds only.
enum MacHangWatchdog {
    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "hang")
    private static let threshold: TimeInterval = 0.1

    static func start() {
        let thread = Thread {
            while true {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                // Wait for the ping however long it takes, so one hang is
                // logged once with its whole length — and every second while
                // it lasts, so a hang the run never sees end still shows.
                while answered.wait(timeout: .now() + 1) == .timedOut {
                    log.error("main thread blocked \(Int(Date().timeIntervalSince(sent) * 1000), privacy: .public) ms (still blocked)")
                }
                let late = Date().timeIntervalSince(sent)
                if late > threshold {
                    log.error("main thread blocked \(Int(late * 1000), privacy: .public) ms")
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "MacHangWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }
}
#endif
