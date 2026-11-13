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
        // The best of three per query: tests run four at a time, and one
        // slice of contention is not what a keystroke costs.
        var prefix = Duration.zero
        for typed in ["c", "can", "canon r", "85", "iso 32", "sum"] {
            var best = Duration.seconds(10)
            for _ in 0..<3 {
                let started = clock.now
                _ = try await queries.groups(matching: typed)
                best = min(best, clock.now - started)
            }
            prefix = max(prefix, best)
        }
        let sony = try #require(try await queries.groups(in: [.camera]).first { $0.name == "Sony A7 IV" })
        let iso = try await queries.groups(matching: "iso")
        let scopedStart = clock.now
        _ = try await queries.counts(of: iso, within: SmartAlbumQuery(rules: [sony.rule]))
        let scoped = clock.now - scopedStart

        // A6: free text through the trigram index, and the six-column LIKE
        // it replaced — same photos, measured both ways.
        let library = LibraryQueries(database: database)
        let likeSQL = SmartAlbumSQLBuilder.anyTextColumns.map { "\($0) LIKE '%mg_12%' COLLATE NOCASE" }.joined(separator: " OR ")
        let scanStart = clock.now
        let scanned = try await database.reader.read { db in
            try Set(String.fetchAll(db, sql: "SELECT assetId FROM photo_metadata WHERE \(likeSQL)"))
        }
        let scan = clock.now - scanStart
        let likeStart = clock.now
        let found = try await library.gridItems(
            matching: SmartAlbumQuery(rules: [SmartAlbumRule(field: .anyText, op: .contains, text: "mg_12")]),
            sort: .dateTakenNewest
        )
        let like = clock.now - likeStart

        // Both ways on the raw condition, for a common and a rare term.
        func timed(_ sql: String, _ args: StatementArguments) async throws -> Duration {
            var best = Duration.seconds(10)
            for _ in 0..<3 {
                let started = clock.now
                _ = try await database.reader.read { db in try Int.fetchOne(db, sql: sql, arguments: args) }
                best = min(best, clock.now - started)
            }
            return best
        }
        for term in ["mg_12", "img_54321"] {
            let indexed = try await timed("SELECT COUNT(*) FROM photo_metadata WHERE rowid IN (SELECT rowid FROM photo_text_fts WHERE photo_text_fts MATCH ?)", ["\"\(term)\""])
            let likeAll = SmartAlbumSQLBuilder.anyTextColumns.map { "\($0) LIKE ? COLLATE NOCASE" }.joined(separator: " OR ")
            let scanned = try await timed("SELECT COUNT(*) FROM photo_metadata WHERE \(likeAll)",
                                          StatementArguments(SmartAlbumSQLBuilder.anyTextColumns.map { _ in "%\(term)%" }))
            print("SEARCHPERF term=\(term) trigram=\(indexed) likeScan=\(scanned)")
        }
        print("SEARCHPERF rebuild=\(rebuild) prefix=\(prefix) scopedCounts=\(scoped) anyTextIndexed=\(like) oldLIKEscan=\(scan) found=\(found.count)")
        #expect(Set(found.map(\.assetId)) == scanned)
        #expect(rebuild < .seconds(3))
        #expect(prefix < .milliseconds(50))
        #expect(scoped < .milliseconds(300))
        #expect(found.count > 0)
    }

    /// AC-19: the index finds what the LIKE scan found, and follows edits —
    /// a renamed file, a deleted row, a rewrite that changes no text.
    @Test func freeTextIndexMatchesLike() async throws {
        var a = SearchIndexTests.photo("a")
        a.originalFilename = "IMG_1234.HEIC"
        var b = SearchIndexTests.photo("b", camera: "X-T5", brand: "Fujifilm")
        b.originalFilename = "DSCF0001.RAF"
        let database = try SearchIndexTests.library([a, b])
        let library = LibraryQueries(database: database)
        func ids(_ term: String) async throws -> Set<String> {
            Set(try await library.gridItems(matching: SmartAlbumQuery(rules: [SmartAlbumRule(field: .anyText, op: .contains, text: term)]),
                                            sort: .dateTakenNewest).map(\.assetId))
        }
        #expect(try await ids("img_12") == ["a"])
        #expect(try await ids("x-t") == ["b"])
        #expect(try await ids("eos") == ["a"])
        #expect(try await ids("F0") == ["b"])        // two characters: the scan
        a.originalFilename = "IMG_9999.HEIC"
        try MetadataStore(database: database).saveBatch([a], cursorAssetId: nil)
        #expect(try await ids("img_12").isEmpty)
        #expect(try await ids("9999") == ["a"])
        try MetadataStore(database: database).saveBatch([a], cursorAssetId: nil) // same text again
        #expect(try await ids("9999") == ["a"])
        try MetadataStore(database: database).deleteAssets(ids: ["b"])
        #expect(try await ids("x-t").isEmpty)
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_text_fts(photo_text_fts, rank) VALUES('integrity-check', 1)")
        }
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
