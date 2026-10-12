import CoreSpotlight
import ShotDexKit
import SwiftUI

@main
struct ShotDexApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Before anything opens a session of its own: whatever is left under
        // /tmp from a run that was force-quit or killed is ours and is dead.
        _ = TemporaryWorkspace.sweepOrphans()
        MetadataLevel.migrateLegacySharingSwitch()
        let dependencies = AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
        // BGTaskScheduler requires registration before launch finishes.
        dependencies.backgroundIndex.register()
        // Same requirement: a notification tap that launched the app is
        // delivered to nobody unless the delegate is already in place.
        dependencies.onThisDayNotifications.registerDelegate()
        dependencies.resolveNewlyKnownCameras()
        dependencies.serverUploadIndex.loadIfNeeded()
        dependencies.unsupportedRAWIndex.loadIfNeeded()
        dependencies.fileServerCatalog.reload()
        dependencies.backupCoordinator.startWatching(photoLibrary: dependencies.photoLibrary)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .environment(dependencies.photoLibrary)
                .environment(dependencies.serverUploadIndex)
                .environment(dependencies.unsupportedRAWIndex)
                .environment(dependencies.photoMarks)
                .environment(dependencies.fileServerCatalog)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dependencies.backgroundIndex.scheduleContinuationIfNeeded()
                    }
                    if phase == .active {
                        // Widgets ask for things while the app is away — an
                        // album picked in "Edit Widget", a day that rolled
                        // over, weather gone stale. The launch `task` runs
                        // once, so coming back to the foreground is the other
                        // moment those asks can be answered.
                        Task { await dependencies.refreshWidgetSnapshot() }
                        // Looks "Add to ShotDex" left while the app was away.
                        Task { await dependencies.lookInbox.drain() }
                        // Files added to a folder source while ShotDex was
                        // away: read now, no Re-index (FS-19.01 §5).
                        Task { await dependencies.sources.readAll() }
                        // Backups catch up on what arrived while away (FS-22.02 §1).
                        dependencies.backupCoordinator.appBecameActive()
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
                // A widget tap. The URL is built by `WidgetDeepLink` in the
                // widget process and parsed by the same type here, so the two
                // cannot drift apart.
                .onOpenURL { url in
                    // A look opened from AirDrop, Files, Messages or Mail.
                    if url.isFileURL {
                        Task { await dependencies.lookInbox.receive(url) }
                        return
                    }
                    guard let link = WidgetDeepLink(url: url) else { return }
                    switch link {
                    case .onThisDay(let dayKey):
                        guard let date = WidgetSharedContainer.date(fromDayKey: dayKey) else { return }
                        IntentRouter.shared.request(.onThisDay(date: date))
                    case .photo(let assetId, let opensEditor):
                        IntentRouter.shared.request(
                            .photo(assetId: assetId, opensEditor: opensEditor)
                        )
                    }
                }
                .task {
                    // Flags and pending stars, for the grid's glyphs (FS-01.12 §4).
                    await dependencies.photoMarks.loadIfNeeded()
                    // A look still waiting from a launch that ended mid-import.
                    await dependencies.lookInbox.drain()
                    // Cheap: a few SELECT DISTINCTs and one Spotlight write.
                    await dependencies.backfillMediaSubtypes()
                    // iOS 27: Photos' star ratings into the filter column.
                    await dependencies.backfillRatings()
                    // …and the stars set below iOS 27 move into Photos, once.
                    await dependencies.ratingMigration.runIfNeeded()
                    // Cameras this iOS build has not judged yet (FS-03.04b §2).
                    dependencies.unsupportedRAWIndex.runPass()
                    await dependencies.spotlight.reindex()
                    await dependencies.refreshWidgetSnapshot()
                }
        }
        // The Video Studio's keys in the iPad's menu bar and ⌘ list, while
        // the studio is open (FS-12.17b §4).
        .commands { VideoStudioCommands() }
    }
}
