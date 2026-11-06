import Foundation
import GRDB
import Testing
@testable import ShotDex

/// A photo library with albums and nothing else.
actor FakePhotosAlbums: PhotosAlbumWriting {
    var albums: [String: (title: String, ids: [String])] = [:]
    var writes: [Int] = []
    var failNextWrite = false
    private var next = 0

    func seed(_ id: String, title: String, ids: [String]) { albums[id] = (title, ids) }
    func delete(_ id: String) { albums[id] = nil }
    func edit(_ id: String, adding: [String] = [], removing: [String] = [], droppingLast: Int = 0) {
        guard var a = albums[id] else { return }
        a.ids.removeAll { removing.contains($0) }
        a.ids.removeLast(droppingLast)
        a.ids += adding
        albums[id] = a
    }
    func count(_ id: String) -> Int? { albums[id]?.ids.count }
    func ids(_ id: String) -> [String]? { albums[id]?.ids }
    func albumTitle(_ id: String) -> String? { albums[id]?.title }
    var albumCount: Int { albums.count }
    func failOnce() { failNextWrite = true }

    var missing: Set<String> = []
    func forget(_ ids: [String]) { missing.formUnion(ids) }
    func existing(_ ids: [String]) async -> Set<String> { Set(ids).subtracting(missing) }
    func albumExists(_ id: String) async -> Bool { albums[id] != nil }
    func title(of id: String) async -> String? { albums[id]?.title }
    func assetIds(in id: String) async -> [String] { albums[id]?.ids ?? [] }
    func createAlbum(named name: String) async throws -> String {
        next += 1
        let id = "album\(next)"
        albums[id] = (name, [])
        return id
    }
    func rename(_ id: String, to name: String) async throws { albums[id]?.title = name }
    func add(_ assetIds: [String], to id: String) async throws {
        try write(assetIds.count)
        guard var album = albums[id] else { return }
        let have = Set(album.ids)
        album.ids += assetIds.filter { !have.contains($0) }
        albums[id] = album
    }
    func remove(_ assetIds: [String], from id: String) async throws {
        try write(assetIds.count)
        let gone = Set(assetIds)
        albums[id]?.ids.removeAll { gone.contains($0) }
    }
    private func write(_ count: Int) throws {
        if failNextWrite { failNextWrite = false; throw PhotosAlbumSyncError.albumNotEditable }
        writes.append(count)
    }
}

/// FS-06.12: Keep in Photos keeps one real album equal to the smart album.
@MainActor
struct PhotosAlbumSyncTests {
    let database: AppDatabase
    let photos = FakePhotosAlbums()
    let sync: PhotosAlbumSync
    let links: SmartAlbumPhotosAlbumStore
    static let favorites = SmartAlbumQuery(rules: [SmartAlbumRule(field: .favorite, boolValue: true)])

    init() throws {
        database = try AppDatabase.makeEmpty()
        sync = PhotosAlbumSync(database: database, writer: photos, canWrite: { true }, minimumGap: .zero)
        links = SmartAlbumPhotosAlbumStore(database: database)
    }

    /// `count` Photos items P0…, the first `favorites` of them favorites.
    func library(_ count: Int, favorites: Int) throws {
        try MetadataStore(database: database).saveBatch(
            (0..<count).map { PhotoMarksStoreTests.record("P\($0)", favorite: $0 < favorites, created: 1_700_000_000 + $0) },
            cursorAssetId: nil)
    }

    func setFavorites(_ ids: [String], _ value: Bool) throws {
        try database.writer.write { db in
            for id in ids { try db.execute(sql: "UPDATE photo_metadata SET isFavorite = ? WHERE assetId = ?", arguments: [value, id]) }
        }
    }

    func album(_ name: String = "Shared NAS", keep: Bool = true) throws {
        try SmartAlbumStore(database: database).upsert(SmartAlbum(id: "S", name: name, query: Self.favorites, createdAt: 1))
        if keep { try links.setEnabled(true, smartAlbumId: "S") }
    }

    func link() throws -> SmartAlbumPhotosAlbum { try #require(try links.link("S")) }

    func kept() async throws -> (title: String, ids: Set<String>) {
        let id = try #require(try link().collectionLocalId)
        let title = try #require(await photos.albumTitle(id))
        let ids = try #require(await photos.ids(id))
        return (title, Set(ids))
    }

    /// AC-2: turning it on makes an album of the same name with exactly the
    /// 120 matching photos, and the link reads synced with 120.
    @Test func createsAndFills() async throws {
        try library(150, favorites: 120)
        try album()
        await sync.syncNow()
        let kept = try await kept()
        #expect(kept.title == "Shared NAS")
        #expect(kept.ids == Set((0..<120).map { "P\($0)" }))
        #expect(try link().state == .synced && link().assetCount == 120 && link().lastSyncedAt != nil)
    }

    /// AC-3: a user album of the same name is never adopted or touched.
    @Test func neverAdoptsUserAlbum() async throws {
        try library(10, favorites: 4)
        await photos.seed("mine", title: "Shared NAS", ids: ["X1", "X2", "X3", "X4", "X5"])
        try album()
        await sync.syncNow()
        #expect(try link().collectionLocalId != "mine")
        #expect(await photos.count("mine") == 5)
    }

    /// AC-4: 30 new matches and 4 that stopped matching; the 4 stay in the
    /// library, they only leave the album.
    @Test func followsMatchChanges() async throws {
        try library(200, favorites: 120)
        try album()
        await sync.syncNow()
        try setFavorites((120..<150).map { "P\($0)" }, true)
        try setFavorites((0..<4).map { "P\($0)" }, false)
        await sync.syncNow()
        let kept = try await kept()
        #expect(kept.ids.count == 146)
        #expect(!kept.ids.contains("P0") && kept.ids.contains("P149"))
        #expect(try await database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM photo_metadata") } == 200)
    }

    /// AC-5: hand edits in Photos are overwritten.
    @Test func overwritesManualEdits() async throws {
        try library(130, favorites: 120)
        try album()
        await sync.syncNow()
        let id = try #require(try link().collectionLocalId)
        await photos.edit(id, adding: ["P125", "P126", "P127"], removing: ["P0", "P1"])
        await sync.syncNow()
        #expect(try await kept().ids == Set((0..<120).map { "P\($0)" }))
    }

    /// AC-7: items that live only on a server (no PHAsset) are left out.
    @Test func ignoresNonPhotosItems() async throws {
        let f = try OnServerFixture(photos: 50)
        let sync = PhotosAlbumSync(database: f.database, writer: photos, canWrite: { true }, minimumGap: .zero)
        for n in 0..<8 { try f.server("Shared/NAS_\(n).JPG", size: Int64(n), sha: "s\(n)") }
        try await f.database.writer.write { db in try db.execute(sql: "UPDATE photo_metadata SET isFavorite = 1") }
        try SmartAlbumStore(database: f.database).upsert(SmartAlbum(id: "S", name: "All", query: Self.favorites, createdAt: 1))
        let links = SmartAlbumPhotosAlbumStore(database: f.database)
        try links.setEnabled(true, smartAlbumId: "S")
        await sync.syncNow()
        let id = try #require(try links.link("S")?.collectionLocalId)
        #expect(await photos.count(id) == 50)
        #expect(try links.link("S")?.state == .synced)
    }

    /// AC-8: off leaves the album alone; a new match does not reach it.
    @Test func offLeavesAlbum() async throws {
        try library(130, favorites: 120)
        try album()
        await sync.syncNow()
        try links.setEnabled(false, smartAlbumId: "S")
        try setFavorites((120..<125).map { "P\($0)" }, true)
        await sync.syncNow()
        #expect(try await kept().ids.count == 120)
    }

    /// AC-9 (store half): deleting the smart album drops its link, the album
    /// in Photos keeps its photos.
    @Test func deleteKeepsPhotosAlbum() async throws {
        try library(130, favorites: 120)
        try album()
        await sync.syncNow()
        let id = try #require(try link().collectionLocalId)
        try SmartAlbumStore(database: database).delete(id: "S")
        #expect(try links.link("S") == nil)
        #expect(await photos.count(id) == 120)
    }

    /// AC-10: deleted in Photos while kept → switch off, no new album.
    @Test func deletedInPhotosTurnsOff() async throws {
        try library(20, favorites: 10)
        try album()
        await sync.syncNow()
        let id = try #require(try link().collectionLocalId)
        await photos.delete(id)
        await sync.syncNow()
        #expect(try link().isEnabled == false && link().state == .deletedInPhotos)
        #expect(await photos.albumCount == 0)
    }

    /// AC-12: 1,234 matches go in runs of at most 500; a killed pass is
    /// finished by the next one with no duplicates.
    @Test func batchesAndResumes() async throws {
        try library(1_234, favorites: 1_234)
        try album()
        await sync.syncNow()
        #expect(await photos.writes == [500, 500, 234])
        let id = try #require(try link().collectionLocalId)
        await photos.edit(id, droppingLast: 700)
        await sync.syncNow()
        let kept = try await kept()
        #expect(kept.ids.count == 1_234)
        #expect(await photos.count(id) == 1_234)
    }

    /// AC-13: a failed write marks the link failed; the next pass completes.
    @Test func retriesAfterError() async throws {
        try library(700, favorites: 700)
        try album()
        await photos.failOnce()
        await sync.syncNow()
        #expect(try link().state == .failed)
        await sync.syncNow()
        #expect(try link().state == .synced)
        #expect(try await kept().ids.count == 700)
    }

    /// AC-15: renaming the smart album renames the album in Photos.
    @Test func followsRename() async throws {
        try library(5, favorites: 5)
        try album()
        await sync.syncNow()
        try album("Family NAS", keep: false)
        await sync.syncNow()
        #expect(try await kept().title == "Family NAS")
    }

    /// AC-17: on again reuses the old album when it is still there, and makes
    /// a new one when it was deleted meanwhile.
    @Test func reenableReusesAlbum() async throws {
        try library(130, favorites: 120)
        try album()
        await sync.syncNow()
        let id = try #require(try link().collectionLocalId)
        try links.setEnabled(false, smartAlbumId: "S")
        await photos.edit(id, adding: ["P125", "P126"])
        try links.setEnabled(true, smartAlbumId: "S")
        await sync.syncNow()
        #expect(try link().collectionLocalId == id)
        #expect(await photos.albumCount == 1)
        #expect(try await kept().ids.count == 120)
        try links.setEnabled(false, smartAlbumId: "S")
        await photos.delete(id)
        try links.setEnabled(true, smartAlbumId: "S")
        await sync.syncNow()
        #expect(try link().collectionLocalId != id && link().isEnabled)
        #expect(try await kept().ids.count == 120)
    }

    /// Review fix: ids Photos no longer has are left out, so the pass settles
    /// on synced with the real count instead of re-adding them forever.
    @Test func unresolvableIdsSettle() async throws {
        try library(20, favorites: 20)
        await photos.forget(["P3", "P7"])
        try album()
        await sync.syncNow()
        #expect(try link().state == .synced && link().assetCount == 18)
        let writes = await photos.writes.count
        await sync.syncNow()
        #expect(await photos.writes.count == writes)
    }

    /// Review fix: without Full Access nothing is written and the link says why.
    @Test func limitedAccessSaysSo() async throws {
        try library(5, favorites: 5)
        try album()
        let limited = PhotosAlbumSync(database: database, writer: photos, canWrite: { false }, minimumGap: .zero)
        await limited.syncNow()
        #expect(try link().state == .needsFullAccess)
        #expect(await photos.albumCount == 0)
    }

    /// Review fix (🔴): a pass never writes the switch back on, nor a link
    /// back for a smart album deleted meanwhile.
    @Test func passNeverRevivesALink() async throws {
        try library(5, favorites: 5)
        try album()
        var stale = try link()
        try links.setEnabled(false, smartAlbumId: "S")
        stale.state = .synced
        #expect(try links.recordSync(stale) == false)
        #expect(try link().isEnabled == false)
        try SmartAlbumStore(database: database).delete(id: "S")
        #expect(try links.recordSync(stale) == false)
        #expect(try links.link("S") == nil)
    }

    /// Review fix: no condition (or one that compiles to nothing) keeps no
    /// photos rather than the whole library.
    @Test func emptyQueryKeepsNothing() throws {
        try library(10, favorites: 10)
        #expect(try links.photoKitIds(matching: .empty).isEmpty)
        let blank = SmartAlbumQuery(rules: [SmartAlbumRule(field: .caption, op: .contains, text: "  ")])
        #expect(try links.photoKitIds(matching: blank).isEmpty)
        #expect(try links.photoKitIds(matching: Self.favorites).count == 10)
    }

    /// The diff keeps the smart album's order and splits into runs.
    @Test func diffAndBatches() {
        let diff = PhotosAlbumDiff(target: ["a", "b", "c", "b"], current: ["c", "x"])
        #expect(diff.add == ["a", "b"] && diff.remove == ["x"])
        #expect(PhotosAlbumDiff.batches(Array(repeating: "z", count: 1_001)).map(\.count) == [500, 500, 1])
    }
}
