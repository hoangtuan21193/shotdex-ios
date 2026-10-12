import BackgroundTasks
import Foundation

/// Backup's background time (FS-22.02 §3): a short refresh that finds new
/// files and copies small ones, a long processing slot iOS grants when it
/// likes, and on iOS 26 a continued-processing task that keeps a run the user
/// started going after they leave the app.
@MainActor
final class BackupBackgroundService {
    static let refreshIdentifier = "com.hoangtuan.shotdex.backup.refresh"
    static let processingIdentifier = "com.hoangtuan.shotdex.backup"
    static let continuedIdentifier = "com.hoangtuan.shotdex.backup.continued"

    private let coordinator: BackupCoordinator
    private let servers: FileServerStore
    /// A continued-processing request was accepted for the run going now.
    private(set) var hasContinuedTask = false

    init(coordinator: BackupCoordinator, servers: FileServerStore) {
        self.coordinator = coordinator
        self.servers = servers
        coordinator.onUserStart = { [weak self] jobId in self?.userStartedRun(jobId) }
        coordinator.screen = ScreenAwakeCoordinator.shared
        coordinator.onJobsReloaded = { jobs in BackupUploadExtensionSync.apply(jobs: jobs, servers: servers) }
        BackupUploadExtensionSync.apply(jobs: coordinator.jobs, servers: servers)
    }

    /// Before launch finishes (BGTaskScheduler rule) — see `ShotDexApp.init`.
    func register() {
        let coordinator = coordinator
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                Self.run(task, coordinator: coordinator, then: { Self.scheduleProcessing(coordinator) })
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                Self.run(task, coordinator: coordinator, then: {})
            }
        }
        if #available(iOS 26.0, *) {
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
    }

    /// The app is leaving the screen: ask for a refresh and, when there is
    /// work left, a processing slot.
    func appDidEnterBackground() {
        guard !coordinator.jobs.isEmpty else { return }
        // Without an accepted continued task the run stops at the file it is
        // on, cleanly, rather than being frozen mid-write (FS-22.02 §3).
        if !hasContinuedTask { coordinator.systemWillStop() }
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)
        Self.scheduleProcessing(coordinator)
    }

    /// A run the user started (Start, Resume, Back Up Now, Retry): on iOS 26
    /// it may go on after they leave, with the system's own progress UI.
    /// "Run now or not at all" — never queued for later.
    func userStartedRun(_ jobId: String) {
        guard #available(iOS 26.0, *) else { return }
        let name = coordinator.jobs.first { $0.id == jobId }
            .flatMap { try? servers.fetch(id: $0.connectionId)?.name } ?? ""
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: String(localized: "Backing up to \(name)", comment: "System progress title for a backup run"),
            subtitle: String(localized: "Starting…", comment: "System progress subtitle before the first file")
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            hasContinuedTask = true
        } catch {
            hasContinuedTask = false
        }
    }

    private static func scheduleProcessing(_ coordinator: BackupCoordinator) {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = coordinator.jobs.allSatisfy(\.settings.onlyWhileCharging)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Registered with `using: .main`, so the handlers run on the main thread
    /// and `assumeIsolated` above holds.
    private static func run(_ task: BGTask, coordinator: BackupCoordinator, then: @escaping @MainActor () -> Void) {
        let completion = TaskCompletion(task)
        task.expirationHandler = {
            Task { @MainActor in
                coordinator.systemWillStop()
                // Even if a call does not notice the cancel, iOS is told.
                completion.finish(success: false)
            }
        }
        coordinator.appBecameActive()
        coordinator.sourcesTick()
        Task { @MainActor in
            await coordinator.waitUntilIdle()
            then()
            completion.finish(success: true)
        }
    }

    @available(iOS 26.0, *)
    private func runContinued(_ task: BGContinuedProcessingTask) {
        let coordinator = coordinator
        task.expirationHandler = {
            Task { @MainActor in coordinator.systemWillStop() }
        }
        task.progress.totalUnitCount = 1_000
        Task { @MainActor in
            while !coordinator.isIdle {
                if let id = coordinator.runningJobId, let progress = coordinator.progress[id], progress.total > 0 {
                    task.progress.completedUnitCount = Int64(Double(progress.done) / Double(progress.total) * 1_000)
                    task.updateTitle(task.title, subtitle: String(
                        localized: "\(progress.done) of \(progress.total) · \(progress.bytesDone.formatted(.byteCount(style: .file))) of \(progress.bytesTotal.formatted(.byteCount(style: .file)))",
                        comment: "System progress subtitle for a backup run"
                    ))
                }
                try? await Task.sleep(for: .seconds(1))
            }
            let stopped = coordinator.states.values.contains { $0.status == .pausedBySystem }
            hasContinuedTask = false
            task.setTaskCompleted(success: !stopped)
        }
    }
}

/// Ends a background task exactly once — the run finishing and the expiry
/// can both try.
@MainActor
private final class TaskCompletion {
    private let task: BGTask
    private var isDone = false

    init(_ task: BGTask) { self.task = task }

    func finish(success: Bool) {
        guard !isDone else { return }
        isDone = true
        task.setTaskCompleted(success: success)
    }
}
