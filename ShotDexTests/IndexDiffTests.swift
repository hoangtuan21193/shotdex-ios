import Photos
import Testing
@testable import ShotDex

/// Matrix for the pure incremental-diff decision (`IndexPipeline.needsReindex`).
struct IndexDiffTests {

    private func state(
        _ status: ExifStatus,
        modified: Int? = 100,
        version: Int = PhotoMetadata.currentIndexerVersion
    ) -> IndexedAssetState {
        IndexedAssetState(modificationDate: modified, exifStatus: status.rawValue, indexerVersion: version)
    }

    @Test func newAssetIsIndexed() {
        #expect(IndexPipeline.needsReindex(existing: nil, currentModificationDate: 100, allowNetworkRetry: false))
    }

    @Test func unchangedCompleteRowIsSkipped() {
        #expect(!IndexPipeline.needsReindex(existing: state(.indexed), currentModificationDate: 100, allowNetworkRetry: true))
        #expect(!IndexPipeline.needsReindex(existing: state(.noExif), currentModificationDate: 100, allowNetworkRetry: true))
    }

    @Test func modifiedAssetIsReindexed() {
        #expect(IndexPipeline.needsReindex(existing: state(.indexed), currentModificationDate: 200, allowNetworkRetry: false))
        #expect(IndexPipeline.needsReindex(existing: state(.indexed, modified: nil), currentModificationDate: 100, allowNetworkRetry: false))
        #expect(IndexPipeline.needsReindex(existing: state(.indexed), currentModificationDate: nil, allowNetworkRetry: false))
    }

    @Test func pendingICloudRetriedOnlyWhenNetworkAllowed() {
        #expect(IndexPipeline.needsReindex(existing: state(.pendingICloud), currentModificationDate: 100, allowNetworkRetry: true))
        #expect(!IndexPipeline.needsReindex(existing: state(.pendingICloud), currentModificationDate: 100, allowNetworkRetry: false))
    }

    @Test func errorAlwaysRetried() {
        #expect(IndexPipeline.needsReindex(existing: state(.error), currentModificationDate: 100, allowNetworkRetry: false))
    }

    @Test func pendingReadAlwaysRetried() {
        #expect(IndexPipeline.needsReindex(existing: state(.pendingRead), currentModificationDate: 100, allowNetworkRetry: false))
        #expect(IndexPipeline.needsReindex(existing: state(.pendingRead), currentModificationDate: 100, allowNetworkRetry: true))
    }

    @Test func staleIndexerVersionReindexed() {
        // Complete, unchanged rows written by an older build are re-read so
        // fields added since backfill; current-version rows stay skipped.
        #expect(IndexPipeline.needsReindex(
            existing: state(.indexed, version: 0), currentModificationDate: 100, allowNetworkRetry: false
        ))
        #expect(IndexPipeline.needsReindex(
            existing: state(.noExif, version: 1), currentModificationDate: 100, allowNetworkRetry: false
        ))
        #expect(!IndexPipeline.needsReindex(
            existing: state(.indexed, version: 2), currentModificationDate: 100,
            allowNetworkRetry: false, currentIndexerVersion: 2
        ))
    }

    @Test func unrecognizedStatusRetried() {
        let bogus = IndexedAssetState(modificationDate: 100, exifStatus: "garbage")
        #expect(IndexPipeline.needsReindex(existing: bogus, currentModificationDate: 100, allowNetworkRetry: false))
    }

    @Test func screenshotsSkipExifRead() {
        let image = PHAssetMediaType.image.rawValue
        #expect(IndexPipeline.shouldSkipExifRead(mediaType: image, mediaSubtypes: .photoScreenshot))
        #expect(IndexPipeline.shouldSkipExifRead(mediaType: image, mediaSubtypes: [.photoScreenshot, .photoHDR]))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaType: image, mediaSubtypes: []))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaType: image, mediaSubtypes: .photoHDR))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaType: image, mediaSubtypes: .photoLive))
    }

    @Test func videosSkipExifRead() {
        let video = PHAssetMediaType.video.rawValue
        // A video never carries readable photo EXIF — skip it regardless of subtype.
        #expect(IndexPipeline.shouldSkipExifRead(mediaType: video, mediaSubtypes: []))
        #expect(IndexPipeline.shouldSkipExifRead(mediaType: video, mediaSubtypes: .videoHighFrameRate))
        // A plain photo is still read.
        #expect(!IndexPipeline.shouldSkipExifRead(mediaType: PHAssetMediaType.image.rawValue, mediaSubtypes: []))
    }

    /// FS-01.12 AC-11 on the full walk: a skipped row whose favorite or
    /// Photos rating no longer matches the asset is a drift, written without
    /// a read; a row the query loaded no facts for never drifts.
    @Test func factsDriftWithoutEdit() {
        var stored = state(.indexed)
        stored.isFavorite = false
        stored.rating = 2

        #expect(!AssetFacts.drifted(stored: stored, current: AssetFacts(isFavorite: false, rating: 2)))
        #expect(AssetFacts.drifted(stored: stored, current: AssetFacts(isFavorite: true, rating: 2)))
        #expect(AssetFacts.drifted(stored: stored, current: AssetFacts(isFavorite: false, rating: 4)))
        // Below iOS 27 the asset has no rating to disagree with.
        #expect(!AssetFacts.drifted(stored: stored, current: AssetFacts(isFavorite: false, rating: nil)))
        // A NULL column on iOS 27 is filled.
        stored.rating = nil
        #expect(AssetFacts.drifted(stored: stored, current: AssetFacts(isFavorite: false, rating: 0)))
        #expect(!AssetFacts.drifted(stored: nil, current: AssetFacts(isFavorite: true, rating: 5)))
        #expect(!AssetFacts.drifted(stored: state(.indexed), current: AssetFacts(isFavorite: true, rating: nil)))
    }
}
