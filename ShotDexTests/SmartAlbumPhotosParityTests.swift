import Foundation
import Testing
@testable import ShotDex

/// FS-06.08 §3c — the smart album work done to match Photos: date units and
/// *is not in the last* (AC-33, AC-34), the *Photo is …* condition (AC-35),
/// the editor's row edits (AC-21, AC-23) and the one-condition match row (AC-20).
@MainActor
struct SmartAlbumPhotosParityTests {

    // MARK: Dates (AC-33, AC-34)

    @Test func lastAndNotLastWithCalendarUnits() async throws {
        let database = try AppDatabase.makeEmpty()
        let now = Date()
        func daysAgo(_ days: Int) -> Int { Int(now.addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970) }
        var undated = PhotoMarksStoreTests.record("undated")
        undated.creationDate = nil
        try MetadataStore(database: database).saveBatch([
            PhotoMarksStoreTests.record("d10", created: daysAgo(10)),
            PhotoMarksStoreTests.record("d40", created: daysAgo(40)),
            PhotoMarksStoreTests.record("d400", created: daysAgo(400)),
            undated,
        ], cursorAssetId: nil)
        let queries = LibraryQueries(database: database)
        func ids(_ op: RuleOperator, _ count: Double, _ unit: DateUnit?) async throws -> Set<String> {
            let query = SmartAlbumQuery(rules: [SmartAlbumRule(field: .dateTaken, op: op, number: count, unit: unit)])
            return Set(try await queries.gridItems(matching: query, sort: .dateTakenNewest).map(\.assetId))
        }
        #expect(try await ids(.inLastDays, 1, .months) == ["d10"])
        #expect(try await ids(.inLastDays, 1, .years) == ["d10", "d40"])
        #expect(try await ids(.notInLast, 1, .years) == ["d400"])
        #expect(try await ids(.inLastDays, 2, .weeks) == ["d10"])
        // No unit is days — what albums saved before units meant.
        #expect(try await ids(.inLastDays, 30, nil) == ["d10"])
        // Undated photos are in neither answer.
        #expect(try await ids(.notInLast, 1, .days) == ["d10", "d40", "d400"])
    }

    @Test func oldInLastDaysJSONReadsAsDaysAndRoundTrips() throws {
        let json = #"{"matchMode":"all","rules":[{"id":"\#(UUID().uuidString)","field":"dateTaken","op":"inLastDays","text":"","number":30,"boolValue":true,"focalMode":"actual"}]}"#
        let query = try JSONDecoder().decode(SmartAlbumQuery.self, from: Data(json.utf8))
        #expect(query.rules.count == 1)
        #expect(query.rules[0].op == .inLastDays)
        #expect(query.rules[0].unit == nil)
        #expect(query.rules[0].isValid)
        let again = try JSONDecoder().decode(SmartAlbumQuery.self, from: JSONEncoder().encode(query))
        #expect(again == query)

        var weeks = query
        weeks.rules[0].unit = .weeks
        weeks.rules[0].op = .notInLast
        #expect(try JSONDecoder().decode(SmartAlbumQuery.self, from: JSONEncoder().encode(weeks)) == weeks)
    }

    @Test func monthsBackIsTheSameDayNotThirtyDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12)))
        let cutoff = DateUnit.months.cutoff(count: 1, from: now, calendar: calendar)
        #expect(calendar.dateComponents([.month, .day], from: cutoff) == DateComponents(month: 2, day: 28))
    }

    // MARK: Photo is … (AC-35)

    /// Every value: *is* matches the row that has it, *is not* the row that
    /// does not, and a row whose fact was never read matches neither.
    @Test func everyPhotoKindSplitsHasFromHasNot() async throws {
        for kind in PhotoKind.allCases {
            let database = try AppDatabase.makeEmpty()
            var has = PhotoMarksStoreTests.record("has")
            var hasNot = PhotoMarksStoreTests.record("not")
            Self.give(kind, to: &has)
            hasNot.mediaSubtypes = 0
            hasNot.isPanorama = false
            hasNot.hasAdjustments = false
            hasNot.isBurst = false
            hasNot.originalFilename = "IMG_0001.HEIC"
            var unread = PhotoMarksStoreTests.record("unread")
            unread.mediaSubtypes = nil
            unread.hasAdjustments = nil
            unread.isBurst = nil
            unread.originalFilename = "IMG_0002.HEIC"
            try MetadataStore(database: database).saveBatch([has, hasNot, unread], cursorAssetId: nil)
            let queries = LibraryQueries(database: database)
            func ids(_ op: RuleOperator) async throws -> Set<String> {
                let query = SmartAlbumQuery(rules: [SmartAlbumRule(field: .photoKind, op: op, text: kind.rawValue)])
                return Set(try await queries.gridItems(matching: query, sort: .dateTakenNewest).map(\.assetId))
            }
            let yes = try await ids(.isExactly)
            let no = try await ids(.isNot)
            #expect(yes == ["has"], "\(kind) is")
            #expect(no.contains("not") && !no.contains("has"), "\(kind) is not")
            // Facts read off the mask or the new columns: unknown stays out.
            let readFromFacts: Set<PhotoKind> = [.edited, .burst, .livePhoto, .panorama, .hdr, .portrait, .screenshot,
                                                 .screenRecording, .slowMotion, .timelapse, .cinematic, .spatial]
            if readFromFacts.contains(kind) {
                #expect(!no.contains("unread"), "\(kind) unread is not")
            }
        }
    }

    private static func give(_ kind: PhotoKind, to row: inout PhotoMetadata) {
        row.mediaSubtypes = 0
        row.isPanorama = false
        row.hasAdjustments = false
        row.isBurst = false
        row.originalFilename = "IMG_0003.HEIC"
        switch kind {
        case .favorite: row.isFavorite = true
        case .edited: row.hasAdjustments = true
        case .burst: row.isBurst = true
        case .taggedWithGPS: row.latitude = 10; row.longitude = 106
        case .raw: row.originalFilename = "DSC0001.ARW"
        case .animated: row.originalFilename = "loop.gif"
        case .video: row.mediaType = MediaKind.video.storedValue
        case .livePhoto: row.mediaSubtypes = PhotoMediaSubtype.livePhoto.bit
        case .panorama: row.isPanorama = true
        case .hdr: row.mediaSubtypes = PhotoMediaSubtype.hdr.bit
        case .portrait: row.mediaSubtypes = PhotoMediaSubtype.portrait.bit
        case .screenshot: row.mediaSubtypes = PhotoMediaSubtype.screenshot.bit
        case .slowMotion: row.mediaSubtypes = PhotoMediaSubtype.slowMotion.bit
        case .timelapse: row.mediaSubtypes = PhotoMediaSubtype.timelapse.bit
        case .cinematic: row.mediaSubtypes = PhotoMediaSubtype.cinematic.bit
        case .screenRecording: row.mediaSubtypes = PHAssetMediaSubtypeBit.screenRecording.rawValue
        case .spatial: row.mediaSubtypes = PHAssetMediaSubtypeBit.spatial.rawValue
        }
    }

    @Test func oneCaptureKindFilterSavesAsAPhotoRule() {
        var criteria = FilterCriteria()
        criteria.mediaSubtypes = [.livePhoto]
        #expect(SmartAlbumQuery.migrationGaps(criteria).isEmpty)
        let rule = SmartAlbumQuery.migrating(criteria).rules.first { $0.field == .photoKind }
        #expect(rule?.text == PhotoKind.livePhoto.rawValue)
        criteria.mediaSubtypes = [.livePhoto, .hdr]
        #expect(!SmartAlbumQuery.migrationGaps(criteria).isEmpty)
    }

    // MARK: Editor rows (AC-20, AC-21, AC-23)

    @Test func plusInsertsBelowOnTheSameField() {
        let a = SmartAlbumRule(field: .lens, op: .contains, text: "85")
        let b = SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200)
        let c = SmartAlbumRule(field: .aperture, op: .lessThan, number: 2)
        var query = SmartAlbumQuery(rules: [a, b, c])
        let id = query.insertRule(after: a.id)
        #expect(query.rules.map(\.id) == [a.id, id, b.id, c.id])
        #expect(query.rules[1].field == .lens)
        #expect(query.rules[1].text.isEmpty)
        // Unknown id: the end, like Add Condition.
        let end = query.insertRule(after: UUID())
        #expect(query.rules.last?.id == end)
    }

    @Test func changingFieldKeepsWhatStillFits() {
        let range = SmartAlbumRule(field: .iso, op: .inRange, number: 100, numberUpper: 6400)
        let focal = range.changingField(to: .focalLength)
        #expect(focal.id == range.id)
        #expect(focal.op == .inRange && focal.number == 100 && focal.numberUpper == 6400)
        let lens = range.changingField(to: .lens)
        #expect(lens.op == RuleField.lens.defaultOperator)
        #expect(lens.number == nil && lens.text.isEmpty)
        let text = SmartAlbumRule(field: .lens, op: .doesNotContain, text: "Sigma").changingField(to: .cameraBody)
        #expect(text.op == .doesNotContain && text.text == "Sigma")
        // A choice value belongs to its own field.
        let choice = SmartAlbumRule(field: .fileType, op: .isNot, text: "raw").changingField(to: .photoKind)
        #expect(choice.op == .isNot && choice.text.isEmpty)
    }

    @Test func conditionCountLeavesMediaTypeOutAndCountsGroups() {
        var query = SmartAlbumQuery(rules: [SmartAlbumRule(field: .mediaType, op: .isExactly, text: "photo"), SmartAlbumRule()])
        #expect(query.conditionCount() == 1)
        query.groups = [SmartAlbumRuleGroup()]
        #expect(query.conditionCount() == 2)
    }

    // MARK: Rename / Duplicate (AC-31, AC-32)

    @Test func duplicateNamesCopiesAndKeepsInPhotosOff() throws {
        let database = try AppDatabase.makeEmpty()
        let store = SmartAlbumStore(database: database)
        let query = SmartAlbumQuery(rules: [SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200)],
                                    groups: [SmartAlbumRuleGroup(matchMode: .any, rules: [SmartAlbumRule(field: .lens, op: .contains, text: "85")])])
        try store.upsert(SmartAlbum(id: "night", name: "Night", query: query, createdAt: 1))
        let first = try #require(try store.duplicate(id: "night"))
        let second = try #require(try store.duplicate(id: "night"))
        #expect(first.name == "Night copy")
        #expect(second.name == "Night copy 2")
        #expect(first.query == query && second.query == query)
        let links = SmartAlbumPhotosAlbumStore(database: database)
        // The default-on pass must not turn the copies on.
        try links.addDefaultLinks()
        #expect(try links.isEnabled(first.id) == false)
        #expect(try links.isEnabled(second.id) == false)
        #expect(try store.duplicate(id: "missing") == nil)
    }

    @Test func renameRefusesTakenAndEmptyNames() throws {
        let database = try AppDatabase.makeEmpty()
        let store = SmartAlbumStore(database: database)
        try store.upsert(SmartAlbum(id: "n", name: "Night", query: .empty, createdAt: 1))
        try store.upsert(SmartAlbum(id: "d", name: "Day", query: .empty, createdAt: 2))
        #expect(throws: SmartAlbumStore.NameError.taken("day")) { try store.rename(id: "n", to: " day ") }
        #expect(throws: SmartAlbumStore.NameError.empty) { try store.rename(id: "n", to: "  ") }
        #expect(try store.rename(id: "n", to: "Late")?.name == "Late")
        #expect(try store.fetch(id: "n")?.name == "Late")
        // Its own name, other case, is not "taken".
        #expect(try store.rename(id: "n", to: "LATE")?.name == "LATE")
    }
}
