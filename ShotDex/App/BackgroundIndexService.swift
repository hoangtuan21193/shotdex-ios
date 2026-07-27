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
/// Background runs use the **same network policy as the foreground** (Wi-Fi
/// always, cellular only on opt-in). They used to be pinned to
/// `allowNetwork: false`, which made them useless on the library this was
/// measured against: with "Optimize iPhone Storage" on, ~91 % of assets have no
/// local original, so a local-only background run reads nothing at all. Reading
/// them costs ~1 MB each over iCloud (PhotoKit's minimum chunk) — tens of hours
/// of downloading for a 50k-photo library, which is only tolerable if it happens
/// while the app is not in front of the user.
@MainActor
final class BackgroundIndexService {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.hoangtuan.shotdex.index"

    private let pipeline: IndexPipeline
    private let metadataStore: MetadataStore
    /// Re-evaluated per batch by the pipeline, so a background run that starts
    /// on Wi-Fi and drops to cellular stops streaming at the next batch.
    private let allowNetwork: @Sendable () -> Bool
    private var assertionId: UIBackgroundTaskIdentifier = .invalid

    init(
        pipeline: IndexPipeline,
        metadataStore: MetadataStore,
        allowNetwork: @escaping @Sendable () -> Bool
    ) {
        self.pipeline = pipeline
        self.metadataStore = metadataStore
        self.allowNetwork = allowNetwork
    }

    // MARK: BGProcessingTask

    /// Must be called before the app finishes launching
    /// (BGTaskScheduler requirement) — see `ShotDexApp.init`.
    func register() {
        let pipeline = self.pipeline
        let metadataStore = self.metadataStore
        let allowNetwork = self.allowNetwork
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
                let summary = try? await pipeline.run(allowNetwork: allowNetwork)
                // "Finished" means the library is actually read, not merely that
                // this slot ran to its end. A run that walks everything and
                // leaves 40k rows `pendingICloud` (iCloud slow or wedged) is not
                // done, and without rescheduling here it would never be picked up
                // again in the background — the old check only looked at
                // `wasCancelled`, so exactly that case silently stopped.
                let pending = (try? metadataStore.pendingICloudReadCount()) ?? 0
                let finished = summary?.wasCancelled == false && pending == 0
                if !finished {
                    Self.schedule(requiresNetwork: pending > 0)
                }
                task.setTaskCompleted(success: finished)
            }
        }
    }

    /// Asks the system for a background continuation slot. A duplicate
    /// submit replaces the pending request; errors (e.g. running on the
    /// simulator, where BGTaskScheduler is unavailable) are non-fatal.
    /// `requiresNetwork` when the remaining work is iCloud reads: without it the
    /// system may hand over a slot with no connectivity, where such a run can
    /// only re-confirm that it cannot read anything.
    static func schedule(requiresNetwork: Bool = false) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = requiresNetwork
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
            // Rows still waiting on iCloud count as unfinished work even when no
            // cursor is left behind: a completed-but-incomplete run clears the
            // cursor, and keying only off that meant the long iCloud tail never
            // got a background continuation.
            let pending = (try? metadataStore.pendingICloudReadCount()) ?? 0
            if await pipeline.isActive || (try? metadataStore.indexState())?.cursorAssetId != nil || pending > 0 {
                Self.schedule(requiresNetwork: pending > 0)
            }
        }
    }

    // MARK: Foreground-run assertion

    /// Taken at the start of every foreground pipeline run so a brief trip
    /// to the background doesn't suspend it mid-batch. On expiry: stop the
    /// run (cursor persists) and hand off to the BGProcessingTask.
    /// `onExpiry` runs after the stop is requested, on the main actor. The caller
    /// needs it because cancelling the pipeline is **not** visible in the UI for
    /// a long time: the run's task is suspended along with the app, so its
    /// cleanup may not execute until the user comes back — leaving the indexing
    /// indicator claiming a run that was already stopped minutes ago.
    func beginRunAssertion(onExpiry: @escaping @MainActor () -> Void = {}) {
        guard assertionId == .invalid else { return }
        let metadataStore = self.metadataStore
        assertionId = UIApplication.shared.beginBackgroundTask(withName: "index-run") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.pipeline.cancel()
                let pending = (try? metadataStore.pendingICloudReadCount()) ?? 0
                Self.schedule(requiresNetwork: pending > 0)
                self.endRunAssertion()
                onExpiry()
            }
        }
    }

    func endRunAssertion() {
        guard assertionId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(assertionId)
        assertionId = .invalid
    }
}
