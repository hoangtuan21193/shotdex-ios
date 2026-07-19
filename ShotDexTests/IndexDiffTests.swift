import Photos
import Testing
@testable import ShotDex

/// Matrix for the pure incremental-diff decision (`IndexPipeline.needsReindex`).
struct IndexDiffTests {

    private func state(_ status: ExifStatus, modified: Int? = 100) -> IndexedAssetState {
        IndexedAssetState(modificationDate: modified, exifStatus: status.rawValue)
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

    @Test func unrecognizedStatusRetried() {
        let bogus = IndexedAssetState(modificationDate: 100, exifStatus: "garbage")
        #expect(IndexPipeline.needsReindex(existing: bogus, currentModificationDate: 100, allowNetworkRetry: false))
    }

    @Test func screenshotsSkipExifRead() {
        #expect(IndexPipeline.shouldSkipExifRead(mediaSubtypes: .photoScreenshot))
        #expect(IndexPipeline.shouldSkipExifRead(mediaSubtypes: [.photoScreenshot, .photoHDR]))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaSubtypes: []))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaSubtypes: .photoHDR))
        #expect(!IndexPipeline.shouldSkipExifRead(mediaSubtypes: .photoLive))
    }
}
