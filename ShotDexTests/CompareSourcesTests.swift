import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-01.08c with FS-19 sources: Compare's Delete N goes through the
/// photos' sources when any of them lives outside Photos — the same
/// confirmation and run as the grid (FS-19.04 §2).
@MainActor
@Suite struct CompareSourcesTests {
    private final class DeletionLog { var asked: [[String]] = [] }

    /// Two photos of one kind of source, both Rejected, in a comparison.
    private func model(kind: String, sourceKind: String, hasTrash: Bool = true,
                       extraPhotos: Bool = false) async throws -> (CompareModel, DeletionLog) {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: sourceKind == "server" ? "NAS Home" : "2026 Japan",
                                                                    bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true,
                                                                    kind: sourceKind)
        try await database.writer.write { db in
            for id in ["a", "b", "c"] {
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 0)", arguments: [id])
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline)
                    VALUES (?, ?, ?, ?, ?, ?, 1)
                    """, arguments: ["copy-\(id)", id, sourceId, kind, "DSC_\(id).ARW", "dsc_\(id).arw"])
            }
            if extraPhotos {
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('p', 0)")
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, isOnline)
                    VALUES ('photos:p', 'p', 'photos-library', 'photos', 'p', 1)
                    """)
            }
        }
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        let log = DeletionLog()
        let ids = extraPhotos ? ["a", "p"] : ["a", "b", "c"]
        let model = CompareModel(
            session: CompareSession(selection: ids)!, marks: marks,
            deleter: RejectedDeleter(deleteAssets: { log.asked.append($0) }, banner: nil),
            assets: [:], metadata: [:],
            sourceRequest: { ids in
                try? DeletionTargetQueries(database: database, hasTrash: { _ in hasTrash }).request(photoIds: ids, selection: .rejected)
            }
        )
        for id in ids.prefix(2) {
            model.session.setWorking(id)
            await model.apply(.flag(.reject))
        }
        return (model, log)
    }

    /// AC-13: photos on a NAS are hidden, never deleted — *Hide 2 Photos?*
    /// — and PhotoKit is not asked.
    @Test func nasPhotosAreHidden() async throws {
        let (model, log) = try await model(kind: "server", sourceKind: "server")
        let result = await model.deleteRejected()
        let request = try #require(result.sourceRequest)
        #expect(request.plan.title == "Hide 2 photos?")
        #expect(request.plan.confirmTitle == "Hide")
        #expect(log.asked.isEmpty)
        // Hide ran and took both out: the comparison carries on with the third.
        #expect(model.removedThroughSources(["a", "b"]) == .single("c"))
    }

    /// AC-24: a drive with no Trash asks a second, red question.
    @Test func driveWithoutTrashAsksTwice() async throws {
        let (model, log) = try await model(kind: "file", sourceKind: "drive", hasTrash: false)
        let request = try #require(await model.deleteRejected().sourceRequest)
        #expect(request.plan.needsPermanentConfirmation)
        #expect(!request.plan.permanentTitle.isEmpty)
        #expect(log.asked.isEmpty)
        // Cancel at the second question: nothing left the comparison.
        #expect(model.removedThroughSources([]) == nil)
        #expect(model.session.ids == ["a", "b", "c"])
    }

    /// AC-23: a Photos photo and a folder photo, both Rejected — one
    /// confirmation naming both destinations; the Photos part goes through
    /// the system dialog inside the run, not before it.
    @Test func mixedSourcesShareOneConfirmation() async throws {
        let (model, log) = try await model(kind: "file", sourceKind: "folder", extraPhotos: true)
        let request = try #require(await model.deleteRejected().sourceRequest)
        #expect(Set(request.photoIds) == ["a", "p"])
        #expect(request.targets.joined().contains { $0.destination == .trash })
        #expect(request.targets.joined().contains { $0.destination == .recentlyDeleted } || request.photosOnly == ["p"])
        #expect(log.asked.isEmpty)
    }

    /// AC-25: a folder RAW Rejected in Compare carries −1 into the `.xmp`
    /// beside it, and opening ShotDex again it is still Rejected.
    @Test func rejectInCompareReachesTheSidecar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Japan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = MetadataFixture.Options()
        options.starRating = nil
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("DSC04513.ARW"))
        options.width = 300
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("DSC04514.ARW"))
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        _ = try FolderSourceIndexer(database: database, composer: FolderSourceIndexTests.composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        let ids = try await database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT photoId FROM photo_copies WHERE sourceId = ? ORDER BY relativePath", arguments: [sourceId])
        }
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database, fileURL: { _, path in root.appendingPathComponent(path) },
                                                            isEnabled: { true }))
        let marks = PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue)
        let model = CompareModel(session: CompareSession(selection: ids)!, marks: marks,
                                 deleter: RejectedDeleter(deleteAssets: { _ in }, banner: nil), assets: [:], metadata: [:])
        model.session.setWorking(ids[0])
        await model.apply(.flag(.reject))
        await queue.flush()
        let sidecar = root.appendingPathComponent("DSC04513.xmp")
        #expect(SidecarReader.read(sidecarAt: sidecar)?.isRejected == true)
        let reopened = PhotoMarks(store: PhotoMarksStore(database: database))
        await reopened.reload()
        #expect(reopened.flag(for: ids[0]) == .reject)
    }
}
