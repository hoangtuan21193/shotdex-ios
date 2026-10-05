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
