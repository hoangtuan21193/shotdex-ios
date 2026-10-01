import Foundation
import ShotDexKit
import Testing
import UIKit
@testable import ShotDex

/// FS-02.06 §9 / FS-08.06 §5: the share sheet opens with lazy items, and
/// nothing is downloaded or written until a destination asks.
@MainActor
@Suite(.serialized) struct LazyShareItemTests {
    let directory: URL
    let photo: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyShareItemTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options = MetadataFixture.Options()
        options.width = 60
        options.height = 40
        photo = directory.appendingPathComponent("local.jpg")
        try MetadataFixture.encode(.jpeg, options: options).write(to: photo)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func batch(_ count: Int, script: String) -> (LazyShareBatch, FakeOriginalFetcher) {
        let ids = (1...count).map { String(format: "%02d", $0) }
        let sources = ids.map { ShareSource(id: $0, kind: .photo, filename: "IMG_\($0).JPG", uniformType: "public.jpeg") }
        let originals = Dictionary(uniqueKeysWithValues: ids.map { ($0, OriginalItem.test($0)) })
        let fake = FakeOriginalFetcher(script: .init(script), base: FixtureOriginalFetcher())
        let reader = ShareExportPipelineTests.FakeReader(photos: Dictionary(uniqueKeysWithValues: ids.map { ($0, photo) }))
        let batch = LazyShareBatch(
            sources: sources, originals: originals, level: .all, fetcher: fake,
            availableBytes: { 10_000_000_000 }, reader: reader, directory: directory
        )
        return (batch, fake)
    }

    /// What a destination does: asks every provider for its item, each on
    /// a thread of its own, the way UIKit's operation queue does — never on
    /// the Swift concurrency pool, which a blocked provider would starve.
    nonisolated static func ask(_ providers: [LazyShareItemProvider], activity: UIActivity.ActivityType? = nil) async -> [Any] {
        await withTaskGroup(of: (Int, Any).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        Thread { continuation.resume(returning: (index, provider.item(for: activity))) }.start()
                    }
                }
            }
            var items: [(Int, Any)] = []
            for await item in group { items.append(item) }
            return items.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// AC-6. Twelve photos, three only in iCloud: the sheet gets twelve lazy
    /// items and nothing is fetched; once a destination asks, the three are
    /// downloaded and every item is a file; the files go when the sheet closes.
    @Test func sheetOpensWithZeroFetches() async throws {
        defer { cleanUp() }
        let (batch, fake) = batch(12, script: "cloud=3,seconds=0.4")
        let providers = batch.providers(header: ShareHeader(title: "All metadata"))
        #expect(providers.count == 12)
        #expect(fake.fetchCount == 0)
        #expect(fake.downloadCount == 0)
        #expect(batch.stage == .waiting)
        #expect(!batch.results.hasBeenAsked)
        #expect((providers[0].placeholderItem as? URL)?.lastPathComponent == "IMG_01.JPG")

        let items = await Self.ask(providers)
        let files = items.compactMap { $0 as? URL }
        #expect(files.count == 12)
        #expect(Set(files.map(\.path)).count == 12)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(fake.downloadCount == 3)
        #expect(batch.stage == .finished)
        // The downloaded originals went once the copies were written.
        #expect(batch.preparation.map { FileManager.default.fileExists(atPath: $0.folder.path) } == false)
        batch.removeFiles()
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    /// The level rows reopen the sheet: choosing one prepares nothing.
    @Test func levelRowsPrepareNothing() async {
        defer { cleanUp() }
        let (batch, fake) = batch(2, script: "cloud=all,seconds=0.2")
        let providers = batch.providers(header: nil)
        let items = await Self.ask(providers, activity: ShareLevelRow.activityType(for: .noLocation))
        #expect(items.allSatisfy { $0 is URL })
        #expect(fake.fetchCount == 0)
        #expect(!batch.results.hasBeenAsked)
    }

    /// FS-08.06 AC-11 / FS-02.06 §5. Cancel in the modal while the batch is
    /// gathering: the destination gets no file, the folders of this share
    /// are gone, and the share sheet is told to close.
    @Test func cancelWhileGatheringDeliversNothing() async throws {
        defer { cleanUp() }
        let (batch, fake) = batch(20, script: "cloud=5,seconds=30")
        var closed = false
        batch.onCancel = { closed = true }
        let providers = batch.providers(header: nil)
        let asking = Task { await Self.ask(providers) }
        try await Task.sleep(for: .milliseconds(500))
        #expect(batch.stage == .preparing)
        #expect(fake.downloadCount == 4)
        batch.cancel()
        let items = await asking.value
        #expect(items.allSatisfy { !($0 is URL) })
        #expect(closed)
        #expect(batch.stage == .cancelled)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(left.allSatisfy { !$0.hasPrefix(OriginalPreparation.prefix) && !$0.hasPrefix(ShareExportPipeline.prefix) })
    }

    /// Waits, briefly, for a condition the batch reaches on its own.
    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        #expect(condition())
    }

    /// AC-7. Twelve photos, three in iCloud, two of the downloads fail: the
    /// modal names them with "Share 10" · Retry · Cancel, and no provider
    /// has handed anything over while it asks. Share 10 hands over ten.
    @Test func failuresHoldProvidersUntilChoice() async throws {
        defer { cleanUp() }
        let (batch, fake) = batch(12, script: "cloud=3,seconds=0.3,fail=1+2")
        let providers = batch.providers(header: nil)
        let asking = Task { await Self.ask(providers) }
        try await until { batch.preparation?.state.phase == .failed }
        let state = try #require(batch.preparation?.state)
        #expect(state.failureTitle == "2 of 12 photos couldn't be downloaded from iCloud.")
        #expect(state.failedNames.count == 2)
        #expect(state.continueCount == 10)
        #expect(batch.isShown)
        #expect(batch.shareFolder == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(batch.stage == .preparing)
        batch.preparation?.choose(.continueWithout)
        let items = await asking.value
        #expect(items.compactMap { $0 as? URL }.count == 10)
        #expect(fake.downloadCount == 3)
        batch.removeFiles()
    }

    /// AC-7. Cancel at the failure: nothing reaches the destination and the
    /// share sheet is told to close.
    @Test func cancelDeliversNothing() async throws {
        defer { cleanUp() }
        let (batch, _) = batch(12, script: "cloud=3,seconds=0.3,fail=2")
        var closed = false
        batch.onCancel = { closed = true }
        let asking = Task { await Self.ask(batch.providers(header: nil)) }
        try await until { batch.preparation?.state.phase == .failed }
        batch.cancel()
        let items = await asking.value
        #expect(items.allSatisfy { !($0 is URL) })
        #expect(closed)
    }

    /// AC-18. Indexing pauses while a share downloads, and runs again once
    /// the modal is gone.
    @Test func indexGateHeldDuringShare() async throws {
        defer { cleanUp() }
        let gate = IndexInteractionGate()
        let ids = ["01", "02"]
        let sources = ids.map { ShareSource(id: $0, kind: .photo, filename: "IMG_\($0).JPG", uniformType: "public.jpeg") }
        let fake = FakeOriginalFetcher(script: .init("cloud=all,seconds=0.6"), base: FixtureOriginalFetcher())
        let batch = LazyShareBatch(
            sources: sources, originals: Dictionary(uniqueKeysWithValues: ids.map { ($0, OriginalItem.test($0)) }),
            level: .all, fetcher: fake, gate: gate, availableBytes: { nil },
            reader: ShareExportPipelineTests.FakeReader(photos: ["01": photo, "02": photo]), directory: directory
        )
        #expect(!gate.shouldPauseIndexing)
        let asking = Task { await Self.ask(batch.providers(header: nil)) }
        try await until { batch.stage == .preparing && fake.downloadCount > 0 }
        #expect(gate.shouldPauseIndexing)
        _ = await asking.value
        #expect(batch.stage == .finished)
        #expect(!gate.shouldPauseIndexing)
        batch.removeFiles()
    }

    /// AC-18 / §9. Every way into Share from the library — selection, tile
    /// menu, album, smart album, On This Day, viewer — opens the lazy share;
    /// none gathers before the sheet, and no toolbar grows a download token.
    @Test func everyShareEntryIsLazy() throws {
        let files = [
            "ShotDex/Features/Library/LibraryScreen.swift",
            "ShotDex/App/AssetActionsCoordinator.swift",
            "ShotDex/Features/Albums/AlbumDetailScreen.swift",
            "ShotDex/Features/Albums/SmartAlbumDetailScreen.swift",
            "ShotDex/Features/Albums/OnThisDayScreen.swift",
        ]
        for path in files {
            let code = try AssetMetadataCarryOverTests.codeLines(of: path).joined(separator: "\n")
            #expect(code.contains("PhotoShareSheet.share(assets:"), "\(path)")
            #expect(!code.contains("PhotoShareSheet.gather(assets:"), "\(path)")
            #expect(!code.contains("isPreparingShare"), "\(path)")
            #expect(!code.contains("OriginalDownloadLine"), "\(path)")
        }
    }
}
