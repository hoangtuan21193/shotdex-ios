import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §1 — deleting a photo that lives in several places.
@Suite struct MultiCopyDeletionTests {
    /// AC-57: photo A is in Photos (original on device), on T7 and on NAS
    /// Home. Deleted inside T7, only the T7 copy goes to the Trash and A
    /// keeps "2 copies". Deleted from All Photos, the dialog lists Photos
    /// Library (on) and NAS Home (hide) (off); Move removes only the Photos
    /// copy and A stays, on the NAS.
    @Test func onlyViewedSourceThenChecklist() async throws {
        let library = try MixedDeletionTests.library()
        defer { try? FileManager.default.removeItem(at: library.root.deletingLastPathComponent()) }
        let database = library.database
        let a = library.ids[0]
        let t7 = library.folder
        let nas = try #require(try SourceStore(database: database).sources().first { $0.kind == "server" }?.id)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE sources SET kind = 'drive', name = 'T7' WHERE id = ?", arguments: [t7])
            try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId) VALUES ('A-photos', ?, ?, 'photos', 'A-asset')",
                           arguments: [a, PhotoLibrarySource.id])
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES ('A-nas', ?, ?, 'server', 'DSC0.ARW', 'dsc0.arw')
                """, arguments: [a, nas])
        }
        let queries = DeletionTargetQueries(database: database)
        func copies() throws -> Int {
            try database.reader.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE photoId = ? AND missingSince IS NULL", arguments: [a])
            } ?? 0
        }
        #expect(try copies() == 3)

        let inT7 = try queries.targets(photoIds: [a], inSource: t7)
        #expect(inT7.flatMap { $0.map(\.sourceId) } == [t7])
        let first = try await MixedDeletionTests.service(library, photos: { _ in Issue.record("Photos asked") }).run(inT7)
        #expect(first.trashedFiles == 1)
        #expect(try copies() == 2)

        let all = try queries.allCopies(photoIds: [a])
        var checklist = try #require(CopyChecklist(copies: all))
        #expect(checklist.rows.map(\.title) == ["Photos Library", "NAS Home (hide)"])
        #expect(checklist.rows.map(\.isOn) == [true, false])
        let asked = MixedDeletionTests.Recorder()
        let second = try await MixedDeletionTests.service(library, photos: { asked.record($0) }).run(checklist.selected(all))
        #expect(asked.ids == ["A-asset"])
        #expect(second.hidden.isEmpty)
        #expect(try copies() == 1)
        #expect(try LibraryQueries(database: database).count(matching: FilterCriteria()) >= 1)
        let visible = try await database.reader.read { db in
            try Bool.fetchOne(db, sql: "SELECT \(PhotoVisibility.condition) FROM photo_metadata WHERE assetId = ?", arguments: [a])
        }
        #expect(visible == true)

        // Turning the NAS row on hides that copy too.
        checklist.rows[1].isOn = true
        #expect(checklist.selected(all).flatMap { $0.map(\.destination) }.contains(.hide(sourceName: "NAS Home")))

        // Several photos: one row per source, with its count.
        let many = try #require(CopyChecklist(copies: [all[0], all[0]]))
        #expect(many.rows.map(\.count) == [2, 2])
        #expect(CopyChecklist(copies: [[all[0][0]]]) == nil)
    }
}
