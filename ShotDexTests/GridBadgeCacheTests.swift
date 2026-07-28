import Foundation
import Testing
@testable import ShotDex

/// Decision matrix + storage of the lazy-badge cache: final statuses cache,
/// pending ones retry, a reload wipes everything.
@MainActor
struct GridBadgeCacheTests {

    private func makeRow(
        assetId: String = "a1",
        iso: Int? = 200,
        status: ExifStatus
    ) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: 1_700_000_000,
            modificationDate: 1_700_000_000,
            mediaType: 1,
            cameraManufacturer: nil,
            cameraModel: nil,
            normalizedCameraModel: nil,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: nil,
            iso: iso,
            aperture: 2.8,
            shutterSpeedSeconds: 0.005,
            shutterSpeedDisplay: "1/200",
            focalLength: 50,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: 75,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: nil,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: 1_700_000_000,
            exifStatus: status.rawValue
        )
    }

    // MARK: Decision matrix

    @Test func indexedRowIsFinalAndCarriesFields() {
        let entry = GridBadgeCache.entry(for: makeRow(status: .indexed))
        guard case .badge(let item)? = entry else {
            Issue.record("expected .badge, got \(String(describing: entry))")
            return
        }
        #expect(item.assetId == "a1")
        #expect(item.iso == 200)
        #expect(item.aperture == 2.8)
        #expect(item.shutterSpeedDisplay == "1/200")
        #expect(item.focalLength == 50)
        #expect(item.equivalentFocalLength == 75)
    }

    @Test func noExifRowIsFinalAndStillCarriesFileType() {
        let entry = GridBadgeCache.entry(for: makeRow(iso: nil, status: .noExif))
        guard case .badge(let item)? = entry else {
            Issue.record("expected .badge, got \(String(describing: entry))")
            return
        }
        #expect(item.mediaType == 1)
    }

    @Test func missingRowIsFinalNegative() {
        // A deleted asset no longer has a row.
        #expect(GridBadgeCache.entry(for: nil) == .noBadge)
    }

    @Test func nonFinalStatusesAreNotCached() {
        #expect(GridBadgeCache.entry(for: makeRow(iso: nil, status: .pendingRead)) == nil)
        #expect(GridBadgeCache.entry(for: makeRow(iso: nil, status: .pendingICloud)) == nil)
        #expect(GridBadgeCache.entry(for: makeRow(iso: nil, status: .error)) == nil)
    }

    // MARK: Storage

    @Test func recordCachesFinalResults() {
        let cache = GridBadgeCache()
        let item = cache.record(makeRow(status: .indexed), assetId: "a1")
        #expect(item?.iso == 200)
        guard case .badge(let cached)? = cache.cachedEntry(for: "a1") else {
            Issue.record("expected cached .badge")
            return
        }
        #expect(cached.iso == 200)

        cache.record(nil, assetId: "a2")
        #expect(cache.cachedEntry(for: "a2") == .noBadge)
    }

    @Test func recordSkipsPendingSoNextDisplayRetries() {
        let cache = GridBadgeCache()
        let item = cache.record(makeRow(iso: nil, status: .pendingRead), assetId: "a1")
        #expect(item == nil)
        #expect(cache.cachedEntry(for: "a1") == nil)

        // The row upgraded — the retry now caches the badge.
        let upgraded = cache.record(makeRow(status: .indexed), assetId: "a1")
        #expect(upgraded?.iso == 200)
        #expect(cache.cachedEntry(for: "a1") != nil)
    }

    @Test func removeAllInvalidatesEntries() {
        let cache = GridBadgeCache()
        cache.record(makeRow(status: .indexed), assetId: "a1")
        cache.record(nil, assetId: "a2")
        cache.removeAll()
        #expect(cache.cachedEntry(for: "a1") == nil)
        #expect(cache.cachedEntry(for: "a2") == nil)
    }

    @Test func fileTypeBadgeNormalizesCommonPhotoAndVideoFormats() {
        func item(filename: String?, mediaType: Int = 1) -> LibraryGridItem {
            LibraryGridItem(
                assetId: "a1",
                creationDate: nil,
                mediaType: mediaType,
                originalFilename: filename,
                iso: nil,
                aperture: nil,
                shutterSpeedDisplay: nil,
                focalLength: nil,
                equivalentFocalLength: nil,
                width: nil,
                height: nil,
                fileSize: nil
            )
        }

        #expect(item(filename: "IMG_0001.CR3").fileTypeBadgeText == "RAW")
        #expect(item(filename: "IMG_0002.jpeg").fileTypeBadgeText == "JPG")
        #expect(item(filename: "IMG_0003.heif").fileTypeBadgeText == "HEIC")
        #expect(item(filename: "clip.mov", mediaType: 2).fileTypeBadgeText == "MOV")
        #expect(item(filename: nil, mediaType: 2).fileTypeBadgeText == "VIDEO")
        #expect(item(filename: nil).fileTypeBadgeText == "PHOTO")
    }
}
