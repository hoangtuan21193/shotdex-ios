import SwiftUI
import UIKit

/// The app's accent colour: the amber of the sun in the app icon. Fixed — there
/// is no accent setting.
///
/// It is not the app's tint either: standard controls (navigation bars, menus,
/// sheets, toggles) keep the iOS default. This colour is only for what ShotDex
/// draws itself — grid selection badges, the editor's active states, charts —
/// reachable as `\.appAccent` in SwiftUI or `AppAccent.color` / `.uiColor` from
/// the places that cannot read the environment.
enum AppAccent {
    /// The icon's sun is `#EB9526`. That value on white is too pale to read as a
    /// control colour, so light mode gets a deeper mix of it and dark mode the
    /// icon's own.
    static let color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.922, green: 0.584, blue: 0.149, alpha: 1)
            : UIColor(red: 0.776, green: 0.451, blue: 0.055, alpha: 1)
    })

    /// The same colour for the UIKit layers (the grid's cells are UIKit).
    static let uiColor = UIColor(color)
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = AppAccent.color
}

extension EnvironmentValues {
    /// The app accent, for views that draw an accent themselves rather than
    /// inheriting a tint. Same value everywhere; the environment entry stays so
    /// views keep reading it the SwiftUI way.
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}
