import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.04 §4 — Duplicates stays inside one source.
@Suite struct DuplicateSourceScopeTests {
    /// AC-44: DSC04512.ARW is identical in T7 RAW/2026-09-27, in T7's
    /// Backup folder and on NAS Home. Exact shows one group — "2 identical
    /// copies of DSC04512.ARW · both on T7 RAW Archive" — and no group with
    /// the NAS copy. Moving the Backup copy leaves the photo with 2 copies,
    /// on T7 and the NAS.
    @Test func groupsStayInOneSource() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Exact-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("T7", isDirectory: true)
        let trash = base.appendingPathComponent("Trash", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        for folder in ["RAW/2026-09-27", "Backup"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var options = MetadataFixture.Options()
        options.starRating = nil
        let data = try MetadataFixture.encode(.jpeg, options: options)
        for folder in ["RAW/2026-09-27", "Backup"] { try data.write(to: root.appendingPathComponent("\(folder)/DSC04512.ARW")) }

        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let t7 = try sources.addFolder(name: "T7 RAW Archive", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        _ = try FolderSourceIndexer(database: database, composer: ServerSourceIndexTests.composer, readsSidecars: false)
            .index(sourceId: t7, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try IdentityMergePass(database: database) { _, path in root.appendingPathComponent(path) }.run()
        let photoId = try #require(try await database.reader.read { db in try String.fetchOne(db, sql: "SELECT DISTINCT photoId FROM photo_copies WHERE sourceId = ?", arguments: [t7]) })
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey) VALUES ('nas', ?, ?, 'server', 'DSC04512.ARW', 'dsc04512.arw')",
                           arguments: [photoId, nas])
        }

        let queries = ExactCopyGroupQueries(database: database)
        let groups = try queries.groups()
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.title == "2 identical copies of DSC04512.ARW · both on T7 RAW Archive")
        #expect(group.copies.allSatisfy { $0.sourceId == t7 })
        #expect(try queries.groups(sourceId: nas).isEmpty)

        let backup = try #require(group.copies.first { $0.relativePath?.hasPrefix("Backup/") == true })
        let summary = try await DeletionService(database: database, deletePhotosAssets: { _ in Issue.record("Photos asked") },
                                                root: { $0 == t7 ? root : nil },
                                                trash: { try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent)) })
            .run([[backup]])
        #expect(summary.trashedFiles == 1)
        let left = try await database.reader.read { db in
            try String.fetchAll(db, sql: """
                SELECT s.name FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.photoId = ? AND c.missingSince IS NULL ORDER BY s.name
                """, arguments: [photoId])
        }
        #expect(left == ["NAS Home", "T7 RAW Archive"])
        #expect(try queries.groups().isEmpty)
        #expect(try LibraryQueries(database: database).count(matching: FilterCriteria()) == 1)
    }

    /// AC-72: a group of similar photos on T7 and another in Photos. The
    /// Source popup set to T7 shows only T7's group; All Sources shows both,
    /// each in its own source.
    @Test func sourcePopupFilters() throws {
        let database = try AppDatabase.makeEmpty()
        let t7 = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let ids = try database.writer.write { db in
            let files = try MixedDeletionPlanTests.addPhotos(db, count: 2, sourceId: t7, kind: "file", prefix: "F")
            let photos = try MixedDeletionPlanTests.addPhotos(db, count: 2, sourceId: PhotoLibrarySource.id, kind: "photos", prefix: "P")
            for id in files + photos {
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, width, height) VALUES (?, 1, 0, 1, 'indexed', 6000, 4000)",
                               arguments: [id])
            }
            return (files, photos)
        }
        let hashes = PerceptualHashStore(database: database)
        try hashes.upsert((ids.0 + ids.1).map { PerceptualHashRecord(assetId: $0, hash: PerceptualHash(bits: 7), modificationDate: 1, computedAt: 1) })
        func group(_ members: [String]) -> DuplicateGroup {
            DuplicateGroup(members: members.map { HashedPhoto(assetId: $0, hash: PerceptualHash(bits: 7), width: 6000, height: 4000,
                                                              fileSize: nil, creationDate: nil, isFavorite: false) }, kind: .copies)
        }
        try hashes.replaceGroups([group(ids.0)], scannedAt: Date(), sourceId: t7)
        try hashes.replaceGroups([group(ids.1)], scannedAt: Date())

        let queries = DuplicateSourceQueries(database: database)
        #expect(try queries.sources().map(\.name) == ["Photos Library", "T7"])
        let onlyT7 = try queries.groups(sourceId: t7)
        #expect(onlyT7.map(\.sourceId) == [t7])
        #expect(Set(onlyT7[0].group.members.map(\.assetId)) == Set(ids.0))
        let all = try queries.groups(sourceId: nil)
        #expect(all.map(\.sourceId) == [PhotoLibrarySource.id, t7])
        #expect(DuplicateSourceQueries.allSources == "All Sources")
    }
}
