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

    /// §14.4: the photo-info count the keeper tiebreak reads — every
    /// `photo_metadata` column once, empty text is not info, a photo with no
    /// `duplicate_quality` row still comes back, and a quality row adds
    /// nothing (only scored copies have one; it must not tilt the tie).
    @Test func infoFieldCountCountsEachPhotoInfoColumnOnce() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        let hashes = PerceptualHashStore(database: database)
        let quality = DuplicateQualityStore(database: database)
        var full = makeRecord("full")
        full.cameraManufacturer = "Canon"; full.cameraModel = "R6"; full.lensModel = "RF 85"
        full.focalLength = 85; full.aperture = 1.8; full.shutterSpeedSeconds = 0.01; full.iso = 100; full.latitude = 10.5
        var empty = makeRecord("empty")
        empty.cameraManufacturer = ""; empty.cameraModel = ""; empty.lensModel = ""
        for record in [full, empty, makeRecord("bare")] { try metadata.upsert(record) }
        try hashes.upsert(["full", "empty", "bare"].map {
            PerceptualHashRecord(assetId: $0, hash: PerceptualHash(bits: 1), modificationDate: 1_700_000_000, computedAt: 1)
        })
        func counts() throws -> [String: Int] {
            Dictionary(uniqueKeysWithValues: try hashes.hashedPhotos().map { ($0.assetId, $0.infoFieldCount) })
        }
        #expect(try counts() == ["full": 8, "empty": 0, "bare": 0])

        try quality.upsert([
            DuplicateQualityRecord(assetId: "full", modificationDate: 1_700_000_000, score: DuplicateQualityScore(),
                                   exposureBias: -0.3, software: "Lightroom", scoredAt: 1),
            DuplicateQualityRecord(assetId: "empty", modificationDate: 1_700_000_000, score: DuplicateQualityScore(),
                                   exposureBias: 0, software: "", scoredAt: 1),
        ])
        #expect(try counts() == ["full": 8, "empty": 0, "bare": 0])

        // The cached-group read carries the same count.
        try hashes.replaceGroups(
            [DuplicateGroup(members: try hashes.hashedPhotos().filter { $0.assetId != "bare" }, kind: .exact)],
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let cached = try #require(try hashes.cachedGroups()).flatMap(\.members)
        #expect(Dictionary(uniqueKeysWithValues: cached.map { ($0.assetId, $0.infoFieldCount) }) == ["full": 8, "empty": 0])
    }

    /// §14.2: a checksum reads back only while the photo is unchanged; an
    /// edit (new modification date) leaves it unread again.
    @Test func checksumFollowsTheModificationDate() throws {
        let (metadata, hashes) = try makeStores()
        try metadata.upsert(makeRecord("a"))
        try hashes.upsert([PerceptualHashRecord(assetId: "a", hash: PerceptualHash(bits: 1), modificationDate: 1_700_000_000, computedAt: 1)])
        try hashes.upsertChecksums([(assetId: "a", modificationDate: 1_700_000_000, sha256: "abc")])
        #expect(try hashes.hashedPhotos().first?.contentChecksum == "abc")
        try hashes.upsertChecksums([(assetId: "a", modificationDate: 1_600_000_000, sha256: "old")])
        #expect(try hashes.hashedPhotos().first?.contentChecksum == nil)
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

    /// A4: thumbnails that could not be read are counted for the iCloud line.
    @Test func unreadableThumbnailsAreCounted() throws {
        let (metadata, hashes) = try makeStores()
        for record in [makeRecord("cloud1"), makeRecord("cloud2"), makeRecord("local")] { try metadata.upsert(record) }
        try hashes.upsert([
            PerceptualHashRecord(assetId: "cloud1", hash: nil, modificationDate: 1_700_000_000, computedAt: 1),
            PerceptualHashRecord(assetId: "cloud2", hash: nil, modificationDate: 1_700_000_000, computedAt: 1),
            PerceptualHashRecord(assetId: "local", hash: PerceptualHash(bits: 3), modificationDate: 1_700_000_000, computedAt: 1),
        ])
        #expect(try hashes.unreadableCount() == 2)
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
        #expect(try store.cachedGroups() == nil)
        #expect(try store.scanState() == nil)

        let groups = [
            DuplicateGroup(members: [hashed("a", bits: 1, size: 20), hashed("b", bits: 1, size: 10)], kind: .similar),
            DuplicateGroup(members: [hashed("c", bits: 1), hashed("d", bits: 1)], kind: .exact),
        ]
        let scannedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try store.replaceGroups(groups, scannedAt: scannedAt)

        let cached = try #require(try store.cachedGroups())
        #expect(cached.count == 2)
        #expect(Set(cached.flatMap { $0.members.map(\.assetId) }) == ["a", "b", "c", "d"])
        // The kind round-trips with the group.
        #expect(Set(cached.map { "\($0.kind)" + $0.members.map(\.assetId).sorted().joined() }) == ["similarab", "exactcd"])
        // Facts come from photo_metadata at read time, not from the cache.
        #expect(cached.flatMap(\.members).allSatisfy { $0.fileSize == 10_000_000 })
        #expect(try store.scanState() == DuplicateScanState(scannedAt: scannedAt, groupCount: 2))

        // Deleting one member of a pair dissolves that group; the other stays.
        try store.removeFromGroups(assetIds: ["c"])
        let afterDelete = try #require(try store.cachedGroups())
        #expect(afterDelete.count == 1)
        #expect(Set(afterDelete[0].members.map(\.assetId)) == ["a", "b"])

        // Replacing with an empty grouping leaves a state but no groups.
        try store.replaceGroups([], scannedAt: scannedAt)
        #expect(try store.cachedGroups() == [])
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
