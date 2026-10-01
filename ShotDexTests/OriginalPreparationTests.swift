import Foundation
import Testing
@testable import ShotDex

/// FS-02.06 §5: one batch's preparation over a scripted iCloud library.
@MainActor
@Suite(.serialized) struct OriginalPreparationTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginalPreparationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func items(_ count: Int) -> [OriginalItem] {
        (1...count).map { OriginalItem.test(String(format: "%02d", $0)) }
    }

    /// AC-6. Twelve photos, three of them only in iCloud (20 MB each): only
    /// the three are downloaded and counted; the percent is the average per
    /// photo; the share line names the size; three files land on disk and
    /// go with `removeFiles()`.
    @Test func twelvePhotosThreeInICloud() async throws {
        defer { cleanUp() }
        let fake = FakeOriginalFetcher(script: .init("cloud=3,seconds=0.6,mb=20"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(
            items: items(12), fetcher: fake, availableBytes: { 10_000_000_000 }, in: directory
        )
        var seen: [OriginalPreparationState] = []
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                seen.append(preparation.state)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let outcome = await preparation.run()
        watch.cancel()
        guard case .ready(let files, let skipped) = outcome else { Issue.record("\(outcome)"); return }
        #expect(skipped.isEmpty)
        #expect(files.count == 3)
        #expect(fake.downloadCount == 3)
        #expect(preparation.state.downloadCount == 3)
        #expect(preparation.state.totalBytes == 60_000_000)
        #expect(preparation.state.shareLine == "Downloading from iCloud · 100% · 60 MB")
        let middle = try #require(seen.first { $0.phase == .downloading && $0.percent > 20 && $0.percent < 80 })
        let average = middle.downloads.map { $0.isFinished ? 1 : $0.fraction }.reduce(0, +) / 3
        #expect(middle.percent == Int((average * 100).rounded(.down)))
        #expect(middle.progressLine.hasPrefix("Downloading from iCloud · "))
        #expect(middle.progressLine.contains(" of 3 · "))
        for file in files.values { #expect(FileManager.default.fileExists(atPath: file.path)) }
        preparation.removeFiles()
        #expect(!FileManager.default.fileExists(atPath: preparation.folder.path))
    }

    /// §3. A batch already on the device never shows anything: done well
    /// inside 350 ms, never shown.
    @Test func aLocalBatchShowsNothing() async {
        defer { cleanUp() }
        let fake = FakeOriginalFetcher(script: .init("cloud=none"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(items: items(12), fetcher: fake, in: directory)
        let started = ContinuousClock.now
        let outcome = await preparation.run()
        #expect(outcome == .ready(files: [:], skipped: []))
        #expect(ContinuousClock.now - started < .milliseconds(350))
        #expect(!preparation.isShown)
        #expect(fake.fetchCount == 0)
    }

    /// §3. Past 350 ms a running batch is shown.
    @Test func aSlowBatchShowsAfterTheThreshold() async throws {
        defer { cleanUp() }
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=1"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(items: items(2), fetcher: fake, in: directory)
        let run = Task { await preparation.run() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!preparation.isShown)
        try await Task.sleep(for: .milliseconds(400))
        #expect(preparation.isShown)
        _ = await run.value
        #expect(!preparation.isShown)
        preparation.removeFiles()
    }

    /// §3 (Q2). User downloads run at most four at a time, and indexing is
    /// paused for exactly as long as the batch runs.
    @Test func fourAtATimeWithTheIndexPaused() async throws {
        defer { cleanUp() }
        let gate = IndexInteractionGate()
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=0.3"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(items: items(10), fetcher: fake, gate: gate, in: directory)
        #expect(!gate.shouldPauseIndexing)
        let run = Task { await preparation.run() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(gate.shouldPauseIndexing)
        _ = await run.value
        #expect(fake.peakConcurrency == 4)
        #expect(fake.downloadCount == 10)
        #expect(!gate.shouldPauseIndexing)
        preparation.removeFiles()
    }

    /// §3. 15 s at 0% says iCloud is not answering, and cancels nothing
    /// (a short window here stands in for the 15 s).
    @Test func aStallIsSaidAndNotCancelled() async throws {
        defer { cleanUp() }
        let fake = FakeOriginalFetcher(script: .init("cloud=all,stall"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(
            items: items(2), fetcher: fake, in: directory, stallWindow: .milliseconds(400)
        )
        let run = Task { await preparation.run() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!preparation.isStalled)
        try await Task.sleep(for: .milliseconds(800))
        #expect(preparation.isStalled)
        #expect(fake.cancelledCount == 0)
        #expect(preparation.state.phase == .downloading)
        preparation.cancel()
        #expect(await run.value == .cancelled)
        #expect(OriginalPreparationState.stallWindow == .seconds(15))
    }

    /// §5. Cancel stops every download within a second, and nothing stays.
    @Test func cancelStopsEveryDownload() async throws {
        defer { cleanUp() }
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=30"), base: FixtureOriginalFetcher())
        let preparation = OriginalPreparation(items: items(6), fetcher: fake, in: directory)
        let run = Task { await preparation.run() }
        try await Task.sleep(for: .milliseconds(300))
        let pressed = ContinuousClock.now
        preparation.cancel()
        #expect(await run.value == .cancelled)
        #expect(ContinuousClock.now - pressed < .seconds(1))
        #expect(fake.cancelledCount == 4)
        #expect(!FileManager.default.fileExists(atPath: preparation.folder.path))
    }
}
