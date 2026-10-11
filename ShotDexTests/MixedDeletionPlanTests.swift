import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §1–§2 — what a deletion across sources says it will do.
@Suite struct MixedDeletionPlanTests {
    /// Photos with one copy each in `sourceId`; returns their ids.
    static func addPhotos(_ db: Database, count: Int, sourceId: String, kind: String, prefix: String) throws -> [String] {
        try (0..<count).map { n in
            let id = "\(prefix)-\(n)"
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 1)", arguments: [id])
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey, isOnline)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1)
                """, arguments: ["\(id)-copy", id, sourceId, kind, kind == "photos" ? id : nil,
                                 kind == "photos" ? nil : "\(prefix)/\(n).ARW", kind == "photos" ? nil : "\(prefix)/\(n).arw"])
            return id
        }
    }

    /// AC-40: Cull, 120 Rejected — 84 in a folder, 30 in Photos, 6 on NAS
    /// Home, one copy each. The command is Move 120 Rejected…, the dialog
    /// "Move 120 rejected photos?" counts by destination, carries the
    /// promise line, and its button is Move. No copy checklist: no photo
    /// has two copies.
    @Test func messageCountsByDestination() throws {
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let folder = try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        let ids = try database.writer.write { db in
            try Self.addPhotos(db, count: 84, sourceId: folder, kind: "file", prefix: "F")
                + Self.addPhotos(db, count: 30, sourceId: PhotoLibrarySource.id, kind: "photos", prefix: "P")
                + Self.addPhotos(db, count: 6, sourceId: nas, kind: "server", prefix: "N")
        }
        let queries = DeletionTargetQueries(database: database)
        var plan = try queries.plan(photoIds: ids.shuffled(), selection: .rejected)
        plan.trashName = MixedDeletionPlan.macTrashName

        #expect(plan.count == 120)
        #expect(plan.commandName == "Move 120 Rejected…")
        #expect(plan.needsConfirmation)
        #expect(!plan.needsPermanentConfirmation)
        #expect(plan.title == "Move 120 rejected photos?")
        #expect(plan.message == "84 go to the Trash, 30 to Recently Deleted. 6 on NAS Home can't be deleted from ShotDex and will be hidden.")
        #expect(MixedDeletionPlan.footnote == "ShotDex never edits file contents.")
        #expect(plan.confirmTitle == "Move")
        #expect(try queries.copies(photoIds: ids).values.allSatisfy { $0.count == 1 })

        // iPad, iPhone, Duo: the Trash is Files' Recently Deleted.
        let ipad = try queries.plan(photoIds: Array(ids.prefix(84)), selection: .photos)
        #expect(ipad.message == "84 go to Recently Deleted in Files.")
        #expect(ipad.commandName == "Move 84 Photos…")

        // Only Photos items: the system's dialog alone.
        let photosOnly = try queries.plan(photoIds: Array(ids[84..<114]), selection: .photos)
        #expect(!photosOnly.needsConfirmation)
        #expect(photosOnly.commandName == "Delete 30 Photos")

        // A volume with no Trash: Delete, and the second red dialog.
        let noTrash = DeletionTargetQueries(database: database, hasTrash: { $0 != folder })
        let sd = try noTrash.plan(photoIds: Array(ids.prefix(12)), selection: .photos)
        #expect(sd.commandName == "Delete 12 Photos")
        #expect(sd.needsPermanentConfirmation)
        #expect(sd.permanentTitle == "Delete 12 Photos Permanently?")
        #expect(sd.permanentMessage == "“2026 Japan” has no Trash. These files can't be recovered.")

        // One photo reads as one: "Move 1 photo?", "1 goes to …".
        let one = try queries.plan(photoIds: [ids[0]], selection: .photos)
        #expect(one.title == "Move 1 photo?")
        #expect(one.commandName == "Move 1 Photo…")
        #expect(one.message == "1 goes to Recently Deleted in Files.")
        let lone = try noTrash.plan(photoIds: [ids[0]], selection: .photos)
        #expect(lone.title == "Delete 1 photo?")
        #expect(lone.message == "1 on 2026 Japan is deleted permanently.")
        #expect(lone.permanentTitle == "Delete 1 Photo Permanently?")
        #expect(lone.permanentMessage == "“2026 Japan” has no Trash. This file can't be recovered.")
    }

    /// AC-43: six photos only on NAS Home. The dialog is "Hide 6 photos?"
    /// with a Hide button and no word "delete"; Hide takes them out of the
    /// grid and Statistics, and the files on the server are untouched.
    @Test func allServerIsHide() throws {
        let database = try AppDatabase.makeEmpty()
        let nas = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let ids = try database.writer.write { db in
            let ids = try Self.addPhotos(db, count: 6, sourceId: nas, kind: "server", prefix: "N")
                + Self.addPhotos(db, count: 2, sourceId: PhotoLibrarySource.id, kind: "photos", prefix: "P")
            for id in ids {
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus) VALUES (?, 1, 0, 1, 'indexed')",
                               arguments: [id])
            }
            return Array(ids.prefix(6))
        }
        let queries = DeletionTargetQueries(database: database)
        let plan = try queries.plan(photoIds: ids, selection: .photos)
        #expect(plan.verb == .hide)
        #expect(plan.commandName == "Hide 6 Photos")
        #expect(plan.title == "Hide 6 photos?")
        #expect(plan.message == "Files on NAS Home stay on the server; ShotDex hides them.")
        #expect(plan.confirmTitle == "Hide")
        for text in [plan.commandName, plan.title, plan.message, plan.confirmTitle] {
            #expect(!text.localizedCaseInsensitiveContains("delete"))
        }

        let library = LibraryQueries(database: database)
        #expect(try library.count(matching: FilterCriteria()) == 8)
        try HiddenCopyStore(database: database).hide(copyIds: try queries.targets(photoIds: ids).flatMap { $0.map(\.copyId) })
        #expect(try library.count(matching: FilterCriteria()) == 2)
        #expect(try StatisticsQueries(database: database).totalPhotos(scope: .allTime) == 2)
        #expect(try HiddenCopyStore(database: database).hiddenPhotoIds().sorted() == ids.sorted())
    }
}
