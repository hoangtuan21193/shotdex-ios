import SwiftUI
import UIKit

/// The app's accent colour: the amber of the sun in the app icon. Fixed — there
/// is no accent setting.
///
/// It is also the app's tint (user, 2026-10-12): `ShotDexApp` sets it on the
/// root view and on every window, so standard buttons, links, toggles and menus
/// use it instead of the iOS blue; destructive actions keep red through their
/// role. Views that draw an accent themselves read `\.appAccent`, or
/// `AppAccent.color` / `.uiColor` where the environment cannot be read.
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
