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

    /// FS-19.07 AC-145 (§12.1), the hashing half: the Mac reads every file of
    /// a server source, not only those the size of a Photos file; a pass
    /// stopped midway goes on from the next file (AC-157).
    @MainActor
    @Test func macHashesEveryServerFile() async throws {
        let client = InMemoryRemoteFileClient()
        for n in 0..<5 {
            client.put("iCloud Photo/Shared/s\(n).ARW", try ServerSourceIndexTests.raw(padding: 4_096 + n * 512, seed: UInt8(n)))
        }
        let f = try OnServerFixture(photos: 0)
        let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "iCloud Photo"), password: "pw")
        let refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in client }
        _ = await refresh.rescan(sourceId: f.source)
        let store = CopyFileStore(database: f.database)
        var pass = ServerFileHashPass(store: store, client: client)

        #expect(try await pass.run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo").hashed == 0)

        pass.hashesEverything = true
        let first = try await pass.run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo", limit: 2)
        let rest = try await pass.run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo")

        #expect(first.hashed == 2 && rest.hashed == 3)
        #expect(Set(client.sha256Paths).count == 5 && client.sha256Paths.count == 5)
        let hashed = try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM copy_files WHERE sha256 IS NOT NULL AND origin = 'hashed'")
        }
        #expect(hashed == 5)
    }

    // MARK: Ledger on the NAS (§12.2)

    /// A device of its own (its own database) over one shared NAS.
    @MainActor
    private struct Device {
        let f: OnServerFixture
        let refresh: ServerSourceRefresh
        let store: CopyFileStore
        let client: InMemoryRemoteFileClient
        let id: String

        init(_ id: String, nas client: InMemoryRemoteFileClient) async throws {
            self.id = id
            self.client = client
            f = try OnServerFixture(photos: 0)
            let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
            try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                        folder: "iCloud Photo"), password: "pw")
            refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in client }
            store = CopyFileStore(database: f.database)
            _ = await refresh.rescan(sourceId: f.source)
        }

        /// One pass of the server side, hashing everything (as the Mac does,
        /// or as a phone whose Photos files make every file a candidate).
        @discardableResult
        func pass(everything: Bool = true) async throws -> ServerFileHashPass.Summary {
            var pass = ServerFileHashPass(store: store, client: client)
            pass.hashesEverything = everything
            pass.deviceId = id
            return try await pass.run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo")
        }

        func hashes() async throws -> [(origin: String?, from: String?)] {
            try await f.database.reader.read { db in
                try Row.fetchAll(db, sql: "SELECT origin, sharedFrom FROM copy_files ORDER BY copyId").map { ($0["origin"], $0["sharedFrom"]) }
            }
        }
    }

    private static func nas(files: Int = 5) throws -> InMemoryRemoteFileClient {
        let client = InMemoryRemoteFileClient()
        for n in 0..<files {
            let path = "iCloud Photo/Shared/s\(n).ARW"
            client.put(path, try ServerSourceIndexTests.raw(padding: 4_096 + n * 512, seed: UInt8(n)))
            client.modified[path] = Date(timeIntervalSince1970: 1_000 + TimeInterval(n))
        }
        return client
    }

    private static let ledger = "iCloud Photo/.shotdex/hash-index"

    /// AC-145: the Mac's hashes land in one segment at the source's root —
    /// path under the root, size, write time, SHA — through a part file; a
    /// second pass with nothing new writes nothing.
    @MainActor
    @Test func ledgerWrittenAtSourceRoot() async throws {
        let nas = try Self.nas()
        let mac = try await Device("MAC", nas: nas)

        let summary = try await mac.pass()

        #expect(summary.hashed == 5 && summary.published == 5)
        let segment = try #require(nas.files["\(Self.ledger)/MAC-000001.jsonl"])
        let lines = BackupContentIndex.decode(segment)
        #expect(lines.count == 5)
        #expect(Set(lines.map(\.path)) == Set((0..<5).map { "Shared/s\($0).ARW" }))
        #expect(lines.allSatisfy { $0.device == "MAC" && $0.modified != nil })
        #expect(!nas.files.keys.contains { $0.hasSuffix(ServerUploadPath.partSuffix) })

        let again = try await mac.pass()
        #expect(again.published == 0)
        #expect(nas.files.keys.filter { $0.hasPrefix(Self.ledger) }.count == 1)
    }

    /// AC-146: a phone over the same NAS takes every hash from the ledger —
    /// not one file read — each marked as the Mac's.
    @MainActor
    @Test func readerSkipsDownloads() async throws {
        let nas = try Self.nas()
        try await Device("MAC", nas: nas).pass()
        let phone = try await Device("PHONE", nas: nas)
        let reads = nas.sha256Paths.filter { !$0.contains(".shotdex") }.count

        let summary = try await phone.pass()

        #expect(summary.fromLedger == 5 && summary.hashed == 0)
        #expect(nas.sha256Paths.filter { !$0.contains(".shotdex") }.count == reads)
        #expect(try await phone.hashes().allSatisfy { $0.origin == "ledger" && $0.from == "MAC" })
    }

    /// AC-147: one file's write time moved after the Mac wrote its line —
    /// that line is passed over and the file read; the other four are not.
    @MainActor
    @Test func staleLineIgnored() async throws {
        let nas = try Self.nas()
        try await Device("MAC", nas: nas).pass()
        nas.modified["iCloud Photo/Shared/s1.ARW"] = Date(timeIntervalSince1970: 9_999)
        let phone = try await Device("PHONE", nas: nas)
        let reads = nas.sha256Paths.filter { !$0.contains(".shotdex") }

        let summary = try await phone.pass()

        #expect(summary.fromLedger == 4 && summary.hashed == 1)
        #expect(Array(nas.sha256Paths.filter { !$0.contains(".shotdex") }.dropFirst(reads.count)) == ["iCloud Photo/Shared/s1.ARW"])
    }

    /// AC-148: the ledger is never a photo, a file count or a write outside
    /// `.shotdex/`.
    @MainActor
    @Test func ledgerNeverAPhoto() async throws {
        let nas = try Self.nas()
        let mac = try await Device("MAC", nas: nas)
        let before = nas.commands.count
        try await mac.pass()
        _ = await mac.refresh.rescan(sourceId: mac.f.source)

        let copies = try await mac.f.database.reader.read { db in
            try String.fetchAll(db, sql: "SELECT relativePath FROM photo_copies WHERE kind = 'server'")
        }
        #expect(copies.count == 5 && !copies.contains { $0.contains(".shotdex") })
        let writes = nas.commands.dropFirst(before).filter { $0.hasPrefix("upload ") || $0.hasPrefix("move ") || $0.hasPrefix("remove ") }
        #expect(!writes.isEmpty)
        #expect(writes.allSatisfy { $0.contains("iCloud Photo/.shotdex/hash-index/") })
    }

    /// AC-158: two devices write in one run — two segments, nothing lost; a
    /// third reads both.
    @MainActor
    @Test func twoWritersTwoSegments() async throws {
        let nas = try Self.nas()
        try await Device("MAC", nas: nas).pass()
        try await Device("PHONE", nas: nas).pass(everything: true)
        // The phone took the Mac's hashes, so it wrote nothing; make it hash
        // a file of its own.
        nas.put("iCloud Photo/Shared/s9.ARW", try ServerSourceIndexTests.raw(padding: 9_000, seed: 9))
        nas.modified["iCloud Photo/Shared/s9.ARW"] = Date(timeIntervalSince1970: 1_009)
        let phone = try await Device("PHONE", nas: nas)
        try await phone.pass()

        let segments = nas.files.keys.filter { $0.hasPrefix(Self.ledger) }.sorted()
        #expect(segments == ["\(Self.ledger)/MAC-000001.jsonl", "\(Self.ledger)/PHONE-000001.jsonl"])
        let third = try await Device("IPAD", nas: nas)
        let summary = try await third.pass()
        #expect(summary.fromLedger == 6 && summary.hashed == 0)
    }

    /// A ledger line is taken only from the device its segment is named
    /// after, in lower case, and never from a device caught wrong before it
    /// wrote the line.
    @MainActor
    @Test func ledgerTrustRules() async throws {
        let nas = try Self.nas(files: 3)
        try await Device("MAC", nas: nas).pass()
        let mac = BackupContentIndex.decode(try #require(nas.files["\(Self.ledger)/MAC-000001.jsonl"]))
        // A segment named after the iPad that claims to be the Mac, and an
        // upper-case SHA in the Mac's own.
        var forged = mac
        for index in forged.indices { forged[index].device = "MAC" }
        nas.put("\(Self.ledger)/IPAD-000001.jsonl", BackupContentIndex.encode(forged))
        var upper = mac
        for index in upper.indices { upper[index].sha256 = upper[index].sha256.uppercased() }
        nas.put("\(Self.ledger)/MAC-000001.jsonl", BackupContentIndex.encode(upper))

        let phone = try await Device("PHONE", nas: nas)
        try phone.store.distrust(device: "MAC", at: Date(timeIntervalSince1970: TimeInterval(mac[0].recordedAt - 1)))
        let summary = try await phone.pass()
        #expect(summary.fromLedger == 3)
        let kept = try await phone.f.database.reader.read { db in try String.fetchAll(db, sql: "SELECT DISTINCT device FROM hash_index_lines") }
        #expect(kept == ["MAC"] || Set(kept) == ["MAC", "PHONE"])
        let shas = try await phone.f.database.reader.read { db in try String.fetchAll(db, sql: "SELECT sha256 FROM copy_files") }
        #expect(shas.allSatisfy { $0 == $0.lowercased() })

        // Caught wrong after it wrote them: the same lines are refused.
        let later = try await Device("PHONE2", nas: nas)
        try later.store.distrust(device: "MAC", at: Date(timeIntervalSince1970: TimeInterval(mac[0].recordedAt)))
        let refused = try await later.pass()
        #expect(refused.fromLedger == 0 && refused.hashed == 3)
    }

    /// A server error at connect — a share gone, a refused login — stops the
    /// source's pass and is reported, as before the ledger.
    @MainActor
    @Test func connectErrorStopsThePass() async throws {
        let nas = try Self.nas(files: 1)
        let mac = try await Device("MAC", nas: nas)
        nas.connectError = .permissionDenied("photos")
        let summary = try await mac.pass()
        #expect(summary.stoppedBy == .permissionDenied("photos"))
    }
}

