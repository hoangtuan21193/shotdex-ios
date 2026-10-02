import Foundation
import Photos
import Testing

/// FS-01.12 plan M1 — a measurement, not a feature test. On iOS 27 it writes
/// a star rating onto 1, 300 and 2,000 library assets in **one**
/// `performChanges` each and prints what PhotoKit did: how long the block
/// took, whether `modificationDate` moved, whether the ids came back in
/// `fetchPersistentChanges(…).updatedLocalIdentifiers`, whether the change
/// counted as structural for the all-photos fetch (the rule
/// `PhotoLibraryService.isStructural` applies), whether a video takes a
/// rating, and whether `PHFetchOptions` filters on `rating`. Every rating it
/// writes is set back to unset before it returns.
///
/// Skips itself below iOS 27 and without full photo access, so it never runs
/// in `Tools/gate` on the 26.5 simulator. Run it on purpose:
/// `-only-testing:ShotDexTests/PhotoPropertyProbeTests` with an iOS 27
/// destination. Shared with the FS-02.07 caption/keyword probe (plan M1).
@Suite(.serialized)
struct PhotoPropertyProbeTests {

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("[PhotoPropertyProbe] \(line)\n".utf8))
    }

    private static var canRun: Bool {
        guard #available(iOS 27, *) else { return false }
        return PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    /// Mirrors `PhotoLibraryService.refreshAllPhotos` — the fetch whose change
    /// details decide whether the grid reloads.
    private static func allPhotosFetch() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        return PHAsset.fetchAssets(with: options)
    }

    /// Collects the change notifications that arrive while a block runs.
    private final class ChangeRecorder: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var baseline: PHFetchResult<PHAsset>
        private(set) var structural = false
        private(set) var changedCount = 0
        private(set) var notifications = 0

        init(baseline: PHFetchResult<PHAsset>) { self.baseline = baseline }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            lock.lock(); defer { lock.unlock() }
            notifications += 1
            guard let details = changeInstance.changeDetails(for: baseline) else { return }
            baseline = details.fetchResultAfterChanges
            changedCount += details.changedIndexes?.count ?? 0
            if !details.hasIncrementalChanges
                || details.insertedIndexes?.isEmpty == false
                || details.removedIndexes?.isEmpty == false
                || details.hasMoves {
                structural = true
            }
        }
    }

    @available(iOS 27, *)
    private static func measure(count: Int, from fetch: PHFetchResult<PHAsset>, rating: PHAsset.Rating) async throws {
        let limit = min(count, fetch.count)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, index, stop in
            if asset.mediaType == .image { assets.append(asset) }
            if assets.count == limit { stop.pointee = true }
        }
        let ids = assets.map(\.localIdentifier)
        let datesBefore = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0.modificationDate) })
        let token = PHPhotoLibrary.shared().currentChangeToken

        let recorder = ChangeRecorder(baseline: allPhotosFetch())
        PHPhotoLibrary.shared().register(recorder)
        defer { PHPhotoLibrary.shared().unregisterChangeObserver(recorder) }

        let start = ContinuousClock.now
        var failure: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for asset in assets {
                    PHAssetChangeRequest(for: asset).rating = rating
                }
            }
        } catch {
            failure = "\(error)"
        }
        let elapsed = ContinuousClock.now - start
        try await Task.sleep(for: .seconds(2))

        let after = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var ratedCount = 0
        var dateMoved = 0
        after.enumerateObjects { asset, _, _ in
            if asset.rating == rating { ratedCount += 1 }
            if asset.modificationDate != datesBefore[asset.localIdentifier] ?? nil { dateMoved += 1 }
        }

        var updated = Set<String>()
        var inserted = 0
        var deleted = 0
        if let changes = try? PHPhotoLibrary.shared().fetchPersistentChanges(since: token) {
            for change in changes {
                guard let details = try? change.changeDetails(for: .asset) else { continue }
                updated.formUnion(details.updatedLocalIdentifiers)
                inserted += details.insertedLocalIdentifiers.count
                deleted += details.deletedLocalIdentifiers.count
            }
        }
        let inUpdated = ids.filter(updated.contains).count

        log("""
            count=\(ids.count) rating=\(rating.rawValue) block=\(elapsed) error=\(failure ?? "none") \
            readBack=\(ratedCount)/\(ids.count) modificationDateMoved=\(dateMoved) \
            inUpdatedLocalIdentifiers=\(inUpdated) persistentInserted=\(inserted) persistentDeleted=\(deleted) \
            notifications=\(recorder.notifications) changedIndexes=\(recorder.changedCount) \
            structural=\(recorder.structural)
            """)
        #expect(failure == nil)
    }

    @available(iOS 27, *)
    private static func reset(_ fetch: PHFetchResult<PHAsset>) async throws {
        var rated: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in
            if asset.rating != .unset { rated.append(asset) }
        }
        guard !rated.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in rated { PHAssetChangeRequest(for: asset).rating = .unset }
        }
        log("reset \(rated.count) ratings to unset")
    }

    @Test func ratingWrites() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        let fetch = Self.allPhotosFetch()
        Self.log("library=\(fetch.count)")
        // Anything a previous, interrupted run left behind goes first, so the
        // read-back counts are this run's.
        try await Self.reset(Self.allPhotosFetch())
        for count in [1, 300, 2_000] {
            try await Self.measure(count: count, from: Self.allPhotosFetch(), rating: .three)
        }

        // A second write over already-rated assets: does it count as a
        // change at all when only the value moves?
        try await Self.measure(count: 300, from: Self.allPhotosFetch(), rating: .five)

        // Video.
        let videos = PHAsset.fetchAssets(with: .video, options: nil)
        if let video = videos.firstObject {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest(for: video).rating = .four
                }
                let back = PHAsset.fetchAssets(withLocalIdentifiers: [video.localIdentifier], options: nil).firstObject
                Self.log("video rating write ok, readBack=\(back?.rating.rawValue ?? -1)")
            } catch {
                Self.log("video rating write failed: \(error)")
            }
        } else {
            Self.log("no video in the library")
        }

        // Favorite, for comparison: does toggling the heart move the date?
        if let asset = Self.allPhotosFetch().firstObject {
            let before = asset.modificationDate
            let was = asset.isFavorite
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = !was
            }
            let back = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil).firstObject
            Self.log("favorite toggle modificationDateMoved=\(back?.modificationDate != before)")
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = was
            }
        }

        // Last, because an unsupported key raises an Objective-C exception
        // that ends the process: everything above is already printed.
        Self.log("predicate rating >= 3: trying")
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "rating >= %d", 3)
        let filtered = PHAsset.fetchAssets(with: options)
        Self.log("predicate rating >= 3: supported, count=\(filtered.count)")

        try await Self.reset(Self.allPhotosFetch())
    }
}
