import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-02.06 AC-9, AC-10, AC-16: Resize prepares every original before it
/// creates a copy or deletes an original.
@MainActor
@Suite(.serialized) struct CompressionPreparationTests {
    /// What Resize did to the "library".
    final class Library {
        var created: [String] = []
        var compressedFrom: [String: URL?] = [:]
        var deleted: [String] = []
        var removed: [String] = []
    }

    func resize(_ count: Int, script: String) -> (CompressionController, Library, FakeOriginalFetcher) {
        let library = Library()
        let photos = (1...count).map { OriginalItem.test(String(format: "%02d", $0)) }
        let fake = FakeOriginalFetcher(script: .init(script), base: FixtureOriginalFetcher())
        let operations = ResizeOperations(
            compress: { photo, prepared, _ in
                library.created.append("copy-\(photo.id)")
                library.compressedFrom[photo.id] = prepared
                return PhotoSaveResult(assetID: "copy-\(photo.id)", format: .jpeg, fellBackToJPEG: false)
            },
            deleteOriginals: { library.deleted += $0 },
            removeCreated: { library.removed += $0 }
        )
        let controller = CompressionController(photos: photos, operations: operations, fetcher: fake)
        controller.deleteOriginals = true
        return (controller, library, fake)
    }

    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() { try await Task.sleep(for: .milliseconds(40)) }
        #expect(condition())
    }

    /// AC-16. Five photos only in iCloud, Delete Originals on, the fifth
    /// fails: when the message shows, no copy exists, nothing is deleted,
    /// and the four that came down are on disk.
    @Test func failureAlertBeforeAnyWrite() async throws {
        let (controller, library, _) = resize(5, script: "cloud=all,seconds=0.3,fail=5")
        controller.startExport()
        try await until { controller.preparation?.state.phase == .failed }
        let preparation = try #require(controller.preparation)
        #expect(preparation.state.failureTitle == "1 of 5 photos couldn't be downloaded from iCloud.")
        #expect(library.created.isEmpty)
        #expect(library.deleted.isEmpty)
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: preparation.folder.path)
        #expect(onDisk.count == 4)
        preparation.choose(.cancel)
        try await until { !controller.isExporting }
        #expect(library.created.isEmpty)
        #expect(library.deleted.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: preparation.folder.path))
    }

    /// AC-9. Five photos, two only in iCloud and not coming down, Delete
    /// Originals on, Continue with 3: three copies, exactly those three
    /// originals deleted; the two stay, with no copy, named in the summary.
    @Test func continueWithThreeDeletesOnlyThree() async throws {
        let (controller, library, _) = resize(5, script: "cloud=2,seconds=0.2,fail=1+2")
        controller.startExport()
        try await until { controller.preparation?.state.phase == .failed }
        let failed = Set(try #require(controller.preparation).state.downloads.filter(\.hasFailed).map(\.id))
        #expect(failed.count == 2)
        #expect(controller.preparation?.state.continueCount == 3)
        controller.preparation?.choose(.continueWithout)
        try await until { controller.didFinish }
        let kept = Set(controller.photos.map(\.id)).subtracting(failed)
        #expect(library.created.count == 3)
        #expect(Set(library.deleted) == kept)
        #expect(Set(library.deleted).isDisjoint(with: failed))
        #expect(Set(library.created) == Set(kept.map { "copy-\($0)" }))
        #expect(controller.failures.count == 2)
        #expect(controller.deletedOriginalCount == 3)
    }

    /// AC-10. Twenty photos only in iCloud: the processing modal's line is
    /// "Downloading from iCloud · k of 20 · N%" before any photo is
    /// processed.
    @Test func progressLineInProcessingModal() async throws {
        let (controller, library, _) = resize(20, script: "cloud=all,seconds=1")
        controller.startExport()
        try await until { controller.preparation?.state.phase == .downloading && (controller.preparation?.state.percent ?? 0) > 0 }
        #expect(controller.isPreparing)
        let line = try #require(controller.preparation?.state.progressLine)
        #expect(line.wholeMatch(of: /Downloading from iCloud · \d+ of 20 · \d+%/) != nil, "\(line)")
        #expect(library.created.isEmpty)
        controller.cancelExport()
        try await until { !controller.isExporting }
    }

    /// AC-10. Cancel while the fourth original downloads: nothing created,
    /// nothing deleted, the modal gone within a second, back on the form.
    @Test func cancelDuringDownloadCreatesNothing() async throws {
        let (controller, library, fake) = resize(20, script: "cloud=all,seconds=30")
        controller.startExport()
        try await until { fake.downloadCount == 4 }
        let pressed = ContinuousClock.now
        controller.cancelExport()
        try await until { !controller.isExporting }
        #expect(ContinuousClock.now - pressed < .seconds(1))
        #expect(library.created.isEmpty)
        #expect(library.deleted.isEmpty)
        #expect(library.removed.isEmpty)
        #expect(fake.cancelledCount == 4)
        #expect(!controller.didFinish)
    }

    /// The prepared original is what the copy is made from: nothing is
    /// fetched again mid-batch.
    @Test func copiesReadThePreparedOriginals() async throws {
        let (controller, library, _) = resize(3, script: "cloud=2,seconds=0.1")
        controller.startExport()
        try await until { controller.didFinish }
        #expect(library.compressedFrom.values.compactMap { $0 }.count == 2)
        #expect(library.compressedFrom.count == 3)
    }
}
