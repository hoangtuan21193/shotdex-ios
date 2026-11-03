import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §12: hashes another device worked out — who sent each, and what
/// a random check that finds one wrong takes away.
@Suite struct SharedHashTests {
    private func store() throws -> (CopyFileStore, AppDatabase) {
        let database = try AppDatabase.makeEmpty()
        try database.writer.write { db in
            for (copy, key) in [("S1", "primary"), ("S2", "primary"), ("S3", "primary"), ("P1", "1:a.HEIC")] {
                try db.execute(sql: "INSERT INTO copy_files (copyId, fileKey, role, size) VALUES (?, ?, 'photo', 10)",
                               arguments: [copy, key])
            }
        }
        return (CopyFileStore(database: database), database)
    }

    private let sha = String(repeating: "a", count: 64)

    /// A hash from another device keeps its sender and when it was hashed;
    /// one worked out here has no sender.
    @Test func storeKeepsSender() throws {
        let (store, _) = try store()
        try store.saveHash(sha, copyId: "S1", fileKey: "primary", origin: .shared, sharedFrom: "MAC",
                           hashedAt: Date(timeIntervalSince1970: 100), at: Date(timeIntervalSince1970: 500))
        try store.saveHash(sha, copyId: "S2", fileKey: "primary", origin: .hashed, sharedFrom: "MAC")

        let shared = try #require(try store.files(copyId: "S1").first)
        #expect(shared.origin == .shared)
        #expect(shared.sharedFrom == "MAC")
        #expect(try store.files(copyId: "S2").first?.sharedFrom == nil)
        #expect(CopyFile.Origin.ledger.isFromAnotherDevice && !CopyFile.Origin.backup.isFromAnotherDevice)
    }

    /// §12.4: caught wrong, a device's hashes up to then go — over iCloud
    /// and from the ledger — and nothing else; newer ones are taken again.
    @Test func distrustDropsOnlyThatDevicesOlderHashes() throws {
        let (store, _) = try store()
        try store.saveHash(sha, copyId: "S1", fileKey: "primary", origin: .shared, sharedFrom: "MAC", hashedAt: Date(timeIntervalSince1970: 100))
        try store.saveHash(sha, copyId: "S2", fileKey: "primary", origin: .ledger, sharedFrom: "MAC", hashedAt: Date(timeIntervalSince1970: 150))
        try store.saveHash(sha, copyId: "S3", fileKey: "primary", origin: .shared, sharedFrom: "IPAD", hashedAt: Date(timeIntervalSince1970: 100))
        try store.saveHash(sha, copyId: "P1", fileKey: "1:a.HEIC", origin: .hashed)

        #expect(try store.distrust(device: "MAC", at: Date(timeIntervalSince1970: 150)) == 2)

        #expect(try store.files(copyId: "S1").first?.sha256 == nil)
        // Hashed the same second as the catch: dropped too.
        #expect(try store.files(copyId: "S2").first?.sha256 == nil)
        #expect(try store.files(copyId: "S3").first?.sha256 == sha)
        #expect(try store.files(copyId: "P1").first?.sha256 == sha)
        #expect(try !store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 150)))
        #expect(try store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 151)))
        // Per device: distrusting the iPad leaves the Mac's newer hashes alone.
        try store.distrust(device: "IPAD", at: Date(timeIntervalSince1970: 300))
        #expect(try !store.accepts(device: "IPAD", hashedAt: Date(timeIntervalSince1970: 200)))
        #expect(try store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 200)))
    }

    /// A file changed on the server loses its hash and its sender together.
    @Test func changedFileForgetsTheSender() throws {
        let (store, database) = try store()
        try store.saveHash(sha, copyId: "S1", fileKey: "primary", origin: .ledger, sharedFrom: "MAC")
        try database.writer.write { db in
            try CopyFileStore.saveServerFiles(db, copyId: "S1", files: [
                CopyFileStore.ListedFile(fileKey: "primary", relativePath: "a.HEIC", size: 11, modifiedAt: 5),
            ])
        }
        let file = try #require(try store.files(copyId: "S1").first)
        #expect(file.sha256 == nil && file.origin == nil && file.sharedFrom == nil)
    }

    /// A shared row with no time is dropped too; a sender's clock running
    /// ahead cannot slip a hash past the cut.
    @Test func distrustEdges() throws {
        let (store, database) = try store()
        try store.saveHash(sha, copyId: "S1", fileKey: "primary", origin: .shared, sharedFrom: "MAC", hashedAt: Date(timeIntervalSince1970: 50))
        try database.writer.write { db in try db.execute(sql: "UPDATE copy_files SET hashedAt = NULL WHERE copyId = 'S1'") }
        // A shared hash saved with no time counts as the oldest.
        try store.saveHash(sha, copyId: "S3", fileKey: "primary", origin: .shared, sharedFrom: "MAC", at: Date(timeIntervalSince1970: 300))
        try store.saveHash(sha, copyId: "S2", fileKey: "primary", origin: .shared, sharedFrom: "MAC",
                           hashedAt: Date(timeIntervalSince1970: 9_000), at: Date(timeIntervalSince1970: 100))

        #expect(try store.distrust(device: "MAC", at: Date(timeIntervalSince1970: 200)) == 3)
        #expect(try !store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 200), now: Date(timeIntervalSince1970: 300)))
        #expect(try store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 201), now: Date(timeIntervalSince1970: 300)))
        // Ahead of this device's clock: counted as received now.
        #expect(try !store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 9_000), now: Date(timeIntervalSince1970: 150)))
    }

    /// A Photos file whose stamp did not change keeps its sender; a new
    /// stamp drops hash and sender.
    @Test func listingKeepsOrDropsTheSender() throws {
        let (store, _) = try store()
        let file = PhotosFile(fileKey: "1:a.HEIC", role: .photo, size: 10, stamp: "s1")
        try store.saveListing(copyId: "P1", stamp: 1, files: [file])
        try store.saveHash(sha, copyId: "P1", fileKey: "1:a.HEIC", origin: .shared, sharedFrom: "MAC")
        try store.saveListing(copyId: "P1", stamp: 1, files: [file])
        #expect(try store.files(copyId: "P1").first?.sharedFrom == "MAC")

        var edited = file
        edited.stamp = "s2"
        try store.saveListing(copyId: "P1", stamp: 2, files: [edited])
        let read = try #require(try store.files(copyId: "P1").first)
        #expect(read.sha256 == nil && read.sharedFrom == nil)
    }

    /// Clear Local Metadata Index keeps who was caught wrong.
    @Test func clearingTheIndexKeepsDistrust() throws {
        let (store, database) = try store()
        try store.distrust(device: "MAC", at: Date(timeIntervalSince1970: 200))
        try MetadataStore(database: database).deleteAll()
        #expect(try !store.accepts(device: "MAC", hashedAt: Date(timeIntervalSince1970: 100)))
    }
}

