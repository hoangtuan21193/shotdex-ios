import Foundation
import GRDB
import Testing
@testable import ShotDex

extension BackupRunnerTests {
    /// FS-19.07 AC-85: Backup puts 10 photos into a folder that is inside a
    /// server source. Listing the source and its hash pass give every copy
    /// the SHA-256 Backup checked on the way up — not one file is read back
    /// or downloaded to learn it.
    @Test func recordsServerCopyHash() async throws {
        var f = try BackupFixture(photos: 0)
        var items: [BackupSourceItem] = []
        var contents: [String: Data] = [:]
        for n in 0..<10 {
            let data = try ServerSourceIndexTests.raw(padding: 20_000 + n, seed: UInt8(n))
            let name = "IMG_\(n).JPG"
            let file = AssetUploadFile(key: "1:\(name)", filename: name, isRAW: false, role: .original, estimatedBytes: Int64(data.count))
            items.append(BackupSourceItem(itemKey: "A\(n)", date: BackupFixture.taken, isVideo: false, album: nil,
                                          files: [BackupSourceFile(file: file, sourceStamp: "\(data.count)")]))
            contents[FakeAssetExporter.key("A\(n)", file.key)] = data
        }
        f.source.replace(items)
        f.contents = contents
        #expect(await f.runner().run().stop == .finished)

        let source = try SourceStore(database: f.database).addServer(name: "NAS Home", connectionId: "S1")
        let (hashReads, downloads) = (f.client.sha256Paths.count, f.client.downloadCount)
        let indexer = ServerSourceIndexer(database: f.database, composer: ServerSourceIndexTests.composer,
                                          client: f.client, readsSidecars: false)
        #expect(try await indexer.index(sourceId: source, folder: "Backup", pairsRawAndJpeg: true).photos == 10)
        let pass = ServerFileHashPass(store: CopyFileStore(database: f.database), client: f.client)
        #expect(try await pass.run(sourceId: source, connectionId: "S1", folder: "Backup").seeded == 10)

        #expect(f.client.sha256Paths.count == hashReads)
        #expect(f.client.downloadCount == downloads)
        let rows = try await f.database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.relativePath, f.sha256, f.origin FROM copy_files f JOIN photo_copies c ON c.id = f.copyId
                WHERE c.sourceId = ?
                """, arguments: [source]).map { (path: $0["relativePath"] as String, sha256: $0["sha256"] as String?, origin: $0["origin"] as String?) }
        }
        #expect(rows.count == 10)
        for row in rows {
            let n = Int(row.path.dropFirst("iPhone/IMG_".count).dropLast(".JPG".count))!
            #expect(row.sha256 == BackupFixture.sha(contents[FakeAssetExporter.key("A\(n)", "1:IMG_\(n).JPG")]!))
            #expect(row.origin == "backup")
        }
        // Nothing left to seed on the next pass.
        #expect(try await pass.run(sourceId: source, connectionId: "S1", folder: "Backup").seeded == 0)
    }
}
