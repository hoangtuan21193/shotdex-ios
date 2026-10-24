import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-06.06b §1 — marks, Keep all, keeper picks and Not duplicates live on
/// disk until the user deletes or undoes them.
struct DuplicateReviewStoreTests {

    private func photo(_ id: String) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id, creationDate: 1_700_000_000, modificationDate: 1_700_000_000,
            mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: nil, cameraModel: nil, normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
            lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil,
            iso: nil, aperture: nil, shutterSpeedSeconds: nil, shutterSpeedDisplay: nil,
            focalLength: nil, focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil,
            sensorFormat: nil, cropFactor: nil, width: 4032, height: 3024, fileSize: 2_000_000,
            latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    /// A database file that outlives the `AppDatabase` opened on it — the
    /// closest a unit test gets to killing the app and launching it again.
    private func withRelaunch(_ body: (_ open: () throws -> AppDatabase) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dup-review-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try body { try AppDatabase(DatabaseQueue(path: url.path)) }
    }

    @Test func marksSurviveRelaunch() throws {
        try withRelaunch { open in
            do {
                let database = try open()
                for id in ["a", "b", "c"] { try MetadataStore(database: database).upsert(photo(id)) }
                try DuplicateReviewStore(database: database).setMarked(["a", "b"], true)
            }
            let state = try DuplicateReviewStore(database: try open()).load()
            #expect(state.marks == ["a", "b"])
        }
    }

    @Test func unmarkRemovesOnlyThatPhoto() throws {
        let store = DuplicateReviewStore(database: try AppDatabase.makeEmpty())
        try store.setMarked(["a", "b"], true)
        try store.setMarked(["a"], false)
        #expect(try store.load().marks == ["b"])
    }

    @Test func deletedPhotoDropsItsMark() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        for id in ["a", "b", "c"] { try metadata.upsert(photo(id)) }
        let store = DuplicateReviewStore(database: database)
        try store.setMarked(["a", "b"], true)
        try store.addSet(.keepAll, members: ["b", "c"])

        // Deleted in Photos: the library-change path drops the index row.
        try metadata.deleteAssets(ids: ["a"])
        // Deleted here: the model forgets it at once.
        try store.forget(assetIds: ["b"])

        let state = try store.load()
        #expect(state.marks.isEmpty)
        #expect(state.keptAll.map(\.members) == [["c"]])
    }

    /// Clear Index empties `photo_metadata`; the user's work must not go with it.
    @Test func clearIndexKeepsReviewRows() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        for id in ["a", "b"] { try metadata.upsert(photo(id)) }
        let store = DuplicateReviewStore(database: database)
        try store.setMarked(["a"], true)
        try store.setKeeper("b", groupMembers: ["a", "b"])
        try metadata.deleteAll()
        let state = try store.load()
        #expect(state.marks == ["a"])
        #expect(state.keepers == ["b"])
    }

    @Test func keepAllAndKeeperOverrideSurviveRelaunch() throws {
        try withRelaunch { open in
            do {
                let store = DuplicateReviewStore(database: try open())
                try store.addSet(.keepAll, members: ["a", "b"])
                try store.setKeeper("y", groupMembers: ["x", "y", "z"])
                try store.addSet(.collapsed, members: ["x", "y", "z"])
            }
            let state = try DuplicateReviewStore(database: try open()).load()
            #expect(state.isKeptAll(["a", "b"]))
            #expect(state.keeper(among: ["x", "y", "z"]) == "y")
            #expect(state.isCollapsed(["x", "y", "z"]))
        }
    }

    @Test func newKeeperReplacesTheOldOne() throws {
        let store = DuplicateReviewStore(database: try AppDatabase.makeEmpty())
        try store.setKeeper("x", groupMembers: ["x", "y"])
        try store.setKeeper("y", groupMembers: ["x", "y"])
        #expect(try store.load().keepers == ["y"])
    }

    /// AC-N1 / AC-N2: a dismissal is a set of photos, so it outlives the group
    /// id a regroup mints — and a newcomer brings the group back.
    @Test func dismissalSurvivesRegroup() throws {
        let store = DuplicateReviewStore(database: try AppDatabase.makeEmpty())
        let setId = try store.addSet(.notDuplicates, members: ["a", "b"])
        let state = try store.load()

        #expect(state.dismissal(of: ["a", "b"]) == .hidden(setId: setId))
        #expect(state.dismissal(of: ["a", "b", "c"]) == .newPhotoSince(setId: setId))
        #expect(state.dismissal(of: ["a", "d"]) == nil)

        try store.removeSet(.notDuplicates, id: setId)
        #expect(try store.load().dismissal(of: ["a", "b"]) == nil)
    }

    @Test func removeSetsContainingAnyMember() throws {
        let store = DuplicateReviewStore(database: try AppDatabase.makeEmpty())
        try store.addSet(.keepAll, members: ["a", "b"])
        try store.addSet(.keepAll, members: ["c", "d"])
        try store.removeSets(.keepAll, containingAnyOf: ["b"])
        #expect(try store.load().keptAll.map(\.members) == [["c", "d"]])
    }

    @Test func unknownRoleRowIsSkipped() throws {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO duplicate_review (role, setId, assetId, createdAt) VALUES ('future', '', 'z', 0)")
        }
        let store = DuplicateReviewStore(database: database)
        try store.setMarked(["a"], true)
        #expect(try store.load().marks == ["a"])
    }

    /// The session updates at once and writes in order behind the scenes;
    /// a fresh session (a relaunch) reads back exactly what the user did.
    @MainActor @Test func sessionWritesThroughInOrder() throws {
        let database = try AppDatabase.makeEmpty()
        let session = DuplicateReviewSession(store: DuplicateReviewStore(database: database))
        session.setMarks(of: ["a", "b", "c"], to: ["b", "c"])
        session.setKeeper("a", groupMembers: ["a", "b", "c"])
        session.setKeptAll(["x", "y"], true)
        session.setMarked(["c"], false)
        session.dismiss(["p", "q"])
        #expect(session.marks == ["b"])
        session.flushWrites()

        let relaunched = DuplicateReviewSession(store: DuplicateReviewStore(database: database))
        #expect(relaunched.marks == ["b"])
        #expect(relaunched.keeper(among: ["a", "b", "c"]) == "a")
        #expect(relaunched.isKeptAll(["x", "y"]))
        #expect(relaunched.notDuplicates.map(\.id) == session.notDuplicates.map(\.id))
    }

    /// The keeper takes a mark like any other photo: a group can be marked
    /// whole, and the card still has a photo to put in the big slot
    /// (user, 2026-10-24 — the keep-one gate is gone).
    @MainActor @Test func everyPhotoOfAGroupCanBeMarked() {
        let model = DuplicatesModel(dependencies: AppDependencies.preview())
        let hashed = { (id: String) in
            HashedPhoto(assetId: id, hash: PerceptualHash(bits: 1), width: 6000, height: 4000,
                        fileSize: 10_000_000, creationDate: 1_700_000_000, isFavorite: false)
        }
        let group = DuplicateGroup(members: [hashed("dup-a"), hashed("dup-b")], kind: .similar)
        model.clearMarks(in: group)
        let keeper = model.keeper(of: group)!.assetId
        let copy = group.members.first { $0.assetId != keeper }!.assetId
        model.toggleMark(copy, in: group)
        model.toggleMark(keeper, in: group)
        #expect(model.isMarked(keeper))
        #expect(model.isMarked(copy))
        #expect(model.markedCount(in: group) == 2)
        #expect(model.keeper(of: group) != nil)
        // And back: unmarking still works one tile at a time.
        model.toggleMark(keeper, in: group)
        #expect(!model.isMarked(keeper))
        model.toggleMark(copy, in: group)
    }
}
