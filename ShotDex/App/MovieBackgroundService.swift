import BackgroundTasks
import Foundation
import UIKit

/// Movie downloads and the app's lifecycle (FS-23.01 §6, AC-54). A download
/// the app reads itself (SMB, SFTP, Files) asks iOS 26 for a
/// continued-processing task, with the system's own progress UI; without
/// one it is stopped cleanly when the app leaves the screen and carries on
/// when it comes back. Background-session downloads (WebDAV) need none of
/// this: iOS runs them.
@MainActor
final class MovieBackgroundService {
    static let continuedIdentifier = "com.hoangtuan.shotdex.movies.continued"

    private let runner: MovieDownloadRunner
    private(set) var hasContinuedTask = false

    init(runner: MovieDownloadRunner) {
        self.runner = runner
        runner.onForegroundDownloadStarted = { [weak self] movie in self?.downloadStarted(movie) }
    }

    /// Before launch finishes (BGTaskScheduler rule).
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
        if !hasContinuedTask { runner.pauseForSystem() }
    }

    func appBecameActive() {
        runner.resumeInterrupted()
    }

    private func downloadStarted(_ movie: Movie) {
        guard #available(iOS 26.0, *), !hasContinuedTask else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIdentifier,
            title: String(localized: "Downloading \(movie.displayTitle)", comment: "System progress title for a movie download"),
            subtitle: String(localized: "Starting…", comment: "System progress subtitle before the first bytes")
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
        let runner = runner
        task.expirationHandler = {
            Task { @MainActor in runner.pauseForSystem() }
        }
        task.progress.totalUnitCount = 1_000
        Task { @MainActor in
            while let id = runner.current, !runner.currentIsBackground {
                if let movie = try? runner.movie(id), movie.byteCount > 0 {
                    let bytes = runner.bytes(for: movie)
                    task.progress.completedUnitCount = Int64(Double(bytes) / Double(movie.byteCount) * 1_000)
                    task.updateTitle(
                        String(localized: "Downloading \(movie.displayTitle)", comment: "System progress title for a movie download"),
                        subtitle: String(localized: "\(bytes.formatted(.byteCount(style: .file))) of \(movie.byteCount.formatted(.byteCount(style: .file)))", comment: "System progress subtitle for a movie download")
                    )
                }
                try? await Task.sleep(for: .seconds(1))
            }
            hasContinuedTask = false
            task.setTaskCompleted(success: true)
        }
    }
}

/// Only for what SwiftUI has no hook for: iOS waking the app to finish a
/// background URL session.
final class ShotDexAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            BackgroundURLSessionEvents.store(completionHandler, for: identifier)
        }
    }
}
