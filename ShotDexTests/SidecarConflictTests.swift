import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.02 §6 — a sidecar another app writes while ShotDex holds the photo.
@MainActor
@Suite struct SidecarConflictTests {
    /// A folder with one RAW and its Lightroom sidecar, read into a fresh
    /// library, plus the marks and the write queue a test drives.
    struct Library {
        let root: URL
        let database: AppDatabase
        let marks: PhotoMarks
        let queue: SidecarWriteQueue
        let photoId: String
        var sidecar: URL { root.appendingPathComponent("A.xmp") }
    }

    static func library(sidecar: Data, modified: Date) throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var options = MetadataFixture.Options()
        options.starRating = nil
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("A.ARW"))
        let url = root.appendingPathComponent("A.xmp")
        try sidecar.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let photoId = try #require(try database.reader.read { db in try String.fetchOne(db, sql: "SELECT id FROM photos") })
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database) { _, path in root.appendingPathComponent(path) })
        return Library(root: root, database: database, marks: PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue),
                       queue: queue, photoId: photoId)
    }

    /// Lightroom writes the sidecar behind ShotDex's back.
    static func overwrite(_ url: URL, with data: Data, modified: Date) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    /// AC-26: ShotDex read A ★3. Lightroom then rewrites A's sidecar as ★3
    /// with the keyword "Nara". Pick in ShotDex rereads the sidecar before
    /// writing: the sidecar ends with ★3, "Nara" and Pick in ShotDex's
    /// namespace, and ShotDex shows "Nara".
    @Test func rereadsBeforeWrite() async throws {
        let read = Date(timeIntervalSince1970: 1_790_000_000)
        let library = try Self.library(sidecar: SidecarReaderTests.lightroomSidecar(rating: 3), modified: read)
        defer { try? FileManager.default.removeItem(at: library.root) }
        try Self.overwrite(library.sidecar, with: SidecarReaderTests.lightroomSidecar(rating: 3, keywords: ["Nara"]),
                           modified: read.addingTimeInterval(60))

        await library.marks.setFlag(.pick, ids: [library.photoId])
        #expect(await library.queue.flush().written == 1)

        let values = try #require(SidecarReader.read(sidecarAt: library.sidecar))
        #expect(values.rating == 3)
        #expect(values.keywords == ["Nara"])
        let text = try String(contentsOf: library.sidecar, encoding: .utf8)
        #expect(text.contains(#"shotdex:Flag="pick""#))
        #expect(text.contains(#"crs:Exposure2012="+1.00""#))
        var criteria = FilterCriteria()
        criteria.searchText = "Nara"
        #expect(try LibraryQueries(database: library.database).count(matching: criteria) == 1)
    }

    /// AC-27: ShotDex sets A ★4; five seconds later, before ShotDex writes,
    /// Lightroom writes A's sidecar as ★2. The later change wins: the sidecar
    /// and ShotDex both say ★2. The other way round — Lightroom's ★2 five
    /// seconds before ShotDex's ★4 — ★4 wins in both.
    @Test func sameFieldLastWriterWins() async throws {
        for (offset, expected) in [(5.0, 2), (-5.0, 4)] {
            let library = try Self.library(sidecar: SidecarReaderTests.lightroomSidecar(rating: 3),
                                           modified: Date().addingTimeInterval(-3600))
            defer { try? FileManager.default.removeItem(at: library.root) }
            let changed = Date()
            await library.marks.setRating(4, ids: [library.photoId])
            try Self.overwrite(library.sidecar, with: SidecarReaderTests.lightroomSidecar(rating: 2),
                               modified: changed.addingTimeInterval(offset))

            await library.queue.flush()
            #expect(SidecarReader.read(sidecarAt: library.sidecar)?.rating == expected, "Lightroom \(offset)s")
            let stored = try await library.database.reader.read { [photoId = library.photoId] db in
                try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [photoId])
            }
            #expect(stored == expected)
            try await waitUntil { library.marks.rating(for: library.photoId) == expected }
            #expect(library.marks.rating(for: library.photoId) == expected, "Lightroom \(offset)s")
        }
    }

    /// AC-28: photo A has a sidecar saying ★2 in "2026 Japan" and one saying
    /// ★5 on T7, the T7 one newer. Both sources read and merged: A is ★5,
    /// and the "2026 Japan" sidecar is rewritten to ★5.
    @Test func copiesDisagreeNewestWins() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Disagree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let japan = base.appendingPathComponent("2026 Japan"), t7 = base.appendingPathComponent("T7")
        var options = MetadataFixture.Options()
        options.starRating = nil
        let raw = try MetadataFixture.encode(.tiff, options: options)
        let now = Date()
        for (folder, stars, age) in [(japan, 2, 600.0), (t7, 5, 60.0)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try raw.write(to: folder.appendingPathComponent("A.ARW"))
            try Self.overwrite(folder.appendingPathComponent("A.xmp"), with: SidecarReaderTests.lightroomSidecar(rating: stars),
                               modified: now.addingTimeInterval(-age))
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let roots = [try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true): japan,
                     try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive"): t7]
        let indexer = FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
        for (id, root) in roots { _ = try indexer.index(sourceId: id, root: root, includesSubfolders: true, pairsRawAndJpeg: true) }
        let fileURL: @Sendable (String, String) -> URL? = { sourceId, path in roots[sourceId]?.appendingPathComponent(path) }
        let merge = try IdentityMergePass(database: database, fileURL: fileURL).run()
        #expect(merge.survivors.count == 1)

        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database, fileURL: fileURL))
        await queue.schedule(merge.survivors)
        #expect(await queue.flush().written == 2)
        for folder in [japan, t7] {
            #expect(SidecarReader.read(sidecarAt: folder.appendingPathComponent("A.xmp"))?.rating == 5, "\(folder.lastPathComponent)")
        }
        let stored = try await database.reader.read { db in try Int.fetchAll(db, sql: "SELECT rating FROM photo_user_marks") }
        #expect(stored == [5])
    }

    /// Polls the main actor for up to 5 s.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < 5 {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
