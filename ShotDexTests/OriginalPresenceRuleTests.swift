import Foundation
import Testing
@testable import ShotDex

/// FS-06.10 AC-2, AC-10 — the **Original** rule reads the offline check's
/// table; an unchecked photo is in neither value.
@MainActor
struct OriginalPresenceRuleTests {
    static func rule(_ op: RuleOperator, _ value: OriginalPresence) -> SmartAlbumRule {
        SmartAlbumRule(field: .original, op: op, text: value.rawValue)
    }

    private static func count(_ database: AppDatabase, _ rules: [SmartAlbumRule]) async throws -> Int {
        try await LibraryQueries(database: database).count(matching: SmartAlbumQuery(matchMode: .all, rules: rules))
    }

    /// AC-2: 60 on the device, 30 only in iCloud, 10 not checked.
    @Test func isAndIsNotLeaveUncheckedOut() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<100).map { "P\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        let store = OriginalPresenceStore(database: database)
        try store.record(Dictionary(uniqueKeysWithValues: ids.prefix(60).map { ($0, .onDevice) }), at: 10)
        try store.record(Dictionary(uniqueKeysWithValues: ids[60..<90].map { ($0, .iCloudOnly) }), at: 10)
        // Two of the last ten were looked at and could not tell; the rest never.
        try store.record(["P90": nil, "P91": nil], at: 10)

        #expect(try await Self.count(database, [Self.rule(.isExactly, .onDevice)]) == 60)
        #expect(try await Self.count(database, [Self.rule(.isNot, .onDevice)]) == 30)
        #expect(try await Self.count(database, [Self.rule(.isExactly, .iCloudOnly)]) == 30)
        #expect(try await Self.count(database, [Self.rule(.isNot, .iCloudOnly)]) == 60)

        // A recheck takes a photo out of both until it is checked again.
        try store.markForRecheck(["P0", "P60"])
        #expect(try await Self.count(database, [Self.rule(.isExactly, .onDevice)]) == 59)
        #expect(try await Self.count(database, [Self.rule(.isNot, .onDevice)]) == 29)
    }

    /// AC-10: *Source is NAS Home* AND *Original is iCloud Only* — only
    /// photos on the NAS whose original is not on the device.
    @Test func combinesWithSourceOnServer() async throws {
        let f = try OnServerFixture(photos: 10)
        for n in 0..<10 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        for n in 0..<6 { try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        let store = OriginalPresenceStore(database: f.database)
        try store.record(Dictionary(uniqueKeysWithValues: (0..<10).map { ("P\($0)", $0 % 2 == 0 ? .iCloudOnly : .onDevice) }), at: 10)

        let source = SmartAlbumRule(field: .source, op: .isExactly, text: f.source)
        let both = [source, Self.rule(.isExactly, .iCloudOnly)]
        let ids = try await LibraryQueries(database: f.database)
            .gridItems(matching: SmartAlbumQuery(matchMode: .all, rules: both), sort: .dateTakenNewest).map(\.assetId)
        #expect(Set(ids) == ["P0", "P2", "P4"])
        #expect(try await Self.count(f.database, [source, Self.rule(.isNot, .iCloudOnly)]) == 3)
    }

    @Test func chipReadsFieldAndValue() {
        #expect(Self.rule(.isExactly, .iCloudOnly).displaySummary == "Original is iCloud Only")
        #expect(Self.rule(.isNot, .onDevice).displaySummary == "Original is not \(OriginalPresence.onThisDevice)")
        #expect(RuleField.original.choiceValues.map(\.value) == ["onDevice", "iCloudOnly"])
    }

    /// The result-bar chip uses the Filter toggle's words; *is not* reads as
    /// the other answer.
    @Test func compactChips() {
        #expect(Self.rule(.isExactly, .onDevice).compactDisplaySummary == OriginalPresence.filterTitle)
        #expect(Self.rule(.isNot, .iCloudOnly).compactDisplaySummary == OriginalPresence.filterTitle)
        #expect(Self.rule(.isExactly, .iCloudOnly).compactDisplaySummary == "Original in iCloud Only")
        #expect(Self.rule(.isNot, .onDevice).compactDisplaySummary == "Original in iCloud Only")
        #expect(SmartAlbumRule(field: .original, op: .isExactly, text: "").compactDisplaySummary == "original")
        #expect(Self.rule(.isExactly, .onDevice).compactDisplaySummary(naming: ["S1": "NAS"]) == OriginalPresence.filterTitle)
    }

    /// *Any* of the two values is every checked photo — still not the
    /// unchecked ones.
    @Test func anyOfBothIsEveryCheckedPhoto() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<10).map { "P\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        try OriginalPresenceStore(database: database).record(
            Dictionary(uniqueKeysWithValues: ids.prefix(9).map { ($0, $0 == "P0" ? .iCloudOnly : .onDevice) }), at: 10)
        let query = SmartAlbumQuery(matchMode: .any, rules: [Self.rule(.isExactly, .onDevice), Self.rule(.isExactly, .iCloudOnly)])
        #expect(try await LibraryQueries(database: database).count(matching: query) == 9)
    }

    /// A value or operator this build does not know adds no condition — it
    /// never empties the album.
    @Test func unknownValueOrOperatorIsSkipped() async throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            [PhotoMarksStoreTests.record("P0", favorite: true), PhotoMarksStoreTests.record("P1")], cursorAssetId: nil)
        let favorite = SmartAlbumRule(field: .favorite, boolValue: true)
        let bogus = SmartAlbumRule(field: .original, op: .isExactly, text: "sometimes")
        let wrongOp = SmartAlbumRule(field: .original, op: .contains, text: "onDevice")
        let queries = LibraryQueries(database: database)
        #expect(try await queries.count(matching: SmartAlbumQuery(matchMode: .all, rules: [favorite, bogus, wrongOp])) == 1)
    }

    /// The raw values are saved in album JSON: renaming one breaks albums.
    @Test func rawValuesArePinned() throws {
        #expect(RuleField.original.rawValue == "original")
        #expect(OriginalPresence.onDevice.rawValue == "onDevice")
        #expect(OriginalPresence.iCloudOnly.rawValue == "iCloudOnly")
        let data = try JSONEncoder().encode(Self.rule(.isNot, .iCloudOnly))
        let back = try JSONDecoder().decode(SmartAlbumRule.self, from: data)
        #expect(back.field == .original && back.op == .isNot && back.text == "iCloudOnly")
    }

    @Test func offeredInTheFieldMenu() {
        #expect(RuleField.selectableCases(extendedMetadata: false).contains(.original))
    }
}

extension OriginalPresenceRuleTests {
    /// AC-8's trigger: only an album with an Original condition keeps the
    /// check going while it is open.
    @Test func usesOriginalOnlyWithTheField() {
        #expect(SmartAlbumQuery(matchMode: .all, rules: [Self.rule(.isExactly, .onDevice)]).usesOriginal)
        #expect(!SmartAlbumQuery(matchMode: .all, rules: [SmartAlbumRule(field: .source, op: .isExactly, text: "S1")]).usesOriginal)
    }
}
