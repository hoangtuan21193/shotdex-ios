import Foundation
import Testing
@testable import ShotDex

struct PerceptualHashStoreTests {

    private func makeRecord(_ id: String, modified: Int? = 1_700_000_000, kind: MediaKind = .photo) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id,
            creationDate: modified,
            modificationDate: modified,
            mediaType: kind.storedValue,
            cameraManufacturer: nil,
            cameraModel: nil,
            normalizedCameraModel: nil,
            normalizedCameraManufacturer: nil,
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: nil,
            iso: nil,
            aperture: nil,
            shutterSpeedSeconds: nil,
            shutterSpeedDisplay: nil,
            focalLength: nil,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: nil,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: 10_000_000,
            latitude: nil,
            longitude: nil,
            isFavorite: true,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func makeStores() throws -> (MetadataStore, PerceptualHashStore) {
        let database = try AppDatabase.makeEmpty()
        return (MetadataStore(database: database), PerceptualHashStore(database: database))
    }

    @Test func pendingSkipsVideosAndUpToDateHashes() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("photo"), makeRecord("hashed"), makeRecord("video", kind: .video)] { try metadata.upsert(record) }
        try hashes.upsert([
            PerceptualHashRecord(assetId: "hashed", hash: PerceptualHash(bits: 5), modificationDate: 1_700_000_000, computedAt: 1),
        ])
        #expect(try hashes.pendingAssetIds(retryingFailed: false) == ["photo"])
    }

    @Test func editedPhotoIsRequeued() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("edited", modified: 1_700_000_500)] { try metadata.upsert(record) }
        try hashes.upsert([
            PerceptualHashRecord(assetId: "edited", hash: PerceptualHash(bits: 5), modificationDate: 1_700_000_000, computedAt: 1),
        ])
        #expect(try hashes.pendingAssetIds(retryingFailed: false) == ["edited"])
    }

    @Test func failedReadIsRetriedOnlyWhenAsked() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("cloudOnly")] { try metadata.upsert(record) }
        try hashes.upsert([
            PerceptualHashRecord(assetId: "cloudOnly", hash: nil, modificationDate: 1_700_000_000, computedAt: 1),
        ])
        #expect(try hashes.pendingAssetIds(retryingFailed: false).isEmpty)
        #expect(try hashes.pendingAssetIds(retryingFailed: true) == ["cloudOnly"])
        #expect(try hashes.hashedPhotos().isEmpty)
    }

    @Test func hashedPhotosJoinMetadataFacts() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("a")] { try metadata.upsert(record) }
        let bits = UInt64.max - 3
        try hashes.upsert([
            PerceptualHashRecord(assetId: "a", hash: PerceptualHash(bits: bits), modificationDate: 1_700_000_000, computedAt: 1),
        ])
        let photos = try hashes.hashedPhotos()
        #expect(photos.count == 1)
        #expect(photos[0].hash.bits == bits)
        #expect(photos[0].width == 6000)
        #expect(photos[0].fileSize == 10_000_000)
        #expect(photos[0].isFavorite)
        #expect(try hashes.coverage() == PerceptualHashCoverage(hashedPhotos: 1, indexedPhotos: 1))
    }

    @Test func pruneRemovesRowsWithoutMetadata() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("kept")] { try metadata.upsert(record) }
        try hashes.upsert([
            PerceptualHashRecord(assetId: "kept", hash: PerceptualHash(bits: 1), modificationDate: 1_700_000_000, computedAt: 1),
            PerceptualHashRecord(assetId: "gone", hash: PerceptualHash(bits: 2), modificationDate: 1_700_000_000, computedAt: 1),
        ])
        #expect(try hashes.pruneOrphans() == 1)
        #expect(try hashes.hashedPhotos().map(\.assetId) == ["kept"])
        try hashes.delete(assetIds: ["kept"])
        #expect(try hashes.hashedPhotos().isEmpty)
    }
}

struct DuplicateGroupCacheTests {

    private func makeRecord(_ id: String, size: Int = 10_000_000) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: 1_700_000_000, modificationDate: 1_700_000_000,
            mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: nil, cameraModel: nil, normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil,
            iso: nil, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil, width: 6000, height: 4000, fileSize: size,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    private func hashed(_ id: String, bits: UInt64, size: Int = 10_000_000) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits), width: 6000, height: 4000, fileSize: size, creationDate: 1_700_000_000, isFavorite: false)
    }

    @Test func cacheRoundTripsAndDropsDeletedMembers() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        let store = PerceptualHashStore(database: database)
        for id in ["a", "b", "c", "d"] { try metadata.upsert(makeRecord(id)) }
        try store.upsert(["a", "b", "c", "d"].map {
            PerceptualHashRecord(assetId: $0, hash: PerceptualHash(bits: 1), modificationDate: 1_700_000_000, computedAt: 1)
        })
        #expect(try store.cachedGroups(strictness: .similar) == nil)
        #expect(try store.scanState(strictness: .similar) == nil)

        let groups = [
            DuplicateGroup(members: [hashed("a", bits: 1, size: 20), hashed("b", bits: 1, size: 10)]),
            DuplicateGroup(members: [hashed("c", bits: 1), hashed("d", bits: 1)]),
        ]
        let scannedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try store.replaceGroups(groups, strictness: .similar, scannedAt: scannedAt)

        let cached = try #require(try store.cachedGroups(strictness: .similar))
        #expect(cached.count == 2)
        #expect(Set(cached.flatMap { $0.members.map(\.assetId) }) == ["a", "b", "c", "d"])
        // Facts come from photo_metadata at read time, not from the cache.
        #expect(cached.flatMap(\.members).allSatisfy { $0.fileSize == 10_000_000 })
        #expect(try store.scanState(strictness: .similar) == DuplicateScanState(strictness: .similar, scannedAt: scannedAt, groupCount: 2))
        // The other strictness is untouched.
        #expect(try store.cachedGroups(strictness: .exact) == nil)

        // Deleting one member of a pair dissolves that group; the other stays.
        try store.removeFromGroups(assetIds: ["c"])
        let afterDelete = try #require(try store.cachedGroups(strictness: .similar))
        #expect(afterDelete.count == 1)
        #expect(Set(afterDelete[0].members.map(\.assetId)) == ["a", "b"])

        // Replacing with an empty grouping leaves a state but no groups.
        try store.replaceGroups([], strictness: .similar, scannedAt: scannedAt)
        #expect(try store.cachedGroups(strictness: .similar) == [])
    }

    @Test func pendingCountMatchesWorkList() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        let store = PerceptualHashStore(database: database)
        for id in ["a", "b", "c"] { try metadata.upsert(makeRecord(id)) }
        try store.upsert([PerceptualHashRecord(assetId: "a", hash: PerceptualHash(bits: 1), modificationDate: 1_700_000_000, computedAt: 1)])
        #expect(try store.pendingCount(retryingFailed: false) == 2)
        #expect(try store.pendingCount(retryingFailed: false) == (try store.pendingAssetIds(retryingFailed: false).count))
    }
}
