import Foundation
import UserNotifications

/// App-facing façade for the "On This Day" reminder: the entry points Settings
/// and the root view call, plus the tapped-notification handoff. All scheduling
/// work is delegated to `OnThisDayNotificationScheduler`.
@MainActor
@Observable
final class OnThisDayNotificationService {
    private let scheduler: OnThisDayNotificationScheduler
    private let calendar: Calendar
    /// `UNUserNotificationCenter.delegate` is weak and must be an `NSObject`;
    /// kept as a separate forwarder so this stays a plain `@Observable` type.
    private let forwarder = OnThisDayNotificationForwarder()

    /// The day a tapped reminder wants to open. A tap can arrive before
    /// `RootTabView` exists at all (cold launch straight from the notification),
    /// so it parks here until the UI drains it.
    private(set) var pendingOpenDate: Date?

    init(scheduler: OnThisDayNotificationScheduler, calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.calendar = calendar
        forwarder.service = self
    }

    /// Must run before the app finishes launching — a tap that launched the app
    /// is otherwise delivered to nobody. See `ShotDexApp.init`.
    func registerDelegate() {
        UNUserNotificationCenter.current().delegate = forwarder
    }

    func consumePendingOpenDate() -> Date? {
        defer { pendingOpenDate = nil }
        return pendingOpenDate
    }

    func refresh() async {
        await scheduler.refresh()
    }

    /// Asks for permission, then fills the week. Returns false when the user
    /// declines — or has already denied notifications in Settings, where the
    /// request returns immediately without prompting — so the caller can revert
    /// the toggle instead of storing a preference that cannot fire.
    func enable() async -> Bool {
        guard await scheduler.requestAuthorization() else { return false }
        await scheduler.refresh()
        return true
    }

    func disable() async {
        await scheduler.cancelAll()
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await scheduler.authorizationState()
    }

    fileprivate func open(dayKey: String?) {
        guard let dayKey,
              let date = OnThisDayNotificationSchedule.date(fromDayKey: dayKey, calendar: calendar)
        else { return }
        pendingOpenDate = date
    }
}

/// Bridges the UserNotifications delegate callbacks onto the main actor.
private final class OnThisDayNotificationForwarder: NSObject, UNUserNotificationCenterDelegate {
    weak var service: OnThisDayNotificationService?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let dayKey = userInfo[OnThisDayNotificationSchedule.dayKeyUserInfoKey] as? String
        Task { @MainActor [weak self] in
            self?.service?.open(dayKey: dayKey)
        }
        completionHandler()
    }

    /// Still shown while the app is open: the reminder is an invitation to go
    /// look at a specific day, which is just as useful mid-session, and it stays
    /// tappable.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
