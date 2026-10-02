import Foundation
import Testing
@testable import ShotDex

/// FS-01.12 AC-7 — the star and flag filters in the grid query, the chips,
/// and the album fetch.
@MainActor
struct MarkFilterTests {

    /// Ten photos rated 0,0,1,2,3,3,4,5,5,5; the first 5★ and the first 3★
    /// are Picked.
    private func tenPhotoLibrary() async throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        let ratings = [0, 0, 1, 2, 3, 3, 4, 5, 5, 5]
        try MetadataStore(database: database).saveBatch(
            ratings.indices.map { PhotoMarksStoreTests.record("p\($0)", created: 1_700_000_000 + $0) },
            cursorAssetId: nil
        )
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        for (index, rating) in ratings.enumerated() where rating > 0 {
            await marks.setRating(rating, ids: ["p\(index)"])
        }
        await marks.setFlag(.pick, ids: ["p7", "p4"])
        return database
    }

    private func ids(_ criteria: FilterCriteria, _ database: AppDatabase) async throws -> Set<String> {
        Set(try await LibraryQueries(database: database).gridItems(matching: criteria, sort: .dateTakenNewest).map(\.assetId))
    }

    @Test func ratingAndPicksFilter() async throws {
        let database = try await tenPhotoLibrary()
        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(3)
        criteria.flags = [.picks]

        #expect(try await ids(criteria, database) == ["p4", "p7"])
        #expect(FilterTokenBar.tokens(for: criteria).map(\.label) == ["★ ≥ 3", "Picks"])

        // x on the Picks chip.
        let picks = try #require(FilterTokenBar.tokens(for: criteria).first { $0.label == "Picks" })
        picks.clear(&criteria)
        #expect(try await ids(criteria, database).count == 6)
        #expect(!criteria.isEmpty)
    }

    @Test func unratedUnflaggedAndRejected() async throws {
        let database = try await tenPhotoLibrary()
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        await marks.setFlag(.reject, ids: ["p0"])

        var criteria = FilterCriteria()
        criteria.ratingFilter = .unrated
        #expect(try await ids(criteria, database) == ["p0", "p1"])

        criteria = FilterCriteria()
        criteria.flags = [.rejected, .picks]
        #expect(try await ids(criteria, database) == ["p0", "p4", "p7"])

        criteria.flags = [.unflagged]
        #expect(try await ids(criteria, database).count == 7)
        #expect(FilterTokenBar.tokens(for: criteria).map(\.label) == ["Unflagged"])
    }

    @Test func ratingChipLabel() {
        var criteria = FilterCriteria()
        criteria.ratingFilter = .unrated
        #expect(FilterTokenBar.tokens(for: criteria).map(\.label) == ["Unrated"])
        criteria.ratingFilter = .atLeast(5)
        #expect(FilterTokenBar.tokens(for: criteria).map(\.label) == ["★ ≥ 5"])
        #expect(MarkCopy.ratingMenuRow(.atLeast(3)) == "★★★ & Up")
        #expect(MarkCopy.ratingMenuRow(.atLeast(5)) == "★★★★★")
    }

    @Test func criteriaRoundTripAndLossyFlags() throws {
        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(4)
        criteria.flags = [.rejected]
        let data = try JSONEncoder().encode(criteria)
        #expect(try JSONDecoder().decode(FilterCriteria.self, from: data) == criteria)

        let foreign = #"{"flags":["picks","maybe"],"favoritesOnly":true}"#
        let decoded = try JSONDecoder().decode(FilterCriteria.self, from: Data(foreign.utf8))
        #expect(decoded.flags == [.picks])
        #expect(decoded.favoritesOnly)
    }

    // MARK: Album fetch (FS-06.09)

    private func matches(_ predicate: NSPredicate?, _ id: String, rating: Int = 0) -> Bool {
        predicate?.evaluate(with: ["localIdentifier": id, "rating": rating] as NSDictionary) ?? true
    }

    @Test func flagsByIdentifiers() {
        let marks = MarkFilterSnapshot(flags: ["A": .pick, "B": .reject])
        var criteria = FilterCriteria()
        criteria.flags = [.picks]
        let picks = AlbumFilterPredicate.predicate(for: criteria, marks: marks)
        #expect(matches(picks, "A") && !matches(picks, "B") && !matches(picks, "C"))

        criteria.flags = [.unflagged]
        let unflagged = AlbumFilterPredicate.predicate(for: criteria, marks: marks)
        #expect(!matches(unflagged, "A") && !matches(unflagged, "B") && matches(unflagged, "C"))
        #expect(!AlbumFilterPredicate.needsIndex(criteria))
    }

    @Test func ratingByIdentifiersAndPhotos() {
        var criteria = FilterCriteria()
        criteria.ratingFilter = .atLeast(3)

        // Below iOS 27: only the pending rows rate anything.
        let below = AlbumFilterPredicate.predicate(for: criteria, marks: MarkFilterSnapshot(pendingRatings: ["A": 4, "B": 2]))
        #expect(matches(below, "A") && !matches(below, "B") && !matches(below, "C", rating: 5))

        // iOS 27: Photos' rating counts unless a pending row says otherwise.
        let ios27 = AlbumFilterPredicate.predicate(
            for: criteria, marks: MarkFilterSnapshot(pendingRatings: ["B": 2], photosHoldsRatings: true)
        )
        #expect(matches(ios27, "C", rating: 5) && !matches(ios27, "B", rating: 5) && !matches(ios27, "D", rating: 1))
        #expect(!AlbumFilterPredicate.needsIndex(criteria))
    }
}
