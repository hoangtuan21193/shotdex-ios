import Foundation
import Photos
import UserNotifications

/// Notification permission, in the app's own vocabulary — mirrors
/// `PhotoLibraryService.authorizationState` so views never import
/// UserNotifications.
enum NotificationAuthorizationState: Sendable {
    case notDetermined
    case authorized
    case provisional
    case denied

    var canNotify: Bool { self == .authorized || self == .provisional }
}

/// The seam over `UNUserNotificationCenter`. Deliberately tiny: everything that
/// decides *what* to schedule lives in `OnThisDayNotificationSchedule`, which is
/// pure and unit-tested.
protocol UserNotificationScheduling: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String]) async
    func add(_ request: UNNotificationRequest) async throws
}

struct SystemNotificationScheduler: UserNotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationState() async -> NotificationAuthorizationState {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .provisional, .ephemeral: .provisional
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}

/// Owns the reminder schedule: read the settings, measure the next few days,
/// replace this feature's pending requests.
///
/// An `actor` rather than a `@MainActor` type on purpose. It does synchronous
/// GRDB reads, it has to be callable from the `@Sendable` closure the
/// background task hands over, and the serialization means a foreground refresh
/// and a background refresh cannot interleave inside the remove-then-add window.
actor OnThisDayNotificationScheduler {
    private let queries: OnThisDayQueries
    private let center: any UserNotificationScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        queries: OnThisDayQueries,
        center: any UserNotificationScheduling = SystemNotificationScheduler(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.queries = queries
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
    }

    var isEnabled: Bool {
        defaults.bool(forKey: SettingsKeys.onThisDayNotificationsEnabled)
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await center.authorizationState()
    }

    func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    /// Rebuilds the whole pending set. Cheap to call blindly: when the reminder
    /// is off this costs one `UserDefaults` read and nothing touches the
    /// database or PhotoKit.
    ///
    /// Every bail-out cancels rather than returning early, so a set scheduled
    /// under different settings can never outlive them.
    func refresh(now: Date = .now) async {
        guard isEnabled,
              PHPhotoLibrary.authorizationStatus(for: .readWrite).canReadLibrary,
              await center.authorizationState().canNotify
        else {
            await cancelAll()
            return
        }

        let minutes = notifyMinutes
        let days = OnThisDayNotificationSchedule.targetDays(
            notifyMinutes: minutes, calendar: calendar, now: now
        )
        guard let tallies = try? queries.tallies(for: days, calendar: calendar, now: now) else {
            await cancelAll()
            return
        }
        let requests = OnThisDayNotificationSchedule.requests(
            from: tallies,
            notifyMinutes: minutes,
            calendar: calendar,
            now: now,
            body: { OnThisDayNotificationCopy.body(for: $0) }
        )
        await replacePending(with: requests)
    }

    /// Removes only this feature's requests — never
    /// `removeAllPendingNotificationRequests()`, which would take out anything
    /// else the app ever schedules.
    func cancelAll() async {
        let ours = await center.pendingIdentifiers().filter {
            $0.hasPrefix(OnThisDayNotificationSchedule.identifierPrefix)
        }
        await center.removePending(identifiers: ours)
    }

    // MARK: Private

    /// `integer(forKey:)` answers 0 for a key that was never written, which
    /// would schedule at midnight while the Settings picker shows its 09:00
    /// default. The nil check is what keeps the two in agreement.
    private var notifyMinutes: Int {
        guard defaults.object(forKey: SettingsKeys.onThisDayNotifyMinutes) != nil else {
            return OnThisDayNotificationSchedule.defaultNotifyMinutes
        }
        return defaults.integer(forKey: SettingsKeys.onThisDayNotifyMinutes)
    }

    private func replacePending(with requests: [OnThisDayNotificationRequest]) async {
        await cancelAll()
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.categoryIdentifier = OnThisDayNotificationSchedule.categoryIdentifier
            content.userInfo = [
                OnThisDayNotificationSchedule.dayKeyUserInfoKey: request.dayKey,
            ]
            // No `timeZone` on the components: fire at the chosen wall-clock
            // time wherever the user is, rather than 03:00 after a flight.
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: request.fireComponents, repeats: false
            )
            try? await center.add(
                UNNotificationRequest(
                    identifier: request.identifier, content: content, trigger: trigger
                )
            )
        }
    }
}

private extension PHAuthorizationStatus {
    /// A reminder that opens an empty screen is worse than no reminder, so the
    /// schedule is only built while the library is actually readable.
    var canReadLibrary: Bool {
        self == .authorized || self == .limited
    }
}
