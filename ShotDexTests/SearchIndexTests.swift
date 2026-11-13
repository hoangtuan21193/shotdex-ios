import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.03c — the search index (§1), prefix matching (§2), counts inside the
/// chosen tokens (§3), calendar conditions (§5) and *Did you mean* (§6).
@MainActor
struct SearchIndexTests {

    /// Noon UTC on a day: the same calendar day in every zone from −11 to +11,
    /// so the local-time calendar facts do not depend on the test machine.
    nonisolated static func noon(_ year: Int, _ month: Int, _ day: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return Int(date.timeIntervalSince1970)
    }

    static func photo(_ id: String, camera: String = "EOS R6", brand: String = "Canon",
                      lens: String? = nil, focal: Double = 35, created: Int = noon(2024, 6, 10),
                      latitude: Double? = nil) -> PhotoMetadata {
        var row = PhotoMarksStoreTests.record(id, created: created)
        row.cameraManufacturer = brand
        row.normalizedCameraManufacturer = brand
        row.cameraModel = camera
        row.normalizedCameraModel = "\(brand) \(camera)"
        row.lensModel = lens
        row.normalizedLensModel = lens
        row.focalLength = focal
        row.latitude = latitude
        row.longitude = latitude.map { _ in 100 }
        return row
    }

    static func library(_ rows: [PhotoMetadata], places: [String: String] = [:]) throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(rows, cursorAssetId: nil)
        try database.writer.write { db in
            for (id, place) in places {
                try db.execute(sql: "UPDATE photo_metadata SET placeLocality = ?, placeSearchText = ? WHERE assetId = ?",
                               arguments: [place, PlaceSearchText.normalized(place), id])
            }
        }
        try SearchIndexStore(database: database).rebuild()
        return database
    }

    // MARK: AC-1

    @Test func buildsGroupsWithCounts() async throws {
        let database = try Self.library([
            Self.photo("a", lens: "RF 85mm F1.2 L USM", focal: 85, created: Self.noon(2024, 6, 10)),
            Self.photo("b", lens: "RF 85mm F1.2 L USM", focal: 85, created: Self.noon(2024, 6, 12)),
            Self.photo("c", created: Self.noon(2023, 1, 5)),
            Self.photo("d", camera: "X-T5", brand: "Fujifilm", created: Self.noon(2022, 3, 3)),
        ], places: ["c": "Cannes"])
        let queries = SearchIndexQueries(database: database)
        let all = try await queries.groups(in: SearchGroupCategory.allCases)
        func group(_ category: SearchGroupCategory, _ name: String) -> SearchGroup? {
            all.first { $0.category == category && $0.name == name }
        }
        #expect(group(.camera, "Canon EOS R6")?.count == 3)
        #expect(group(.cameraBrand, "Canon")?.count == 3)
        #expect(group(.lens, "RF 85mm F1.2 L USM")?.count == 2)
        #expect(group(.focalLength, "85mm")?.count == 2)
        #expect(group(.place, "Cannes")?.count == 1)
        #expect(group(.year, "2024")?.count == 2)
        // The newest photo is the row's picture.
        #expect(group(.camera, "Canon EOS R6")?.keyAssetId == "b")
        // Every group's rule finds exactly its count.
        let library = LibraryQueries(database: database)
        for g in all where g.category != .keyword {
            let found = try await library.count(matching: SmartAlbumQuery(rules: [g.rule]))
            #expect(found == g.count, "\(g.category) \(g.name)")
        }
    }

    // MARK: AC-2, AC-3

    @Test func prefixMatchesWordStarts() async throws {
        let database = try Self.library([
            Self.photo("a", lens: "RF 85mm F1.2 L USM"),
            Self.photo("b"),
        ], places: ["b": "Cannes"])
        let queries = SearchIndexQueries(database: database)
        let names = Set(try await queries.groups(matching: "can").map(\.name))
        #expect(names.isSuperset(of: ["Canon", "Canon EOS R6", "Cannes"]))
        #expect(!names.contains("RF 85mm F1.2 L USM"))
        // A later word: `r6` starts the third word of the camera.
        #expect(try await queries.groups(matching: "r6").contains { $0.name == "Canon EOS R6" })
        // Two words must both match.
        #expect(try await queries.groups(matching: "canon r6").map(\.name).contains("Canon EOS R6"))
        #expect(try await queries.groups(matching: "canon 85").isEmpty)
        // A typed quote is text, not FTS syntax.
        #expect(try await queries.groups(matching: "\"can").map(\.name).contains("Canon"))
    }

    @Test func diacriticInsensitive() async throws {
        let database = try Self.library([Self.photo("a")], places: ["a": "Đà Lạt"])
        let names = try await SearchIndexQueries(database: database).groups(matching: "da lat").map(\.name)
        #expect(names.contains("Đà Lạt"))
    }

    // MARK: AC-4

    @Test func refreshFollowsMetadata() async throws {
        let database = try Self.library([Self.photo("a"), Self.photo("b")])
        var moved = Self.photo("b", camera: "X-T5", brand: "Fujifilm")
        moved.modificationDate = 1_800_000_000
        try MetadataStore(database: database).saveBatch([moved], cursorAssetId: nil)
        try SearchIndexStore(database: database).rebuild()
        let all = try await SearchIndexQueries(database: database).groups(in: [.camera])
        #expect(all.first { $0.name == "Canon EOS R6" }?.count == 1)
        #expect(all.first { $0.name == "Fujifilm X-T5" }?.count == 1)
        try MetadataStore(database: database).saveBatch([Self.photo("a", camera: "X-T5", brand: "Fujifilm")], cursorAssetId: nil)
        try SearchIndexStore(database: database).rebuild()
        let after = try await SearchIndexQueries(database: database).groups(in: [.camera])
        #expect(!after.contains { $0.name == "Canon EOS R6" })
    }

    // MARK: AC-5

    @Test func countsWithinTokens() async throws {
        var rows = (0..<4).map { Self.photo("s\($0)", camera: "A7 IV", brand: "Sony") }
        rows[0].iso = 3200
        rows[1].iso = 3200
        var other = Self.photo("c")
        other.iso = 3200
        rows.append(other)
        let database = try Self.library(rows)
        let queries = SearchIndexQueries(database: database)
        let iso = try await queries.groups(matching: "iso 3200")
        #expect(iso.first?.count == 3)
        let sony = try #require(try await queries.groups(in: [.camera]).first { $0.name == "Sony A7 IV" })
        let counts = try await queries.counts(of: iso, within: SmartAlbumQuery(rules: [sony.rule]))
        #expect(counts[iso[0].id] == 2)
    }

    // MARK: AC-13, AC-14, AC-15

    @Test func seasonByHemisphere() async throws {
        let database = try Self.library([
            Self.photo("hanoi", created: Self.noon(2024, 6, 10), latitude: 21),
            Self.photo("sydney", created: Self.noon(2024, 1, 10), latitude: -33.8),
            Self.photo("noLocation", created: Self.noon(2024, 1, 11)),
        ])
        let library = LibraryQueries(database: database)
        func ids(_ field: RuleField, _ value: String) async throws -> Set<String> {
            Set(try await library.gridItems(matching: SmartAlbumQuery(rules: [SmartAlbumRule(field: field, op: .isExactly, text: value)]),
                                            sort: .dateTakenNewest).map(\.assetId))
        }
        #expect(try await ids(.season, CaptureSeason.summer.rawValue) == ["hanoi", "sydney"])
        #expect(try await ids(.season, CaptureSeason.winter.rawValue) == ["noLocation"])
        // The index counts the same way.
        let seasons = try await SearchIndexQueries(database: database).groups(in: [.season])
        #expect(seasons.first { $0.rule.text == "summer" }?.count == 2)
    }

    @Test func calendarFields() async throws {
        // 2024-06-10 is a Monday; 2024-06-15 a Saturday.
        let database = try Self.library([
            Self.photo("mon", created: Self.noon(2024, 6, 10)),
            Self.photo("sat", created: Self.noon(2024, 6, 15)),
            Self.photo("jan", created: Self.noon(2023, 1, 4)),
        ])
        let library = LibraryQueries(database: database)
        func ids(_ field: RuleField, _ value: String, _ op: RuleOperator = .isExactly) async throws -> Set<String> {
            Set(try await library.gridItems(matching: SmartAlbumQuery(rules: [SmartAlbumRule(field: field, op: op, text: value)]),
                                            sort: .dateTakenNewest).map(\.assetId))
        }
        #expect(try await ids(.monthOfYear, "6") == ["mon", "sat"])
        #expect(try await ids(.dayOfWeek, CaptureWeekday.monday.rawValue) == ["mon"])
        #expect(try await ids(.dayOfWeek, CaptureWeekday.weekend.rawValue) == ["sat"])
        #expect(try await ids(.dayOfWeek, CaptureWeekday.weekend.rawValue, .isNot) == ["mon", "jan"])
        #expect(RuleField.selectableCases(extendedMetadata: false).contains(.monthOfYear))
        #expect(RuleField.selectableCases(extendedMetadata: false).contains(.season))
        #expect(RuleField.selectableCases(extendedMetadata: false).contains(.dayOfWeek))
        let saved = SmartAlbumQuery(rules: [SmartAlbumRule(field: .season, op: .isExactly, text: "summer")])
        #expect(try JSONDecoder().decode(SmartAlbumQuery.self, from: JSONEncoder().encode(saved)) == saved)
    }

    // MARK: AC-16, AC-17, ranking

    @Test func didYouMeanOnlyForNearNames() {
        func group(_ name: String, _ count: Int) -> SearchGroup {
            SearchGroup(id: Int64(name.count), category: .cameraBrand, name: name, count: count, keyAssetId: nil,
                        rule: SmartAlbumRule(field: .cameraBrand, op: .isExactly, text: name))
        }
        let groups = [group("Fujifilm", 3120), group("Leica", 12), group("R6", 4)]
        #expect(SearchSpelling.suggestion(for: "fujiflim", in: groups)?.name == "Fujifilm")
        #expect(SearchSpelling.suggestion(for: "leica", in: groups) == nil)
        #expect(SearchSpelling.suggestion(for: "r5", in: groups) == nil)
        #expect(SearchSpelling.suggestion(for: "nikon", in: groups) == nil)
    }

    @Test func rankerPutsNameStartsFirst() {
        func group(_ id: Int64, _ category: SearchGroupCategory, _ name: String, _ count: Int) -> SearchGroup {
            SearchGroup(id: id, category: category, name: name, count: count, keyAssetId: nil,
                        rule: SmartAlbumRule(field: .place, op: .contains, text: name))
        }
        let ranked = SearchSuggestionRanker.rank([
            group(1, .lens, "RF 85mm F1.2 L USM", 318),
            group(2, .focalLength, "85mm", 412),
            group(3, .place, "Cannes", 1),
            group(4, .camera, "Canon EOS R6", 3),
            group(5, .iso, "ISO 0", 0),
        ], typed: "85", limit: 8)
        #expect(ranked.map(\.id) == [2, 4, 1, 3])
        #expect(SearchSuggestionRanker.rank(ranked, typed: "85", limit: 2).count == 2)
    }
}
