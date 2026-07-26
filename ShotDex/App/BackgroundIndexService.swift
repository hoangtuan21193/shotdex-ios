import BackgroundTasks
import UIKit

/// Keeps indexing going when the app leaves the foreground.
///
/// Two mechanisms, in order:
/// 1. A UIKit background-task assertion, taken for every foreground pipeline
///    run, buys a short grace period (~30s) when the user backgrounds the
///    app mid-run. On expiry the run stops cleanly (cursor persists).
/// 2. A `BGProcessingTask` continues the walk later — while the app is
///    suspended or terminated — whenever the system decides conditions are
///    right (device idle, battery OK). Each continuation is cheap because
///    the pipeline's incremental diff skips everything already indexed.
///
/// Background runs never use the network (`allowNetwork: false`);
/// iCloud-only assets stay `pendingICloud` for a foreground retry.
@MainActor
final class BackgroundIndexService {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.hoangtuan.shotdex.index"

    private let pipeline: IndexPipeline
    private let metadataStore: MetadataStore
    private var assertionId: UIBackgroundTaskIdentifier = .invalid

    init(pipeline: IndexPipeline, metadataStore: MetadataStore) {
        self.pipeline = pipeline
        self.metadataStore = metadataStore
    }

    // MARK: BGProcessingTask

    /// Must be called before the app finishes launching
    /// (BGTaskScheduler requirement) — see `ShotDexApp.init`.
    func register() {
        let pipeline = self.pipeline
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier, using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            task.expirationHandler = {
                Task { await pipeline.cancel() }
            }
            Task {
                let summary = try? await pipeline.run(allowNetwork: { false })
                let finished = summary?.wasCancelled == false
                if !finished {
                    Self.schedule()
                }
                task.setTaskCompleted(success: finished)
            }
        }
    }

    /// Asks the system for a background continuation slot. A duplicate
    /// submit replaces the pending request; errors (e.g. running on the
    /// simulator, where BGTaskScheduler is unavailable) are non-fatal.
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called when the app enters the background: schedules a continuation
    /// if there is unfinished work — a run in flight, or a persisted cursor
    /// left behind by a cancelled/expired one.
    func scheduleContinuationIfNeeded() {
        let pipeline = self.pipeline
        let metadataStore = self.metadataStore
        Task {
            if await pipeline.isActive {
                Self.schedule()
            } else if (try? metadataStore.indexState())?.cursorAssetId != nil {
                Self.schedule()
            }
        }
    }

    // MARK: Foreground-run assertion

    /// Taken at the start of every foreground pipeline run so a brief trip
    /// to the background doesn't suspend it mid-batch. On expiry: stop the
    /// run (cursor persists) and hand off to the BGProcessingTask.
    func beginRunAssertion() {
        guard assertionId == .invalid else { return }
        assertionId = UIApplication.shared.beginBackgroundTask(withName: "index-run") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.pipeline.cancel()
                Self.schedule()
                self.endRunAssertion()
            }
        }
    }

    func endRunAssertion() {
        guard assertionId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(assertionId)
        assertionId = .invalid
    }
}
