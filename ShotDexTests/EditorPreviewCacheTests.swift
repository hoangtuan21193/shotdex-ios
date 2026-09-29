import Foundation
import Testing
import UIKit
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.09b AC-1…AC-4: a multi-photo run preloads every photo's
/// full-quality preview in the background and keeps it on disk, so going back
/// to a photo shows it at once instead of "Loading full-quality preview…".
@MainActor
struct EditorPreviewCacheTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotDexPhoto-PreviewsTest-\(UUID().uuidString)", isDirectory: true)
    }

    /// A flat-colour frame. No photos in tests: nothing here can show a face.
    private func image(width: Int = 240, height: Int = 160, gray: CGFloat = 0.5) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: gray, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func edited(exposure: Double) -> PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = exposure
        return recipe
    }

    // MARK: Order

    /// AC-1. The photo on screen first, then outward one step at a time,
    /// next before previous — the direction a filmstrip walk goes.
    @Test func preloadOrderWalksOutwardFromTheCurrentPhoto() {
        #expect(EditorPreloadOrder.indices(count: 7, around: 3) == [3, 4, 2, 5, 1, 6, 0])
        #expect(EditorPreloadOrder.indices(count: 5, around: 0) == [0, 1, 2, 3, 4])
        #expect(EditorPreloadOrder.indices(count: 5, around: 4) == [4, 3, 2, 1, 0])
        #expect(EditorPreloadOrder.indices(count: 1, around: 0) == [0])
        #expect(EditorPreloadOrder.indices(count: 0, around: 0).isEmpty)
        #expect(EditorPreloadOrder.indices(count: 3, around: 9) == [2, 1, 0], "an index past the end clamps")
    }

    /// Every photo exactly once, whatever the start.
    @Test func preloadOrderCoversEveryPhotoOnce() {
        for count in 1...12 {
            for start in 0..<count {
                let order = EditorPreloadOrder.indices(count: count, around: start)
                #expect(order.sorted() == Array(0..<count))
            }
        }
    }

    // MARK: Fingerprint

    @Test func fingerprintFollowsTheRecipe() {
        let a = edited(exposure: 0.4)
        let b = edited(exposure: 0.4)
        let c = edited(exposure: 0.5)
        #expect(EditorPreviewFingerprint.of(a) == EditorPreviewFingerprint.of(b))
        #expect(EditorPreviewFingerprint.of(a) != EditorPreviewFingerprint.of(c))
        #expect(EditorPreviewFingerprint.of(.identity) != EditorPreviewFingerprint.of(a))
    }

    // MARK: Index

    /// AC-3. A cached preview is a hit only for the recipe it was drawn with:
    /// with no draft, that is the photo's saved recipe; with a draft, the
    /// draft. An edit since is a stale placeholder, not a hit, and a photo
    /// changed in the library since is nothing at all.
    @Test func hitOnlyWhenTheFingerprintMatches() {
        var index = EditorPreviewIndex()
        let baseline = EditorPreviewFingerprint.of(.identity)
        let draft = EditorPreviewFingerprint.of(edited(exposure: 0.3))
        _ = index.recordEdited(assetID: "a", stamp: 10, baselineFingerprint: baseline, fingerprint: baseline, file: "a1")

        #expect(index.editedLookup(assetID: "a", stamp: 10, draftFingerprint: nil) == .hit(file: "a1", fingerprint: baseline))
        #expect(index.editedLookup(assetID: "a", stamp: 10, draftFingerprint: draft) == .stale(file: "a1"))
        #expect(index.editedLookup(assetID: "a", stamp: 11, draftFingerprint: nil) == .miss)
        #expect(index.editedLookup(assetID: "b", stamp: 10, draftFingerprint: nil) == .miss)

        _ = index.recordEdited(assetID: "a", stamp: 10, baselineFingerprint: baseline, fingerprint: draft, file: "a2")
        #expect(index.editedLookup(assetID: "a", stamp: 10, draftFingerprint: draft) == .hit(file: "a2", fingerprint: draft))
        #expect(index.editedLookup(assetID: "a", stamp: 10, draftFingerprint: nil) == .stale(file: "a2"),
                "the draft went away: the saved recipe is what the photo shows now")
    }

    /// Replacing an entry hands back the file it no longer needs — unless the
    /// other half of the entry still points at it.
    @Test func replacedFilesAreHandedBackForDeletion() {
        var index = EditorPreviewIndex()
        let baseline = EditorPreviewFingerprint.of(.identity)
        #expect(index.recordOriginal(assetID: "a", stamp: 1, optionID: "raw", file: "shared").isEmpty)
        #expect(index.recordEdited(assetID: "a", stamp: 1, baselineFingerprint: baseline, fingerprint: baseline, file: "shared").isEmpty)
        #expect(index.recordEdited(assetID: "a", stamp: 1, baselineFingerprint: baseline, fingerprint: "x", file: "e2").isEmpty,
                "the original still uses the shared file")
        #expect(index.recordEdited(assetID: "a", stamp: 1, baselineFingerprint: baseline, fingerprint: "y", file: "e3") == ["e2"])
        #expect(index.recordOriginal(assetID: "a", stamp: 1, optionID: "jpeg", file: "o2") == ["shared"])
        #expect(index.originalFile(assetID: "a", stamp: 1, optionID: "jpeg") == "o2")
        #expect(index.originalFile(assetID: "a", stamp: 1, optionID: "raw") == nil)
        #expect(Set(index.remove(assetID: "a")) == ["e3", "o2"])
        #expect(index.files.isEmpty)
    }

    /// A photo changed in the library since it was cached starts over: its
    /// old files are handed back rather than kept beside the new ones.
    @Test func aNewModificationStampReplacesTheWholeEntry() {
        var index = EditorPreviewIndex()
        let baseline = EditorPreviewFingerprint.of(.identity)
        _ = index.recordOriginal(assetID: "a", stamp: 1, optionID: "o", file: "old-o")
        _ = index.recordEdited(assetID: "a", stamp: 1, baselineFingerprint: baseline, fingerprint: baseline, file: "old-e")
        let obsolete = index.recordEdited(assetID: "a", stamp: 2, baselineFingerprint: baseline, fingerprint: baseline, file: "new-e")
        #expect(Set(obsolete) == ["old-o", "old-e"])
        #expect(index.originalFile(assetID: "a", stamp: 2, optionID: "o") == nil)
    }

    /// AC-1. The preloader skips a photo once it has both halves for the
    /// recipe that photo will open with — and once it has tried a recipe it
    /// cannot draw on its own (text tokens), it does not try that one again.
    @Test func needsPreloadUntilBothHalvesAreThere() {
        var index = EditorPreviewIndex()
        let baseline = EditorPreviewFingerprint.of(.identity)
        #expect(index.needsPreload(assetID: "a", stamp: 1, draftFingerprint: nil))
        _ = index.recordOriginal(assetID: "a", stamp: 1, optionID: "o", file: "o")
        index.recordBaseline(assetID: "a", stamp: 1, fingerprint: baseline)
        #expect(index.needsPreload(assetID: "a", stamp: 1, draftFingerprint: nil), "no edited half yet")
        _ = index.recordEdited(assetID: "a", stamp: 1, baselineFingerprint: baseline, fingerprint: baseline, file: "o")
        #expect(!index.needsPreload(assetID: "a", stamp: 1, draftFingerprint: nil))
        #expect(index.needsPreload(assetID: "a", stamp: 1, draftFingerprint: "synced"), "a draft arrived: draw it")
        index.markSkipped(assetID: "a", stamp: 1, fingerprint: "synced")
        #expect(!index.needsPreload(assetID: "a", stamp: 1, draftFingerprint: "synced"))
    }

    // MARK: Memory

    @Test func recentListKeepsOnlyTheNewest() {
        var list = EditorRecentList<String>(capacity: 2)
        #expect(list.touch("a").isEmpty)
        #expect(list.touch("b").isEmpty)
        #expect(list.touch("a").isEmpty, "touching refreshes, it does not add")
        #expect(list.touch("c") == ["b"])
        #expect(list.keys == ["a", "c"])
        list.remove("a")
        #expect(list.keys == ["c"])
    }

    // MARK: Cache

    /// AC-2. Stored once, a preview comes back from memory in the same frame
    /// — the tap back to a photo does not wait on anything.
    @Test func storedPreviewComesBackFromMemory() async throws {
        let cache = EditorPreviewCache(directory: makeDirectory(), memoryCapacity: 3)
        defer { cache.clear() }
        let recipe = edited(exposure: 0.2)
        let picture = image()
        await cache.store(assetID: "a", stamp: 5, baseline: .identity, edited: (picture, recipe), original: nil)

        let hit = try #require(cache.memoryEditedPreview(assetID: "a", stamp: 5, draft: recipe))
        #expect(hit.isCurrent)
        #expect(hit.image === picture)
        #expect(cache.memoryEditedPreview(assetID: "a", stamp: 5, draft: nil)?.isCurrent == false,
                "without the draft the photo opens on its saved recipe, which this is not")
    }

    /// AC-2. Pushed out of memory by newer photos, a preview is still read
    /// back from disk at full size — the disk is the cache, RAM only the
    /// last few.
    @Test func evictedPreviewIsReadBackFromDisk() async throws {
        let cache = EditorPreviewCache(directory: makeDirectory(), memoryCapacity: 1)
        defer { cache.clear() }
        await cache.store(assetID: "a", stamp: 1, baseline: .identity, edited: (image(gray: 0.2), .identity), original: nil)
        await cache.store(assetID: "b", stamp: 1, baseline: .identity, edited: (image(gray: 0.8), .identity), original: nil)

        #expect(cache.memoryEditedPreview(assetID: "a", stamp: 1, draft: nil) == nil, "only one photo stays in memory")
        let fromDisk = try #require(await cache.editedPreview(assetID: "a", stamp: 1, draft: nil))
        #expect(fromDisk.isCurrent)
        #expect(fromDisk.image.cgImage?.width == 240)
        #expect(fromDisk.image.cgImage?.height == 160)
    }

    /// An unedited photo's edited preview *is* its original: one file, one
    /// decode, both halves.
    @Test func unchangedPhotoSharesOneFile() async throws {
        let directory = makeDirectory()
        let cache = EditorPreviewCache(directory: directory, memoryCapacity: 3)
        defer { cache.clear() }
        let picture = image()
        await cache.store(assetID: "a", stamp: 1, baseline: .identity, edited: (picture, .identity), original: (picture, "o"))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
        let original = try #require(await cache.originalPreview(assetID: "a", stamp: 1, optionID: "o"))
        #expect(original === picture)
        #expect(!cache.needsPreload(assetID: "a", stamp: 1, draft: nil))
    }

    /// AC-4. Closing the editor deletes every file, and a write still in
    /// flight when it closed does not bring an entry back.
    @Test func clearRemovesTheDirectory() async throws {
        let directory = makeDirectory()
        let cache = EditorPreviewCache(directory: directory, memoryCapacity: 3)
        await cache.store(assetID: "a", stamp: 1, baseline: .identity, edited: (image(), .identity), original: nil)
        #expect(FileManager.default.fileExists(atPath: directory.path))

        cache.clear()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await cache.editedPreview(assetID: "a", stamp: 1, draft: nil) == nil)
    }

    /// A saved photo's cached preview is dropped: what the library now holds
    /// is the thing to show.
    @Test func invalidateDropsThePhoto() async throws {
        let cache = EditorPreviewCache(directory: makeDirectory(), memoryCapacity: 3)
        defer { cache.clear() }
        await cache.store(assetID: "a", stamp: 1, baseline: .identity, edited: (image(), .identity), original: nil)
        cache.invalidate(assetID: "a")
        #expect(cache.memoryEditedPreview(assetID: "a", stamp: 1, draft: nil) == nil)
        #expect(await cache.editedPreview(assetID: "a", stamp: 1, draft: nil) == nil)
        #expect(cache.needsPreload(assetID: "a", stamp: 1, draft: nil))
    }

    /// Memory warning: RAM goes, disk stays.
    @Test func memoryWarningKeepsTheDisk() async throws {
        let cache = EditorPreviewCache(directory: makeDirectory(), memoryCapacity: 3)
        defer { cache.clear() }
        await cache.store(assetID: "a", stamp: 1, baseline: .identity, edited: (image(), .identity), original: nil)
        cache.handleMemoryWarning()
        #expect(cache.memoryEditedPreview(assetID: "a", stamp: 1, draft: nil) == nil)
        #expect(await cache.editedPreview(assetID: "a", stamp: 1, draft: nil)?.isCurrent == true)
    }
}
