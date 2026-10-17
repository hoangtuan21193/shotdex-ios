import BackgroundTasks
import Foundation

/// A card import's time after the user leaves (FS-20 §7, AC-26): on iOS 26
/// the run asks for a continued-processing task when it starts, so iOS keeps
/// it going with its own progress; without one, leaving stops it like Stop.
/// The same shape as Backup's (`BackupBackgroundService`).
@MainActor
final class IngestBackgroundService {
    static let continuedIdentifier = "com.hoangtuan.shotdex.ingest.continued"

    private let center: IngestCenter
    /// A continued-processing request was accepted for the run going now.
    private(set) var hasContinuedTask = false

    init(center: IngestCenter) {
        self.center = center
        center.onUserStart = { [weak self] model in self?.userStartedRun(model) }
    }

    /// Before launch finishes (BGTaskScheduler rule) — see `ShotDexApp.init`.
    func register() {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.continuedIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.runContinued(continued)
            }
        }
    }

    func appDidEnterBackground() {
        for model in center.models.values where IngestBackgroundPolicy.onBackground(
            isRunning: model.isRunning, hasContinuedTask: hasContinuedTask) == .stop {
            model.stop()
        }
    }

    /// Import N Photos, Import Remaining, Retry Failed: "run now or not at
    /// all", never queued for later.
    private func userStartedRun(_ model: IngestModel) {
        guard #available(iOS 26.0, *) else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: String(localized: "Importing from \(model.card.name)", table: IngestCopy.table,
                          comment: "System progress title for a card import"),
            subtitle: String(localized: "Starting…", table: IngestCopy.table, comment: "System progress subtitle before the first file")
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            hasContinuedTask = true
        } catch {
            hasContinuedTask = false
        }
    }

    @available(iOS 26.0, *)
    private func runContinued(_ task: BGContinuedProcessingTask) {
        let center = center
        task.expirationHandler = {
            Task { @MainActor in center.running?.stop() }
        }
        task.progress.totalUnitCount = 1_000
        Task { @MainActor in
            while let model = center.running {
                task.progress.completedUnitCount = Int64(model.progress.fraction * 1_000)
                task.updateTitle(task.title, subtitle: IngestCopy.progressLine(model.progress))
                try? await Task.sleep(for: .seconds(1))
            }
            hasContinuedTask = false
            task.setTaskCompleted(success: true)
        }
    }
}
