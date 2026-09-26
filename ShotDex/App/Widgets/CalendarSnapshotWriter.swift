import EventKit
import Foundation
import WidgetKit

/// Reads today's events out of the user's calendars for the widgets.
///
/// Access is never asked for on its own: the user grants it from the calendar
/// widget's settings section, and the month grid is arithmetic and needs
/// nothing at all. What crosses into the App Group is a title, a time and a
/// colour — never a calendar identifier, never a note, never an attendee.
@MainActor
final class CalendarSnapshotWriter {
    private let store = EKEventStore()

    /// Authorization as the app talks about it, so views never import EventKit.
    enum Access {
        case notDetermined
        case granted
        case denied
    }

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .granted
        default: .denied
        }
    }

    /// Asks for access, and only from the settings button the user taps. iOS
    /// 17 splits calendar access in two and this is the read side.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    @discardableResult
    func write(now: Date = .now, calendar: Calendar = .current, force: Bool = false) async -> Bool {
        guard let container = WidgetSharedContainer.url else { return false }
        let settings = PhotoWidgetSettingsFile.read()
        let isNeeded = await InstalledWidgets.needsCalendarEvents(settings: settings)
        guard force || isNeeded else { return false }
        // Never prompts. Access is asked for in the calendar widget's own
        // settings, behind a button that says what it is for; until then the
        // widget shows "calendar access is off" rather than a dialog the user
        // did not ask for.
        guard access == .granted else {
            write(CalendarSnapshot(
                dayKey: WidgetSharedContainer.dayKey(for: now, calendar: calendar),
                events: [],
                hasAccess: false,
                generatedAt: now
            ), to: container)
            return true
        }

        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { lhs, rhs in
                // All-day events first, then by start; that is the order
                // Calendar itself lists a day in.
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .prefix(CalendarSnapshot.maxEvents)
            .map { event in
                CalendarSnapshot.Event(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Event",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: event.calendar.cgColor.map(Self.hex(from:))
                )
            }

        write(CalendarSnapshot(
            dayKey: WidgetSharedContainer.dayKey(for: now, calendar: calendar),
            events: Array(events),
            hasAccess: true,
            generatedAt: now
        ), to: container)
        return true
    }

    private func write(_ snapshot: CalendarSnapshot, to container: URL) {
        try? WidgetSharedContainer.encode(
            snapshot,
            to: container.appendingPathComponent(CalendarSnapshot.fileName)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: PhotoWidgetIdentity.widgetKind)
    }

    /// A calendar's colour as the hex the snapshot carries. sRGB components,
    /// because that is what both processes draw in.
    private nonisolated static func hex(from color: CGColor) -> String {
        guard let converted = color.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ), let components = converted.components, components.count >= 3 else {
            return WidgetTextColor.fallbackHex
        }
        let values = components.prefix(3).map { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", values[0], values[1], values[2])
    }
}
