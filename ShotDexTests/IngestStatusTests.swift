import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-20 §5: which card photos are new, by the import history.
@Suite struct IngestStatusTests {
    static let base = Date(timeIntervalSince1970: 1_790_500_000)

    private func items(_ count: Int, day: Int = 0, start: Int = 1) -> [CardItem] {
        (0..<count).map { n in
            CardItem(kind: .photo, files: [CardFile(path: String(format: "DCIM/100CANON/IMG_%04d.CR3", start + n), size: 1_000 + Int64(n),
                                                    modified: Self.base.addingTimeInterval(Double(day) * 86_400 + Double(n)))])
        }
    }

    private func history(_ store: CardImportStore, _ items: [CardItem], sourceId: String) throws {
        for item in items {
            let file = item.primary
            try store.record(.init(cardId: "card", cardName: "EOS_DIGITAL", originalPath: file.path, originalName: file.name,
                                   byteCount: file.size, capturedAt: Int64(file.modified!.timeIntervalSince1970), sha256: "sha-\(file.name)",
                                   sourceId: sourceId, destinationPath: "RAW/" + file.name, photoId: nil, backupPath: nil, importedAt: 0))
        }
    }

    /// The table: its own, no foreign key, the two lookups indexed.
    @Test func migrationShape() throws {
        let database = try AppDatabase.makeEmpty()
        try database.reader.read { db in
            let columns = try db.columns(in: "card_imports").map(\.name)
            #expect(columns == ["id", "cardId", "cardName", "originalPath", "originalName", "byteCount", "capturedAt", "sha256",
                                "sourceId", "destinationPath", "photoId", "backupPath", "importedAt"])
            #expect(try db.foreignKeys(on: "card_imports").isEmpty)
            #expect(Set(try db.indexes(on: "card_imports").map(\.name)) == ["card_imports_key", "card_imports_card"])
        }
    }

    /// AC-1 (scaled 1,046 → 46): 12 in the history are imported, 34 new and ticked.
    @Test func historyMarksImported() throws {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let store = CardImportStore(database: database)
        let all = items(46)
        try history(store, Array(all.prefix(12)), sourceId: sourceId)
        let matches = try store.matches(for: all.map(\.primary))
        let imported = Set(all.filter { IngestStatus.isImported($0, matches: matches) }.map(\.id))
        #expect(imported.count == 12)
        let selection = IngestSelection(items: all, imported: imported)
        #expect(selection.checked.count == 34)
        #expect(selection.checked.isDisjoint(with: imported))
    }

    /// AC-3: a day whose every photo is imported is one collapsed row.
    @Test func fullyImportedDayCollapses() {
        let sept27 = items(5, day: 0), sept28 = items(4, day: 1, start: 100)
        let days = IngestStatus.days(sept27 + sept28, imported: Set(sept27.map(\.id) + [sept28[0].id]))
        #expect(days.map(\.isFullyImported) == [true, false])
        #expect(days[0].importedCount == 5)
        #expect(days[1].newCount == 3)
    }

    /// AC-16: everything on the card imported — no new photos.
    @Test func everythingImported() throws {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let store = CardImportStore(database: database)
        let all = items(8)
        try history(store, all, sourceId: sourceId)
        let matches = try store.matches(for: all.map(\.primary))
        #expect(all.allSatisfy { IngestStatus.isImported($0, matches: matches) })
        #expect(IngestCopy.everythingImported(card: "EOS_DIGITAL") == "Everything on EOS_DIGITAL is already imported.")
        #expect(IngestCopy.header(new: 0, imported: 8) == "0 new photos · 8 already imported · skipped")
    }

    /// AC-21: an imported photo whose copy was deleted at the destination is
    /// new again; one whose source is only unplugged stays imported (Q2).
    @Test func deletedAtDestinationIsNewAgain() throws {
        let database = try AppDatabase.makeEmpty()
        let sourceId = try SourceStore(database: database).addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true)
        let store = CardImportStore(database: database)
        let all = items(3)
        try history(store, all, sourceId: sourceId)
        try database.writer.write { db in
            for (index, item) in all.enumerated() {
                let path = "RAW/" + item.primary.name
                try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 0)", arguments: ["p\(index)"])
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline, missingSince)
                    VALUES (?, ?, ?, 'file', ?, ?, ?, ?)
                    """, arguments: ["c\(index)", "p\(index)", sourceId, path, FolderSourceIndexer.pathKey(path), index == 2 ? 0 : 1, index == 0 ? 100 : nil])
            }
        }
        let matches = try store.matches(for: all.map(\.primary))
        #expect(all.map { IngestStatus.isImported($0, matches: matches) } == [false, true, true])
        // No copy in the index: the file in the source decides; a source
        // that can't be opened keeps it imported.
        try database.writer.write { db in try db.execute(sql: "DELETE FROM photo_copies WHERE id = 'c1'") }
        #expect(!IngestStatus.isImported(all[1], matches: try store.matches(for: all.map(\.primary), fileExists: { _, _ in false })))
        #expect(IngestStatus.isImported(all[1], matches: try store.matches(for: all.map(\.primary), fileExists: { _, _ in true })))
        #expect(IngestStatus.isImported(all[1], matches: try store.matches(for: all.map(\.primary))))
        try SourceStore(database: database).remove(sourceId: sourceId)
        let afterRemoval = try store.matches(for: all.map(\.primary))
        #expect(all.allSatisfy { !IngestStatus.isImported($0, matches: afterRemoval) })
    }

    /// AC-22 (logic): history matches by name but the content differs → new;
    /// no history but the content is already in a source → imported.
    @Test func hashRefinesTheHistory() {
        let photo = items(1)[0]
        let key = IngestStatus.Key(photo.primary)
        let matches = [key: IngestStatus.Match(sha256: "old", isCopyGone: false)]
        #expect(IngestStatus.isImported(photo, matches: matches))
        #expect(!IngestStatus.isImported(photo, matches: matches, hashed: [photo.id: .init(sha256: "new", isInASource: false)]))
        #expect(IngestStatus.isImported(photo, matches: [:], hashed: [photo.id: .init(sha256: "x", isInASource: true)]))
    }
}

extension IngestStatusTests {
    /// The history is the user's: Clear Local Metadata Index and the
    /// 30-day orphan purge both leave it (BD-02 §1).
    @Test func historySurvivesClearAndPurge() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CardImportStore(database: database)
        try store.record(.init(cardId: "card", cardName: "EOS_DIGITAL", originalPath: "DCIM/IMG_1.CR3", originalName: "IMG_1.CR3",
                               byteCount: 1, capturedAt: 1, sha256: "s", sourceId: "src", destinationPath: "IMG_1.CR3",
                               photoId: "orphan", backupPath: nil, importedAt: 0))
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt, orphanedAt) VALUES ('orphan', 0, 0)")
        }
        try MetadataStore(database: database).deleteAll()
        _ = try PhotoOrphanStore(database: database).purge(orphanedBefore: Date())
        #expect(try store.rows(cardId: "card").count == 1)
    }
}

/// FS-20 §5: ticks and the total under the grid.
@Suite struct IngestSelectionTests {
    /// AC-2: unticking a 9.8 MB HIF drops one photo and its bytes.
    @Test func untickHIFDropsBytes() {
        let date = Date(timeIntervalSince1970: 1_790_500_000)
        let items = [
            CardItem(kind: .photo, files: [CardFile(path: "DCIM/IMG_1.CR3", size: 30_000_000, modified: date),
                                           CardFile(path: "DCIM/IMG_1.HIF", size: 9_800_000, modified: date)]),
            CardItem(kind: .photo, files: [CardFile(path: "DCIM/IMG_2.HIF", size: 9_800_000, modified: date)]),
        ]
        var selection = IngestSelection(items: items, imported: [])
        #expect(selection.bytes(items) == 49_600_000)
        selection.toggle("DCIM/IMG_2.HIF")
        #expect(selection.checked.count == 1)
        #expect(selection.bytes(items) == 39_800_000)
        #expect(IngestCopy.checkedLine(count: 1, bytes: 39_800_000) == "1 checked · 39.8 MB")
        #expect(IngestCopy.importButton(count: 811) == "Import 811 Photos")
    }
}
