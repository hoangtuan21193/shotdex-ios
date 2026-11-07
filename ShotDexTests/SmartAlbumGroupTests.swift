import Foundation
import Testing
@testable import ShotDex

/// FS-06.08 §2b — a nested group of conditions with its own Any/All, one
/// more condition of the album it sits in.
@MainActor
struct SmartAlbumGroupTests {

    /// "Picked, and rated 5 or 1": the group's OR stays inside its
    /// parentheses, the album's AND outside them.
    @Test func groupIsOneConditionOfTheAlbum() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            (1...5).map { PhotoMarksStoreTests.record("r\($0)", created: 1_700_000_000 + $0) },
            cursorAssetId: nil
        )
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        for stars in 1...5 { await marks.setRating(stars, ids: ["r\(stars)"]) }
        await marks.setFlag(.pick, ids: ["r1", "r2", "r5"])

        let album = SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .flag, op: .isExactly, text: "pick"),
        ], groups: [
            SmartAlbumRuleGroup(matchMode: .any, rules: [
                SmartAlbumRule(field: .rating, op: .equalTo, number: 5),
                SmartAlbumRule(field: .rating, op: .equalTo, number: 1),
            ]),
        ])
        let queries = LibraryQueries(database: database)
        #expect(Set(try await queries.gridItems(matching: album, sort: .dateTakenNewest).map(\.assetId)) == ["r1", "r5"])
        #expect(try await queries.count(matching: album) == 2)

        // The same rules flat under All match nothing: a photo has one rating.
        let flat = SmartAlbumQuery(matchMode: .all, rules: album.rules + album.groups[0].rules)
        #expect(try await queries.count(matching: flat) == 0)
    }

    /// A group alone is a whole album: not empty, and it narrows.
    @Test func albumOfOnlyAGroupIsNotEmpty() async throws {
        let query = SmartAlbumQuery(rules: [], groups: [
            SmartAlbumRuleGroup(matchMode: .all, rules: [SmartAlbumRule(field: .rating, op: .atLeast, number: 4)]),
        ])
        #expect(!query.isEmpty)
        #expect(!SmartAlbumSQLBuilder.predicate(for: query).sql.isEmpty)
    }

    @Test func cleanedDropsBlankLinesAndEmptyGroupsButKeepsGroups() {
        let query = SmartAlbumQuery(matchMode: .any, rules: [SmartAlbumRule(), SmartAlbumRule(field: .lens, op: .contains, text: "85")],
                                    groups: [SmartAlbumRuleGroup(), SmartAlbumRuleGroup(matchMode: .all, rules: [
                                        SmartAlbumRule(), SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200),
                                    ])])
        let cleaned = query.cleaned
        #expect(cleaned.matchMode == .any)
        #expect(cleaned.rules.map(\.field) == [.lens])
        #expect(cleaned.groups.count == 1)
        #expect(cleaned.groups[0].matchMode == .all)
        #expect(cleaned.groups[0].rules.map(\.field) == [.iso])
    }

    @Test func groupsRoundTripAndOldJSONHasNone() throws {
        let query = SmartAlbumQuery(rules: [SmartAlbumRule(field: .lens, op: .contains, text: "85")], groups: [
            SmartAlbumRuleGroup(matchMode: .any, rules: [SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200)]),
        ])
        let decoded = try JSONDecoder().decode(SmartAlbumQuery.self, from: JSONEncoder().encode(query))
        #expect(decoded == query)

        let old = #"{"matchMode":"all","rules":[]}"#
        #expect(try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(old.utf8)).groups.isEmpty)
        // No groups: the stored JSON is the shape older builds wrote.
        let plain = String(decoding: try JSONEncoder().encode(SmartAlbumQuery(rules: query.rules)), as: UTF8.self)
        #expect(!plain.contains("groups"))
    }

    /// One unreadable group drops itself; a removed field drops only its rule.
    @Test func unreadableGroupDropsAlone() throws {
        let rule = #"{"id":"\#(UUID().uuidString)","field":"lens","op":"contains","text":"85","boolValue":true,"focalMode":"actual"}"#
        let removed = #"{"id":"\#(UUID().uuidString)","field":"colorLabel","op":"contains","text":"x","boolValue":true,"focalMode":"actual"}"#
        let json = #"{"matchMode":"all","rules":[],"groups":[42,{"matchMode":"any","rules":[\#(rule),\#(removed)]}]}"#
        let query = try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))
        #expect(query.groups.count == 1)
        #expect(query.groups[0].rules.map(\.field) == [.lens])
        #expect(!query.isEmpty)
    }
}
