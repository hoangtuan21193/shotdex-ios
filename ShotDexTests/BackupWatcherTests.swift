import Foundation
import Testing
@testable import ShotDex

/// The coordinator that keeps jobs watching (FS-22.02 §1, §4).
@Suite @MainActor struct BackupWatcherTests {
    /// Photos stand-in: a token that moves on every change, and can be made
    /// unreadable.
    final class FakePhotos: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 1
        var tokenIsBroken = false

        func change() { lock.withLock { generation += 1 } }

        func check(_ token: Data?) -> (changed: Bool, token: Data?) {
            lock.withLock {
                let current = Data("\(generation)".utf8)
                guard !tokenIsBroken, let token else { return (true, current) }
                return (token != current, current)
            }
        }
    }

    private func coordinator(_ f: BackupFixture, photos: FakePhotos = FakePhotos(), exporter: (any AssetFileExporting)? = nil) -> BackupCoordinator {
        BackupCoordinator(store: f.store, environment: BackupEnvironment(
            makeRunner: { _, retries, onProgress in f.runner(exporter: exporter, retriesExhausted: retries, onProgress: onProgress) },
            photosChange: { photos.check($0) },
            settle: .milliseconds(50)
        ))
    }

    private func settle(_ c: BackupCoordinator) async throws {
        try await Task.sleep(for: .milliseconds(150))
        await c.waitUntilIdle()
    }

    /// Coming forward never asks Photos on the main thread: on a busy Photos
    /// daemon that call blocks, and the app froze for minutes at launch.
    @Test func foregroundCheckRunsOffTheMainThread() async throws {
        let f = try BackupFixture(photos: 2)
        let c = coordinator(f)
        await c.appBecameActive().value
        await c.waitUntilIdle()
        let onMain = MainThreadProbe()
        let probing = BackupCoordinator(store: f.store, environment: BackupEnvironment(
            makeRunner: { _, retries, onProgress in f.runner(retriesExhausted: retries, onProgress: onProgress) },
            photosChange: { token in
                onMain.record(Thread.isMainThread)
                return (false, token)
            },
            settle: .milliseconds(50)
        ))
        await probing.appBecameActive().value
        #expect(onMain.calls > 0)
        #expect(onMain.sawMain == false)
    }

    /// AC-10: a job up to date sees 3 photos appear — it uploads them and
    /// goes back to Watching · Up to Date.
    @Test func libraryChangeQueuesNewItems() async throws {
        let f = try BackupFixture(photos: 2)
        let photos = FakePhotos()
        let c = coordinator(f, photos: photos)
        await c.appBecameActive().value
        await c.waitUntilIdle()
        #expect(c.states[f.job.id]?.status == .watching)

        var added: [String: Data] = [:]
        var items: [BackupSourceItem] = []
        for n in 100..<103 {
            let (item, data) = BackupFixture.item(n, name: "NEW_\(n).HEIC")
            items.append(item)
            added.merge(data) { $1 }
        }
        var bigger = f
        bigger.contents.merge(added) { $1 }
        let c2 = coordinator(bigger, photos: photos)
        f.source.add(items)
        photos.change()

        var sawUploading = false
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                if c2.states[f.job.id]?.status == .uploading { sawUploading = true }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        c2.photoLibraryDidChange()
        try await settle(c2)
        watch.cancel()

        #expect(c2.progress[f.job.id]?.total == 3)
        #expect(sawUploading || c2.progress[f.job.id]?.done == 3)
        #expect(c2.states[f.job.id]?.status == .watching)
        #expect(f.remoteFiles.count == 5)
    }

    /// AC-11: two photos added while the app was away are copied when it
    /// comes forward; nothing else is copied again.
    @Test func catchUpOnForeground() async throws {
        var f = try BackupFixture(photos: 4)
        let photos = FakePhotos()
        let c = coordinator(f, photos: photos)
        await c.appBecameActive().value
        await c.waitUntilIdle()
        let uploads = f.client.uploadCount

        let (a, da) = BackupFixture.item(50, name: "AWAY_1.HEIC")
        let (b, db) = BackupFixture.item(51, name: "AWAY_2.HEIC")
        f.contents.merge(da) { $1 }
        f.contents.merge(db) { $1 }
        f.source.add([a, b])
        photos.change()

        let back = coordinator(f, photos: photos)
        await back.appBecameActive().value
        await back.waitUntilIdle()
        #expect(f.client.uploadCount == uploads + 2)
        #expect(back.states[f.job.id]?.status == .watching)

        // Forward again with nothing new: the token says so, no run.
        let quiet = coordinator(f, photos: photos)
        await quiet.appBecameActive().value
        #expect(quiet.isIdle)
    }

    /// AC-12: an unreadable change token means a whole comparison, with the
    /// same outcome as a good token.
    @Test func expiredTokenFallsBackToFullDiff() async throws {
        var f = try BackupFixture(photos: 3)
        let photos = FakePhotos()
        let c = coordinator(f, photos: photos)
        await c.appBecameActive().value
        await c.waitUntilIdle()

        let (n, dn) = BackupFixture.item(60, name: "LATE.HEIC")
        f.contents.merge(dn) { $1 }
        f.source.add([n])
        photos.tokenIsBroken = true

        let back = coordinator(f, photos: photos)
        await back.appBecameActive().value
        await back.waitUntilIdle()
        #expect(back.progress[f.job.id]?.total == 1)
        #expect(f.remoteFiles.count == 4)
        #expect(back.states[f.job.id]?.status == .watching)
    }

    /// AC-16: Pause stops the file in flight within 2 s and removes its part
    /// file; a library change does not start the job; Resume copies the rest.
    @Test func pauseStopsWatchingUntilResume() async throws {
        let f = try BackupFixture(photos: 10, bytes: 64)
        let photos = FakePhotos()
        let slow = SlowExporter(base: FakeAssetExporter(contents: f.contents), delay: .milliseconds(500))
        let c = coordinator(f, photos: photos, exporter: slow)
        c.backUpNow(f.job.id)
        while (c.progress[f.job.id]?.done ?? 0) < 4 { try await Task.sleep(for: .milliseconds(10)) }

        let start = Date()
        c.pause(f.job.id)
        await c.waitUntilIdle()
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(c.states[f.job.id]?.status == .pausedByUser)
        #expect(f.partFiles.isEmpty)
        let copied = try f.store.handledCount(jobId: f.job.id)
        #expect(copied < 10)

        photos.change()
        c.photoLibraryDidChange()
        try await settle(c)
        #expect(try f.store.handledCount(jobId: f.job.id) == copied)

        c.resume(f.job.id)
        await c.waitUntilIdle()
        #expect(c.states[f.job.id]?.status == .watching)
        #expect(f.remoteFiles.count == 10)
    }

    /// iOS ending the background time leaves the job watching, with numbers
    /// for "iOS stopped ShotDex at N of M".
    @Test func systemStopKeepsWatching() async throws {
        let f = try BackupFixture(photos: 6, bytes: 64)
        let slow = SlowExporter(base: FakeAssetExporter(contents: f.contents), delay: .milliseconds(500))
        let c = coordinator(f, exporter: slow)
        c.backUpNow(f.job.id)
        while (c.progress[f.job.id]?.done ?? 0) < 2 { try await Task.sleep(for: .milliseconds(10)) }
        c.systemWillStop()
        await c.waitUntilIdle()
        let state = try #require(c.states[f.job.id])
        #expect(state.status == .pausedBySystem)
        #expect(state.statusTotal == 6)
        #expect((2...6).contains(state.statusDone ?? 0))
    }
}

/// Waits before each export, so a test can act mid-run.
struct SlowExporter: AssetFileExporting {
    let base: FakeAssetExporter
    let delay: Duration

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        try await Task.sleep(for: delay)
        return try await base.export(assetId: assetId, file: file, into: directory)
    }
}

private final class MainThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var main = false
    var calls: Int { lock.withLock { count } }
    var sawMain: Bool { lock.withLock { main } }
    func record(_ isMain: Bool) { lock.withLock { count += 1; main = main || isMain } }
}
