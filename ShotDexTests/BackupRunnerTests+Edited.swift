import Foundation
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// AC-24: with Include Edited Versions on, an edited photo puts its
    /// original and `_edited` render side by side; editing it again adds
    /// `_edited (2)` and the original is not copied again.
    @Test func editedVersionAddedBesideOriginal() async throws {
        var f = try BackupFixture(photos: 0)
        f.job.settings.includesEditedVersions = true
        try f.store.update(f.job)
        let (first, d1) = BackupFixture.item(5, name: "IMG_5.HEIC", seed: 5, edited: "IMG_5_edited.JPG", editedBytes: 3_000)
        f.source.replace([first])
        f.contents = d1

        let run1 = await f.runner().run()
        #expect(run1.stop == .finished)
        #expect(Set(f.remoteFiles.keys) == ["Backup/iPhone/IMG_5.HEIC", "Backup/iPhone/IMG_5_edited.JPG"])

        let (again, d2) = BackupFixture.item(5, name: "IMG_5.HEIC", seed: 6, edited: "IMG_5_edited.JPG", editedBytes: 3_500)
        // The original keeps its bytes and stamp; only the render changed.
        let original = first.files[0]
        let reEdited = BackupSourceItem(itemKey: again.itemKey, date: again.date, isVideo: false, album: nil, files: [original, again.files[1]])
        f.source.replace([reEdited])
        f.contents = d1.merging(d2.filter { $0.key.hasSuffix("FullSizeRender.JPG") }) { $1 }
        let uploadsBefore = f.client.uploadCount

        let run2 = await f.runner().run()
        #expect(run2.progress.total == 1)
        #expect(f.client.uploadCount == uploadsBefore + 1)
        #expect(f.remoteFiles["Backup/iPhone/IMG_5_edited (2).JPG"] != nil)
        #expect(f.remoteFiles.count == 3)
    }

    /// Off by default: the render is never copied.
    @Test func editedVersionSkippedWhenOff() async throws {
        var f = try BackupFixture(photos: 0)
        let (item, data) = BackupFixture.item(5, name: "IMG_5.HEIC", edited: "IMG_5_edited.JPG")
        f.source.replace([item])
        f.contents = data
        _ = await f.runner().run()
        #expect(Set(f.remoteFiles.keys) == ["Backup/iPhone/IMG_5.HEIC"])
    }
}
