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

    /// AC-157: the Mac hashing a NAS for everyone lets Backup in between
    /// two files — Backup asks during file 2 and goes before file 3 — and
    /// carries on from file 3, every file read once.
    @MainActor
    @Test func hashingYieldsToBackup() async throws {
        let client = try Self.nas(files: 5)
        let f = try OnServerFixture(photos: 0)
        let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "iCloud Photo"), password: "pw")
        _ = await ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in client }
            .rescan(sourceId: f.source)
        let lock = ConnectionLock()
        let order = OrderLog()
        client.whileHashing = { count in
            await order.add("hash \(count)")
            guard count == 2 else { return }
            Task {
                await lock.acquire("C1", priority: .backup)
                await order.add("backup")
                await lock.release("C1")
            }
            while await lock.waitingCount("C1") < 1 { await Task.yield() }
        }
        var pass = ServerFileHashPass(store: CopyFileStore(database: f.database),
                                      client: LockedRemoteFileClient(client, lock: lock, connectionId: "C1", priority: .normal))
        pass.hashesEverything = true

        let summary = try await pass.run(sourceId: f.source, connectionId: "C1", folder: "iCloud Photo")

        #expect(summary.hashed == 5)
        #expect(await order.entries == ["hash 1", "hash 2", "backup", "hash 3", "hash 4", "hash 5"])
        #expect(Set(client.sha256Paths).count == 5 && client.sha256Paths.count == 5)
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

    // MARK: Over iCloud (§12.3)

    /// The iCloud records as the pull leaves them: what the "channel" here is.
    private static func exchange(_ f: OnServerFixture, device: String = "PHONE") -> SharedHashExchange {
        SharedHashExchange(database: f.database, device: device, cloudIds: { ids in
            Dictionary(uniqueKeysWithValues: ids.map { ($0, "CLOUD-" + $0) })
        })
    }

    private func photoOffer(size: Int64 = 10, modified: Int = 1_700_000_000, device: String = "MAC",
                            hashedAt: Int = 100) -> SharedPhotoHash {
        SharedPhotoHash(cloudId: "CLOUD-P0", fileKey: "1:a.HEIC", assetModified: modified, size: size,
                        sha256: sha, device: device, hashedAt: hashedAt)
    }

    private func photoHash(_ f: OnServerFixture) async throws -> (sha: String?, origin: String?, from: String?) {
        try await f.database.reader.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT sha256, origin, sharedFrom FROM copy_files WHERE copyId = 'photos:P0'")
            return (row?["sha256"], row?["origin"], row?["sharedFrom"])
        }
    }

    /// AC-149: a Photos file the Mac hashed is filled here from the record,
    /// with the Mac as its sender — nothing to download.
    @MainActor
    @Test func photoHashesFromMac() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:a.HEIC", .photo, 10, nil)])
        try SharedIndexStore(database: f.database).saveRemote(photoHashes: [photoOffer()], serverHashes: [])

        #expect(try await Self.exchange(f).adopt(now: Date(timeIntervalSince1970: 500)) == 1)

        let hash = try await photoHash(f)
        #expect(hash.sha == sha && hash.origin == "shared" && hash.from == "MAC")
        #expect(try CopyFileStore(database: f.database).photosCandidates(triedBefore: Date(timeIntervalSince1970: 1_000), limit: 10).isEmpty)
    }

    /// AC-150: edited on this device since, a different size, or this
    /// device's own record — none is taken, the file waits to be hashed here.
    @MainActor
    @Test func editedOnPhoneRehashes() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:a.HEIC", .photo, 10, nil)])
        try SharedIndexStore(database: f.database).saveRemote(photoHashes: [
            photoOffer(modified: 1_699_999_000), photoOffer(size: 11, device: "IPAD"), photoOffer(device: "PHONE"),
        ], serverHashes: [])

        #expect(try await Self.exchange(f).adopt(now: Date(timeIntervalSince1970: 500)) == 0)
        #expect(try await photoHash(f).sha == nil)
    }

    /// AC-151: a server file takes the hash another device read from the
    /// same server, path, size and write time — not one from another server
    /// at the same path.
    @MainActor
    @Test func serverIdentityMustMatch() async throws {
        let f = try OnServerFixture(photos: 0)
        let server = FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                share: "photos", folder: "iCloud Photo")
        try FileServerStore(database: f.database, passwords: InMemoryPasswordStore()).save(server, password: "pw")
        try f.server("Shared/a.ARW", size: 20, sha: nil)
        try f.server("Shared/b.ARW", size: 20, sha: nil)
        var other = server
        other.host = "office.local"
        let key = try #require(ServerIdentity.key(server))
        let offers = [
            SharedServerHash(serverKey: key, pathKey: SharedHashExchange.pathKey(server: server, relativePath: "Shared/a.ARW"),
                             size: 20, modifiedAt: 1, sha256: sha, device: "MAC", hashedAt: 100),
            SharedServerHash(serverKey: try #require(ServerIdentity.key(other)),
                             pathKey: SharedHashExchange.pathKey(server: server, relativePath: "Shared/b.ARW"),
                             size: 20, modifiedAt: 1, sha256: sha, device: "MAC", hashedAt: 100),
        ]
        try SharedIndexStore(database: f.database).saveRemote(photoHashes: [], serverHashes: offers)

        #expect(try await Self.exchange(f).adopt(now: Date(timeIntervalSince1970: 500)) == 1)
        let rows = try await f.database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT copyId, sha256 FROM copy_files ORDER BY copyId").map { ($0["copyId"] as String, $0["sha256"] as String?) }
        }
        #expect(rows.map(\.1) == [sha, nil])
    }

    /// AC-155: with the index not shared there is no exchange at all — the
    /// pass takes nothing from the records and sends nothing.
    @MainActor
    @Test func offDoesNothing() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:a.HEIC", .photo, 10, nil)])
        try SharedIndexStore(database: f.database).saveRemote(photoHashes: [photoOffer()], serverHashes: [])
        let servers = FileServerStore(database: f.database, passwords: InMemoryPasswordStore())
        let refresh = ServerSourceRefresh(database: f.database, servers: servers, composer: ServerSourceIndexTests.composer) { _, _ in
            InMemoryRemoteFileClient()
        }
        let environment = OnServerCheck.Environment.live(database: f.database, servers: servers, refresh: refresh,
                                                         connectionLock: ConnectionLock(), hashesEverything: { false },
                                                         indexShare: nil, listingChanged: {})

        #expect(await environment.adoptShared(Date()) == 0)
        await environment.publishShared(Date())
        #expect(try await photoHash(f).sha == nil)
        #expect(try SharedIndexStore(database: f.database).outboxCount() == 0)
    }

    /// AC-156: what this device hashed itself goes up once; a hash taken
    /// from another device is not sent back.
    @MainActor
    @Test func recordOwnQueuesOnlyOwnHashes() async throws {
        let f = try OnServerFixture(photos: 2)
        try f.photo(0, files: [("1:a.HEIC", .photo, 10, sha)])
        try f.photo(1, files: [("1:b.HEIC", .photo, 10, nil)])
        try CopyFileStore(database: f.database).saveHash(sha, copyId: "photos:P1", fileKey: "1:b.HEIC", origin: .shared,
                                                         sharedFrom: "MAC", hashedAt: Date(timeIntervalSince1970: 100))
        let exchange = Self.exchange(f)
        let shared = SharedIndexStore(database: f.database)

        #expect(try await exchange.recordOwn(now: Date(timeIntervalSince1970: 500)) == 1)
        #expect(try shared.outboxCount() == 1)
        // Sent with when it was hashed, not when it was sent (§12.4).
        let sent = try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT hashedAt FROM shared_photo_hashes")
        }
        let hashed = try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT hashedAt FROM copy_files WHERE copyId = 'photos:P0'")
        }
        #expect(sent == hashed && sent != 500)
        // Nothing changed: not queued again, not even read again.
        try shared.removeFromOutbox(try shared.outbox(limit: 10))
        #expect(try await exchange.recordOwn(now: Date(timeIntervalSince1970: 600)) == 0)
        #expect(try shared.outboxCount() == 0)
        // Hashed again here: it goes up again.
        try CopyFileStore(database: f.database).saveHash(String(repeating: "b", count: 64), copyId: "photos:P0",
                                                         fileKey: "1:a.HEIC", origin: .hashed)
        #expect(try await exchange.recordOwn(now: Date(timeIntervalSince1970: 700)) == 1)
    }

    /// A hash from another device never replaces one this device worked out
    /// while the offer was being matched.
    @Test func sharedNeverOverwritesOwn() throws {
        let (store, _) = try store()
        try store.saveHash(sha, copyId: "S1", fileKey: "primary", origin: .hashed)
        #expect(try !store.saveHash(String(repeating: "b", count: 64), copyId: "S1", fileKey: "primary", origin: .shared,
                                    sharedFrom: "MAC", hashedAt: Date(timeIntervalSince1970: 100)))
        #expect(try store.files(copyId: "S1").first?.origin == .hashed)
        #expect(try store.files(copyId: "S1").first?.sha256 == sha)
    }

    /// WebDAV over http and https on one port are two servers.
    @Test func webdavTLSIsPartOfTheIdentity() {
        var plain = FileServer(id: "W", name: "DAV", transferProtocol: .webdav, host: "nas.local", port: 5005, username: "u",
                               share: "/dav")
        var secure = plain
        plain.usesTLS = false
        secure.usesTLS = true
        #expect(ServerIdentity.key(plain) != ServerIdentity.key(secure))
    }

    // MARK: Random check (§12.4)

    /// `count` server files whose hashes came from the Mac, each matching a
    /// Photos file hashed here.
    @MainActor
    private static func matched(_ count: Int, from device: String = "MAC", hashedAt: Int = 100) throws -> OnServerFixture {
        let f = try OnServerFixture(photos: count)
        let store = CopyFileStore(database: f.database)
        for n in 0..<count {
            let sha = String(format: "%064x", n + 1)
            try f.photo(n, files: [("1:p\(n).HEIC", .photo, 20, sha)])
            try f.server("Shared/s\(n).HEIC", size: 20, sha: nil)
            try store.saveHash(sha, copyId: "server:Shared/s\(n).HEIC", fileKey: "primary", origin: .shared, sharedFrom: device,
                               hashedAt: Date(timeIntervalSince1970: TimeInterval(hashedAt)), at: Date(timeIntervalSince1970: 200))
        }
        return f
    }

    private static func origins(_ f: OnServerFixture) async throws -> [String: Int] {
        try await f.database.reader.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: """
                SELECT COALESCE(origin, 'none') AS origin, COUNT(*) AS n FROM copy_files
                WHERE copyId LIKE 'server:%' GROUP BY 1
                """).map { ($0["origin"] as String, $0["n"] as Int) })
        }
    }

    /// AC-152: of 12 files matched on the Mac's word, exactly 10 are read
    /// here; all agree, so every match stands and the 10 are now this
    /// device's own hashes.
    @MainActor
    @Test func auditsTen() async throws {
        let f = try Self.matched(12)
        let read = ReadLog()
        let pass = SharedHashAuditPass(store: CopyFileStore(database: f.database)) { file in
            await read.add(file)
            return file.sha256.uppercased()
        }

        let summary = try await pass.run(now: Date(timeIntervalSince1970: 500))

        #expect(summary.checked == 10 && summary.caught.isEmpty && summary.dropped == 0 && summary.cleared == ["MAC"])
        #expect(await read.files.allSatisfy { $0.kind == "server" && $0.device == "MAC" && $0.connectionId == "C1" })
        #expect(Set(await read.files.map(\.copyId)).count == 10)
        #expect(try await Self.origins(f) == ["hashed": 10, "shared": 2])
    }

    /// A hash that makes nothing match is not worth reading again.
    @MainActor
    @Test func auditSkipsUnmatched() async throws {
        let f = try Self.matched(2)
        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE copy_files SET sha256 = ? WHERE copyId = 'photos:P0'", arguments: [String(repeating: "f", count: 64)])
        }
        #expect(try CopyFileStore(database: f.database).auditSample(device: "MAC", limit: 10).map(\.copyId) == ["server:Shared/s1.HEIC"])
    }

    /// AC-153: one of the files read here differs — the Mac's hashes up to
    /// then all go, from iCloud and the ledger alike, and are tried again
    /// here; one it sends later is taken (and checked the same way), one it
    /// made before never.
    @MainActor
    @Test func mismatchDropsOlderHashes() async throws {
        let f = try Self.matched(12)
        let store = CopyFileStore(database: f.database)
        let wrong = String(repeating: "e", count: 64)
        let pass = SharedHashAuditPass(store: store) { _ in wrong }

        let summary = try await pass.run(now: Date(timeIntervalSince1970: 500))

        #expect(summary.checked == 1 && summary.caught == ["MAC"] && summary.dropped == 11)
        #expect(try await Self.origins(f) == ["hashed": 1, "none": 11])
        let tried = try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM copy_files WHERE copyId LIKE 'server:%' AND triedAt IS NOT NULL")
        }
        #expect(tried == 1)
        #expect(try store.auditDevices().isEmpty)
        // Unmatched now, so nothing to read until the Mac sends again.
        #expect(try await pass.run(now: Date(timeIntervalSince1970: 501)).checked == 0)
    }

    /// AC-153, later: what the Mac made after it was caught is trusted again;
    /// what it made before is not, whichever channel brings it back.
    @MainActor
    @Test func newerHashesTrustedAgain() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:a.HEIC", .photo, 10, nil)])
        try CopyFileStore(database: f.database).distrust(device: "MAC", at: Date(timeIntervalSince1970: 300))
        let cloud = SharedIndexStore(database: f.database)
        try cloud.saveRemote(photoHashes: [photoOffer(hashedAt: 250)], serverHashes: [])

        #expect(try await Self.exchange(f).adopt(now: Date(timeIntervalSince1970: 500)) == 0)

        try cloud.saveRemote(photoHashes: [photoOffer(hashedAt: 400)], serverHashes: [])
        #expect(try await Self.exchange(f).adopt(now: Date(timeIntervalSince1970: 500)) == 1)
        #expect(try await photoHash(f).from == "MAC")
        #expect(try CopyFileStore(database: f.database).auditDevices() == ["MAC"])
    }

    /// A file that cannot be read now is skipped — not a mismatch — and a
    /// source the rules hold back is not sampled at all.
    @MainActor
    @Test func unreadableIsNotWrong() async throws {
        let f = try Self.matched(3)
        let store = CopyFileStore(database: f.database)
        var pass = SharedHashAuditPass(store: store) { _ in nil }
        #expect(try await pass.run(now: Date(timeIntervalSince1970: 500)) == .init())
        #expect(try await Self.origins(f) == ["shared": 3])

        pass.sources = []
        #expect(try store.auditSample(device: "MAC", limit: 10, sources: []).isEmpty)
        #expect(try store.auditSample(device: "MAC", limit: 10, sources: [f.source]).count == 3)
    }

    /// A Photos file on the Mac's word is checked only when iCloud may be
    /// read and its listing is current.
    @MainActor
    @Test func photosSideSampledWhenReadable() async throws {
        let f = try OnServerFixture(photos: 1)
        let store = CopyFileStore(database: f.database)
        let sha = String(repeating: "d", count: 64)
        try f.photo(0, files: [("1:a.HEIC", .photo, 20, nil)])
        try f.server("Shared/a.HEIC", size: 20, sha: sha)
        try store.saveHash(sha, copyId: "photos:P0", fileKey: "1:a.HEIC", origin: .shared, sharedFrom: "MAC",
                           hashedAt: Date(timeIntervalSince1970: 100))
        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET modificationDate = (SELECT stamp FROM copy_file_listings WHERE copyId = 'photos:P0') WHERE assetId = 'P0'")
        }

        #expect(try store.auditSample(device: "MAC", limit: 10, photos: false).isEmpty)
        #expect(try store.auditSample(device: "MAC", limit: 10).map(\.kind) == ["photos"])
        // Changed in Photos since it was listed: not the Mac's fault if it differs.
        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET modificationDate = modificationDate + 1 WHERE assetId = 'P0'")
        }
        #expect(try store.auditSample(device: "MAC", limit: 10).isEmpty)
    }

    /// Cancelled after one device was caught: that catch is still reported.
    @MainActor
    @Test func cancelKeepsWhatWasCaught() async throws {
        let f = try Self.matched(3, from: "IPAD")
        let store = CopyFileStore(database: f.database)
        // One file from a second device, checked first.
        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE copy_files SET sharedFrom = 'AMAC' WHERE copyId = 'server:Shared/s0.HEIC'")
        }
        let pass = SharedHashAuditPass(store: store) { file in
            if file.device == "AMAC" {
                withUnsafeCurrentTask { $0?.cancel() }
                return String(repeating: "e", count: 64)
            }
            return file.sha256
        }
        let summary = try await Task { try await pass.run(now: Date(timeIntervalSince1970: 500)) }.value
        #expect(summary == .init(checked: 1, caught: ["AMAC"]))
    }

    /// A pass that catches a device hashes again at once, and says which
    /// device; a later check that finds its files right clears that.
    @MainActor
    @Test func checkHashesAgainAfterCatch() async throws {
        let rounds = Tally()
        let caught = Tally()
        let check = OnServerCheck(environment: OnServerCheck.Environment(
            serverSources: { [(id: "S1", name: "NAS Home", connectionId: "C1")] },
            jobRules: { _ in [] },
            conditions: { (false, false) },
            list: { _ in true },
            hashServer: { _, _, _ in await rounds.bump(); return .init() },
            hashPhotos: { _ in .init() },
            audit: { _, photos, sources in
                #expect(photos && sources == ["S1"])
                return await caught.bump() == 1 ? .init(checked: 1, caught: ["MAC"], dropped: 4)
                    : .init(checked: 3, cleared: ["MAC"])
            }
        ))

        await check.run()
        #expect(check.caughtDevices == ["MAC"])
        #expect(await rounds.value == 2)

        await check.run()
        #expect(check.caughtDevices.isEmpty)
        #expect(await rounds.value == 3)
    }
}


private actor ReadLog {
    var files: [CopyFileStore.AuditFile] = []
    func add(_ file: CopyFileStore.AuditFile) { files.append(file) }
}

private actor Tally {
    var value = 0
    @discardableResult
    func bump() -> Int {
        value += 1
        return value
    }
}

private actor OrderLog {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}
