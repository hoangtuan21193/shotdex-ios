import CoreSpotlight
import SwiftUI

@main
struct ShotDexApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Before anything opens a session of its own: whatever is left under
        // /tmp from a run that was force-quit or killed is ours and is dead.
        _ = TemporaryWorkspace.sweepOrphans()
        let dependencies = AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
        // BGTaskScheduler requires registration before launch finishes.
        dependencies.backgroundIndex.register()
        // Same requirement: a notification tap that launched the app is
        // delivered to nobody unless the delegate is already in place.
        dependencies.onThisDayNotifications.registerDelegate()
        dependencies.resolveNewlyKnownCameras()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .environment(dependencies.photoLibrary)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dependencies.backgroundIndex.scheduleContinuationIfNeeded()
                    }
                }
                // A tapped Spotlight result arrives as a user activity rather
                // than an intent, so it is translated into the same request an
                // intent would have made.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[
                        CSSearchableItemActivityIdentifier
                    ] as? String,
                        let request = SpotlightIndexer.request(
                            forSpotlightIdentifier: identifier
                        )
                    else { return }
                    IntentRouter.shared.request(request)
                }
                // A photo handed over from another device. The payload is a
                // cloud identifier, so it has to be translated into this
                // device's own before anything can be opened.
                .onContinueUserActivity(HandoffActivity.viewPhoto) { activity in
                    Task {
                        guard let local = await HandoffActivity.localIdentifier(from: activity)
                        else { return }
                        IntentRouter.shared.request(.photo(assetId: local))
                    }
                }
                .task {
                    // Cheap: a few SELECT DISTINCTs and one Spotlight write.
                    await dependencies.backfillMediaSubtypes()
                    await dependencies.spotlight.reindex()
                    await dependencies.refreshWidgetSnapshot()
                }
        }
    }
}
