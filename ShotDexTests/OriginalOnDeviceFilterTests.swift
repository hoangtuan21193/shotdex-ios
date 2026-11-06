import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-06.10 AC-11 — the Filter menu's "Original on This iPhone": the same
/// positive match as the Original rule, one source with Advanced, and kept
/// when the filter is saved as a smart album.
@MainActor
struct OriginalOnDeviceFilterTests {
    private static var onDevice: FilterCriteria {
        var criteria = FilterCriteria()
        criteria.originalOnDeviceOnly = true
        return criteria
    }

    /// 100 photos: 60 on the device, 30 only in iCloud, 10 never checked.
    private static func library() throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<100).map { "P\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, favorite: $0 % 2 == 0, created: 1_700_000_000 + $0) },
            cursorAssetId: nil)
        let store = OriginalPresenceStore(database: database)
        try store.record(Dictionary(uniqueKeysWithValues: ids.prefix(60).map { ($0, .onDevice) }), at: 10)
        try store.record(Dictionary(uniqueKeysWithValues: ids[60..<90].map { ($0, .iCloudOnly) }), at: 10)
        return database
    }

    /// AC-11, data side: the toggle leaves the 60 on the device; unchecked
    /// and iCloud-only photos are out.
    @Test func togglesToThePhotosOnTheDevice() async throws {
        let database = try Self.library()
        let queries = LibraryQueries(database: database)
        let ids = try await queries.gridItems(matching: Self.onDevice, sort: .dateTakenNewest).map(\.assetId)
        #expect(ids.count == 60)
        #expect(Set(ids) == Set((0..<60).map { "P\($0)" }))
        #expect(try await queries.count(matchingAll: [.criteria(Self.onDevice)]) == 60)

        // ANDs with the other quick filters: the even ones are favorites.
        var both = Self.onDevice
        both.favoritesOnly = true
        #expect(try await queries.count(matchingAll: [.criteria(both)]) == 30)

        // The album path asks Photos by identifier: the same 60.
        #expect(Set(try await queries.originalOnDeviceIds()) == Set((0..<60).map { "P\($0)" }))
    }

    /// A photo marked for a recheck drops out until it is checked again.
    @Test func recheckDropsOutUntilCheckedAgain() async throws {
        let database = try Self.library()
        try OriginalPresenceStore(database: database).markForRecheck(["P0"])
        #expect(try await LibraryQueries(database: database).count(matchingAll: [.criteria(Self.onDevice)]) == 59)
    }

    @Test func countsAsOneCondition() {
        #expect(FilterCriteria().isEmpty)
        #expect(!Self.onDevice.isEmpty)
        #expect(Self.onDevice.activeConditionCount == 1)
    }

    /// AC-11: turning the toggle on clears an advanced query, in Library and
    /// in an album; an advanced query clears the toggle.
    @Test func exclusiveWithAdvancedQuery() {
        let iso = SmartAlbumQuery(matchMode: .all, rules: [SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200)])

        let model = LibraryModel(dependencies: AppDependencies.preview())
        model.advancedQuery = iso
        model.criteria = Self.onDevice
        #expect(model.advancedQuery == nil)
        #expect(model.criteria.originalOnDeviceOnly)
        model.advancedQuery = iso
        #expect(model.criteria.isEmpty)

        var filter = AlbumFilter()
        filter.setAdvancedQuery(iso)
        filter.setCriteria(Self.onDevice)
        #expect(filter.advancedQuery == nil)
        #expect(filter.criteria.originalOnDeviceOnly)
        filter.setAdvancedQuery(iso)
        #expect(filter.criteria.isEmpty)
    }

    /// The chip carries the toggle's words, and × turns the toggle off.
    @Test func chipReadsTheToggleTitle() throws {
        let token = try #require(FilterTokenBar.tokens(for: Self.onDevice).first { $0.id == "originalOnDevice" })
        #expect(token.label == OriginalPresence.filterTitle)
        var criteria = Self.onDevice
        token.clear(&criteria)
        #expect(criteria.isEmpty)
    }

    /// Album path: Photos is asked by identifier, so the predicate carries the
    /// check's ids — none yet matches none — and the flag needs no index.
    @Test func albumPredicateUsesTheCheckedIds() throws {
        let predicate = try #require(AlbumFilterPredicate.predicate(for: Self.onDevice, originalOnDeviceIds: ["A", "B"]))
        #expect(predicate.predicateFormat.contains("localIdentifier IN"))
        #expect(predicate.predicateFormat.contains("\"A\""))
        let none = try #require(AlbumFilterPredicate.predicate(for: Self.onDevice))
        #expect(none.predicateFormat == "FALSEPREDICATE")
        #expect(!AlbumFilterPredicate.needsIndex(Self.onDevice))
    }

    /// "Save as Smart Album" keeps the toggle as the rule it stands for, and
    /// the saved album finds the same 60.
    @Test func savingKeepsTheRule() async throws {
        let query = SmartAlbumQuery.migrating(Self.onDevice)
        #expect(query.rules.count == 1)
        #expect(query.rules.first?.field == .original)
        #expect(query.rules.first?.op == .isExactly)
        #expect(query.rules.first?.text == OriginalPresence.onDevice.rawValue)
        #expect(query.usesOriginal)

        let database = try Self.library()
        #expect(try await LibraryQueries(database: database).count(matching: query) == 60)
    }

    /// Persisted inside smart albums' legacy JSON and the Library's restore:
    /// the flag survives a round trip, and an older payload without it
    /// decodes as off.
    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.onDevice)
        #expect(try JSONDecoder().decode(FilterCriteria.self, from: data) == Self.onDevice)
        let older = try JSONDecoder().decode(FilterCriteria.self, from: Data(#"{"favoritesOnly":true}"#.utf8))
        #expect(!older.originalOnDeviceOnly)
        let wrongType = try JSONDecoder().decode(FilterCriteria.self, from: Data(#"{"originalOnDeviceOnly":"yes"}"#.utf8))
        #expect(!wrongType.originalOnDeviceOnly)
    }

    /// A merged photo: its Photos copy has a PhotoKit id that is not the
    /// photo's own id. Library answers in photo ids, an album in PhotoKit ids;
    /// the two must name the same photos.
    @Test func mergedPhotoAgreesAcrossLibraryAndAlbum() async throws {
        let database = try AppDatabase.makeEmpty()
        let ids = (0..<4).map { "P\($0)" }
        try MetadataStore(database: database).saveBatch(
            ids.enumerated().map { PhotoMarksStoreTests.record($1, created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE photo_copies SET photoKitId = 'K-P0' WHERE photoId = 'P0' AND kind = 'photos'")
        }
        try OriginalPresenceStore(database: database).record(["K-P0": .onDevice, "P1": .onDevice, "P2": .iCloudOnly], at: 10)

        let queries = LibraryQueries(database: database)
        let library = Set(try await queries.gridItems(matching: Self.onDevice, sort: .dateTakenNewest).map(\.assetId))
        #expect(library == ["P0", "P1"])
        let album = try await queries.originalOnDeviceIds()
        #expect(album == ["K-P0", "P1"])
        let libraryAsPhotoKit = try await database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT photoKitId FROM photo_copies WHERE kind = 'photos' AND photoId IN ('P0', 'P1') ORDER BY photoKitId
                """)
        }
        #expect(libraryAsPhotoKit == album)
    }
}

/// The screen side of the toggle: open/close stay paired, batches reload at
/// most once per 3 s, nothing is lost while the screen is covered or while a
/// reload runs.
@MainActor
struct OriginalOnDeviceReloaderTests {
    @MainActor
    final class Probe {
        var opens = 0
        var closes = 0
        var reloads = 0
        var clock = Date(timeIntervalSince1970: 1_000)
        var slept: [Duration] = []
        /// Held open to simulate a reload still in flight.
        var reloadGate: CheckedContinuation<Void, Never>?
        var holdsReloads = false

        func reloader() -> OriginalOnDeviceReloader {
            OriginalOnDeviceReloader(hooks: .init(
                open: { self.opens += 1 },
                close: { self.closes += 1 },
                reload: {
                    self.reloads += 1
                    if self.holdsReloads { await withCheckedContinuation { self.reloadGate = $0 } }
                },
                now: { self.clock },
                sleep: { duration in
                    self.slept.append(duration)
                    self.clock += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                }
            ))
        }
    }

    private static func settle(_ reloader: OriginalOnDeviceReloader) async {
        for _ in 0..<50 where reloader.reloadTask != nil { await Task.yield() }
        await reloader.reloadTask?.value
    }

    @Test func opensAndClosesInPairs() {
        let probe = Probe()
        let reloader = probe.reloader()
        reloader.update(isActive: false, isOnScreen: true, isPaused: false, generation: 0)
        #expect(probe.opens == 0)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 0)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 1)
        #expect(probe.opens == 1)
        reloader.update(isActive: true, isOnScreen: false, isPaused: false, generation: 1)
        reloader.update(isActive: false, isOnScreen: false, isPaused: false, generation: 1)
        #expect(probe.closes == 1)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 1)
        reloader.update(isActive: false, isOnScreen: true, isPaused: false, generation: 1)
        #expect(probe.opens == 2 && probe.closes == 2)
    }

    /// Turning the toggle on is its own reload; only later batches reload,
    /// and the second within 3 s waits out the rest of the interval.
    @Test func reloadsLaterBatchesThrottled() async {
        let probe = Probe()
        let reloader = probe.reloader()
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 5)
        await Self.settle(reloader)
        #expect(probe.reloads == 0)

        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 6)
        await Self.settle(reloader)
        #expect(probe.reloads == 1)
        #expect(probe.slept.isEmpty)

        probe.clock += 1
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 7)
        await Self.settle(reloader)
        #expect(probe.reloads == 2)
        #expect(probe.slept == [.seconds(2)])
        #expect(reloader.seenGeneration == 7)
    }

    /// Batches that land while the viewer covers the grid — even the last one
    /// of the pass — are caught up with one reload on return.
    @Test func catchesUpAfterBeingCovered() async {
        let probe = Probe()
        let reloader = probe.reloader()
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 1)
        reloader.update(isActive: true, isOnScreen: false, isPaused: false, generation: 1)
        for generation in 2...9 {
            reloader.update(isActive: true, isOnScreen: false, isPaused: false, generation: generation)
        }
        await Self.settle(reloader)
        #expect(probe.reloads == 0)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 9)
        await Self.settle(reloader)
        #expect(probe.reloads == 1)
        #expect(reloader.seenGeneration == 9)
    }

    /// Selection holds reloads; ending it catches up.
    @Test func holdsWhileSelecting() async {
        let probe = Probe()
        let reloader = probe.reloader()
        reloader.update(isActive: true, isOnScreen: true, isPaused: true, generation: 1)
        reloader.update(isActive: true, isOnScreen: true, isPaused: true, generation: 2)
        await Self.settle(reloader)
        #expect(probe.reloads == 0)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 2)
        await Self.settle(reloader)
        #expect(probe.reloads == 1)
    }

    /// A batch landing mid-reload — the pass's last bump — gets its own
    /// reload once the running one finishes.
    @Test func batchDuringReloadIsNotLost() async {
        let probe = Probe()
        probe.holdsReloads = true
        let reloader = probe.reloader()
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 1)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 2)
        for _ in 0..<50 where probe.reloadGate == nil { await Task.yield() }
        #expect(probe.reloads == 1)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 3)
        probe.holdsReloads = false
        probe.reloadGate?.resume()
        await Self.settle(reloader)
        #expect(probe.reloads == 2)
        #expect(reloader.seenGeneration == 3)
    }

    /// Turning the toggle off forgets where it was: turning it on again starts
    /// from the current batch without an extra reload.
    @Test func offForgetsTheGeneration() async {
        let probe = Probe()
        let reloader = probe.reloader()
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 1)
        reloader.update(isActive: false, isOnScreen: true, isPaused: false, generation: 4)
        #expect(reloader.seenGeneration == nil)
        reloader.update(isActive: true, isOnScreen: true, isPaused: false, generation: 4)
        await Self.settle(reloader)
        #expect(probe.reloads == 0)
    }
}
