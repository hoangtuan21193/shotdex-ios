import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.02 §7 — sidecars of copies that cannot be written now.
@MainActor
@Suite struct PendingSidecarTests {
    /// One photo, A, with a copy on the internal drive and one on T7.
    struct TwoCopies {
        let base: URL
        let internalFolder: URL
        let t7: URL
        let database: AppDatabase
        let t7Id: String
        let photoId: String
        let roots: [String: URL]
        let queue: SidecarWriteQueue
        let marks: PhotoMarks

        func pendingCount() throws -> Int {
            try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sidecar") ?? -1 }
        }
    }

    static func twoCopies() throws -> TwoCopies {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Pending-\(UUID().uuidString)", isDirectory: true)
        let internalFolder = base.appendingPathComponent("Pictures"), t7 = base.appendingPathComponent("T7")
        var options = MetadataFixture.Options()
        options.starRating = nil
        let raw = try MetadataFixture.encode(.tiff, options: options)
        for folder in [internalFolder, t7] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try raw.write(to: folder.appendingPathComponent("A.ARW"))
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let internalId = try sources.addFolder(name: "Pictures", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let t7Id = try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let roots = [internalId: internalFolder, t7Id: t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        let fileURL: @Sendable (String, String) -> URL? = { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }
        _ = try IdentityMergePass(database: database, fileURL: fileURL).run()
        let photoId = try #require(try database.reader.read { db in try String.fetchOne(db, sql: "SELECT id FROM photos") })
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database, fileURL: fileURL))
        return TwoCopies(base: base, internalFolder: internalFolder, t7: t7, database: database, t7Id: t7Id, photoId: photoId,
                         roots: roots, queue: queue, marks: PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue))
    }

    /// AC-29: A has a copy on the internal drive and on T7; T7 is unplugged.
    /// ★5, then ★3: the internal sidecar says ★3, nothing is written on T7,
    /// and one pending mark stands for the T7 copy. Clear Local Metadata
    /// Index keeps it — it is user data.
    @Test func offlineCopyMarkedSurvivesClear() async throws {
        let library = try Self.twoCopies()
        defer { try? FileManager.default.removeItem(at: library.base) }
        try SourceStore(database: library.database).setOnline(false, sourceId: library.t7Id)

        await library.marks.setRating(5, ids: [library.photoId])
        await library.queue.flush()
        await library.marks.setRating(3, ids: [library.photoId])
        await library.queue.flush()

        #expect(SidecarReader.read(sidecarAt: library.internalFolder.appendingPathComponent("A.xmp"))?.rating == 3)
        #expect(!FileManager.default.fileExists(atPath: library.t7.appendingPathComponent("A.xmp").path))
        #expect(try library.pendingCount() == 1)
        let pendingCopy = try await library.database.reader.read { db in
            try String.fetchOne(db, sql: """
                SELECT c.sourceId FROM pending_sidecar p JOIN photo_copies c ON c.id = p.copyId
                """)
        }
        #expect(pendingCopy == library.t7Id)

        try MetadataStore(database: library.database).deleteAll()
        #expect(try library.pendingCount() == 1)
    }
}
