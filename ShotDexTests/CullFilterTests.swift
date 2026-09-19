import Foundation
import Testing
@testable import ShotDex

/// Filtering and sorting the library by the culling pass. The data lives in
/// `photo_cull`, not in `photo_metadata`, so every one of these is a test that
/// the subquery joins the two correctly — including for photos that have no
/// cull row at all, which is most of a library.
@MainActor
struct CullFilterTests {

    private func makeRecord(assetId: String, creation: Int) -> PhotoMetadata {
        PhotoMetadata(
            assetId: assetId,
            creationDate: creation,
            modificationDate: creation,
            mediaType: MediaKind.photo.storedValue,
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
            isFavorite: false,
            indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    /// Four photos: five stars and picked, three stars, rejected, untouched.
    private func makeLibrary() throws -> (LibraryQueries, CullStore) {
        let database = try AppDatabase.makeEmpty()
        let metadataStore = MetadataStore(database: database)
        try metadataStore.saveBatch([
            makeRecord(assetId: "five", creation: 1_700_000_400),
            makeRecord(assetId: "three", creation: 1_700_000_300),
            makeRecord(assetId: "rejected", creation: 1_700_000_200),
            makeRecord(assetId: "untouched", creation: 1_700_000_100),
        ], cursorAssetId: nil)

        let cullStore = CullStore(database: database)
        try cullStore.setRating(5, ids: ["five"])
        try cullStore.setFlag(.picked, ids: ["five"])
        try cullStore.setRating(3, ids: ["three"])
        try cullStore.setFlag(.rejected, ids: ["rejected"])
        return (LibraryQueries(database: database), cullStore)
    }

    @Test func minimumRatingIsAFloorNotAnEquality() async throws {
        let (queries, _) = try makeLibrary()
        var criteria = FilterCriteria()
        criteria.minRating = 3
        let matches = try await queries.gridItems(matching: criteria, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["five", "three"])

        criteria.minRating = 5
        #expect(try queries.count(matching: criteria) == 1)
    }

    @Test func flagFilterMatchesAnyOfTheSelected() async throws {
        let (queries, _) = try makeLibrary()
        var criteria = FilterCriteria()
        criteria.flags = [.picked]
        #expect(try queries.count(matching: criteria) == 1)

        criteria.flags = [.picked, .rejected]
        let both = try await queries.gridItems(matching: criteria, sort: .dateTakenNewest)
        #expect(both.map(\.assetId) == ["five", "rejected"])
    }

    /// Unflagged is the awkward one: a photo with no row at all is unflagged,
    /// and so is one whose row exists only for a rating.
    @Test func unflaggedIncludesPhotosWithNoCullRowAndRatedOnes() async throws {
        let (queries, _) = try makeLibrary()
        var criteria = FilterCriteria()
        criteria.flags = [.unflagged]
        let matches = try await queries.gridItems(matching: criteria, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["three", "untouched"])
    }

    @Test func unflaggedCombinesWithAFlagAsAnOr() async throws {
        let (queries, _) = try makeLibrary()
        var criteria = FilterCriteria()
        criteria.flags = [.unflagged, .rejected]
        let matches = try await queries.gridItems(matching: criteria, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["three", "rejected", "untouched"])
    }

    @Test func ratingAndFlagNarrowEachOther() async throws {
        let (queries, _) = try makeLibrary()
        var criteria = FilterCriteria()
        criteria.minRating = 3
        criteria.flags = [.picked]
        #expect(try queries.count(matching: criteria) == 1)

        criteria.flags = [.rejected]
        #expect(try queries.count(matching: criteria) == 0)
    }

    /// An unrated photo sorts as zero rather than dropping out of the order.
    @Test func sortByRatingKeepsUnratedPhotos() async throws {
        let (queries, _) = try makeLibrary()
        let highest = try await queries.gridItems(
            matching: FilterCriteria.empty,
            sort: .ratingHighest
        )
        #expect(highest.map(\.assetId) == ["five", "three", "rejected", "untouched"])

        let lowest = try await queries.gridItems(
            matching: FilterCriteria.empty,
            sort: .ratingLowest
        )
        #expect(lowest.count == 4)
        #expect(lowest.last?.assetId == "five")
        // Ties fall back to newest-first, so the two unrated photos keep the
        // order the rest of the app shows them in.
        #expect(lowest.map(\.assetId).prefix(2) == ["rejected", "untouched"])
    }

    @Test func noCullCriteriaLeavesTheLibraryAlone() async throws {
        let (queries, _) = try makeLibrary()
        #expect(try queries.count(matching: FilterCriteria.empty) == 4)
        #expect(FilterCriteria.empty.isEmpty)
    }

    /// The cache the grid reads is written by the same call that writes the
    /// table, so a badge appears without a reload.
    @Test func theCacheFollowsTheWrites() throws {
        let (_, cullStore) = try makeLibrary()
        #expect(cullStore.states["five"]?.rating == 5)
        #expect(cullStore.states["untouched"] == nil)

        let before = cullStore.version
        try cullStore.setRating(2, ids: ["untouched"])
        #expect(cullStore.states["untouched"]?.rating == 2)
        #expect(cullStore.version != before)

        // Back to untouched drops the row, and must drop the cache entry with
        // it — a stale entry is a badge on a photo the table disagrees about.
        try cullStore.setRating(0, ids: ["untouched"])
        #expect(cullStore.states["untouched"] == nil)
    }

    @Test func aReloadSeesWhatAnotherStoreWrote() throws {
        let database = try AppDatabase.makeEmpty()
        let writer = CullStore(database: database)
        let reader = CullStore(database: database)
        try writer.setFlag(.picked, ids: ["a"])

        #expect(reader.states["a"] == nil)
        reader.reloadAll()
        #expect(reader.states["a"]?.flag == .picked)
    }

    // MARK: Smart album rules

    @Test func aSmartAlbumCanAskForThreeStarsAndUp() async throws {
        let (queries, _) = try makeLibrary()
        let query = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .rating, op: .greaterThan, number: 2),
        ])
        let matches = try await queries.gridItems(matching: query, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["five", "three"])
    }

    /// Unrated counts as zero, so "below three stars" includes the photos
    /// nobody has been through yet — which is the point of the rule.
    @Test func belowThreeStarsIncludesTheUnrated() async throws {
        let (queries, _) = try makeLibrary()
        let query = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .rating, op: .lessThan, number: 3),
        ])
        let matches = try await queries.gridItems(matching: query, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["rejected", "untouched"])
    }

    @Test func aSmartAlbumCanAskForPicksAndForUnflagged() async throws {
        let (queries, _) = try makeLibrary()
        let picked = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .flag, op: .isExactly, text: String(PhotoFlag.picked.rawValue)),
        ])
        #expect(try await queries.count(matching: picked) == 1)

        let notRejected = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .flag, op: .isNot, text: String(PhotoFlag.rejected.rawValue)),
        ])
        #expect(try await queries.count(matching: notRejected) == 3)

        let unflagged = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .flag, op: .isExactly, text: String(PhotoFlag.unflagged.rawValue)),
        ])
        let matches = try await queries.gridItems(matching: unflagged, sort: .dateTakenNewest)
        #expect(matches.map(\.assetId) == ["three", "untouched"])
    }

    /// Neither field can be answered from a `PhotoMetadata` value, so the
    /// in-memory matcher must skip them rather than silently return false —
    /// the same call `.place` gets, and for the same reason.
    @Test func cullRulesAreNotEvaluatedInMemory() {
        #expect(!SmartAlbumQuery.isEvaluableInMemory(
            SmartAlbumRule(field: .rating, op: .greaterThan, number: 3)
        ))
        #expect(!SmartAlbumQuery.isEvaluableInMemory(
            SmartAlbumRule(field: .flag, op: .isExactly, text: "1")
        ))
        #expect(SmartAlbumQuery.isEvaluableInMemory(
            SmartAlbumRule(field: .iso, op: .greaterThan, number: 800)
        ))
    }

    /// Criteria round-trip through JSON, because smart albums store them.
    @Test func cullCriteriaSurviveEncoding() throws {
        var criteria = FilterCriteria()
        criteria.minRating = 4
        criteria.flags = [.picked, .rejected]
        let data = try JSONEncoder().encode(criteria)
        let decoded = try JSONDecoder().decode(FilterCriteria.self, from: data)
        #expect(decoded.minRating == 4)
        #expect(decoded.flags == [.picked, .rejected])
        #expect(decoded.activeConditionCount == 2)
    }
}
