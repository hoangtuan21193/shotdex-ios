import Foundation
import os
import UserNotifications

/// The one notice Keep gathering sends (FS-19.08 §6c): a Move set has
/// photos ready to move. Asked for when the user turns Keep gathering on
/// for a Move set — never at launch — and replaced, not stacked, while the
/// same run waits. Clicking it opens the run's window.
@MainActor
final class MacCommonPhotosNotices: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")
    nonisolated private static let runKey = "runId"
    weak var runs: MacCommonPhotosRuns? {
        didSet { deliverPending() }
    }
    /// A click that launched the app lands before any window has handed
    /// over `runs`: kept until it does.
    private var pendingRunId: String?

    private func deliverPending() {
        guard let runs, let runId = pendingRunId else { return }
        pendingRunId = nil
        runs.logRequest = (runId, Date())
    }

    /// Asks once; macOS remembers the answer, and a refusal only means no
    /// notice — the run still waits in Activity.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { log.error("notice authorization: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// "4 photos are ready to move to “Shared”".
    static func title(count: Int, destination: String) -> String {
        count == 1
            ? String(localized: "1 photo is ready to move to “\(destination)”", comment: "Mac notice: Keep gathering found a photo for a Move set")
            : String(localized: "\(count.formatted()) photos are ready to move to “\(destination)”", comment: "Mac notice: Keep gathering found photos for a Move set")
    }

    static func readyToMove(count: Int, destination: String, runId: String) {
        let content = UNMutableNotificationContent()
        content.title = title(count: count, destination: ServerUploadPath.lastComponent(of: destination))
        content.body = String(localized: "Nothing has been moved yet. Open it to move them.", comment: "Mac notice: a Move set's photos wait for the user")
        content.userInfo = [runKey: runId]
        // The same run's notice replaces the last one.
        let request = UNNotificationRequest(identifier: "commonPhotosReady.\(runId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { log.error("notice: \(error.localizedDescription, privacy: .public)") }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let runId = response.notification.request.content.userInfo[Self.runKey] as? String else { return }
        await MainActor.run {
            pendingRunId = runId
            deliverPending()
        }
    }

    /// Shown while ShotDex is in front too: the run is not on screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
