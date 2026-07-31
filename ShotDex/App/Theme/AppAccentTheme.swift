import SwiftUI
import UIKit

/// The app's accent colour, picked in Settings.
///
/// `Color.accentColor` reads the asset catalog, which is fixed at build time, so
/// a stored preference can only reach the UI two ways: the environment's tint,
/// which every standard control already follows, and `\.appAccent` for the views
/// that draw their own accent. Both are set once on the root view; nothing reads
/// `Color.accentColor` directly any more.
enum AppAccentTheme: String, CaseIterable, Identifiable, Sendable {
    /// The amber of the sun in the app icon — the app's own colour, and the
    /// default on a fresh install.
    case amber
    /// The pale sand of the app icon's background.
    case sand
    case green
    /// Whatever iOS tints controls with — the app ships no `AccentColor` asset,
    /// so this is the system blue.
    case system

    static let `default` = AppAccentTheme.amber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: "Amber"
        case .sand: "Sand"
        case .green: "Green"
        case .system: "iOS Default"
        }
    }

    var color: Color {
        switch self {
        case .amber: Self.iconAmber
        case .sand: Self.iconSand
        // A system colour, so its light and dark variants come for free.
        case .green: Color(.systemGreen)
        case .system: .accentColor
        }
    }

    /// A raw value from `UserDefaults` is user data: an unwritten key, or one
    /// left behind by a build that offered a colour this one doesn't, falls back
    /// to the default rather than leaving the UI untinted.
    static func resolved(_ rawValue: String?) -> AppAccentTheme {
        guard let rawValue, let theme = AppAccentTheme(rawValue: rawValue) else {
            return .default
        }
        return theme
    }

    /// The stored choice read straight from `UserDefaults`, for the one place
    /// that cannot take it from the environment: `EditorTheme`'s static tokens.
    static var stored: AppAccentTheme {
        resolved(UserDefaults.standard.string(forKey: SettingsKeys.accentTheme))
    }

    /// The icon's sun is `#EB9526`. That value on white is too pale to read as a
    /// control colour, so light mode gets a deeper mix of it and dark mode the
    /// icon's own.
    private static let iconAmber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.922, green: 0.584, blue: 0.149, alpha: 1)
            : UIColor(red: 0.776, green: 0.451, blue: 0.055, alpha: 1)
    })

    /// The icon's background is `#F1DEC8`. Dark mode can wear it as-is — a pale
    /// colour reads fine on black — but on white it disappears entirely, so
    /// light mode gets the same sand darkened until it holds as a control colour.
    private static let iconSand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.945, green: 0.871, blue: 0.784, alpha: 1)
            : UIColor(red: 0.545, green: 0.427, blue: 0.278, alpha: 1)
    })
}

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    /// The accent from Settings, for views that draw an accent themselves rather
    /// than inheriting the tint. Defaults to the system accent, so a view mounted
    /// outside the root — a preview, a sheet built by hand — still looks right.
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}
