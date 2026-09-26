import Foundation
import WidgetKit

/// Whether any photo widget is on a Home Screen, and what the designs behind
/// the placed ones need fetching for them.
///
/// It decides whether work happens at all: the weather is fetched, and the
/// calendar read, only when a photo widget is placed and a design asks for
/// them. Neither is ever fetched on a device whose owner never placed one.
enum InstalledWidgets {
    /// True when at least one photo widget is on a Home or Lock Screen.
    static func hasPhotoWidget() async -> Bool {
        // `getCurrentConfigurations` rather than the iOS 18 async spelling:
        // this app ships to iOS 17.
        let configurations: [WidgetInfo] = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
        return configurations.contains { $0.kind == PhotoWidgetIdentity.widgetKind }
    }

    /// True when a photo widget is placed and **some** design shows the
    /// weather.
    ///
    /// Deliberately the union over every design rather than only the ones
    /// actually placed: which design a given widget wears is an answer
    /// WidgetKit keeps inside `ConfigurePhotoWidgetIntent`, a type that lives
    /// in the extension, and reading it here would mean declaring the same
    /// AppIntent in two targets and having it listed twice in Shortcuts. The
    /// cost of the union is one extra Open-Meteo request for someone who made
    /// a weather design and then placed a different one; the location itself
    /// is still never asked for without the button in Settings.
    static func needsWeather(settings: PhotoWidgetSettingsFile) async -> Bool {
        guard settings.designs.contains(where: { $0.settings.showsWeather }) else { return false }
        return await hasPhotoWidget()
    }

    /// True when a photo widget is placed and some design lists today's
    /// events. The month grid is arithmetic and needs no access, so a design
    /// showing only the grid does not count.
    static func needsCalendarEvents(settings: PhotoWidgetSettingsFile) async -> Bool {
        let wantsEvents = settings.designs.contains {
            $0.settings.showsCalendar && $0.settings.calendarStyle.showsEvents
        }
        guard wantsEvents else { return false }
        return await hasPhotoWidget()
    }
}
