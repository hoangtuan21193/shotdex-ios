import Foundation
import GRDB
import Photos
import Testing
@testable import ShotDex

/// FS-19.04 §2 — running a deletion across Photos, a folder and a NAS.
@Suite struct MixedDeletionTests {
    struct Library {
        let database: AppDatabase
        let root: URL
        let trashed: URL
        let folder: String
        let ids: [String]
    }

    /// Three RAW + JPEG pairs with Lightroom sidecars in a folder, two Photos
    /// items and one NAS file — every photo Rejected, the first rated ★4.
    static func library() throws -> Library {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MixedDelete-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("2026 Japan", isDirectory: true)
        let trashed = base.appendingPathComponent("Trash", isDirectory: true)
        for url in [root, trashed] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        for n in 0..<3 {
            var options = MetadataFixture.Options()
            options.width += n * 16
            options.starRating = nil
            let data = try MetadataFixture.encode(.jpeg, options: options)
            try data.write(to: root.appendingPathComponent("DSC\(n).ARW"))
            try data.write(to: root.appendingPathComponent("DSC\(n).JPG"))
            try Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8).write(to: root.appendingPathComponent("DSC\(n).xmp"))
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let folder = try sources.addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        _ = try FolderSourceIndexer(database: database, composer: ServerSourceIndexTests.composer, readsSidecars: false)
            .index(sourceId: folder, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let ids = try database.writer.write { db in
            let files = try String.fetchAll(db, sql: "SELECT photoId FROM photo_copies WHERE sourceId = ? ORDER BY relativePath", arguments: [folder])
            let others = try MixedDeletionPlanTests.addPhotos(db, count: 2, sourceId: PhotoLibrarySource.id, kind: "photos", prefix: "P")
                + MixedDeletionPlanTests.addPhotos(db, count: 1, sourceId: nas, kind: "server", prefix: "N")
            for id in others {
                try db.execute(sql: "INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus) VALUES (?, 1, 0, 1, 'indexed')",
                               arguments: [id])
            }
            let all = files + others
            for id in all { try db.execute(sql: "INSERT INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, 'rejected', 1)", arguments: [id]) }
            try db.execute(sql: "INSERT INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, 4, 1)", arguments: [files[0]])
            return all
        }
        return Library(database: database, root: root, trashed: trashed, folder: folder, ids: ids)
    }

    static func service(_ library: Library, photos: @escaping @Sendable ([String]) async throws -> Void,
                        trashed: @escaping @Sendable (URL) -> Void = { _ in }) -> DeletionService {
        let (root, folder, trash) = (library.root, library.folder, library.trashed)
        return DeletionService(database: library.database, deletePhotosAssets: photos,
                               root: { $0 == folder ? root : nil },
                               trash: { url in
                                   trashed(url)
                                   try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
                               })
    }

    /// AC-41: the dialog of AC-40, Move, then Cancel in the system's Photos
    /// dialog. Only the Photos part stays — still there, still Rejected; the
    /// folder files already went to the Trash and the NAS photo is hidden
    /// (board mac-ipad-v2 A7, FS-01.08c §6).
    @Test func photosCancelKeepsPhotosPart() async throws {
        let library = try Self.library()
        defer { try? FileManager.default.removeItem(at: library.root.deletingLastPathComponent()) }
        let targets = try DeletionTargetQueries(database: library.database).targets(photoIds: library.ids)
        let moved = Counter()
        let summary = try await Self.service(library, photos: { _ in throw PHPhotosError(.userCancelled) },
                                             trashed: { _ in moved.add() }).run(targets)
        #expect(summary.photosCancelled)
        #expect(summary.recentlyDeleted == 0)
        #expect(summary.trashedFiles == 3)
        #expect(summary.hidden == ["NAS Home": 1])
        #expect(moved.value == 9)
        let counts = try await library.database.reader.read { db in
            (photos: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE kind = 'photos' AND isHidden = 0"),
             photosRejected: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_flag WHERE flag = 'rejected' AND assetId LIKE 'P-%'"))
        }
        #expect(counts.photos == 2)
        #expect(counts.photosRejected == 2)
        #expect(try LibraryQueries(database: library.database).count(matching: FilterCriteria()) == 2)
    }

    /// AC-42: the same dialog, accepted in the system's. Each folder photo
    /// goes to the Trash with its JPEG twin and its `.xmp`; the Photos items
    /// go to Recently Deleted; the NAS photo is hidden, its file untouched.
    /// Put Back one RAW, twin and sidecar: the next read brings the photo
    /// back with its ★4.
    @Test func trashCarriesPairAndSidecar() async throws {
        let library = try Self.library()
        defer { try? FileManager.default.removeItem(at: library.root.deletingLastPathComponent()) }
        let targets = try DeletionTargetQueries(database: library.database).targets(photoIds: library.ids)
        let asked = Recorder()
        let summary = try await Self.service(library, photos: { asked.record($0) }).run(targets)
        #expect(summary.trashedFiles == 3)
        #expect(summary.recentlyDeleted == 2)
        #expect(summary.hidden == ["NAS Home": 1])
        #expect(summary.banner(trashName: MixedDeletionPlan.macTrashName)
                == "Moved 3 files to the Trash and 2 photos to Recently Deleted. Hid 1 photos on NAS Home.")
        #expect(asked.ids.sorted() == ["P-0", "P-1"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: library.trashed.path))
                == Set((0..<3).flatMap { ["DSC\($0).ARW", "DSC\($0).JPG", "DSC\($0).xmp"] }))
        let grid = LibraryQueries(database: library.database)
        #expect(try grid.count(matching: FilterCriteria()) == 0)

        for name in ["DSC0.ARW", "DSC0.JPG", "DSC0.xmp"] {
            try FileManager.default.moveItem(at: library.trashed.appendingPathComponent(name), to: library.root.appendingPathComponent(name))
        }
        _ = try FolderSourceIndexer(database: library.database, composer: ServerSourceIndexTests.composer, readsSidecars: false)
            .index(sourceId: library.folder, root: library.root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(try grid.count(matching: FilterCriteria()) == 1)
        let rating = try await library.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT rating FROM photo_user_marks WHERE photoId = ?", arguments: [library.ids[0]])
        }
        #expect(rating == 4)
    }

    /// AC-58, data half: a folder on a volume with no Trash ("SD_BACKUP").
    /// The plan asks the red second question; Delete Permanently removes
    /// each file, its twin and its `.xmp` — nothing goes to any Trash or to
    /// Recently Deleted.
    @Test func noTrashDeletesPermanently() async throws {
        let library = try Self.library()
        defer { try? FileManager.default.removeItem(at: library.root.deletingLastPathComponent()) }
        let folder = library.folder
        let queries = DeletionTargetQueries(database: library.database, hasTrash: { $0 != folder })
        let files = Array(library.ids.prefix(3))
        let plan = try queries.plan(photoIds: files, selection: .photos)
        #expect(plan.verb == .delete)
        #expect(plan.needsPermanentConfirmation)
        #expect(plan.permanentTitle == "Delete 3 Photos Permanently?")

        let trashed = Counter()
        let summary = try await Self.service(library, photos: { _ in Issue.record("Photos asked") }, trashed: { _ in trashed.add() })
            .run(try queries.targets(photoIds: files))
        #expect(summary.removedFiles == 3)
        #expect(summary.trashedFiles == 0 && summary.recentlyDeleted == 0)
        #expect(trashed.value == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.root.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.trashed.path).isEmpty)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [String] = []
        var ids: [String] { lock.withLock { all } }
        func record(_ ids: [String]) { lock.withLock { all += ids } }
    }
}
