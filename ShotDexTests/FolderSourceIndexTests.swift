import CryptoKit
import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.01 §3–§4 — reading a folder source.
@MainActor
@Suite struct FolderSourceIndexTests {
    static let composer = MetadataComposer(sensorLookup: SensorLookup(records: [], customMappings: []))

    /// AC-1: a folder of two RAW+JPG pairs (one in a subfolder) and a lone
    /// HEIC becomes three photos — each pair one photo whose copy is the RAW
    /// with the JPG beside it — with a metadata row each. Every file's
    /// SHA-256 and the folder listing are the same after as before: the read
    /// writes nothing into the source. A second read finds nothing changed.
    @Test func pairsAndNeverWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("2026 Japan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let day2 = root.appendingPathComponent("Day 2", isDirectory: true)
        try FileManager.default.createDirectory(at: day2, withIntermediateDirectories: true)
        let tiff = try MetadataFixture.encode(.tiff, options: MetadataFixture.Options())
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        let heic = try MetadataFixture.encode(.heic, options: MetadataFixture.Options())
        try tiff.write(to: root.appendingPathComponent("DSC04512.ARW"))
        try jpeg.write(to: root.appendingPathComponent("DSC04512.JPG"))
        try tiff.write(to: day2.appendingPathComponent("DSC04600.ARW"))
        try jpeg.write(to: day2.appendingPathComponent("dsc04600.jpg"))
        try heic.write(to: root.appendingPathComponent("IMG_0420.HEIC"))
        let before = try Self.fingerprint(root)

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: Self.composer)
        let summary = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)

        #expect(summary.photos == 3)
        #expect(try Self.fingerprint(root) == before)
        let copies = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT relativePath, pairedPath, kind FROM photo_copies WHERE sourceId = ? ORDER BY relativePath", arguments: [sourceId])
                .map { "\($0["relativePath"] as String) + \(($0["pairedPath"] as String?) ?? "-")" }
        }
        #expect(copies == ["DSC04512.ARW + DSC04512.JPG", "Day 2/DSC04600.ARW + Day 2/dsc04600.jpg", "IMG_0420.HEIC + -"])
        let counts = try database.reader.read { db in
            (photos: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos") ?? 0,
             metadata: try String.fetchAll(db, sql: "SELECT originalFilename FROM photo_metadata ORDER BY originalFilename"),
             hashes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM content_hashes WHERE fullHash IS NULL") ?? 0)
        }
        #expect(counts.photos == 3)
        #expect(counts.metadata == ["DSC04512.ARW", "DSC04600.ARW", "IMG_0420.HEIC"])
        #expect(counts.hashes == 3)

        let again = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(again == FolderSourceIndexer.Summary(photos: 0, unchanged: 3))
        #expect(try Self.fingerprint(root) == before)
    }

    /// AC-3: a folder with 100 files at the top and 3 subfolders of 50 each,
    /// added with Include Subfolders off, is 100 photos. Turning it on reads
    /// exactly the 150 new files; the 100 already read are not opened again.
    @Test func subfoldersToggleReadsOnlyDelta() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Delta-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for n in 0..<100 { try jpeg.write(to: root.appendingPathComponent("TOP_\(n).JPG")) }
        for folder in ["A", "B", "C"] {
            let sub = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for n in 0..<50 { try jpeg.write(to: sub.appendingPathComponent("\(folder)_\(n).JPG")) }
        }
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let sourceId = try sources.addFolder(name: "Delta", bookmark: Data(), includesSubfolders: false, pairsRawAndJpeg: true)
        let indexer = FolderSourceIndexer(database: database, composer: Self.composer)

        let first = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: false, pairsRawAndJpeg: true)
        #expect(first == FolderSourceIndexer.Summary(photos: 100, unchanged: 0))

        try sources.setIncludesSubfolders(true, sourceId: sourceId)
        let source = try #require(try sources.sources().first { $0.id == sourceId })
        #expect(source.includesSubfolders)
        let second = try indexer.index(sourceId: sourceId, root: root, includesSubfolders: source.includesSubfolders, pairsRawAndJpeg: true)
        #expect(second == FolderSourceIndexer.Summary(photos: 150, unchanged: 100))
        let total = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE sourceId = ?", arguments: [sourceId]) }
        #expect(total == 250)
    }

    /// AC-6: a first read of 38 files is paused after 12; the app is gone
    /// (a fresh indexer, as after a relaunch) and Resume reads exactly the
    /// 26 left — none of the first 12 again — for 38 photos in all.
    @Test func resumeAfterRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Resume-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        for n in 0..<38 { try jpeg.write(to: root.appendingPathComponent(String(format: "DSC%05d.JPG", n))) }
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "Resume", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)

        var asked = 0
        let first = try FolderSourceIndexer(database: database, composer: Self.composer).index(
            sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true,
            shouldContinue: { asked += 1; return asked <= 12 })
        #expect(first == FolderSourceIndexer.Summary(photos: 12, unchanged: 0, paused: true))

        let resumed = try FolderSourceIndexer(database: database, composer: Self.composer).index(
            sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: true)
        #expect(resumed == FolderSourceIndexer.Summary(photos: 26, unchanged: 12, paused: false))
        let photos = try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE sourceId = ?", arguments: [sourceId]) }
        #expect(photos == 38)
    }

    /// AC-2: the same pairs with Pair RAW + JPEG off are two photos each,
    /// none labelled RAW+JPG. Lightroom's `DSC04512.xmp` (★2) is the RAW's:
    /// the JPEG does not read it, and ★3 on the JPEG goes to a new
    /// `DSC04512.JPG.xmp` while `DSC04512.xmp` keeps every byte.
    @Test func pairingOffSeparateSidecar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Unpaired-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var options = MetadataFixture.Options()
        options.starRating = nil
        try MetadataFixture.encode(.tiff, options: options).write(to: root.appendingPathComponent("DSC04512.ARW"))
        try MetadataFixture.encode(.jpeg, options: options).write(to: root.appendingPathComponent("DSC04512.JPG"))
        let rawSidecar = root.appendingPathComponent("DSC04512.xmp")
        try SidecarReaderTests.lightroomSidecar(rating: 2).write(to: rawSidecar)
        let rawSidecarBefore = try Data(contentsOf: rawSidecar)

        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "2026 Japan", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: false)
        let summary = try FolderSourceIndexer(database: database, composer: Self.composer)
            .index(sourceId: sourceId, root: root, includesSubfolders: true, pairsRawAndJpeg: false)
        #expect(summary.photos == 2)
        struct Copy: Sendable { let path: String, photoId: String, pairedPath: String?, rating: Int? }
        let copies = try await database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.relativePath, c.photoId, c.pairedPath, u.rating FROM photo_copies c
                LEFT JOIN photo_user_marks u ON u.photoId = c.photoId WHERE c.sourceId = ? ORDER BY c.relativePath
                """, arguments: [sourceId])
                .map { Copy(path: $0["relativePath"], photoId: $0["photoId"], pairedPath: $0["pairedPath"], rating: $0["rating"]) }
        }
        #expect(copies.map(\.path) == ["DSC04512.ARW", "DSC04512.JPG"])
        #expect(copies.allSatisfy { $0.pairedPath == nil })
        #expect(copies.map(\.rating) == [2, nil])

        let jpeg = copies[1].photoId
        let queue = SidecarWriteQueue(writer: SidecarWriter(database: database) { _, path in root.appendingPathComponent(path) })
        let marks = PhotoMarks(store: PhotoMarksStore(database: database), sidecarQueue: queue)
        await marks.setRating(3, ids: [jpeg])
        #expect(await queue.flush().written == 1)
        #expect(SidecarReader.read(sidecarAt: root.appendingPathComponent("DSC04512.JPG.xmp"))?.rating == 3)
        #expect(try Data(contentsOf: rawSidecar) == rawSidecarBefore)
    }

    /// Path → SHA-256 of every file under `root`, hidden ones included.
    static func fingerprint(_ root: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walk?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            out[url.path] = digest.map { String(format: "%02x", $0) }.joined()
        }
        return out
    }
}
