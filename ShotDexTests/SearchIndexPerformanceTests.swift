import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.03c AC-25 and the A6 measurement: the index at the library size the
/// app is built for (55,000 photos), and what free-text search costs there.
@MainActor
struct SearchIndexPerformanceTests {
    static let photoCount = 55_000

    static func bigLibrary() throws -> AppDatabase {
        let cameras = [("Canon", "EOS R6"), ("Sony", "A7 IV"), ("Fujifilm", "X-T5"), ("Nikon", "Z8"), ("Leica", "Q3")]
        let lenses = ["RF 85mm F1.2 L USM", "FE 24-70mm F2.8 GM II", "XF 23mm F1.4 R LM WR", "Z 50mm f/1.8 S", "Summilux 28mm"]
        let isos = [100, 200, 400, 800, 1600, 3200, 6400]
        var rows: [PhotoMetadata] = []
        rows.reserveCapacity(photoCount)
        for index in 0..<photoCount {
            let camera = cameras[index % cameras.count]
            var row = SearchIndexTests.photo(
                "p\(index)", camera: camera.1, brand: camera.0,
                lens: lenses[(index / 7) % lenses.count],
                focal: Double([24, 35, 50, 85, 135][index % 5]),
                created: 1_500_000_000 + index * 3_600,
                latitude: index % 3 == 0 ? -33.8 : 35.0
            )
            row.iso = isos[index % isos.count]
            row.originalFilename = "IMG_\(index).HEIC"
            rows.append(row)
        }
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        for start in stride(from: 0, to: rows.count, by: 5_000) {
            try store.saveBatch(Array(rows[start..<min(start + 5_000, rows.count)]), cursorAssetId: nil)
        }
        return database
    }

    @Test func indexAtLibrarySize() async throws {
        let database = try Self.bigLibrary()
        let clock = ContinuousClock()

        let rebuild = try clock.measure { try SearchIndexStore(database: database).rebuild() }
        let queries = SearchIndexQueries(database: database)
        _ = try await queries.groups(matching: "c") // warm the statement cache
        var prefix = Duration.zero
        for typed in ["c", "can", "canon r", "85", "iso 32", "sum"] {
            let started = clock.now
            _ = try await queries.groups(matching: typed)
            prefix = max(prefix, clock.now - started)
        }
        let sony = try #require(try await queries.groups(in: [.camera]).first { $0.name == "Sony A7 IV" })
        let iso = try await queries.groups(matching: "iso")
        let scopedStart = clock.now
        _ = try await queries.counts(of: iso, within: SmartAlbumQuery(rules: [sony.rule]))
        let scoped = clock.now - scopedStart

        // A6: free text the way it always ran — LIKE over six columns plus the
        // caption and keyword tables.
        let library = LibraryQueries(database: database)
        let likeStart = clock.now
        let found = try await library.gridItems(
            matching: SmartAlbumQuery(rules: [SmartAlbumRule(field: .anyText, op: .contains, text: "mg_12")]),
            sort: .dateTakenNewest
        )
        let like = clock.now - likeStart

        print("SEARCHPERF rebuild=\(rebuild) prefix=\(prefix) scopedCounts=\(scoped) anyTextLIKE=\(like) found=\(found.count)")
        #expect(rebuild < .seconds(3))
        #expect(prefix < .milliseconds(50))
        #expect(scoped < .milliseconds(300))
        #expect(found.count > 0)
    }

    @Test func queryJoinsTokensAndText() async throws {
        let database = try SearchIndexTests.library([SearchIndexTests.photo("a")])
        let service = SearchService(
            filterSuggestions: FilterSuggestionCache(libraryQueries: LibraryQueries(database: database)),
            recentSearches: RecentSearchStore()
        )
        let token = SearchToken(name: "ISO 400", symbol: "dial.medium",
                                rules: [SmartAlbumRule(field: .iso, op: .equalTo, number: 400)])
        let both = await service.query(tokens: [token], text: "85mm")
        #expect(both.rules.map(\.field) == [.iso, .focalLength])
        let free = await service.query(tokens: [token], text: "zzqx")
        #expect(free.rules.map(\.field) == [.iso, .anyText])
        let onlyTokens = await service.query(tokens: [token], text: "  ")
        #expect(onlyTokens.rules.count == 1)
    }

    @Test func parserTablesFollowCatalogRevision() {
        var catalog = FilterSuggestionCatalog(places: ["Fukuoka"])
        let first = SearchIntentParser.nameTables(for: catalog)
        #expect(first.places["fukuoka"] == "Fukuoka")
        catalog.places.append("Kyoto")
        #expect(SearchIntentParser.nameTables(for: catalog).places["kyoto"] == "Kyoto")
    }
}
