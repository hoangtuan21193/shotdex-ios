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
            compress: { photo, prepared in
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
