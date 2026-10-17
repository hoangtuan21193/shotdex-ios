import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-20 AC-22: the background hash corrects what name + bytes + date say.
@Suite struct CardHashPassTests {
    private func pass(_ card: IngestFixture, _ database: AppDatabase) -> CardHashPass {
        let root = card.card
        return CardHashPass(database: database, reader: card.reader(), fileURL: { root.appendingPathComponent($0.path) })
    }

    /// `IMG_0100.CR3` matches the history by name, bytes and date but holds
    /// other bytes than the import did: imported at first, new after hashing.
    @Test func historyMatchButContentDiffers() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        try card.add("DCIM/100CANON/IMG_0100.CR3", bytes: 80_000, date: IngestRunnerTests.shot)
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let item = CardCatalog.items(try await card.reader().list())[0]
        try CardImportStore(database: database).record(.init(
            cardId: "EOS", cardName: "EOS_DIGITAL", originalPath: item.primary.path, originalName: item.primary.name,
            byteCount: item.primary.size, capturedAt: Int64(item.primary.modified!.timeIntervalSince1970), sha256: "an older card's bytes",
            sourceId: sourceId, destinationPath: "IMG_0100.CR3", photoId: nil, backupPath: nil, importedAt: 0))
        let matches = try CardImportStore(database: database).matches(for: [item.primary]) { _, _ in true }
        #expect(IngestStatus.isImported(item, matches: matches))
        let hashed = try await pass(card, database).hash(item.primary)
        #expect(hashed.sha256 == (try card.sha(item.primary.path, onDestination: false)))
        #expect(!IngestStatus.isImported(item, matches: matches, hashed: [item.id: hashed]))
    }

    /// No history row, but the same picture is already a photo in a folder
    /// source: imported after hashing.
    @Test func hashMatchesSourceWithoutHistory() async throws {
        let card = try IngestFixture()
        defer { card.cleanUp() }
        let jpeg = try MetadataFixture.encode(.jpeg, options: MetadataFixture.Options())
        let url = card.card.appendingPathComponent("DCIM/100CANON/IMG_0200.JPG")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url)
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let content = try ContentHasher.hash(DataBytes(data: jpeg), full: true)
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('p', 0)")
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline)
                VALUES ('c', 'p', ?, 'file', 'Kyoto/DSC_9.JPG', 'kyoto/dsc_9.jpg', 1)
                """, arguments: [sourceId])
            try db.execute(sql: """
                INSERT INTO content_hashes (copyId, algorithm, algorithmVersion, fastHash, fullHash, hashedAt)
                VALUES ('c', ?, ?, ?, ?, 0)
                """, arguments: [content.algorithm, content.version, content.fast, content.full])
        }
        let item = CardCatalog.items(try await card.reader().list())[0]
        #expect(!IngestStatus.isImported(item, matches: [:]))
        let hashed = try await pass(card, database).hash(item.primary)
        #expect(hashed.isInASource)
        #expect(IngestStatus.isImported(item, matches: [:], hashed: [item.id: hashed]))
    }
}
