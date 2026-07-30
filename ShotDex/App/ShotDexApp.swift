import SwiftUI

@main
struct ShotDexApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.accentTheme) private var accentThemeRawValue =
        AppAccentTheme.default.rawValue

    init() {
        let dependencies = AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
        // BGTaskScheduler requires registration before launch finishes.
        dependencies.backgroundIndex.register()
        // Same requirement: a notification tap that launched the app is
        // delivered to nobody unless the delegate is already in place.
        dependencies.onThisDayNotifications.registerDelegate()
        dependencies.resolveNewlyKnownCameras()
    }

    /// One place sets the accent for the whole app: `tint` for every standard
    /// control, `\.appAccent` for the views that draw their own. Sheets and
    /// full-screen covers inherit both.
    private var accent: Color { AppAccentTheme.resolved(accentThemeRawValue).color }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(accent)
                .environment(\.appAccent, accent)
                .environment(dependencies)
                .environment(dependencies.photoLibrary)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dependencies.backgroundIndex.scheduleContinuationIfNeeded()
                    }
                }
        }
    }
}
