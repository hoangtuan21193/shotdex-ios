import SwiftUI
import WidgetKit

/// Home and Lock Screen widgets for ShotDex.
///
/// Every one of them reads files the app left in the shared App Group
/// container and nothing else. A widget that read PhotoKit, EventKit, the
/// network or the user's location would put that work in a second process on
/// WidgetKit's refresh schedule rather than the user's — the app does it, once,
/// while it is open, and leaves the result behind.
@main
struct ShotDexWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
        ClockPhotoWidget()
        CalendarPhotoWidget()
        WeatherPhotoWidget()
        CombinedPhotoWidget()
    }
}
