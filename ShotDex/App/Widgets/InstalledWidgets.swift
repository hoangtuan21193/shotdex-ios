import Foundation
import WidgetKit

/// Which of this app's widgets the user has actually placed.
///
/// It decides whether work happens at all: the weather is fetched, and the
/// calendar read, **only** when a widget that shows them is on a Home Screen.
/// A user who never placed the weather widget never has their location asked
/// for, and a user who never placed the calendar one is never prompted for
/// calendar access.
enum InstalledWidgets {
    static func kinds() async -> Set<PhotoWidgetKind> {
        // `getCurrentConfigurations` rather than the iOS 18 async spelling:
        // this app ships to iOS 17.
        let configurations: [WidgetInfo] = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
        let placed = Set(configurations.map(\.kind))
        return Set(PhotoWidgetKind.allCases.filter { placed.contains($0.widgetKind) })
    }

    /// True when a placed widget shows the weather.
    static func needsWeather() async -> Bool {
        await kinds().contains { $0.needsWeather }
    }

    /// True when a placed widget lists calendar events — the month grid is
    /// arithmetic and needs no access, so a calendar widget showing only the
    /// grid does not count.
    static func needsCalendarEvents(settings: PhotoWidgetSettingsFile) async -> Bool {
        await kinds().contains { $0.needsCalendarEvents && settings[$0].calendarStyle.showsEvents }
    }
}
