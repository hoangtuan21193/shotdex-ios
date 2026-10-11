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
    }
}
