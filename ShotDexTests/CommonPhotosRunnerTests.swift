import CryptoKit
import Foundation
import os
import Testing
@testable import ShotDex

/// FS-19.08 §6: copying and moving the Same photos into the shared folder.
@Suite struct CommonPhotosRunnerTests {
    /// A NAS with `count` photos present in both `A` and `B`, scanned, and a
    /// run started on them.
    struct Fixture {
        let nas = InMemoryRemoteFileClient()
        let store: CommonPhotosStore
        let work: URL
        var runId = "R1"
        var photos: [String: Data] = [:]

        init(count: Int, layout: (Int) -> (a: String, b: String) = { ("IMG_\($0).JPG", "IMG_\($0).JPG") }) throws {
            store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
            work = FileManager.default.temporaryDirectory.appendingPathComponent("CommonPhotosRunnerTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            for index in 1...count {
                let bytes = Data((0..<(1_000 + index)).map { UInt8(truncatingIfNeeded: $0 &+ index) })
                let (a, b) = layout(index)
                nas.put("A/\(a)", bytes)
                nas.put("B/\(b)", bytes)
                photos[a] = bytes
            }
            nas.addDirectory("C")
        }

        func start(action: CommonPhotosRun.Action = .copy) async throws {
            let scanner = CommonPhotosScanner(client: nas)
            let listing = try await scanner.list(["A", "B"])
            let found = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: ["A", "B"])
            let items = CommonPhotosRunner.items(for: found.sorted { $0.size < $1.size }, runId: runId, folders: ["A", "B"],
                                                 sidecars: listing.sidecars)
            try store.start(CommonPhotosRun(id: runId, connectionId: "S1", folders: ["A", "B"], destination: "C", action: action),
                            items: items)
        }

        var runner: CommonPhotosRunner { CommonPhotosRunner(client: nas, store: store, workDirectory: work) }

        func items() throws -> [CommonPhotosItem] { try store.items(runId: runId) }
    }

    /// AC-121: five Same photos copied; each one read back and matched; the
    /// sources untouched; five Copied rows.
    @Test func copyVerifiesReadBack() async throws {
        let fixture = try Fixture(count: 5)
        try await fixture.start()
        let before = fixture.nas.files.filter { !$0.key.hasPrefix("C/") }

        try await fixture.runner.run("R1")

        let copied = fixture.nas.files.filter { $0.key.hasPrefix("C/") }
        #expect(copied.count == 5)
        for (name, bytes) in fixture.photos { #expect(copied["C/\(name)"] == bytes) }
        #expect(fixture.nas.files.filter { !$0.key.hasPrefix("C/") } == before)
        #expect(Set(fixture.nas.sha256Paths.filter { $0.hasPrefix("C/") }) == Set((1...5).map { "C/IMG_\($0).JPG.shotdex-part" }))
        let items = try fixture.items()
        #expect(items.map(\.status) == Array(repeating: .copied, count: 5))
        #expect(items.allSatisfy { $0.partPath == nil && $0.destinationPath?.hasPrefix("C/") == true })
        #expect(try fixture.store.run(id: "R1")?.state == .finishing)
    }

    /// AC-122: the third read-back is wrong — its part is removed, nothing
    /// under its real name, Failed "Checksum mismatch"; the other four Copied.
    @Test func copyMismatchLeavesNothing() async throws {
        let fixture = try Fixture(count: 5)
        try await fixture.start()
        fixture.nas.corruptReadBack = ["C/IMG_3.JPG.shotdex-part"]

        try await fixture.runner.run("R1")

        let files = fixture.nas.files
        #expect(files["C/IMG_3.JPG"] == nil)
        #expect(files["C/IMG_3.JPG.shotdex-part"] == nil)
        let items = try fixture.items()
        #expect(items.map(\.status) == [.copied, .copied, .failed, .copied, .copied])
        #expect(items[2].failure?.reason == .checksumMismatch)
        #expect(fixture.nas.files.keys.filter { $0.hasPrefix("A/") || $0.hasPrefix("B/") }.count == 10)
    }

    /// A source rewritten since the scan is not copied.
    @Test func changedSourceIsNotCopied() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        fixture.nas.put("A/IMG_1.JPG", Data(repeating: 7, count: 1_001))

        try await fixture.runner.run("R1")

        #expect(fixture.nas.files["C/IMG_1.JPG"] == nil)
        #expect(try fixture.items().map(\.status) == [.failed, .copied])
        #expect(try fixture.items().first?.failure?.reason == .changedOnServer)
    }

    /// A lost connection stops the run, paused, with what is done kept.
    @Test func lostConnectionPauses() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        fixture.nas.dropConnectionOnDownload = 2

        await #expect(throws: RemoteFileError.connectionLost) { try await fixture.runner.run("R1") }

        #expect(try fixture.store.run(id: "R1")?.state == .paused)
        #expect(try fixture.items().map(\.status) == [.copied, .pending, .pending])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
    }

    /// No room on this Mac: stopped before the download, paused.
    @Test func noRoomStops() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        var runner = fixture.runner
        runner.freeBytes = { 100 }

        await #expect(throws: CommonPhotosRunner.Stop.noRoom) { try await runner.run("R1") }

        #expect(fixture.nas.downloadCount == 0)
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
        #expect(try fixture.items().map(\.status) == [.pending])
    }

    /// AC-126: the destination holds `IMG_1.JPG` with the same bytes and
    /// `IMG_2.JPG` with others — IMG_1 Skipped (already there), IMG_2 lands as
    /// `IMG_2 (2).JPG`; nothing written over.
    @Test func nameClashRules() async throws {
        var fixture = try Fixture(count: 2)
        try await fixture.start()
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)
        let other = Data(repeating: 5, count: 1_002)
        fixture.nas.put("C/img_2.jpg", other)
        fixture.photos = [:]

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.skipped, .copied])
        #expect(items[0].failure?.reason == .alreadyThere)
        #expect(items[1].destinationPath == "C/IMG_2 (2).JPG")
        #expect(fixture.nas.files["C/img_2.jpg"] == other)
        #expect(fixture.nas.files["C/IMG_2 (2).JPG"]?.count == 1_002)
        #expect(fixture.nas.downloadCount == 1)
    }

    /// Two different photos of one name in one run: the second takes the
    /// next free name, part file included.
    @Test func sameNameTwiceInOneRun() async throws {
        let fixture = try Fixture(count: 2, layout: { ("\($0)/IMG.JPG", "\($0)/IMG.JPG") })
        try await fixture.start()

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.destinationPath) == ["C/IMG.JPG", "C/IMG (2).JPG"])
        #expect(fixture.nas.files["C/IMG.JPG"] == fixture.photos["1/IMG.JPG"])
        #expect(fixture.nas.files["C/IMG (2).JPG"] == fixture.photos["2/IMG.JPG"])
    }

    /// A source that cannot be read fails that photo; the run goes on.
    @Test func unreadableSourceFailsOnePhoto() async throws {
        let fixture = try Fixture(count: 3)
        try await fixture.start()
        fixture.nas.refuseDownload = (2, .permissionDenied("A/IMG_2.JPG"))

        try await fixture.runner.run("R1")

        let items = try fixture.items()
        #expect(items.map(\.status) == [.copied, .failed, .copied])
        #expect(items[1].failure?.reason == .serverError)
    }

    /// Cancel mid-copy: the run pauses, the photo goes back to pending, no
    /// part is left, nothing is called failed.
    @Test func cancelLeavesNoPart() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        let runner = fixture.runner
        let task = Task { try await runner.run("R1") }
        fixture.nas.onUpload = { number in if number == 2 { task.cancel() } }

        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(try fixture.items().map(\.status) == [.copied, .pending])
        #expect(!fixture.nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })
        #expect(try fixture.store.run(id: "R1")?.state == .paused)
    }

    /// A photo a stopped run left mid-copy that is already in place with the
    /// scanned bytes is Copied without another transfer.
    @Test func copyingFoundInPlace() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        var item = try #require(try fixture.items().first)
        item.status = .copying
        item.destinationPath = "C/IMG_1.JPG"
        item.partPath = "C/IMG_1.JPG.shotdex-part"
        try fixture.store.update(item)
        fixture.nas.put("C/IMG_1.JPG", fixture.photos["IMG_1.JPG"]!)

        try await fixture.runner.run("R1")

        #expect(try fixture.items().map(\.status) == [.copied])
        #expect(fixture.nas.downloadCount == 0)
    }

    /// Progress moves through the steps of each photo and ends full.
    @Test func progressEndsFull() async throws {
        let fixture = try Fixture(count: 2)
        try await fixture.start()
        let reports = OSAllocatedUnfairLock(initialState: [CommonPhotosRunner.Progress]())

        try await fixture.runner.run("R1", progress: { report in reports.withLock { $0.append(report) } })

        let all = reports.withLock { $0 }
        let last = try #require(all.last)
        #expect(last.doneCount == 2)
        #expect(last.doneBytes == last.totalBytes)
        #expect(all.map(\.doneBytes) == all.map(\.doneBytes).sorted())
        let steps = all.compactMap(\.currentStep).reduce(into: [CommonPhotosRunner.Progress.Step]()) { if $0.last != $1 { $0.append($1) } }
        #expect(steps == [.downloading, .uploading, .readingBack, .downloading, .uploading, .readingBack])
    }

    /// A stopped run is not resumed.
    @Test func stoppedRunIsNotResumed() async throws {
        let fixture = try Fixture(count: 1)
        try await fixture.start()
        try fixture.store.markState(.stopped, runId: "R1")

        await #expect(throws: CommonPhotosRunner.Stop.notResumable) { try await fixture.runner.run("R1") }
    }
}
