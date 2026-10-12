import Foundation
import Testing
@testable import ShotDex

/// Background time for backups (FS-22.02 §3).
@Suite @MainActor struct BackupBackgroundTests {
    final class FakeScreen: ScreenHolding {
        var holds = 0
        var begins = 0
        func beginHold() { holds += 1; begins += 1 }
        func endHold() { holds -= 1 }
    }

    private func coordinator(_ f: BackupFixture, exporter: (any AssetFileExporting)? = nil) -> BackupCoordinator {
        BackupCoordinator(store: f.store, environment: BackupEnvironment(
            makeRunner: { _, retries, onProgress in f.runner(exporter: exporter, retriesExhausted: retries, onProgress: onProgress) },
            photosChange: { _ in (true, nil) },
            settle: .milliseconds(20)
        ))
    }

    /// AC-19: the three task identifiers are in Info.plist.
    @Test func identifiersRegistered() {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        #expect(permitted.contains(BackupBackgroundService.refreshIdentifier))
        #expect(permitted.contains(BackupBackgroundService.processingIdentifier))
        #expect(permitted.contains(BackupBackgroundService.continuedIdentifier))
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("fetch") && modes.contains("processing"))
    }

    /// AC-17 (the app's half): a run the user starts asks once for continued
    /// processing; runs found by watching never do; an iOS stop reads
    /// "iOS stopped ShotDex at N of M". The system's own UI is not
    /// reachable on the simulator.
    @Test func continuedTaskOnUserStart() async throws {
        let f = try BackupFixture(photos: 40, bytes: 64)
        let slow = SlowExporter(base: FakeAssetExporter(contents: f.contents), delay: .milliseconds(100))
        let c = coordinator(f, exporter: slow)
        var asked: [String] = []
        c.onUserStart = { asked.append($0) }

        c.appBecameActive()
        #expect(asked.isEmpty)
        while (c.progress[f.job.id]?.done ?? 0) < 3 { try await Task.sleep(for: .milliseconds(20)) }
        c.systemWillStop()
        await c.waitUntilIdle()
        let state = try #require(c.states[f.job.id])
        #expect(state.status == .pausedBySystem)
        #expect(state.statusTotal == 40)
        #expect(asked.isEmpty)

        c.resume(f.job.id)
        #expect(asked == [f.job.id])
        await c.waitUntilIdle()
        #expect(c.states[f.job.id]?.status == .watching)
    }

    /// AC-18: before iOS 26, Keep Screen On holds the screen only while a
    /// run goes, and lets go when it finishes or is paused.
    @Test func pre26KeepsScreenAndSchedules() async throws {
        var f = try BackupFixture(photos: 6, bytes: 64)
        f.job.settings.keepsScreenOn = true
        try f.store.update(f.job)
        let slow = SlowExporter(base: FakeAssetExporter(contents: f.contents), delay: .milliseconds(150))
        let c = coordinator(f, exporter: slow)
        let screen = FakeScreen()
        c.screen = screen
        c.usesKeepScreenOn = true

        c.backUpNow(f.job.id)
        while (c.progress[f.job.id]?.done ?? 0) < 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(screen.holds == 1)
        c.pause(f.job.id)
        await c.waitUntilIdle()
        #expect(screen.holds == 0)

        c.resume(f.job.id)
        await c.waitUntilIdle()
        #expect(screen.holds == 0)
        #expect(screen.begins == 2)

        // iOS 26 path: the switch does nothing.
        c.usesKeepScreenOn = false
        c.backUpNow(f.job.id)
        await c.waitUntilIdle()
        #expect(screen.begins == 2)
    }
}
